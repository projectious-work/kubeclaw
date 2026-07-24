# Quick Start

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

## Prerequisites

### Accounts

- **Hetzner Cloud account** with an API token ([console.hetzner.cloud](https://console.hetzner.cloud))
- **Cloudflare account** with a configured domain (free tier is sufficient)

### Local Machine

- **Docker** and an IDE with Dev Container support (e.g. VS Code + Dev Containers extension)

That's it. All project tools (OpenTofu, Ansible, SSH, `cloudflared`, Hugo,
Kubernetes clients, and AI assistants) are available in the Dev Container. No
local installation is required beyond Docker and an IDE with Dev Container
support.

### Optional

- **cloudflared** on your local machine for SSH via Cloudflare Tunnel (`brew
  install cloudflared` on macOS). It is included in the Dev Container, but is
  useful on the host if you connect outside the container.
- **Dashlane** or another password manager for storing SSH keys and API tokens securely.

## 1. Clone and prepare

```bash
git clone <repo-url>
cd kubeclaw

# Create the persistent SSH directory used by the aibox Dev Container.
mkdir -p .aibox-home/.ssh
chmod 700 .aibox-home/.ssh
```

## 2. Open in Dev Container

Open the project in your IDE and start the Dev Container (e.g. VS Code: "Reopen in Container").

All remaining commands run **inside the Dev Container**.

## 3. Configure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Hetzner API token and other settings
```

See [Variables Reference](/kubeclaw/docs/reference/variables/) for all available configuration options.

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

This exports SSH keys from the OpenTofu state, generates `~/.ssh/config`
entries, and starts the ssh-agent with the cluster keys loaded. The project
override makes `.aibox-home/.ssh/` writable in the container, so these files
persist across container rebuilds without being committed.

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

- [Deploy Kubernetes with kubeadm](/kubeclaw/docs/guide/kubernetes/)
- [DNS and NAT64](/kubeclaw/docs/introduction/dns-and-nat64/) for IPv4 reachability
- [Server management with Ansible](/kubeclaw/docs/guide/ansible/) for ongoing maintenance
