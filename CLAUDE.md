# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure-as-Code project that provisions a secure, IPv6-only Kubernetes cluster on Hetzner Cloud with SSH access exclusively through Cloudflare Tunnel. Uses **OpenTofu** (Terraform-compatible) for infrastructure provisioning and **Ansible** for server management. The next phase deploys **kubeadm** (chosen over K3s for CKA certification preparation) on the provisioned infrastructure.

**Architecture**: Internet → Cloudflare Tunnel (or temporary Admin Node at 10.0.0.254 with public IPv6) → Master Control Node (10.0.0.2, runs cloudflared) → Private Network (10.0.0.0/24) → Replica Control Nodes (10.0.0.3+) + Worker Nodes (offset after replicas). No public IPv4 addresses; **NAT64/DNS64** (enabled by default) provides transparent IPv4 reachability via DNS64 resolvers from nat64.net and the well-known `64:ff9b::/96` prefix. Workers have no external connectivity except DNS64, NAT64, and HTTP/S for updates. The Admin Node is a temporary jump host (`enable_admin_node = true` by default) that provides public IPv6 SSH access for initial Cloudflare Tunnel setup; disable it after the tunnel is configured. The master control node always exists; replica control nodes and workers are optional and support mixed server types via list-of-objects variables.

## Dev Container (primary workflow)

All work happens inside the Dev Container (Debian Trixie). No tools (tofu, ansible, ssh) need to be installed on the host.

- **Persistent SSH**: `.root/.ssh/` in the project directory is bind-mounted to `/root/.ssh/` in the container. SSH keys, config, and known_hosts survive container rebuilds. Docker bind mounts from macOS don't preserve Unix permissions (files appear as 777), so `ssh-agent-setup.sh` automatically fixes permissions on every run.
- **Persistent Vibe**: `.root/.vibe/` is bind-mounted to `/root/.vibe/`.
- `.root/` is gitignored — never committed.
- After cloning, `mkdir -p .root/.ssh && chmod 700 .root/.ssh` must be run before building the container.
- The ssh-agent runs inside the container: `source ./scripts/ssh-agent-setup.sh`
- Ansible runs inside the container using the persistent SSH keys and agent.

## Key Commands

### Infrastructure (OpenTofu)
```bash
tofu init                    # Initialize providers
tofu plan                    # Preview changes
tofu apply                   # Apply infrastructure changes
tofu destroy                 # Tear down all resources
```

### Post-Apply Setup
```bash
./scripts/setup-ssh.sh                    # Export SSH keys and configure ~/.ssh/config
./scripts/generate-ansible-inventory.sh   # Generate Ansible inventory from Terraform state
source ./scripts/ssh-agent-setup.sh       # Setup ssh-agent (MUST be sourced, not executed)
```

### Ansible Server Management
```bash
cd ansible
ansible all -m ping                                                    # Test connectivity
ansible-playbook playbooks/update-system.yml                           # System updates
ansible-playbook playbooks/update-system.yml -e "reboot_after_update=true"  # Updates + reboot
ansible-playbook playbooks/update-system.yml --limit control_nodes     # Only control node
ansible-playbook playbooks/security-hardening.yml                      # Apply security hardening
```

### NAT64/DNS64 (configure on running nodes)
```bash
cd ansible
ansible-playbook playbooks/configure-nat64.yml                         # All nodes
ansible-playbook playbooks/configure-nat64.yml --limit control_nodes   # Control nodes only
```

### Kubernetes Prerequisites (on running nodes)
```bash
cd ansible
ansible-playbook playbooks/prepare-k8s-nodes.yml                      # All nodes
ansible-playbook playbooks/prepare-k8s-nodes.yml --limit control_nodes # Control nodes only
```

### SSH Key Rotation (auto-generated keys)
```bash
tofu taint 'tls_private_key.control_node[0]'
tofu taint 'tls_private_key.worker_node[0]'
tofu apply
./scripts/setup-ssh.sh
```

### Scaling Nodes
Edit `terraform.tfvars` to change `control_node_types` or `worker_node_types`, then `tofu apply` and `./scripts/generate-ansible-inventory.sh`.

## Architecture & Code Relationships

### Terraform (root level)
- **main.tf** — Core infrastructure: providers, SSH keys (conditional on custom vs auto-generated), network/subnet, firewalls (role-specific with descriptions), servers (master control node + replica control nodes + N workers), cloud-init template rendering. Uses `locals` to flatten `control_node_types` and `worker_node_types` into indexed lists for mixed server type support. Firewalls only include base rules (SSH, ICMP); Kubernetes ports (6443, 10250, 2379-2380, 30000-32767) are intentionally excluded until deployment.
- **variables.tf** — All configurable inputs; required: `hcloud_token`, `root_password`
- **outputs.tf** — Exposes IPs, SSH keys (sensitive), ssh_config_snippet, and a next-steps banner; consumed by `setup-ssh.sh` and `generate-ansible-inventory.sh`. The ssh_config_snippet generates independent Host entries for admin-node (ProxyJump) and cloudflare tunnel (ProxyCommand) — both are generated when both are configured. All entries include `IdentitiesOnly yes` to prevent SSH agent key pollution.
- **terraform.tfvars.example** — Reference config (actual `.tfvars` is gitignored)

