# Roadmap

## Completed

- Infrastructure provisioning layer (OpenTofu): network, firewalls, SSH keys, cloud-init, admin/control/worker nodes
- SSH config generation with independent admin-node and cloudflare-tunnel entries, IdentitiesOnly fix
- Firewall rules with descriptions; Kubernetes ports excluded until deployment
- NAT64/DNS64 for IPv4 reachability on IPv6-only nodes (cloud-init + Ansible playbook)
- Ansible playbooks for system updates, security hardening, NAT64/DNS64 configuration, and Kubernetes prerequisites
- kubeadm deployment with dual-stack Cilium CNI, Hetzner CSI, namespace isolation, FQDN-based network policies
- Dual-stack pod networking (IPv4 + IPv6) -- all pods can reach external services via DNS64/NAT64 natively
- CoreDNS forwarding to DNS64 resolvers -- no `hostNetwork` workarounds needed
- Cilium FQDN egress policies enforced on all pods including OpenClaw, CoreDNS, and CSI controller
- Cloudflare Tunnel integration with Kubernetes services
- OpenClaw deployment guide with Cilium FQDN egress whitelist, Control UI via Cloudflare Tunnel with Access policies, multi-channel support (Telegram, WhatsApp, Signal)
- Dev Container with persistent SSH mount (`.root/.ssh/`)
- MkDocs documentation site with Material theme

## Next Steps

### Infrastructure & Cluster

- Upgrade Kubernetes from 1.32 to current upstream (1.35) -- update `kubernetes_version` in `variables.tf`, cloud-init templates, and follow the [upgrade procedure](../operations/kubernetes-maintenance.md#upgrade-kubernetes)
- Add Kubernetes-specific firewall rules (6443, 10250, 2379-2380, 30000-32767) to `main.tf`
- CI/CD pipeline for documentation deployment
- Automated testing for OpenTofu configurations

### Security & Access

- Explicit ingress network policies for `apps-restricted` namespace

### Observability

- Monitoring and alerting setup (Prometheus/Grafana)
