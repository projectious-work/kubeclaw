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
%{ if enable_nat64 ~}
  - systemctl restart systemd-resolved
  - |
    GW6=$(ip -6 route show default dev eth0 | awk '{print $3}' | head -1)
    if [ -n "$GW6" ]; then
      ip -6 route replace 64:ff9b::/96 via "$GW6" dev eth0
    fi
%{ endif ~}
  - reboot
