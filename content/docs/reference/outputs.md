---
title: Outputs Reference
weight: 20
description: Every OpenTofu output, what consumes it, and how to query it.
---


All outputs exposed by the OpenTofu configuration. These are consumed by the setup scripts and can be queried manually.

## Network Information

| Output | Description |
|--------|-------------|
| `network_id` | ID of the private network |
| `network_name` | Name of the private network |

## Cluster Metadata

| Output | Description |
|--------|-------------|
| `cluster_name` | Name of the cluster |
| `admin_user` | Admin user name |
| `ssh_key_prefix` | Prefix used for SSH key filenames |

## Master Control Node

| Output | Description |
|--------|-------------|
| `master_control_node_id` | ID of the master control node |
| `master_control_node_name` | Name of the master control node |
| `master_control_node_private_ip` | Private IP of the master control node |

## All Control Nodes (master + replicas)

| Output | Description |
|--------|-------------|
| `control_node_count` | Total number of control nodes (master + replicas) |
| `control_node_ids` | IDs of all control nodes |
| `control_node_names` | Names of all control nodes |
| `control_node_private_ips` | Private IPs of all control nodes |

## Worker Nodes

| Output | Description |
|--------|-------------|
| `worker_node_count` | Number of worker nodes |
| `worker_node_ids` | IDs of worker nodes |
| `worker_node_names` | Names of worker nodes |
| `worker_node_private_ips` | Private IPs of worker nodes |

## Admin Node

| Output | Description |
|--------|-------------|
| `admin_node_id` | ID of the admin node (null if disabled) |
| `admin_node_name` | Name of the admin node (null if disabled) |
| `admin_node_ipv6` | Public IPv6 address of the admin node (null if disabled) |
| `admin_node_private_ip` | Private IP of the admin node (null if disabled) |
| `enable_admin_node` | Whether the admin node is enabled |

## SSH Keys

These outputs are sensitive when auto-generated keys are used.

| Output | Sensitive | Description |
|--------|-----------|-------------|
| `control_node_ssh_private_key` | Yes | Private SSH key for control nodes (only if auto-generated) |
| `control_node_ssh_public_key` | No | Public SSH key for control nodes |
| `worker_node_ssh_private_key` | Yes | Private SSH key for worker nodes (only if auto-generated) |
| `worker_node_ssh_public_key` | No | Public SSH key for worker nodes |
| `admin_node_ssh_private_key` | Yes | Private SSH key for admin node (only if auto-generated) |
| `admin_node_ssh_public_key` | No | Public SSH key for admin node |
| `using_custom_keys` | No | Map showing which node roles use custom keys |

## SSH Config

| Output | Description |
|--------|-------------|
| `ssh_config_snippet` | SSH config snippet for `~/.ssh/config`. Generates Host entries for admin-node (ProxyJump), cloudflare tunnel (ProxyCommand), and all nodes. All entries include `IdentitiesOnly yes`. |

## Feature Flags

| Output | Description |
|--------|-------------|
| `cloudflare_tunnel_domain` | Configured Cloudflare Tunnel domain |
| `cloudflare_tunnel_configured` | Whether `cloudflare_tunnel_token` was set, i.e. whether cloud-init installed the tunnel automatically |
| `nat64_enabled` | Whether NAT64/DNS64 is enabled |
| `k8s_prereqs_enabled` | Whether Kubernetes prerequisites are installed via cloud-init |

## Next Steps Banner

| Output | Description |
|--------|-------------|
| `next_steps` | Instructions banner displayed after `tofu apply` |

## Querying outputs

```bash
# List all outputs
tofu output

# Get a specific output
tofu output master_control_node_private_ip

# Get a sensitive output (raw)
tofu output -raw control_node_ssh_private_key

# Export SSH key to file
tofu output -raw control_node_ssh_private_key > ~/.ssh/k8s-cluster_control-node_key
chmod 600 ~/.ssh/k8s-cluster_control-node_key
```