### Cloud-Init Templates (`cloud-init/`)
- **admin-node.yaml.tpl** — Minimal jump host: admin user, SSH hardening with `AllowTcpForwarding yes` for ProxyJump, fail2ban, UFW allowing public SSH
- **control-node.yaml.tpl** — Creates admin user, configures UFW (SSH from internal network + localhost for tunnel), fail2ban, SSH hardening. Uses `is_master` boolean: master installs cloudflared and allows localhost SSH; replicas skip cloudflared sections. When `enable_nat64`: configures DNS64 resolvers, NAT64 route, and networkd-dispatcher persistence. When `enable_k8s_prereqs`: installs containerd (with SystemdCgroup), kubeadm, kubelet, kubectl, kernel modules, sysctl params, disables swap, opens kubelet + etcd ports.
- **worker-node.yaml.tpl** — Similar but restrictive: no cloudflared, outbound limited to DNS/HTTP/S only, no TCP forwarding. When `enable_nat64`: uses DNS64 resolvers instead of Hetzner DNS, adds NAT64 prefix UFW rule. When `enable_k8s_prereqs`: same prerequisites as control node (no etcd ports).

### Scripts (`scripts/`)
- **setup-ssh.sh** — Detects tofu/terraform, exports private keys, generates SSH config with backup. Writes to `~/.ssh/` which persists via the `.root/.ssh/` mount.
- **generate-ansible-inventory.sh** — Queries Terraform outputs to build `ansible/inventory.ini` dynamically
- **ssh-agent-setup.sh** — Fixes SSH permissions (bind-mounted dirs default to 777), starts ssh-agent, loads keys; customizable via `CLUSTER_NAME` env var. Run inside the Dev Container for Ansible.

### Ansible (`ansible/`)
- **ansible.cfg** — Remote user: kubernetes-admin, host key checking disabled, become via sudo NOPASSWD
- **inventory.ini** — Auto-generated by script; groups: `control_nodes`, `worker_nodes`, `k8s_cluster`
- Playbooks handle system updates, security hardening (unattended-upgrades, fail2ban, sysctl), NAT64/DNS64 configuration, and Kubernetes prerequisites (containerd, kubeadm, kubelet, kubectl)

### Documentation (`doc/`)
- **doc/kubeadm/README.md** — kubeadm deployment example with OpenClaw application (Cilium egress rules, StatefulSet, Cloudflare Tunnel routing)
- **doc/manual/** — Detailed manual

## Important Conventions

- **Resource naming**: All resources prefixed with `var.cluster_name` (default: "k8s-cluster")
- **Resource labels**: Always include `cluster`, `role`, and `managed="opentofu"` labels on Hetzner resources
- **Firewall rules**: Every rule must have a `description` field
- **Conditional creation**: Use `locals` for boolean logic, then `count` on resources (e.g., SSH keys only created when custom key not provided, worker firewall only when `local.worker_node_count > 0`). Master control node has no count (always exists); replicas use `local.control_node_replica_count`.
- **SSH config generation**: The `ssh_config_snippet` output generates separate Host entries for admin-node access (ProxyJump) and cloudflare tunnel access (ProxyCommand). When both `enable_admin_node` and `cloudflare_tunnel_domain` are set, both entries are generated. The `control-node` Host alias always routes via the available path (admin-node during bootstrap, cloudflare after tunnel setup). All entries include `IdentitiesOnly yes`.
- **SSH key strategy**: Supports both auto-generated (stored in state) and custom keys (user-managed); logic centralized in `local.use_custom_control_key` / `local.use_custom_worker_key` / `local.use_custom_admin_key`. Key filenames use `local.ssh_key_prefix` (defaults to `var.cluster_name`, overridable via `var.ssh_key_prefix`)
- **Cloud-init as `.tpl` files**: Variables injected via `templatefile()` in main.tf
- **Ansible inventory is generated, not hand-edited**: Always regenerate after infrastructure changes
- **Documentation**: All comments and documentation are in English

## Known Quirks

- `keyboard_variant` in cloud-init templates is hardcoded to `"mac"` — may need changing for non-Mac keyboards
- ProxyCommand in generated SSH configs uses `cloudflared` from `$PATH`; ensure it is installed locally (`brew install cloudflared` on macOS, included in the Dev Container)
- Terraform state contains sensitive data (private keys when auto-generated)
- No CI/CD pipelines configured

## Current Project State

### Completed
- Infrastructure provisioning layer (OpenTofu): network, firewalls, SSH keys, cloud-init, admin/control/worker nodes
- SSH config generation with independent admin-node and cloudflare-tunnel entries, IdentitiesOnly fix
- Firewall rules with descriptions; Kubernetes ports removed until deployment
- NAT64/DNS64 for IPv4 reachability on IPv6-only nodes (cloud-init + Ansible playbook)
- Ansible playbooks for system updates, security hardening, and NAT64/DNS64 configuration
- kubeadm deployment guide integrated into README (Cilium CNI, Hetzner CSI, namespace isolation, network policies)
- Dev Container with persistent SSH mount (.root/.ssh/)

### Next Steps
- Deploy infrastructure with `tofu apply` (currently destroyed)
- Set up Cloudflare Tunnel on master control node
- Deploy Kubernetes cluster with kubeadm (replacing K3s for CKA certification preparation)
- Add Kubernetes-specific firewall rules (6443, 10250, 2379-2380, 30000-32767) to main.tf when deploying
