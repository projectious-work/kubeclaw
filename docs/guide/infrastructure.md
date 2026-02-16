# Infrastructure (OpenTofu)

KubeClaw uses OpenTofu (Terraform-compatible) to provision all infrastructure on Hetzner Cloud. This page covers SSH key management, node scaling, and post-apply workflow.

## Post-apply workflow

After `tofu apply`, run these scripts to set up SSH access and Ansible:

```bash
# Export SSH keys and generate ~/.ssh/config
./scripts/setup-ssh.sh

# Generate Ansible inventory from Terraform state
./scripts/generate-ansible-inventory.sh

# Start ssh-agent and load keys (MUST be sourced, not executed)
source ./scripts/ssh-agent-setup.sh
```

## SSH key management

### Option A: Automatically generated keys (default)

OpenTofu generates SSH keys automatically and stores them in the state.

```bash
# Export keys after `tofu apply`
tofu output -raw control_node_ssh_private_key > ~/.ssh/k8s-cluster_control-node_key
tofu output -raw worker_node_ssh_private_key > ~/.ssh/k8s-cluster_worker-node_key
chmod 600 ~/.ssh/k8s-cluster_*_key
```

Advantages:

- No manual key creation required
- Keys are stored in the state

Disadvantages:

- The state file contains sensitive data
- If the state is lost, the keys are lost

### Option B: Use your own SSH keys

For more control, supply your own keys:

```bash
# 1. Create keys
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_control-node_key -C "control-node"
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_worker-node_key -C "worker-node"

# 2. Add them to terraform.tfvars
```

```hcl
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
   ssh-keygen -t ed25519 -f ~/.ssh/k8s-control -C "k8s-control"
   ```

2. **Save to Dashlane**:
   - Create a "Secure Note" in Dashlane
   - Name: "K8s Cluster SSH Keys"
   - Content: paste the private key (`cat ~/.ssh/k8s-control`)
   - Add the public key as an additional field

3. **Public key in terraform.tfvars**:
   ```hcl
   control_node_public_key = "ssh-ed25519 AAAA..."
   ```

4. **Restore when needed**:
   - Copy the private key from Dashlane
   - Save it as `~/.ssh/k8s-control`
   - `chmod 600 ~/.ssh/k8s-control`

!!! tip
    Dashlane supports attaching files to secure notes -- you can attach the key files directly.

## SSH keys with passphrase

### Why use a passphrase?

An SSH key without a passphrase is like a house key without a lock on the key cabinet. If your laptop or key file is stolen, the attacker gains immediate access.

### Creating keys with a passphrase

```bash
# Control node key
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_control-node_key -C "k8s-control"
# Enter a strong passphrase when prompted

# Worker node key
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_worker-node_key -C "k8s-worker"
# Enter a passphrase when prompted
```

### Using ssh-agent

Since Terraform and Ansible cannot directly use encrypted keys, you must use ssh-agent:

```bash
# Start agent (if not already running)
eval "$(ssh-agent -s)"

# Add keys (prompts for passphrase)
ssh-add ~/.ssh/k8s-cluster_control-node_key
ssh-add ~/.ssh/k8s-cluster_worker-node_key

# Check which keys are loaded
ssh-add -l
```

### macOS: Keychain integration

On macOS you can store the passphrase in the system Keychain so the key is automatically available after a reboot:

```bash
# Add key AND store passphrase in Keychain
ssh-add --apple-use-keychain ~/.ssh/k8s-cluster_control-node_key
ssh-add --apple-use-keychain ~/.ssh/k8s-cluster_worker-node_key
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
tofu output -raw control_node_ssh_private_key > ~/.ssh/k8s-cluster_control-node_key
chmod 600 ~/.ssh/k8s-cluster_control-node_key

# Add passphrase
ssh-keygen -p -f ~/.ssh/k8s-cluster_control-node_key
# Old passphrase: [Enter] (empty)
# New passphrase: [enter passphrase]
# Confirm: [repeat]
```

!!! note
    After encryption, `tofu output` still returns the unencrypted key from the state. However, your local key is now protected.

## SSH key rotation

### When to rotate

- Periodically (e.g. annually)
- If compromise is suspected
- When personnel changes occur

### With auto-generated keys

```bash
# 1. Mark old key resources for recreation
tofu taint 'tls_private_key.control_node[0]'
tofu taint 'tls_private_key.worker_node[0]'

# 2. Generate new keys
tofu apply

# 3. Export new keys
./scripts/setup-ssh.sh
```

!!! warning
    During rotation SSH access may be briefly interrupted. Keep Hetzner web console root access available.

### With your own keys

```bash
# 1. Create new keys
ssh-keygen -t ed25519 -f ~/.ssh/k8s-control-new -C "control-node-new"

# 2. Add the new public key to the server (before rotation)
ssh control-node
echo "ssh-ed25519 AAAA... control-node-new" >> ~/.ssh/authorized_keys

# 3. Test the new key
ssh -i ~/.ssh/k8s-control-new kubernetes-admin@...

# 4. Remove the old key
ssh control-node
# Remove the old line from ~/.ssh/authorized_keys

# 5. Update terraform.tfvars
# control_node_public_key = "ssh-ed25519 AAAA... (new key)"

# 6. Sync OpenTofu state
tofu apply
```

## Scaling nodes

### Master-only setup (no replicas, no workers)

```hcl
# terraform.tfvars
master_control_node_type = "cx23"
control_node_types = []
worker_node_types  = []
```

### Add replica control nodes

```hcl
# terraform.tfvars
control_node_types = [
  { type = "cx23", count = 2 },  # 2 replicas → 3 total control nodes
]
```

### Add workers with mixed types

```hcl
# terraform.tfvars
worker_node_types = [
  { type = "cx23", count = 2 },
  { type = "cx32", count = 1 },  # 3 workers total, mixed types
]
```

After changing node counts:

```bash
tofu apply
./scripts/generate-ansible-inventory.sh  # update Ansible inventory
```

## Available OS images

Hetzner Cloud offers the following Debian/Ubuntu images:

| Image | Name | Recommendation |
|-------|------|----------------|
| `debian-13` | Debian 13 Trixie | **Recommended for K8s** |
| `debian-12` | Debian 12 Bookworm | Stable, well-proven |
| `ubuntu-24.04` | Ubuntu 24.04 LTS | Good for K8s |
| `ubuntu-22.04` | Ubuntu 22.04 LTS | Well-proven |

### Why Debian 13?

- Stability: long support cycles
- Compatibility: all K8s tools (kubeadm, k3s, etc.) support Debian
- Small footprint: leaner than Ubuntu, but not as small as Alpine
- No glibc/musl compatibility issues (as with Alpine)

Hetzner Cloud doesn't provide dedicated "slim" or "minimal" variants. The standard images are fairly compact already.
