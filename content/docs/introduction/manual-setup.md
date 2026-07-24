---
title: Manual Setup (Alternative)
---


{{< alert title="This guide is an alternative to OpenTofu" >}}
This guide shows the manual steps that OpenTofu automates. Use this if you want to understand what happens behind the scenes, or if you prefer to set up infrastructure manually via the Hetzner Cloud Console. For the automated approach, see [Infrastructure (OpenTofu)]({{< relref "/docs/guide/infrastructure" >}}).

{{< /alert >}}
## Overview

This setup creates a secure server infrastructure with the following properties:

- **No public IPv4/IPv6 addresses** (after setup)
- **SSH access exclusively via Cloudflare Tunnel**
- **Internal communication via Hetzner Private Network**
- **Hardened SSH configuration with fail2ban and UFW**

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloudflare Tunnel                             │
│                 console.yourdomain.org                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Hetzner Cloud                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Private Network (10.0.0.0/24)              │    │
│  │                                                         │    │
│  │   ┌─────────────────┐       ┌─────────────────┐        │    │
│  │   │  control-node   │       │  worker-node    │        │    │
│  │   │    10.0.0.2     │◄─────►│    10.0.0.3     │        │    │
│  │   │  (cloudflared)  │       │  (isolated)     │        │    │
│  │   └─────────────────┘       └─────────────────┘        │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Hetzner Cloud account
- Cloudflare account with your own domain
- macOS/Linux machine with SSH
- `cloudflared` installed locally (`brew install cloudflared`)

## Step 1: Create Hetzner Private Network

