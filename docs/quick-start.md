# Quick Start

## Prerequisites

### Accounts

- **Hetzner Cloud account** with an API token ([console.hetzner.cloud](https://console.hetzner.cloud))
- **Cloudflare account** with a configured domain (free tier is sufficient)

### Local Machine

- **Docker** and an IDE with Dev Container support (e.g. VS Code + Dev Containers extension)

That's it. All tools (OpenTofu, Ansible, SSH, cloudflared, AI assistants) are pre-installed in the Dev Container -- no local installation needed beyond Docker and your IDE.

### Optional

- **cloudflared** on your local machine for SSH via Cloudflare Tunnel (`brew install cloudflared` on macOS). This is included in the Dev Container but also useful on the host.
- **Dashlane** or another password manager for storing SSH keys and API tokens securely.

## 1. Clone and prepare

```bash
git clone <repo-url>
cd kubeclaw

# Create persistent directories (mounted into the container at /root/.ssh and /root/.vibe)
mkdir -p .root/.ssh
chmod 700 .root/.ssh
```

## 2. Open in Dev Container

Open the project in your IDE and start the Dev Container (e.g. VS Code: "Reopen in Container").

All remaining commands run **inside the Dev Container**.

## 3. Configure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Hetzner API token and other settings
```

See [Variables Reference](reference/variables.md) for all available configuration options.

## 4. Create infrastructure

```bash
tofu init
tofu apply
```

This creates the admin node (temporary jump host), control node, private network, and firewalls. The admin node is enabled by default for initial SSH setup.

## 5. Set up SSH

```bash
./scripts/setup-ssh.sh
source ./scripts/ssh-agent-setup.sh
```

This exports SSH keys from the OpenTofu state, generates `~/.ssh/config` entries, and starts the ssh-agent with the cluster keys loaded. Keys and config are persisted in `.root/.ssh/` across container rebuilds.

## 6. Connect to the control node

```bash
ssh control-node   # Routes via admin node automatically
```

## 7. Install Cloudflare Tunnel

**Option A: Automatic (recommended)** -- Set the tunnel token in `terraform.tfvars` before `tofu apply`:

```hcl
cloudflare_tunnel_token = "eyJ..."
```

Get the token from the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com) under **Networks** > **Tunnels** > **Create/Configure**. The tunnel auto-starts on boot and survives node recreation.

**Option B: Manual** -- SSH to the control node and install manually:

```bash
sudo cloudflared service install <YOUR_TUNNEL_TOKEN>
```

## 8. Disable admin node

After the tunnel is working, disable the temporary admin node:

```hcl
# terraform.tfvars
enable_admin_node = false
```

```bash
tofu apply
```

The master control node always keeps public IPv6 (required for cloudflared).

## Next steps

- [Deploy Kubernetes with kubeadm](guide/kubernetes.md)
- [DNS and NAT64](introduction/dns-and-nat64.md) for IPv4 reachability
- [Server management with Ansible](guide/ansible.md) for ongoing maintenance
