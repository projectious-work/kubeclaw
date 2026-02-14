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

runcmd:
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment 'SSH internal'
%{ if is_master ~}
  - ufw allow from 127.0.0.1 to any port 22 proto tcp comment 'SSH via Tunnel'
%{ endif ~}
  - ufw allow from 10.0.0.0/8 to any port 6443 proto tcp comment 'Kubernetes API'
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw --force enable
%{ if is_master ~}
  - mkdir -p --mode=0755 /usr/share/keyrings
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
  - echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
  - mkdir -p /etc/cloudflared
  - apt-get update && apt-get install -y cloudflared
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
