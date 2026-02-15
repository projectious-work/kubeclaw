# Quick Start

## 1. Clone and prepare

```bash
git clone <repo-url>
cd hetzner-k8s-cluster

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

See [Variables Reference](../reference/variables.md) for all available configuration options.

## 4. Create infrastructure

```bash
tofu init
tofu apply
```

This creates the admin node (temporary jump host), control node, private network, and firewalls. The admin node is enabled by default for initial SSH setup.

## 5. Set up SSH

```bash
./scripts/setup-ssh.sh
```

This exports SSH keys from the OpenTofu state and generates `~/.ssh/config` entries. Keys and config are persisted in `.root/.ssh/` across container rebuilds.

## 6. Connect to the control node

```bash
ssh control-node   # Routes via admin node automatically
```

## 7. Install Cloudflare Tunnel

On the control node:

```bash
sudo cloudflared service install <YOUR_TUNNEL_TOKEN>
```

Get the tunnel token from the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com) under **Networks** > **Tunnels**.

## 8. Disable admin node

After the tunnel is working, disable the temporary admin node and public IPv6:

```hcl
# terraform.tfvars
enable_admin_node  = false
enable_public_ipv6 = false
```

```bash
tofu apply
```

## Next steps

- [Deploy Kubernetes with kubeadm](../guide/kubernetes.md)
- [Configure NAT64/DNS64](../guide/nat64.md) for IPv4 reachability
- [Server management with Ansible](../guide/ansible.md) for ongoing maintenance
