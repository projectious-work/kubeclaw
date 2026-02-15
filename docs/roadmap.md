# Roadmap

## Completed

- Infrastructure provisioning layer (OpenTofu): network, firewalls, SSH keys, cloud-init, admin/control/worker nodes
- SSH config generation with independent admin-node and cloudflare-tunnel entries, IdentitiesOnly fix
- Firewall rules with descriptions; Kubernetes ports excluded until deployment
- NAT64/DNS64 for IPv4 reachability on IPv6-only nodes (cloud-init + Ansible playbook)
- Ansible playbooks for system updates, security hardening, NAT64/DNS64 configuration, and Kubernetes prerequisites
- kubeadm deployment guide with Cilium CNI, Hetzner CSI, namespace isolation, network policies
- OpenClaw deployment guide with application-specific Cilium egress rules
- Dev Container with persistent SSH mount (`.root/.ssh/`)
- MkDocs documentation site with Material theme

## Next Steps

- Deploy infrastructure with `tofu apply` (currently destroyed)
- Set up Cloudflare Tunnel on master control node
- Deploy Kubernetes cluster with kubeadm
- Add Kubernetes-specific firewall rules (6443, 10250, 2379-2380, 30000-32767) to `main.tf` when deploying
- CI/CD pipeline for documentation deployment
- Automated testing for OpenTofu configurations
- Monitoring and alerting setup (Prometheus/Grafana)
