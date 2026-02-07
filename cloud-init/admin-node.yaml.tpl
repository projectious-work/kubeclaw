#cloud-config

# =============================================================================
# Admin Node - Temporary jump host for initial setup
# =============================================================================
# This node provides public IPv6 SSH access to reach the private network.
# Disable with enable_admin_node = false after Cloudflare Tunnel is configured.
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
      X11Forwarding no
      AllowAgentForwarding yes
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

runcmd:
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - ufw allow 22/tcp comment 'SSH public'
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw --force enable
  - reboot
