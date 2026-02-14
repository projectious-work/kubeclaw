# Hetzner Cloud Kubernetes cluster with OpenTofu

This project automates creation of a secure, IPv6-only Kubernetes cluster on Hetzner Cloud with SSH access via a Cloudflare Tunnel.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────────────────────────────────────────┘
                         │              │
                         ▼              ▼
              ┌──────────────┐  ┌───────────────┐
              │  Cloudflare  │  │  Admin Node   │
              │   Tunnel     │  │  10.0.0.254   │
              │  (permanent) │  │  (temporary,  │
              └──────┬───────┘  │  public IPv6) │
                     │          └───────┬───────┘
                     ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Hetzner Cloud                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Private Network (10.0.0.0/24)              │    │
│  │                                                         │    │
│  │   ┌─────────────────┐  ┌─────────────────┐             │    │
│  │   │  control-01     │  │  control-02+    │             │    │
│  │   │    10.0.0.2     │  │   10.0.0.3+     │             │    │
│  │   │  (master,       │◄►│  (replicas,     │             │    │
│  │   │   cloudflared)  │  │   0-n instances) │             │    │
│  │   └────────┬────────┘  └─────────────────┘             │    │
│  │            │                                            │    │
│  │            ▼                                            │    │
│  │   ┌─────────────────┐                                   │    │
│  │   │  worker-nodes   │                                   │    │
│  │   │  (0-n instances) │                                   │    │
│  │   └─────────────────┘                                   │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- ✅ **IPv6-only** — No public IPv4 addresses required, NAT64/DNS64 for transparent IPv4 reachability
- ✅ **Cloudflare Tunnel** — Secure SSH access without open ports
- ✅ **Admin Node** — Temporary jump host with public IPv6 for initial setup (removable)
- ✅ **Scalable** — Master + replica control nodes, 0 to n worker nodes, mixed server types
- ✅ **Custom SSH keys** — Optionally use your own keys, with configurable key file prefix
- ✅ **Ansible-ready** — Playbooks for updates and hardening
- ✅ **Debian 13** — Stable, Kubernetes-compatible OS

## Requirements

- Hetzner Cloud account with API token
- Cloudflare account with a configured domain
- Docker and an IDE with Dev Container support (e.g. VS Code + Dev Containers extension)

All tools (OpenTofu, Ansible, SSH, AI assistants) are pre-installed in the Dev Container — no local installation needed.

## Dev Container Setup

The project uses a Dev Container (Debian Trixie) as a self-contained, reproducible environment. SSH keys and configuration are persisted across container rebuilds via a host-mounted directory.

### After cloning the repository

Create the persistent directories before opening the Dev Container:

```bash
git clone <repo-url>
cd hetzner-k8s-cluster

# Create persistent directories (mounted into the container at /root/.ssh and /root/.vibe)
mkdir -p .root/.ssh
chmod 700 .root/.ssh
```

The `.root/` directory is gitignored — it holds your SSH keys, SSH config, and known_hosts locally without risk of committing secrets.

### What the Dev Container provides

- **OpenTofu** — infrastructure provisioning
- **Ansible** — server management (runs inside the container, no host install needed)
- **ssh-agent** — start inside the container to use passphrase-protected keys with Ansible
- **AI CLI tools** — Claude Code, Vibe, OpenCode
- **Persistence** — `.root/.ssh/` is bind-mounted, so `setup-ssh.sh` output, SSH config, and exported keys survive container rebuilds

### Working inside the Dev Container

After the container starts, all project commands (`tofu`, `ansible`, `ssh`) use the persistent `~/.ssh/` directory. The ssh-agent setup script works inside the container:

```bash
source ./scripts/ssh-agent-setup.sh   # Load keys into agent (needed for Ansible)
```

## Quick Start

```bash
# 1. Clone and prepare persistent directories
git clone <repo-url>
cd hetzner-k8s-cluster
mkdir -p .root/.ssh
chmod 700 .root/.ssh

# 2. Open the project in your IDE and start the Dev Container
#    (e.g. VS Code → "Reopen in Container")
```

