#cloud-config

# =============================================================================
# Control Node - Mit Cloudflare Tunnel Support
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

  - path: /etc/cloudflared/config.yml
    content: |
      edge-ip-version: "6"

runcmd:
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment 'SSH intern'
  - ufw allow from 127.0.0.1 to any port 22 proto tcp comment 'SSH via Tunnel'
  - ufw allow from 10.0.0.0/8 to any port 6443 proto tcp comment 'Kubernetes API'
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw --force enable
  - mkdir -p --mode=0755 /usr/share/keyrings
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
  - echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
  - mkdir -p /etc/cloudflared
  - apt-get update && apt-get install -y cloudflared
  - reboot
