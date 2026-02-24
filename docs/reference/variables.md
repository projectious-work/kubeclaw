# Variables Reference

All configurable inputs for the OpenTofu infrastructure. Set these in `terraform.tfvars`.

## Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `hcloud_token` | `string` | Hetzner Cloud API Token (sensitive) |

## Cluster Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | `string` | `"k8s-cluster"` | Name prefix for all resources |
| `location` | `string` | `"fsn1"` | Hetzner Cloud location (`fsn1`, `nbg1`, `hel1`, `ash`, `hil`) |

## Network Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `network_ip_range` | `string` | `"10.0.0.0/8"` | IP range for the private network |
| `subnet_ip_range` | `string` | `"10.0.0.0/24"` | IP range for the subnet |
| `network_zone` | `string` | `"eu-central"` | Network zone (`eu-central`, `us-east`, `us-west`) |
| `enable_public_ipv6` | `bool` | `true` | Enable public IPv6 for replica control nodes and worker nodes. The master always has public IPv6 (required for cloudflared). Setting to `false` air-gaps replicas and workers. |

## Server Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `server_image` | `string` | `"debian-13"` | Server image to use |
| `master_control_node_type` | `string` | `"cx22"` | Server type for the master control node (runs cloudflared) |
| `control_node_types` | `list(object({type, count}))` | `[]` | Server types and counts for replica control nodes |
| `worker_node_types` | `list(object({type, count}))` | `[]` | Server types and counts for worker nodes |

### Node type examples

```hcl
# Master-only (default)
master_control_node_type = "cx22"
control_node_types = []
worker_node_types  = []

# 3 control nodes + 2 workers
control_node_types = [
  { type = "cx23", count = 2 },
]
worker_node_types = [
  { type = "cx23", count = 2 },
]

# Mixed worker types
worker_node_types = [
  { type = "cx23", count = 2 },
  { type = "cx32", count = 1 },
]
```

## Authentication

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `root_password` | `string` | `"ChangeMe123!"` | Root password for emergency Web-Console access (sensitive) |
| `admin_user` | `string` | `"kubernetes-admin"` | Admin user name for SSH access |
| `keyboard_layout` | `string` | `"de"` | Keyboard layout for cloud-init |

## SSH Keys

If left empty, new keys will be auto-generated and stored in the OpenTofu state. When using custom keys, manage private keys yourself.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `control_node_public_key` | `string` | `""` | Public SSH key for control nodes. Leave empty to auto-generate. |
| `worker_node_public_key` | `string` | `""` | Public SSH key for worker nodes. Leave empty to auto-generate. |
| `admin_node_public_key` | `string` | `""` | Public SSH key for admin node. Leave empty to auto-generate. |
| `ssh_key_prefix` | `string` | `""` | Prefix for SSH key filenames. Defaults to `cluster_name` if empty. |

## Cloudflare Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cloudflare_tunnel_domain` | `string` | `""` | Domain for Cloudflare Tunnel SSH access (e.g., `console.example.org`) |
| `cloudflare_tunnel_token` | `string` | `""` | Cloudflare Tunnel token for automatic setup on master node (sensitive). Leave empty for manual setup. |

## Admin Node

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_admin_node` | `bool` | `true` | Enable a temporary admin node with public IPv6 for initial SSH access. Disable after Cloudflare Tunnel is configured. |
| `admin_node_type` | `string` | `"cx22"` | Server type for admin node |

## NAT64/DNS64

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_nat64` | `bool` | `true` | Enable NAT64/DNS64 for IPv4 reachability on IPv6-only nodes |
| `dns64_resolvers` | `list(string)` | `["2a01:4f8:c2c:123f::1", "2a01:4f9:c010:3f02::1", "2a00:1098:2b::1"]` | DNS64 resolver addresses (nat64.net: Nuremberg, Helsinki, Amsterdam) |

## Kubernetes

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_k8s_prereqs` | `bool` | `true` | Install Kubernetes prerequisites (container runtime, kubeadm, kubelet, kubectl) via cloud-init |
| `kubernetes_version` | `string` | `"1.32"` | Kubernetes minor version for the pkgs.k8s.io apt source |
| `container_runtime` | `string` | `"containerd"` | Container runtime for Kubernetes nodes: `"containerd"` or `"cri-o"` |
