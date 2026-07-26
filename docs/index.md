# Documentation

> Guides and reference material for KubeClaw, a prototype environment for running AI agents on Kubernetes.

---

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

**A prototype environment for running [OpenClaw](https://github.com/openclaw/openclaw) and similar AI agents behind a real isolation boundary**

KubeClaw is a learning project, not production software. Before deploying anything, read
[Project Status](/kubeclaw/docs/project-status/).

Agentic AI environments like OpenClaw execute arbitrary code with tool access -- they can read files, spawn processes, and make network requests. Running such workloads on a local machine or an unsandboxed server is inherently unsafe:

- Agents inherit host-level privileges and can access the entire filesystem, including credentials and private keys
- Without network policy enforcement, agents can exfiltrate data or reach arbitrary endpoints
- A misbehaving agent on a local machine has no isolation boundary; the blast radius is everything on the host
- Containers without network controls only solve half the problem -- an agent with unrestricted egress can still leak data

KubeClaw provides a fully automated Kubernetes cluster on Hetzner Cloud VPS servers where OpenClaw runs inside containers with strict network controls. Infrastructure is managed through **OpenTofu** and **Ansible**, the cluster uses **Cilium CNI** for eBPF-based network policies that enforce per-namespace egress rules (e.g., allowing only Anthropic API and messaging provider endpoints), and all access is routed through a **Cloudflare Tunnel** -- no open ports, no public SSH, outbound-only connectivity.

## How it works

1. **OpenTofu** provisions the infrastructure: private network, firewalls, SSH keys, and servers on Hetzner Cloud
2. **Cloud-init** configures each server on first boot: SSH hardening, fail2ban, UFW, NAT64/DNS64, and Kubernetes prerequisites
3. **Ansible** handles ongoing server management: updates, security hardening, and configuration changes
4. **kubeadm** bootstraps a standard Kubernetes cluster with Cilium CNI and Hetzner CSI for persistent storage
5. **Cloudflare Tunnel** provides secure, outbound-only SSH access without exposing any ports
6. **Cilium network policies** enforce per-namespace egress rules, restricting OpenClaw to only its required API endpoints

For the node roles, IP layout, and traffic flow behind this, see
[Architecture](/kubeclaw/docs/introduction/architecture/).

## Features

- **Container isolation** -- Agentic workloads run in Kubernetes pods, never on bare metal or your local machine
- **Cilium network policies** -- eBPF-based FQDN egress filtering limits what an agent can reach on the network
- **Cloudflare Tunnel** -- Secure SSH and service access without open ports; outbound-only connectivity
- **IPv6-only** -- No public IPv4 addresses required, NAT64/DNS64 for transparent IPv4 reachability
- **Admin Node** -- Temporary jump host with public IPv6 for initial setup (removable)
- **Scalable** -- Master + replica control nodes, 0 to n worker nodes, mixed server types
- **Custom SSH keys** -- Optionally use your own keys, with configurable key file prefix
- **Ansible-ready** -- Playbooks for updates, hardening, NAT64 configuration, and Kubernetes prerequisites
- **Debian 13** -- Stable, Kubernetes-compatible OS
- **kubeadm** -- Standard Kubernetes bootstrapper for CKA certification preparation

## Where to start

| If you want to... | Go to |
|-------------------|-------|
| Deploy a cluster now | [Quick Start](/kubeclaw/docs/quick-start/) |
| Understand the design first | [Introduction](/kubeclaw/docs/introduction/) -- architecture, security model, DNS/NAT64 |
| Follow the full deployment path | [Guide](/kubeclaw/docs/guide/) -- Dev Container through OpenClaw, in order |
| Solve one specific task | [How-to](/kubeclaw/docs/how-to/) |
| Look up a variable, output, or template | [Reference](/kubeclaw/docs/reference/) |
| Run the cluster day to day | [Operations](/kubeclaw/docs/operations/) |

---

Section pages:

- [Project Status](/kubeclaw/docs/project-status/): What KubeClaw is, what it is not, and what you should not do with it.
- [Quick Start](/kubeclaw/docs/quick-start/): Provision the cluster end to end: prerequisites, Dev Container, OpenTofu, SSH, and the Cloudflare Tunnel.
- [Introduction](/kubeclaw/docs/introduction/): Understand KubeClaw's architecture, network model, and security boundaries.
- [Guide](/kubeclaw/docs/guide/): Deploy and operate the KubeClaw infrastructure step by step.
- [How-to](/kubeclaw/docs/how-to/): Focused procedures for common KubeClaw tasks.
- [Reference](/kubeclaw/docs/reference/): Configuration, outputs, templates, and project structure reference.
- [Operations](/kubeclaw/docs/operations/): Keep the cluster secure, healthy, and maintainable after deployment.
- [Roadmap](/kubeclaw/docs/roadmap/): Planned improvements and current infrastructure milestones.
- [Contributing](/kubeclaw/docs/contributing/): Help improve KubeClaw and its documentation.
