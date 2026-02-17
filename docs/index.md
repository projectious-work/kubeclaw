# KubeClaw

**A complete, security-first environment for running [OpenClaw](https://github.com/anthropics/openclaw) safely on remote infrastructure**

Agentic AI environments like OpenClaw execute arbitrary code with tool access -- they can read files, spawn processes, and make network requests. Running such workloads on a local machine or an unsandboxed server is inherently unsafe:

- Agents inherit host-level privileges and can access the entire filesystem, including credentials and private keys
- Without network policy enforcement, agents can exfiltrate data or reach arbitrary endpoints
- A misbehaving agent on a local machine has no isolation boundary; the blast radius is everything on the host
- Containers without network controls only solve half the problem -- an agent with unrestricted egress can still leak data

KubeClaw provides a fully automated Kubernetes cluster on Hetzner Cloud VPS servers where OpenClaw runs inside containers with strict network controls. Infrastructure is managed through **OpenTofu** and **Ansible**, the cluster uses **Cilium CNI** for eBPF-based network policies that enforce per-namespace egress rules (e.g., allowing only Anthropic API and messaging provider endpoints), and all access is routed through a **Cloudflare Tunnel** -- no open ports, no public SSH, outbound-only connectivity.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────────────────────────────────────────┘
                         │              │
                         ▼              ▼
              ┌──────────────┐  ┌───────────────┐
              │  Cloudflare  │  │  Admin Node   │
              │   Tunnel     │  │  10.0.0.254   │
              │  (permanent) │  │  (temporary,  │
              └──────┬───────┘  │  public IPv6) │
                     │          └───────┬───────┘
                     ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Hetzner Cloud                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Private Network (10.0.0.0/24)              │    │
│  │                                                         │    │
│  │   ┌─────────────────┐  ┌─────────────────┐             │    │
│  │   │  control-01     │  │  control-02+    │             │    │
│  │   │    10.0.0.2     │  │   10.0.0.3+     │             │    │
│  │   │  (master,       │◄►│  (replicas,     │             │    │
│  │   │   cloudflared)  │  │   0-n instances) │             │    │
│  │   └────────┬────────┘  └─────────────────┘             │    │
│  │            │                                            │    │
│  │            ▼                                            │    │
│  │   ┌─────────────────┐                                   │    │
│  │   │  worker-nodes   │                                   │    │
│  │   │  (0-n instances) │                                   │    │
│  │   └─────────────────┘                                   │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

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

## Getting Started

Ready to deploy? Start with the [Requirements](getting-started/requirements.md) page, then follow the [Quick Start](getting-started/quick-start.md) guide.

## How It Works

1. **OpenTofu** provisions the infrastructure: private network, firewalls, SSH keys, and servers on Hetzner Cloud
2. **Cloud-init** configures each server on first boot: SSH hardening, fail2ban, UFW, NAT64/DNS64, and Kubernetes prerequisites
3. **Ansible** handles ongoing server management: updates, security hardening, and configuration changes
4. **kubeadm** bootstraps a standard Kubernetes cluster with Cilium CNI and Hetzner CSI for persistent storage
5. **Cloudflare Tunnel** provides secure, outbound-only SSH access without exposing any ports
6. **Cilium network policies** enforce per-namespace egress rules, restricting OpenClaw to only its required API endpoints