1. Open the [Hetzner Cloud Console](https://console.hetzner.cloud)
2. Select your project
3. Go to **Networks** > **Create Network**
4. Configure:
   - **Name**: `k8s-network` (or any name)
   - **IP Range**: `10.0.0.0/8` (Hetzner requires `/8` for the network object)
5. Click **Create Network**
6. Add a **Subnet**: `10.0.0.0/24` in zone `eu-central` (this is the actual range used by nodes)

## Step 2: Generate SSH keys

Create a separate SSH key for each server:

```bash
# Control Node Key
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_control-node_key -C "control-node"

# Worker Node Key
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_worker-node_key -C "worker-node"

# Temporary Admin Node Key (for initial setup)
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_admin-node_key -C "admin-node"
```

## Step 3: Create temporary Admin Node

Since the Hetzner Web Console (VNC) has issues with copy/paste (especially on Firefox/macOS), create a temporary admin server with a public IPv6 address for the initial setup.

### Cloud-Init for Admin Node

```yaml
#cloud-config

users:
  - name: kubernetes-admin
    groups: users, admin, sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... YOUR_ADMIN_NODE_PUBLIC_KEY

keyboard:
  layout: de
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
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding no
      AllowUsers kubernetes-admin
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
  - ufw allow 22
  - ufw --force enable
  - reboot
```

### Create the server

1. **Servers** > **Add Server**
2. **Location**: Any (e.g. Falkenstein)
3. **Image**: Debian 13
4. **Type**: CX22 (smallest size is sufficient)
5. **Networking**:
   - Public IPv6 enabled
   - Private Network: add your network
6. **SSH Keys**: Add Admin Node key
7. **Cloud config**: Paste the YAML above
8. **Create & Buy now**

### Determine IPv6 address

The IPv6 address is displayed in Hetzner only as a subnet (e.g. `2a01:4f8:1c19:c886::/64`). The actual server address is typically `::1` appended:

```
2a01:4f8:1c19:c886::1
```

### Test connection

```bash
ssh -i ~/.ssh/k8s-cluster_admin-node_key kubernetes-admin@2a01:4f8:1c19:c886::1
```

{{< alert title="Note" >}}
Your local machine needs IPv6 connectivity. Test with `ping6 google.com`.

{{< /alert >}}
## Step 4: Create Control Node (with Cloudflare Tunnel)

### Cloud-Init for Control Node

```yaml
#cloud-config

users:
  - name: root
    plain_text_passwd: 'SECURE_PASSWORD_HERE'
    lock_passwd: false
  - name: kubernetes-admin
    groups: users, admin, sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... YOUR_CONTROL_NODE_PUBLIC_KEY

keyboard:
  layout: de
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
      AllowUsers kubernetes-admin
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
  - ufw allow from 10.0.0.0/24 to any port 22 proto tcp comment 'SSH internal'
  - ufw allow from 127.0.0.1 to any port 22 proto tcp comment 'SSH via Tunnel'
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw --force enable
  - mkdir -p --mode=0755 /usr/share/keyrings
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
  - echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
  - mkdir -p /etc/cloudflared
  - apt-get update && apt-get install -y cloudflared
  - reboot
```

### Create the server

1. **Servers** > **Add Server**
2. **Image**: Debian 13
3. **Type**: As needed (e.g. CX22 or larger)
4. **Networking**:
   - **Public IPv4**: Disabled
   - **Public IPv6**: Enabled (temporarily, for installation)
   - **Private Network**: add your network
5. **SSH Keys**: Add Control Node key
6. **Cloud config**: Paste the YAML above
7. **Create & Buy now**

{{< alert title="Important" >}}
The `edge-ip-version: "6"` setting is essential! Cloudflared attempts IPv4 connections to Cloudflare's edge servers by default. Since the server is IPv6-only, this must be set to `"6"` (as a string!).

{{< /alert >}}
## Step 5: Create Worker Node (isolated)

### Cloud-Init for Worker Node

```yaml
#cloud-config

users:
  - name: root
    plain_text_passwd: 'SECURE_PASSWORD_HERE'
    lock_passwd: false
  - name: kubernetes-admin
    groups: users, admin, sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... YOUR_WORKER_NODE_PUBLIC_KEY

keyboard:
  layout: de
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
      AllowUsers kubernetes-admin
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
  - ufw allow from 10.0.0.0/24 to any port 22 proto tcp comment 'SSH internal'
  - ufw allow from 10.0.0.0/24 proto icmp comment 'ICMP internal'
  - ufw allow out to 10.0.0.0/24 comment 'Outbound internal'
  - ufw allow out to 185.12.64.1 port 53 proto udp comment 'DNS Hetzner'
  - ufw allow out to 185.12.64.2 port 53 proto udp comment 'DNS Hetzner'
  - ufw allow out to any port 80 proto tcp comment 'HTTP Updates'
  - ufw allow out to any port 443 proto tcp comment 'HTTPS Updates'
  - ufw --force enable
  - reboot
```

### Create the server

1. **Servers** > **Add Server**
2. **Image**: Debian 13
3. **Type**: As needed
4. **Networking**:
   - **Public IPv4**: Disabled
   - **Public IPv6**: Enabled (temporarily)
   - **Private Network**: add your network
5. **SSH Keys**: Add Worker Node key
6. **Cloud config**: Paste the YAML above
7. **Create & Buy now**

## Step 6: Set up Cloudflare Tunnel

### 6.1 Create tunnel in Cloudflare

1. Open the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com)
2. Go to **Networks** > **Tunnels**
3. Click **Create a tunnel**
4. Select **Cloudflared** as connector
5. **Tunnel name**: e.g. `hetzner-cluster`
6. **Save tunnel**
7. **Copy the install token** (needed in the next step)

### 6.2 Install cloudflared on Control Node

Connect to the Control Node via the Admin Node:

```bash
# First connect to Admin Node
ssh admin-node

# Then connect to Control Node (via internal network)
ssh kubernetes-admin@10.0.0.2
```

On the Control Node:

```bash
# Install tunnel with token
sudo cloudflared service install <YOUR_TUNNEL_TOKEN>

# Check status
sudo systemctl status cloudflared
```

The tunnel should now appear as "Connected" in Cloudflare.

### 6.3 Configure SSH access in Cloudflare

