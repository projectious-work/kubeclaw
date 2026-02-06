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
  - ufw allow out to 185.12.64.1 port 53 proto udp comment 'DNS Hetzner'
  - ufw allow out to 185.12.64.2 port 53 proto udp comment 'DNS Hetzner'
  - ufw allow out to any port 80 proto tcp comment 'HTTP Updates'
  - ufw allow out to any port 443 proto tcp comment 'HTTPS Updates'
  - ufw --force enable
  - reboot
