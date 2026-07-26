# Quick Start

> Provision the cluster end to end: prerequisites, Dev Container, OpenTofu, SSH, and the Cloudflare Tunnel.

---

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

<div class="alert alert-warning" role="alert"><div class="h4 alert-heading" role="heading">This provisions real, billable infrastructure</div>


KubeClaw is a [prototype](/kubeclaw/docs/project-status/) -- a learning
project, not production software. The steps below create servers on Hetzner
Cloud that cost real money, and the resulting cluster has not been security
reviewed. Do not use it for production traffic, real credentials, or
third-party data.
</div>


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
./scripts/generate-ansible-inventory.sh
```

This exports SSH keys from the OpenTofu state, generates `~/.ssh/config`
entries, starts the ssh-agent with the cluster keys loaded, and builds
`ansible/inventory.ini` from the current state. The project override makes
`.aibox-home/.ssh/` writable in the container, so these files persist across
container rebuilds without being committed.

<div class="alert alert-primary" role="alert"><div class="h4 alert-heading" role="heading">Rerun after every infrastructure change</div>


`generate-ansible-inventory.sh` reads the OpenTofu outputs. Run it again after
any `tofu apply` that adds or removes nodes -- never hand-edit
`ansible/inventory.ini`.
</div>


## 6. Connect to the control node

```bash
ssh control-node   # Routes via admin node automatically
```

## 7. Install Cloudflare Tunnel

Creating the tunnel, routing SSH through it, and adding an Access policy are
covered step by step in the [Cloudflare Tunnel Setup](/kubeclaw/docs/guide/cloudflare-tunnel/)
guide. Once you have a tunnel token, install it one of two ways.

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

- [Server management with Ansible](/kubeclaw/docs/guide/ansible/) -- updates, hardening, and Kubernetes prerequisites
- [Deploy Kubernetes with kubeadm](/kubeclaw/docs/guide/kubernetes/)
- [Deploy OpenClaw](/kubeclaw/docs/guide/openclaw/) into an egress-restricted namespace
- [DNS and NAT64](/kubeclaw/docs/introduction/dns-and-nat64/) for IPv4 reachability
