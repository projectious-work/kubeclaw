# How to Contribute

Contributions to KubeClaw are welcome! This page outlines how to get involved.

## Getting Started

1. **Fork** the repository
2. **Clone** your fork and set up the [Dev Container](../guide/dev-container.md)
3. **Create a branch** for your changes (`git checkout -b feature/my-feature`)
4. **Make your changes** following the conventions below
5. **Test** your changes
6. **Submit a Pull Request** with a clear description

## Code Conventions

### OpenTofu / Terraform

- **Resource naming**: All resources prefixed with `var.cluster_name` (default: `k8s-cluster`)
- **Resource labels**: Always include `cluster`, `role`, and `managed="opentofu"` labels on Hetzner resources
- **Firewall rules**: Every rule must have a `description` field
- **Conditional creation**: Use `locals` for boolean logic, then `count` on resources
- **Cloud-init as `.tpl` files**: Variables injected via `templatefile()` in `main.tf`

### Ansible

- Playbooks target the `k8s_cluster` host group by default
- Use `--limit` for node-group-specific operations
- Always use fully qualified collection names (e.g., `ansible.builtin.apt`)

### Documentation

- All comments and documentation in English
- Documentation source lives in `docs/` and uses MkDocs with Material theme
- Preview changes with `mkdocs serve` (port 8000)
- Ansible inventory is generated, not hand-edited

## Reporting Issues

Please report issues at the repository's issue tracker. Include:

- Steps to reproduce
- Expected vs actual behavior
- Relevant log output or error messages
- Your environment (OS, OpenTofu version, etc.)

## Areas for Contribution

- Bug fixes and improvements to existing infrastructure code
- Additional Ansible playbooks
- Documentation improvements
- CI/CD pipeline setup
- Testing infrastructure