1. In Cloudflare Zero Trust Dashboard > **Networks** > **Tunnels**
2. Click on your tunnel > **Configure**
3. Go to the **Public Hostname** tab
4. Click **Add a public hostname**
5. Configure:
   - **Subdomain**: `console`
   - **Domain**: `yourdomain.org` (your domain)
   - **Type**: `SSH`
   - **URL**: `localhost:22`
6. **Save hostname**

### 6.4 Create Access Application

1. Go to **Access** > **Applications**
2. Click **Add an application**
3. Select **Self-hosted**
4. Configure:
   - **Application name**: `SSH Console`
   - **Session Duration**: As needed (e.g. 24 hours)
   - **Application domain**: `console.yourdomain.org`
5. Click **Next**
6. Create a **Policy**:
   - **Policy name**: e.g. `Allow Admin`
   - **Action**: `Allow`
   - **Include**: Your email address or identity provider
7. **Save**

## Step 7: Local SSH configuration

### Install cloudflared on local Mac

```bash
brew install cloudflared
```

### Create/extend SSH config

Add the following to `~/.ssh/config`:

```
# Temporary Admin Node (can be removed after setup)
Host admin-node
    HostName 2a01:4f8:xxxx:xxxx::1
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/k8s-cluster_admin-node_key
    PreferredAuthentications publickey

# Control Node via Admin Node (temporary)
Host control-node-01
    HostName 10.0.0.2
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/k8s-cluster_control-node_key
    PreferredAuthentications publickey
    ProxyJump admin-node

# Worker Node via Admin Node (temporary)
Host worker-node-01
    HostName 10.0.0.3
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/k8s-cluster_worker-node_key
    PreferredAuthentications publickey
    ProxyJump admin-node

# Control Node via Cloudflare Tunnel (permanent)
Host console.yourdomain.org
    HostName console.yourdomain.org
    User kubernetes-admin
    IdentityFile ~/.ssh/k8s-cluster_control-node_key
    ProxyCommand cloudflared access ssh --hostname %h
```

{{< alert title="Note" >}}
`cloudflared` must be installed and available in `$PATH` (`brew install cloudflared` on macOS, included in the Dev Container)

{{< /alert >}}
### Test connection

```bash
# Via Cloudflare Tunnel
ssh console.yourdomain.org
```

On first connection, a browser window will open for Cloudflare Access authentication.

## Step 8: Disable public IPs

After the Cloudflare Tunnel is working:

1. **Hetzner Console** > **Servers** > **control-node-01**
2. **Networking** > **Public Network** > **Disable**
3. Repeat for **worker-node-01**

The servers are now only reachable via the Cloudflare Tunnel (Control Node) or the internal network (Worker Node).

## Step 9: Remove Admin Node

The temporary Admin Node is no longer needed:

1. **Hetzner Console** > **Servers** > **admin-node**
2. **Delete** > Confirm

Also remove the corresponding entries from `~/.ssh/config` and update the ProxyJump entries:

```
# Worker Node via Cloudflare Tunnel (through Control Node)
Host worker-node-01
    HostName 10.0.0.3
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/k8s-cluster_worker-node_key
    PreferredAuthentications publickey
    ProxyJump console.yourdomain.org
```

## Final SSH configuration

After completing all steps:

```
# Control Node via Cloudflare Tunnel
Host control-node-01
    HostName console.yourdomain.org
    User kubernetes-admin
    IdentityFile ~/.ssh/k8s-cluster_control-node_key
    ProxyCommand cloudflared access ssh --hostname %h

# Worker Node via Cloudflare Tunnel → Control Node → Internal network
Host worker-node-01
    HostName 10.0.0.3
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/k8s-cluster_worker-node_key
    PreferredAuthentications publickey
    ProxyJump control-node-01
```

## References

- [Hetzner Cloud-Init Tutorial](https://community.hetzner.com/tutorials/basic-cloud-config/de)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare SSH Access](https://developers.cloudflare.com/cloudflare-one/applications/non-http/ssh/)
