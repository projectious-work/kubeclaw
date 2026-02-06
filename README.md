# Hetzner Cloud Kubernetes cluster with OpenTofu

This project automates creation of a secure, IPv6-only Kubernetes cluster on Hetzner Cloud with SSH access via a Cloudflare Tunnel.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloudflare Tunnel                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Hetzner Cloud                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Private Network (10.0.0.0/24)              │    │
│  │                                                         │    │
│  │   ┌─────────────────┐       ┌─────────────────┐        │    │
│  │   │  control-node   │       │  worker-nodes   │        │    │
│  │   │    10.0.0.2     │◄─────►│   10.0.0.3+     │        │    │
│  │   │  (cloudflared)  │       │  (0-n instances)│       │    │
│  │   └─────────────────┘       └─────────────────┘        │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- ✅ **IPv6-only** — No public IPv4 addresses required
- ✅ **Cloudflare Tunnel** — Secure SSH access without open ports
- ✅ **Scalable** — 0 to n worker nodes
- ✅ **Custom SSH keys** — Optionally use your own keys
- ✅ **Ansible-ready** — Playbooks for updates and hardening
- ✅ **Debian 12** — Stable, Kubernetes-compatible OS

## Requirements

- [OpenTofu](https://opentofu.org/) >= 1.6.0 (or Terraform >= 1.5.0)
- Hetzner Cloud account with API token
- Cloudflare account with a configured domain
- `cloudflared` installed locally (e.g. `brew install cloudflared` on Mac)
- (Optional) Ansible for server management

## Quick Start

```bash
# 1. Clone or unpack the project
cd tofu-hetzner-cluster

# 2. Configure
cp terraform.tfvars.example terraform.tfvars
# → edit terraform.tfvars

# 3. Create infrastructure
tofu init
tofu apply

# 4. Set up SSH
./scripts/setup-ssh.sh

# 5. Install Cloudflare Tunnel (on the control node)
ssh control-node
sudo cloudflared service install <TOKEN>

# 6. Disable IPv6 (optional, after tunnel setup)
# → set enable_public_ipv6 = false in terraform.tfvars
tofu apply
```

---

## SSH key management

### Option A: Automatically generated keys (default)

OpenTofu can generate SSH keys automatically and store them in the state.

```bash
# Export keys after `tofu apply`
tofu output -raw control_node_ssh_private_key > ~/.ssh/k3s-cluster_control-node_key
tofu output -raw worker_node_ssh_private_key > ~/.ssh/k3s-cluster_worker-node_key
chmod 600 ~/.ssh/k3s-cluster_*_key
```

Advantages:
- No manual key creation required
- Keys are stored in the state

Disadvantages:
- The state file contains sensitive data
- If the state is lost, the keys are lost

### Option B: Use your own SSH keys

For more control you can supply your own keys:

```bash
# 1. Create keys
ssh-keygen -t ed25519 -f ~/.ssh/k3s-cluster_control-node_key -C "control-node"
ssh-keygen -t ed25519 -f ~/.ssh/k3s-cluster_worker-node_key -C "worker-node"

# 2. Add them to terraform.tfvars
control_node_public_key = "ssh-ed25519 AAAA... control-node"
worker_node_public_key  = "ssh-ed25519 AAAA... worker-node"
```

Advantages:
- Full control over key storage
- Easy integration with password managers
- State does not contain private keys

### Storing SSH keys in Dashlane

If you use Dashlane, recommended workflow:

1. **Create keys locally**:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/k3s-control -C "k3s-control"
   ```

2. **Save to Dashlane**:
   - Create a "Secure Note" in Dashlane
   - Name: "K3s Cluster SSH Keys"
   - Content: paste the private key (`cat ~/.ssh/k3s-control`)
   - Add the public key as an additional field

3. **Public key in terraform.tfvars**:
   ```hcl
   control_node_public_key = "ssh-ed25519 AAAA..."
   ```

4. **Restore when needed**:
   - Copy the private key from Dashlane
   - Save it as `~/.ssh/k3s-control`
   - `chmod 600 ~/.ssh/k3s-control`

Tip: Dashlane supports attaching files to secure notes — you can attach the key files directly.

---

## SSH keys with passphrase

### Why use a passphrase?

An SSH key without a passphrase is like a house key without a lock on the key cabinet. If your laptop or key file is stolen, the attacker gains immediate access.

### Creating keys with a passphrase

```bash
# Control node key
ssh-keygen -t ed25519 -f ~/.ssh/k3s-cluster_control-node_key -C "k3s-control"
# → Enter a strong passphrase!

# Worker node key
ssh-keygen -t ed25519 -f ~/.ssh/k3s-cluster_worker-node_key -C "k3s-worker"
# → Enter a passphrase!
```

### Using ssh-agent

Since Terraform and Ansible cannot directly use encrypted keys, you must use ssh-agent:

```bash
# Start agent (if not already running)
eval "$(ssh-agent -s)"

# Add keys (prompts for passphrase)
ssh-add ~/.ssh/k3s-cluster_control-node_key
ssh-add ~/.ssh/k3s-cluster_worker-node_key

# Check which keys are loaded
ssh-add -l
```

### macOS: Keychain integration

On macOS you can store the passphrase in the system Keychain so the key is automatically available after a reboot:

```bash
# Add key AND store passphrase in Keychain
ssh-add --apple-use-keychain ~/.ssh/k3s-cluster_control-node_key
ssh-add --apple-use-keychain ~/.ssh/k3s-cluster_worker-node_key
```

Also add the following to `~/.ssh/config`:

```
Host *
    UseKeychain yes
    AddKeysToAgent yes
```

### Helper script

The project includes a script that sets up ssh-agent correctly:

```bash
# Run once before using SSH/Ansible
source ./scripts/ssh-agent-setup.sh

# Afterwards SSH and Ansible work without further passphrase prompts
ssh control-node
ansible all -m ping
```

### Encrypting auto-generated keys after export

If you use auto-generated keys from OpenTofu, you can add a passphrase afterwards:

```bash
# Export key (unencrypted from state)
tofu output -raw control_node_ssh_private_key > ~/.ssh/k3s-cluster_control-node_key
chmod 600 ~/.ssh/k3s-cluster_control-node_key

# Add passphrase
ssh-keygen -p -f ~/.ssh/k3s-cluster_control-node_key
# → Old passphrase: [Enter] (empty)
# → New passphrase: [enter passphrase]
# → Confirm: [repeat]
```

> **Note**: After encryption, `tofu output` still returns the unencrypted key from the state. However, your local key is now protected.

---

## SSH key rotation

### When to rotate

- Periodically (e.g. annually)
- If compromise is suspected
- When personnel changes occur

### How to rotate

#### With auto-generated keys:

```bash
# 1. Mark old key resources for recreation
tofu taint 'tls_private_key.control_node[0]'
tofu taint 'tls_private_key.worker_node[0]'

# 2. Generate new keys
tofu apply

# 3. Export new keys
./scripts/setup-ssh.sh
```

Warning: During rotation SSH access may be briefly interrupted. Keep Hetzner web console root access available.

#### With your own keys:

```bash
# 1. Create new keys
ssh-keygen -t ed25519 -f ~/.ssh/k3s-control-new -C "control-node-new"

# 2. Add the new public key to the server (before rotation)
ssh control-node
echo "ssh-ed25519 AAAA... control-node-new" >> ~/.ssh/authorized_keys

# 3. Test the new key
ssh -i ~/.ssh/k3s-control-new kubernetes-admin@...

# 4. Remove the old key
ssh control-node
# Remove the old line from ~/.ssh/authorized_keys

# 5. Update terraform.tfvars
control_node_public_key = "ssh-ed25519 AAAA... (new key)"

# 6. Sync OpenTofu state
tofu apply
```

---

## Scaling worker nodes

### Scale to 0 workers (control node only)

```hcl
# terraform.tfvars
worker_node_count = 0
```

```bash
tofu apply
```

### Add workers

```hcl
# terraform.tfvars
worker_node_count = 3  # e.g. increase to 3
```

```bash
tofu apply
./scripts/generate-ansible-inventory.sh  # update Ansible inventory
```

---

## Server management with Ansible

### Setup

```bash
# Install Ansible collection
ansible-galaxy collection install ansible.posix

# Generate inventory
./scripts/generate-ansible-inventory.sh

# Test
cd ansible
ansible all -m ping
```

### System updates

```bash
cd ansible

# Update all servers
ansible-playbook playbooks/update-system.yml

# Only control node
ansible-playbook playbooks/update-system.yml --limit control_nodes

# With reboot if needed
ansible-playbook playbooks/update-system.yml -e "reboot_after_update=true"
```

### Security hardening

```bash
ansible-playbook playbooks/security-hardening.yml
```

This enables:
- Unattended upgrades (automatic security updates)
- fail2ban monitoring
- Kernel security parameters

---

## Available OS images

Hetzner Cloud offers the following Debian/Ubuntu images:

| Image | Name | Recommendation |
|-------|------|----------------|
| `debian-13` | Debian 13 Trixie | ✅ **Recommended for K8s** |
| `debian-12` | Debian 12 Bookworm | Stable, well-proven |
| `ubuntu-24.04` | Ubuntu 24.04 LTS | Good for K8s |
| `ubuntu-22.04` | Ubuntu 22.04 LTS | Well-proven |

### Why Debian 13?

- Stability: long support cycles
- Compatibility: all K8s tools (kubeadm, k3s, etc.) support Debian
- Small footprint: leaner than Ubuntu, but not as small as Alpine
- No glibc/musl compatibility issues (as with Alpine)

### No "minimal" image available

Hetzner Cloud doesn't provide dedicated "slim" or "minimal" variants. The standard images are fairly compact already. If you need a smaller image:

1. Use Packer: build a custom image with only required packages
2. Optimize cloud-init: remove unnecessary packages on first boot

```yaml
# Add to cloud-init
runcmd:
  - apt-get purge -y snapd
  - apt-get autoremove -y
```

---

## Password management

### Which credentials exist?

| Credential | Purpose | Storage |
|------------|---------|---------|
| Hetzner API Token | Create infrastructure | `terraform.tfvars` |
| Root password | Emergency web console | `terraform.tfvars` |
| SSH private keys | Server access | `~/.ssh/` or Dashlane |
| Cloudflare Tunnel token | Tunnel auth | Cloudflare Dashboard |

### Recommended Dashlane structure

```
📁 K3s Cluster
├── 🔐 Hetzner API Token
│   └── Token: xxx
├── 🔐 Root Password
│   └── Password: xxx
├── 📝 SSH Keys (Secure Note)
│   ├── Control Node Private Key: ...
│   ├── Control Node Public Key: ...
│   ├── Worker Node Private Key: ...
│   └── Worker Node Public Key: ...
└── 🔐 Cloudflare Tunnel Token
    └── Token: xxx
```

### Securing `terraform.tfvars`

`terraform.tfvars` contains sensitive data. Options:

1. Do not commit: exclude via `.gitignore` (default)
2. Encrypt: with `git-crypt` or `sops`
3. Use environment variables instead of tfvars
   ```bash
   export TF_VAR_hcloud_token="xxx"
   export TF_VAR_root_password="xxx"
   ```

---

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `hcloud_token` | Hetzner API token | - |
| `cluster_name` | Prefix for all resources | `k3s-cluster` |
| `location` | Hetzner datacenter | `fsn1` |
| `server_image` | OS image | `debian-13` |
| `control_node_type` | Control node server type | `cx22` |
| `worker_node_type` | Worker node server type | `cx22` |
| `worker_node_count` | Number of worker nodes (0-n) | `1` |
| `enable_public_ipv6` | Enable IPv6 | `true` |
| `admin_user` | SSH username | `kubernetes-admin` |
| `control_node_public_key` | Custom SSH public key for control node | `""` (auto) |
| `worker_node_public_key` | Custom SSH public key for worker nodes | `""` (auto) |
| `cloudflare_tunnel_domain` | Domain for the tunnel | `""` |

---

## Project structure

```
tofu-hetzner-cluster/
├── main.tf                          # Infrastructure
├── variables.tf                     # Variables
├── outputs.tf                       # Outputs
├── terraform.tfvars.example         # Example configuration
├── .gitignore
├── README.md
├── cloud-init/
│   ├── control-node.yaml.tpl       # Cloud-init template for control node
│   └── worker-node.yaml.tpl        # Cloud-init template for worker nodes
├── scripts/
│   ├── setup-ssh.sh                # SSH setup helper
│   ├── ssh-agent-setup.sh          # ssh-agent setup (macOS Keychain support)
│   └── generate-ansible-inventory.sh
└── ansible/
    ├── ansible.cfg
    ├── inventory.ini
    └── playbooks/
        ├── update-system.yml
        └── security-hardening.yml
```

---

## Troubleshooting

### cloudflared won't start (IPv6-only)

Check `/etc/cloudflared/config.yml`:
```yaml
edge-ip-version: "6"
```

### SSH key rotation failed

1. Connect via Hetzner web console (root password)
2. Add the new key manually:
   ```bash
   echo "ssh-ed25519 AAAA..." >> /home/kubernetes-admin/.ssh/authorized_keys
   ```

### Ansible cannot connect

Check:
1. Is `cloudflared` installed locally?
2. Is the tunnel running? (`cloudflared tunnel list`)
3. Is the inventory correct? (`./scripts/generate-ansible-inventory.sh`)

### State lost / keys gone

With auto-generated keys:
1. Connect via web console (root)
2. Create new keys
3. Add them to authorized_keys
4. Import servers into new state:
   ```bash
   tofu import hcloud_server.control_node <server-id>
   ```

---

## Next steps after cluster setup

1. **Install K3s**:
   ```bash
   curl -sfL https://get.k3s.io | sh -
   ```

2. **Or kubeadm**:
   ```bash
   # See official K8s documentation
   ```

3. **Install Kubernetes Dashboard**

4. **Set up Ingress Controller**

---

## License

MIT
