# Project Structure

```
kubeclaw/
├── main.tf                          # Infrastructure (providers, network, firewalls, servers)
├── variables.tf                     # All configurable inputs
├── outputs.tf                       # IPs, SSH keys, ssh_config_snippet, next-steps banner
├── terraform.tfvars.example         # Example configuration
├── mkdocs.yml                       # MkDocs configuration
├── CLAUDE.md                        # Claude Code project instructions
├── README.md                        # Project overview (concise)
├── LICENSE                          # MIT License
├── .gitignore
├── .devcontainer/
│   ├── devcontainer.json            # Container config (bind mounts, extensions, port forwarding)
│   └── Dockerfile                   # Debian Trixie with tofu, ansible, cloudflared, mkdocs, jq
├── cloud-init/
│   ├── admin-node.yaml.tpl         # Admin node (temporary jump host with public IPv6)
│   ├── control-node.yaml.tpl       # Control node (cloudflared on master, UFW, fail2ban, k8s prereqs)
│   └── worker-node.yaml.tpl        # Worker node (isolated, outbound DNS/HTTP/S only, k8s prereqs)
├── scripts/
│   ├── setup-ssh.sh                # Export SSH keys from tofu state, generate ~/.ssh/config
│   ├── ssh-agent-setup.sh          # Fix SSH permissions, start ssh-agent, load keys
│   ├── generate-ansible-inventory.sh  # Build ansible/inventory.ini from tofu state
│   └── deploy-docs.sh             # Build and deploy MkDocs to pages branch
├── ansible/
│   ├── ansible.cfg                  # Ansible defaults (user, pipelining, SSH args)
│   ├── inventory.ini                # Auto-generated inventory (do not hand-edit)
│   └── playbooks/
│       ├── update-system.yml        # System updates with optional reboot
│       ├── security-hardening.yml   # Unattended upgrades, fail2ban, sysctl hardening
│       ├── configure-nat64.yml      # NAT64/DNS64 for IPv4 reachability on running nodes
│       └── prepare-k8s-nodes.yml   # Kubernetes prerequisites (containerd, kubeadm) on running nodes
└── docs/                           # MkDocs documentation source
    ├── index.md                    # Home page
    ├── quick-start.md              # Combined prerequisites + deployment steps
    ├── introduction/
    │   ├── architecture.md          # Node roles, network design, overview diagram
    │   ├── dns-and-nat64.md         # DNS64/NAT64, CoreDNS, Kubernetes DNS architecture
    │   ├── security-model.md        # Firewall rules, SSH hardening, K8s security
    │   └── manual-setup.md
    ├── guide/
    │   ├── dev-container.md        # Step-by-step Dev Container setup
    │   ├── infrastructure.md       # Step-by-step provisioning workflow
    │   ├── ansible.md              # Step-by-step server management
    │   ├── kubernetes.md           # Step-by-step kubeadm deployment
    │   └── openclaw.md             # OpenClaw deployment guide
    ├── how-to/
    │   ├── ssh-keys-with-passphrase.md      # Passphrase protection for SSH keys
    │   └── store-ssh-keys-in-password-manager.md  # Backup keys in password manager
    ├── reference/
    │   ├── variables.md
    │   ├── outputs.md
    │   ├── cloud-init.md
    │   ├── playbooks.md
    │   ├── os-images.md            # Available Hetzner Cloud OS images
    │   ├── project-structure.md
    │   └── cost-estimate.md
    ├── operations/
    │   ├── scale-up-down.md        # Add/remove nodes (infra + K8s)
    │   ├── ssh-key-rotation.md     # Rotate SSH keys
    │   ├── kubernetes-maintenance.md
    │   ├── troubleshooting.md
    │   ├── security.md
    │   └── password-management.md
    ├── roadmap/
    │   ├── index.md                # Roadmap overview
    │   └── cilium-ipv6.md          # Cilium IPv6 pod network plan
    └── contributing/
        ├── index.md
        ├── code-of-conduct.md
        └── development.md
```

## Key Files

### Infrastructure (root level)

| File | Purpose |
|------|---------|
| `main.tf` | Core infrastructure: providers, SSH keys, network/subnet, firewalls, servers, cloud-init rendering |
| `variables.tf` | All configurable inputs with types, defaults, and descriptions |
| `outputs.tf` | Exposes IPs, SSH keys (sensitive), ssh_config_snippet, and next-steps banner |
| `terraform.tfvars.example` | Reference configuration (actual `.tfvars` is gitignored) |

### Cloud-Init Templates

| File | Purpose |
|------|---------|
| `cloud-init/admin-node.yaml.tpl` | Minimal jump host: admin user, SSH hardening, fail2ban, public SSH |
| `cloud-init/control-node.yaml.tpl` | Control plane: cloudflared (master only), UFW, fail2ban, optional NAT64 + K8s prereqs |
| `cloud-init/worker-node.yaml.tpl` | Worker: restrictive UFW, no TCP forwarding, optional NAT64 + K8s prereqs |

### Scripts

| File | Purpose |
|------|---------|
| `scripts/setup-ssh.sh` | Export SSH keys, generate `~/.ssh/config` with backup |
| `scripts/ssh-agent-setup.sh` | Fix SSH permissions, start ssh-agent, load keys |
| `scripts/generate-ansible-inventory.sh` | Build Ansible inventory from OpenTofu state |
| `scripts/deploy-docs.sh` | Build MkDocs and push to `pages` branch |

### Ansible

| File | Purpose |
|------|---------|
| `ansible/ansible.cfg` | Defaults: remote user, host key checking, privilege escalation |
| `ansible/inventory.ini` | Auto-generated inventory with `control_nodes`, `worker_nodes`, `k8s_cluster` groups |
