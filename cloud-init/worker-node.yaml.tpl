#cloud-config

# =============================================================================
# Worker Node - Isolated in internal network
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
      AllowTcpForwarding no
      X11Forwarding no
      AllowAgentForwarding no
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
  - ufw default deny incoming
  - ufw default deny outgoing
  - ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment 'SSH internal'
  - ufw allow from 10.0.0.0/8 proto icmp comment 'ICMP internal'
  - ufw allow from 10.0.0.0/8 to any port 10250 proto tcp comment 'Kubelet API'
  - ufw allow from 10.0.0.0/8 to any port 30000:32767 proto tcp comment 'NodePort'
  - ufw allow out to 10.0.0.0/8 comment 'Outbound internal'
%{ if enable_nat64 ~}
%{ for resolver in dns64_resolvers ~}
  - ufw allow out to ${resolver} port 53 proto udp comment 'DNS64 nat64.net'
  - ufw allow out to ${resolver} port 53 proto tcp comment 'DNS64 nat64.net'
%{ endfor ~}
  - ufw allow out to 64:ff9b::/96 comment 'NAT64 prefix'
%{ else ~}
  - ufw allow out to 185.12.64.1 port 53 proto udp comment 'DNS Hetzner'
  - ufw allow out to 185.12.64.2 port 53 proto udp comment 'DNS Hetzner'
%{ endif ~}
  - ufw allow out to any port 80 proto tcp comment 'HTTP Updates'
  - ufw allow out to any port 443 proto tcp comment 'HTTPS Updates'
  - ufw --force enable
%{ if enable_k8s_prereqs ~}
  # Disable swap (required by kubeadm)
  - swapoff -a
  - sed -i '/\sswap\s/d' /etc/fstab
  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
  # Install and configure containerd
  - apt-get update && apt-get install -y containerd
  - mkdir -p /etc/containerd
  - containerd config default > /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - sed -i 's|registry.k8s.io/pause:3\.8|registry.k8s.io/pause:3.10|' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable containerd
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
