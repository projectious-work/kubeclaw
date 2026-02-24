# Cloud-Init Templates

Cloud-init templates are located in `cloud-init/` and rendered by OpenTofu via `templatefile()` in `main.tf`. They configure each server on first boot.

## admin-node.yaml.tpl

**Purpose**: Minimal jump host for initial SSH access.

**Used by**: `hcloud_server.admin_node`

**Template variables**:

| Variable | Source |
|----------|--------|
| `ssh_public_key` | `local.admin_node_public_key` |
| `root_password` | `var.root_password` |
| `admin_user` | `var.admin_user` |
| `keyboard_layout` | `var.keyboard_layout` |

**What it configures**:

- Admin user with sudo NOPASSWD
- SSH hardening with `AllowTcpForwarding yes` (needed for ProxyJump)
- fail2ban for SSH protection
- UFW allowing public SSH (port 22 from anywhere)

## control-node.yaml.tpl

**Purpose**: Kubernetes control plane node with optional Cloudflare Tunnel.

**Used by**: `hcloud_server.master_control_node`, `hcloud_server.control_node_replica`

**Template variables**:

| Variable | Source |
|----------|--------|
| `ssh_public_key` | `local.control_node_public_key` |
| `root_password` | `var.root_password` |
| `admin_user` | `var.admin_user` |
| `keyboard_layout` | `var.keyboard_layout` |
| `is_master` | `true` for master, `false` for replicas |
| `enable_nat64` | `var.enable_nat64` |
| `dns64_resolvers` | `var.dns64_resolvers` |
| `enable_k8s_prereqs` | `var.enable_k8s_prereqs` |
| `kubernetes_version` | `var.kubernetes_version` |
| `container_runtime` | `var.container_runtime` |
| `cloudflare_tunnel_token` | `var.cloudflare_tunnel_token` (master), `""` (replicas) |

**What it configures**:

- Admin user with sudo NOPASSWD and root password for emergency console access
- SSH hardening (key-only auth, `AllowTcpForwarding yes`)
- fail2ban for SSH protection
- UFW: SSH from internal network (`10.0.0.0/8`) + localhost (for Cloudflare Tunnel)

**Conditional sections**:

- **`is_master = true`**: Installs `cloudflared`, allows SSH from localhost, creates `/etc/cloudflared/config.yml` with `edge-ip-version: "6"`. When `cloudflare_tunnel_token` is set, runs `cloudflared service install <token>` to auto-configure the tunnel as a systemd service.
- **`is_master = false`**: Skips cloudflared installation (token always empty for replicas)
- **`enable_nat64 = true`**: Configures DNS64 resolvers in systemd-resolved, adds NAT64 route (`64:ff9b::/96`), creates networkd-dispatcher persistence script
- **`enable_k8s_prereqs = true`**: Installs the selected container runtime (`containerd` with SystemdCgroup and sandbox image fix, or `cri-o` from OBS repo with kubelet socket configuration), kubeadm, kubelet, kubectl, loads kernel modules (`overlay`, `br_netfilter`), sets sysctl params, disables swap, opens kubelet (10250) + etcd (2379-2380) ports

## worker-node.yaml.tpl

**Purpose**: Kubernetes worker node with restricted network access.

**Used by**: `hcloud_server.worker_node`

**Template variables**:

| Variable | Source |
|----------|--------|
| `ssh_public_key` | `local.worker_node_public_key` |
| `root_password` | `var.root_password` |
| `admin_user` | `var.admin_user` |
| `keyboard_layout` | `var.keyboard_layout` |
| `enable_nat64` | `var.enable_nat64` |
| `dns64_resolvers` | `var.dns64_resolvers` |
| `enable_k8s_prereqs` | `var.enable_k8s_prereqs` |
| `kubernetes_version` | `var.kubernetes_version` |
| `container_runtime` | `var.container_runtime` |

**What it configures**:

- Admin user with sudo NOPASSWD and root password for emergency console access
- SSH hardening with `AllowTcpForwarding no` (workers cannot be used as jump hosts)
- fail2ban for SSH protection
- UFW: deny all by default, SSH from internal network only, outbound limited to DNS + HTTP/S

**Conditional sections**:

- **`enable_nat64 = true`**: Uses DNS64 resolvers instead of Hetzner DNS, adds NAT64 prefix UFW rule
- **`enable_k8s_prereqs = true`**: Same as control node prerequisites (runtime selected by `container_runtime`), but without etcd ports

## Template rendering

Templates are rendered in `main.tf` via `templatefile()`:

```hcl
user_data = templatefile("${path.module}/cloud-init/control-node.yaml.tpl", {
  ssh_public_key         = local.control_node_public_key
  root_password          = var.root_password
  admin_user             = var.admin_user
  keyboard_layout        = var.keyboard_layout
  is_master              = true
  enable_nat64           = var.enable_nat64
  dns64_resolvers        = var.dns64_resolvers
  enable_k8s_prereqs     = var.enable_k8s_prereqs
  kubernetes_version     = var.kubernetes_version
  container_runtime      = var.container_runtime
  cloudflare_tunnel_token = var.cloudflare_tunnel_token
})
```

!!! note
    The `lifecycle { ignore_changes = [user_data] }` block on all servers prevents re-provisioning when template variables change. Cloud-init only runs on first boot. Use [Ansible playbooks](playbooks.md) for configuration changes on running nodes.
