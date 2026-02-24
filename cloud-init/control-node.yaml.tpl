#cloud-config

# =============================================================================
# ${is_master ? "Master Control Node - With Cloudflare Tunnel" : "Control Node Replica"}
# =============================================================================

users:
  - name: root
    plain_text_passwd: '${root_password}'
    lock_passwd: false
  - name: ${admin_user}
    groups: users, admin, sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key}

keyboard:
  layout: ${keyboard_layout}
  variant: mac

packages:
  - fail2ban
  - ufw
  - curl
  - wget
%{ if enable_k8s_prereqs ~}
  - apt-transport-https
  - ca-certificates
  - gnupg
  - procps
%{ endif ~}

package_update: true
package_upgrade: true

%{ if enable_nat64 ~}
bootcmd:
  - mkdir -p /etc/systemd/resolved.conf.d
  - |
    cat > /etc/systemd/resolved.conf.d/dns64.conf <<'DNSEOF'
    [Resolve]
    DNS=${join(" ", dns64_resolvers)}
    Domains=~.
    DNSEOF
  - systemctl restart systemd-resolved
%{ endif ~}

write_files:
  - path: /etc/ssh/sshd_config.d/ssh-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      ChallengeResponseAuthentication no
      MaxAuthTries 3
      X11Forwarding no
      AllowAgentForwarding no
      AllowTcpForwarding yes
      AllowUsers ${admin_user}
      ClientAliveInterval 300
      ClientAliveCountMax 2

  - path: /etc/fail2ban/jail.local
    content: |
      [sshd]
      enabled = true
      port = 22
      banaction = iptables-multiport
      maxretry = 3
      findtime = 600
      bantime = 3600

%{ if is_master ~}
  - path: /etc/cloudflared/config.yml
    content: |
      edge-ip-version: "6"
%{ endif ~}

%{ if enable_nat64 ~}
  - path: /etc/systemd/resolved.conf.d/dns64.conf
    content: |
      [Resolve]
      DNS=${join(" ", dns64_resolvers)}
      Domains=~.

  - path: /etc/networkd-dispatcher/routable.d/50-nat64-route
    permissions: '0755'
    content: |
      #!/bin/bash
      # Add NAT64 route via default IPv6 gateway
      if [ "$IFACE" = "eth0" ]; then
        GW6=$(ip -6 route show default dev eth0 | awk '{print $3}' | head -1)
        if [ -n "$GW6" ]; then
          ip -6 route replace 64:ff9b::/96 via "$GW6" dev eth0
        fi
      fi
%{ endif ~}

%{ if enable_k8s_prereqs ~}
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
      net.ipv6.conf.all.forwarding        = 1
%{ endif ~}

runcmd:
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment 'SSH internal'
%{ if is_master ~}
  - ufw allow from 127.0.0.1 to any port 22 proto tcp comment 'SSH via Tunnel'
%{ endif ~}
  - ufw allow from 10.0.0.0/8 to any port 6443 proto tcp comment 'Kubernetes API'
%{ if enable_k8s_prereqs ~}
  - ufw allow from 10.0.0.0/8 to any port 10250 proto tcp comment 'Kubelet API'
  - ufw allow from 10.0.0.0/8 to any port 2379:2380 proto tcp comment 'etcd'
%{ endif ~}
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw --force enable
%{ if is_master ~}
  - mkdir -p --mode=0755 /usr/share/keyrings
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
  - echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
  - mkdir -p /etc/cloudflared
  - apt-get update && apt-get install -y cloudflared
%{ if cloudflare_tunnel_token != "" ~}
  - cloudflared service install ${cloudflare_tunnel_token}
%{ endif ~}
%{ endif ~}
%{ if enable_k8s_prereqs ~}
  # Disable swap (required by kubeadm)
  - swapoff -a
  - sed -i '/\sswap\s/d' /etc/fstab
  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
%{ if container_runtime == "containerd" ~}
  # Install and configure containerd
  - apt-get update && apt-get install -y containerd
  - mkdir -p /etc/containerd
  - containerd config default > /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - sed -i 's|registry.k8s.io/pause:3\.8|registry.k8s.io/pause:3.10|' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable containerd
%{ endif ~}
%{ if container_runtime == "cri-o" ~}
  # Install and configure CRI-O
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${kubernetes_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${kubernetes_version}/deb/ /' | tee /etc/apt/sources.list.d/cri-o.list
  - apt-get update && apt-get install -y cri-o
  - systemctl enable crio
  - systemctl start crio
  # Configure kubelet to use CRI-O socket
  - mkdir -p /etc/default
  - echo 'KUBELET_EXTRA_ARGS=--container-runtime-endpoint=unix:///var/run/crio/crio.sock' > /etc/default/kubelet
%{ endif ~}
  # Add Kubernetes apt repository
  - mkdir -p --mode=0755 /usr/share/keyrings
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v${kubernetes_version}/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${kubernetes_version}/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
  # Install kubeadm, kubelet, kubectl
  - apt-get update && apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl
  - systemctl enable kubelet
%{ endif ~}
%{ if enable_nat64 ~}
  - systemctl restart systemd-resolved
  - |
    GW6=$(ip -6 route show default dev eth0 | awk '{print $3}' | head -1)
    if [ -n "$GW6" ]; then
      ip -6 route replace 64:ff9b::/96 via "$GW6" dev eth0
    fi
%{ endif ~}
  - reboot
