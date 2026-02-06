# Hetzner Cloud Kubernetes Cluster with OpenTofu

This project automatically provisions a secure, IPv6-only Kubernetes cluster on Hetzner Cloud with SSH access via a Cloudflare Tunnel.

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
│  │   │  control-node   │       │  worker-node    │        │    │
│  │   │    10.0.0.2     │◄─────►│    10.0.0.3+    │        │    │
│  │   │  (cloudflared)  │       │  (isolated)     │        │    │
│  │   └─────────────────┘       └─────────────────┘        │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Requirements

- [OpenTofu](https://opentofu.org/) >= 1.6.0 (or Terraform >= 1.5.0)
- Hetzner Cloud account with an API token
- Cloudflare account with a configured domain
- `cloudflared` installed on your local machine

## Quick Start

### 1. Clone the repository / copy files

```bash
git clone <repository-url>
cd tofu-hetzner-cluster
```

### 2. Adjust configuration

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Important: Replace at least the following:
- `hcloud_token` - your Hetzner API token
- `cloudflare_tunnel_domain` - your domain (e.g. `console.example.org`)
- `root_password` - a secure password

### 3. Create the infrastructure

```bash
# Initialize
tofu init

# Review plan
tofu plan

# Apply
tofu apply
```

### 4. Export SSH keys

```bash
# Export private keys
tofu output -raw control_node_ssh_private_key > ~/.ssh/k3s-cluster_control-node_key
tofu output -raw worker_node_ssh_private_key > ~/.ssh/k3s-cluster_worker-node_key

# Set permissions
chmod 600 ~/.ssh/k3s-cluster_*_key
```

### 5. Set up SSH config

```bash
tofu output -raw ssh_config_snippet >> ~/.ssh/config
```

### 6. Connect to the control node (IPv6)

```bash
# Use the IPv6 address from the outputs
ssh -i ~/.ssh/k3s-cluster_control-node_key kubernetes-admin@<ipv6-address>
```

### 7. Install Cloudflare Tunnel

On the control node:

```bash
sudo cloudflared service install <YOUR_TUNNEL_TOKEN>
sudo systemctl status cloudflared
```

### 8. Disable public IPs

After the tunnel is successfully set up:

```bash
# Change in terraform.tfvars:
# enable_public_ipv6 = false

tofu apply
```

## Setting up the Cloudflare Tunnel

### In the Cloudflare Zero Trust Dashboard

1. **Networks → Tunnels → Create a tunnel**
2. Give it a name, copy the token
3. **Add a Public Hostname:**
   - Subdomain: `console`
   - Domain: your domain
   - Type: `SSH`
   - URL: `localhost:22`

4. **Access → Applications → Add application**
   - Self-hosted
   - Domain: `console.example.org`
   - Create a policy (e.g. allowlist by email)

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `hcloud_token` | Hetzner API token | - |
| `cluster_name` | Prefix for all resources | `k3s-cluster` |
| `location` | Hetzner datacenter | `fsn1` |
| `control_node_type` | Control node server type | `cx22` |
| `worker_node_type` | Worker node server type | `cx22` |
| `worker_node_count` | Number of worker nodes | `1` |
| `enable_public_ipv6` | Enable IPv6 | `true` |
| `admin_user` | SSH username | `kubernetes-admin` |
| `cloudflare_tunnel_domain` | Domain for the tunnel | `` |

## Outputs

| Output | Description |
|--------|-------------|
| `control_node_ipv6` | IPv6 address of the control node |
| `control_node_private_ip` | Private IP of the control node |
| `worker_node_private_ips` | Private IPs of the worker nodes |
| `control_node_ssh_private_key` | SSH private key (sensitive) |
| `ssh_config_snippet` | Ready-to-use SSH config |
| `next_steps` | Instructions for next steps |

## Files

```
.
├── main.tf                     # Main configuration
├── variables.tf                # Variable definitions
├── outputs.tf                  # Output definitions
├── terraform.tfvars.example    # Example configuration
├── .gitignore                  # Git ignore rules
├── README.md                   # This file (original language)
└── cloud-init/
    ├── control-node.yaml.tpl   # Cloud-init template for control node
    └── worker-node.yaml.tpl    # Cloud-init template for worker node
```

## Security Notes

- **API tokens:** Never commit to Git
- **terraform.tfvars:** Contains sensitive data; do not commit
- **SSH keys:** Are generated automatically; store them securely
- **Root password:** Only use for emergency access via the web console

## Destroying resources

```bash
tofu destroy
```

**Warning:** This will irreversibly delete all created servers, networks, and firewalls!

## Troubleshooting

### cloudflared won't start

Check that `/etc/cloudflared/config.yml` contains:

```yaml
edge-ip-version: "6"
```

### SSH connection fails

1. Check that `cloudflared` is installed locally
2. Verify the path in the SSH config (`/opt/homebrew/bin/cloudflared` for Apple Silicon)
3. Ensure the tunnel shows as "Connected" in Cloudflare

### Worker node unreachable

1. Verify the control node is running
2. Confirm ProxyJump in the SSH config is set correctly
3. Test ping from the control node: `ping 10.0.0.3`

## License

MIT