All remaining commands run **inside the Dev Container**:

```bash
# 3. Configure
cp terraform.tfvars.example terraform.tfvars
# → edit terraform.tfvars

# 4. Create infrastructure (includes admin node by default)
tofu init
tofu apply

# 5. Set up SSH (keys and config are persisted in .root/.ssh/)
./scripts/setup-ssh.sh

# 6. SSH to control node (routes via admin node automatically)
ssh control-node

# 7. Install Cloudflare Tunnel (on the control node)
sudo cloudflared service install <TOKEN>

# 8. Disable admin node and public IPv6 (after tunnel works)
# → set enable_admin_node = false in terraform.tfvars
# → set enable_public_ipv6 = false in terraform.tfvars
tofu apply
```

Infrastructure is ready. Continue with [Kubernetes Deployment with kubeadm](#kubernetes-deployment-with-kubeadm) to set up the cluster.

---

## NAT64/DNS64 (IPv4 reachability)

The cluster is IPv6-only — but many services (GitHub CDN, container registries, package repos) are IPv4-only. **NAT64/DNS64** provides transparent IPv4 reachability at the network layer, no application changes needed.

### How it works

1. **DNS64 resolver** receives a query for `github.com`, sees it only has an A record (IPv4), and synthesizes an AAAA record with the `64:ff9b::/96` prefix
2. Node sends traffic to the synthesized IPv6 address
3. **NAT64 gateway** translates the traffic to IPv4 and forwards it

Default resolvers are from [nat64.net](https://nat64.net/public-providers) (Nuremberg, Helsinki, Amsterdam) — close to Hetzner's `fsn1` datacenter.

### Configuration

NAT64/DNS64 is **enabled by default** (`enable_nat64 = true`). Cloud-init configures it on new nodes automatically. For existing nodes, run the Ansible playbook:

```bash
cd ansible
ansible-playbook playbooks/configure-nat64.yml
```

To disable (e.g., if you set up your own DNS):

```hcl
# terraform.tfvars
enable_nat64 = false
```

### Verification

```bash
# DNS64 synthesis (should show AAAA record with 64:ff9b:: prefix)
resolvectl query github.com

# End-to-end connectivity
curl -6 https://github.com
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

```bash
tofu apply
./scripts/generate-ansible-inventory.sh  # update Ansible inventory
```

---

## Server management with Ansible

### Setup

```bash
# Generate inventory
./scripts/generate-ansible-inventory.sh

# Load SSH keys into the agent (must be sourced, not executed)
source ./scripts/ssh-agent-setup.sh

# Test connectivity
cd ansible
ansible all -m ping
```

> **Important**: The ssh-agent must be running with the cluster keys loaded before Ansible can connect. Run `source ./scripts/ssh-agent-setup.sh` in every new terminal session.

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
| `cluster_name` | Prefix for all resources | `k8s-cluster` |
| `location` | Hetzner datacenter | `fsn1` |
| `server_image` | OS image | `debian-13` |
| `master_control_node_type` | Server type for master control node (runs cloudflared) | `cx22` |
| `control_node_types` | Server types/counts for replica control nodes | `[]` |
| `worker_node_types` | Server types/counts for worker nodes | `[]` |
| `enable_public_ipv6` | Enable IPv6 | `true` |
| `admin_user` | SSH username | `kubernetes-admin` |
| `control_node_public_key` | Custom SSH public key for control node | `""` (auto) |
| `worker_node_public_key` | Custom SSH public key for worker nodes | `""` (auto) |
| `cloudflare_tunnel_domain` | Domain for the tunnel | `""` |
| `enable_admin_node` | Enable temporary admin node with public IPv6 | `true` |
| `admin_node_type` | Admin node server type | `cx22` |
| `admin_node_public_key` | Custom SSH public key for admin node | `""` (auto) |
| `enable_nat64` | Enable NAT64/DNS64 for IPv4 reachability | `true` |
| `dns64_resolvers` | DNS64 resolver addresses (nat64.net) | `["2a01:4f8:c2c:123f::1", ...]` |
| `ssh_key_prefix` | Prefix for SSH key filenames (defaults to `cluster_name`) | `""` |
| `enable_k8s_prereqs` | Install Kubernetes prerequisites (containerd, kubeadm, kubelet, kubectl) via cloud-init | `true` |
| `kubernetes_version` | Kubernetes minor version for the pkgs.k8s.io apt source | `"1.32"` |

---

## Project structure

```
hetzner-k8s-cluster/
├── main.tf                          # Infrastructure (providers, network, firewalls, servers)
├── variables.tf                     # All configurable inputs
├── outputs.tf                       # IPs, SSH keys, ssh_config_snippet, next-steps banner
├── terraform.tfvars.example         # Example configuration
├── CLAUDE.md                        # Claude Code project instructions
├── README.md
├── .gitignore
├── .devcontainer/
│   ├── devcontainer.json            # Container config (bind mounts, extensions)
│   └── Dockerfile                   # Debian Trixie with tofu, ansible, cloudflared, jq
├── cloud-init/
│   ├── admin-node.yaml.tpl         # Admin node (temporary jump host with public IPv6)
│   ├── control-node.yaml.tpl       # Control node (cloudflared on master, UFW, fail2ban, k8s prereqs)
│   └── worker-node.yaml.tpl        # Worker node (isolated, outbound DNS/HTTP/S only, k8s prereqs)
├── scripts/
│   ├── setup-ssh.sh                # Export SSH keys from tofu state, generate ~/.ssh/config
│   ├── ssh-agent-setup.sh          # Fix SSH permissions, start ssh-agent, load keys
│   └── generate-ansible-inventory.sh  # Build ansible/inventory.ini from tofu state
├── ansible/
│   ├── ansible.cfg                  # Ansible defaults (user, pipelining, SSH args)
│   ├── inventory.ini                # Auto-generated inventory (do not hand-edit)
│   └── playbooks/
│       ├── update-system.yml        # System updates with optional reboot
│       ├── security-hardening.yml   # Unattended upgrades, fail2ban, sysctl hardening
│       ├── configure-nat64.yml      # NAT64/DNS64 for IPv4 reachability on running nodes
│       └── prepare-k8s-nodes.yml   # Kubernetes prerequisites (containerd, kubeadm) on running nodes
└── doc/
    ├── manual/
    │   └── README.md                # Step-by-step manual setup guide
    └── kubeadm/
        └── README.md                # kubeadm deployment example (OpenClaw)
```

---

## Kubernetes Deployment with kubeadm

After provisioning the infrastructure with OpenTofu and configuring SSH access, deploy a standard Kubernetes cluster using [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) with [Cilium](https://cilium.io/) as the CNI.

### Why kubeadm + Cilium?

- **kubeadm**: The official Kubernetes bootstrapper. Produces a standard, upstream cluster — exactly what the CKA exam expects. Full control over every component (etcd, kube-apiserver, kube-scheduler, kube-controller-manager).
- **Cilium**: eBPF-based CNI providing advanced network policies with FQDN-based egress filtering — critical for restricting outbound traffic per namespace.

### Cost estimate (example: 2-node cluster)

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| Node 1 (CX22, IPv6-only) | 2 vCPU / 4 GB RAM | ~€3.29 |
| Node 2 (CX22, IPv6-only) | 2 vCPU / 4 GB RAM | ~€3.29 |
| Block Volumes (10 GB each) | Hetzner CSI | ~€0.96 |
| Private Network | — | Free |
| Cloudflare Tunnel + Access | Up to 50 users | Free |
| **Total** | | **~€7.54/month** |

Costs vary with server types and volume count. See [Hetzner Cloud pricing](https://www.hetzner.com/cloud/).

### Step 1: Initialize the Control Plane

SSH into the master control node (`10.0.0.2`). Prerequisites (containerd, kubeadm, kubelet, kubectl) are already installed via cloud-init when `enable_k8s_prereqs = true` (default).

#### 1.1 Verify prerequisites

```bash
# Kernel modules loaded
lsmod | grep -E 'overlay|br_netfilter'

# Sysctl parameters
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# containerd running
systemctl status containerd

# kubeadm available
kubeadm version
```

#### 1.2 Initialize with kubeadm

```bash
sudo kubeadm init \
  --apiserver-advertise-address=10.0.0.2 \
  --pod-network-cidr=10.244.0.0/16 \
  --skip-phases=addon/kube-proxy
```

Flags explained:
- `--apiserver-advertise-address=10.0.0.2` — Bind the API server to the private network IP
- `--pod-network-cidr=10.244.0.0/16` — Pod CIDR for Cilium
- `--skip-phases=addon/kube-proxy` — Cilium replaces kube-proxy with eBPF datapath

> **CKA note:** The CKA exam typically uses kube-proxy. This cluster skips it because Cilium provides a more efficient replacement. On the exam, omit `--skip-phases=addon/kube-proxy`.

**What `kubeadm init` does behind the scenes:**
1. Generates PKI certificates (CA, API server, kubelet, etc.) in `/etc/kubernetes/pki/`
2. Writes static pod manifests for etcd, kube-apiserver, kube-controller-manager, kube-scheduler in `/etc/kubernetes/manifests/`
3. Bootstraps etcd and starts the API server
4. Configures RBAC and creates bootstrap tokens
5. Generates `admin.conf` kubeconfig for cluster administration

#### 1.3 Set up kubeconfig

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

#### 1.4 Save join command

```bash
# Print the join command (token valid for 24h)
kubeadm token create --print-join-command
```

Save this output — you'll need it for worker nodes.

#### 1.5 Verify

```bash
# Node will be NotReady until CNI (Cilium) is installed
kubectl get nodes

# Core system pods should be Running (except coredns — needs CNI)
kubectl get pods -n kube-system
```

### Step 2: Join Worker Nodes

SSH into each worker node and run the join command from Step 1.4:

```bash
sudo kubeadm join 10.0.0.2:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

> **CKA explainer — TLS bootstrap:** The worker uses the bootstrap token to authenticate with the API server, then requests a kubelet client certificate. The API server validates the token, signs the certificate, and the kubelet starts using it for all subsequent communication. This is the TLS bootstrap process.

**For HA control plane (replica control nodes):**

```bash
sudo kubeadm join 10.0.0.2:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane --certificate-key <CERT_KEY>
```

Generate the certificate key on the master: `sudo kubeadm init phase upload-certs --upload-certs`

### Step 3: Install Cilium CNI

On the master control node:

```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
tar xzvf cilium-linux-${CLI_ARCH}.tar.gz
sudo mv cilium /usr/local/bin/
rm cilium-linux-${CLI_ARCH}.tar.gz

# Install Cilium (with kube-proxy replacement since we skipped it)
cilium install --version 1.16.5 --set kubeProxyReplacement=true

# Wait for Cilium to be ready
cilium status --wait

# Verify
kubectl get pods -n kube-system | grep cilium
```

After Cilium is ready, all nodes should show `Ready`:

```bash
kubectl get nodes
```

### Step 4: Install Hetzner CSI Driver

The Hetzner CSI driver enables persistent storage via Hetzner Block Volumes.

#### 4.1 Create a dedicated API token

In the Hetzner Cloud Console: **Security** → **API Tokens** → **Generate API Token** (Read & Write). Name it `k8s-csi`.

#### 4.2 Deploy the CSI driver

```bash
# Create secret with API token
kubectl create secret generic hcloud \
  --namespace kube-system \
  --from-literal=token=<YOUR_HETZNER_CSI_API_TOKEN>

# Deploy CSI driver
kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/main/deploy/kubernetes/hcloud-csi.yml

# Set hcloud-volumes as default storage class
kubectl patch storageclass hcloud-volumes \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify
kubectl get storageclass
kubectl get pods -n kube-system | grep hcloud
```

### Step 5: Namespace Isolation and Network Policies

Use namespaces with Cilium network policies to isolate workloads and control egress traffic.

#### 5.1 Create namespaces

```yaml
# namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: system-unrestricted
  labels:
    egress-policy: unrestricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: apps-restricted
  labels:
    egress-policy: restricted
```

```bash
kubectl apply -f namespaces.yaml
```

- **system-unrestricted**: For infrastructure services (cloudflared, monitoring) that need full network access.
- **apps-restricted**: For application workloads with egress locked down to specific destinations.

#### 5.2 Default deny egress for restricted namespace

```yaml
# default-deny-egress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: apps-restricted
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress: []
```

```bash
kubectl apply -f default-deny-egress.yaml
```

#### 5.3 Whitelist specific egress with Cilium

Cilium supports FQDN-based egress rules, allowing fine-grained control over which external services an application can reach:

```yaml
# example-app-egress.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: example-app-egress
  namespace: apps-restricted
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  egress:
    # DNS resolution (required for FQDN rules)
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP

    # Allow internal cluster communication
    - toEntities:
        - cluster

    # Allow specific external API (example)
    - toFQDNs:
        - matchName: "api.example.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

#### 5.4 Unrestricted egress for system namespace

```yaml
# system-unrestricted-egress.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-all-egress
  namespace: system-unrestricted
spec:
  endpointSelector: {}
  egress:
    - toEntities:
        - all
```

```bash
kubectl apply -f system-unrestricted-egress.yaml
```

#### 5.5 Verify network policies

```bash
# Start a test pod in the restricted namespace
kubectl run test --namespace apps-restricted --rm -it --image=alpine -- sh

# Inside the pod:
apk add curl

# Should FAIL (no egress policy for this pod)
curl -v https://google.com

# Exit test pod
exit
```

### Step 6: Cloudflare Tunnel as Kubernetes Workload

The infrastructure provisioning installs `cloudflared` on the master control node as a system service via cloud-init. Alternatively, you can run cloudflared as a Kubernetes deployment for better integration with the cluster:

```yaml
# cloudflared.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-token
  namespace: system-unrestricted
type: Opaque
stringData:
  token: "<YOUR_CLOUDFLARE_TUNNEL_TOKEN>"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: system-unrestricted
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:latest
          args:
            - tunnel
            - --no-autoupdate
            - run
            - --token
            - $(TUNNEL_TOKEN)
          env:
            - name: TUNNEL_TOKEN
              valueFrom:
                secretKeyRef:
                  name: cloudflared-token
                  key: token
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "200m"
```

```bash
kubectl apply -f cloudflared.yaml
```

Advantages over system-level cloudflared:
- Multiple replicas for high availability
- Managed by Kubernetes (auto-restart, resource limits)
- Network policies control its egress

If using this approach, disable the system-level cloudflared installed via cloud-init:

```bash
ssh control-node sudo systemctl stop cloudflared
ssh control-node sudo systemctl disable cloudflared
```

### Step 7: Configure Cloudflare Access

1. Go to **Cloudflare Zero Trust** → **Networks** → **Tunnels** → your tunnel → **Public Hostnames**
2. Map hostnames to internal Kubernetes services:

| Hostname | Service |
|----------|---------|
| `app.yourdomain.com` | `http://my-app.apps-restricted.svc.cluster.local:8080` |

3. Add authentication policies under **Access** → **Applications** to restrict who can reach the services

---

## Maintenance — Upgrade Kubernetes with kubeadm

Kubernetes upgrades follow a strict order: **control plane first, then workers**. This is the standard CKA upgrade workflow.

### Upgrade control plane

```bash
# 1. Unhold packages
sudo apt-mark unhold kubeadm

# 2. Upgrade kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.33.*-*

# 3. Check available upgrade
sudo kubeadm upgrade plan

# 4. Apply the upgrade
sudo kubeadm upgrade apply v1.33.0

# 5. Drain the control node (if running workloads)
kubectl drain $(hostname) --ignore-daemonsets --delete-emptydir-data

# 6. Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.33.*-* kubectl=1.33.*-*
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 7. Uncordon the node
kubectl uncordon $(hostname)
```

### Upgrade worker nodes

On each worker node:

```bash
# 1. From the control plane: drain the worker
kubectl drain <worker-name> --ignore-daemonsets --delete-emptydir-data

# 2. On the worker: upgrade packages
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get update && sudo apt-get install -y kubeadm=1.33.*-* kubelet=1.33.*-* kubectl=1.33.*-*
sudo apt-mark hold kubeadm kubelet kubectl

# 3. Upgrade node config
sudo kubeadm upgrade node

# 4. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 5. From the control plane: uncordon the worker
kubectl uncordon <worker-name>
```

### Backup PVC data

```bash
# Create snapshot via Hetzner Console or API
# Hetzner Console → Volumes → Select volume → Create Snapshot
```

### Useful kubectl commands

```bash
# Check nodes
kubectl get nodes -o wide

# Check all pods across namespaces
kubectl get pods -A

# Check storage
kubectl get pvc -A
kubectl get pv

# Check CSI driver
kubectl get pods -n kube-system | grep hcloud

# Check Cilium status
cilium status

# Check network policies
kubectl get ciliumnetworkpolicies -A

# Logs for cloudflared (if running as K8s workload)
kubectl logs -n system-unrestricted -l app=cloudflared

# Restart a workload
kubectl rollout restart deployment/my-app -n apps-restricted
```

---

## Security Summary

| Layer | Protection |
|-------|------------|
| **Network (Hetzner)** | Firewall blocks all inbound; IPv6-only, no public IPv4 |
| **Network (K8s)** | Cilium egress whitelist per namespace/app (FQDN-based) |
| **Access** | Cloudflare Tunnel (outbound-only connection, no open ports) |
| **Authentication** | Cloudflare Access policies |
| **Container** | Non-root user, dropped capabilities, resource limits |
| **SSH** | Key-only auth, fail2ban, no TCP forwarding on workers |
| **Storage** | Isolated PVCs per workload |

### What this setup protects against

- Direct server attacks (no public IPs, no open inbound ports)
- Unauthorized access (Cloudflare Access + SSH key-only auth)
- Data exfiltration (FQDN-based egress whitelist)
- Lateral movement (namespace isolation, per-pod network policies)
- Resource abuse (container resource limits)

### What to monitor

- API key and token compromise — rotate regularly
- Cloudflare Tunnel health — monitor via Zero Trust dashboard
- Node resource utilization — watch for memory pressure on small instances

---

## Example Application Deployment

For a complete example of deploying an application (OpenClaw) on this cluster — including application-specific Cilium egress rules, StatefulSet with persistent storage, and Cloudflare Tunnel routing — see [`doc/kubeadm/README.md`](doc/kubeadm/README.md).

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
   tofu import hcloud_server.master_control_node <server-id>
   ```

### Worker nodes not joining

```bash
# On the worker node, check kubelet logs
journalctl -xeu kubelet

# Common issues:
# - Swap not disabled: swapoff -a
# - containerd not running: systemctl status containerd
# - Port 6443 not reachable: curl -k https://10.0.0.2:6443
# - Token expired (24h default): kubeadm token create --print-join-command
```

### Cilium pods not ready

```bash
# Check Cilium status
cilium status

# Check Cilium pod logs
kubectl logs -n kube-system -l k8s-app=cilium

# Check Cilium endpoint status
cilium endpoint list
```

### Network policy blocking traffic unexpectedly

```bash
# Check which policies apply
kubectl get ciliumnetworkpolicies -n apps-restricted

# Check if FQDN rules are resolving
kubectl exec -n kube-system -it \
  $(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -1) \
  -- cilium fqdn cache list
```

### CSI volume not attaching

```bash
kubectl describe pvc -n apps-restricted
kubectl get events -n apps-restricted --sort-by='.lastTimestamp'
```

### Pod not starting (general)

```bash
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> --previous
```

---

## License

MIT
