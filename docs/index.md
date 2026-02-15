# KubClaw

**Secure IPv6-only Kubernetes cluster on Hetzner Cloud with Cloudflare Tunnel**

KubClaw automates the creation of a production-ready Kubernetes cluster using OpenTofu for infrastructure provisioning, Ansible for server management, and kubeadm for cluster bootstrapping. The cluster is designed with security-first principles: no public IPv4 addresses, SSH access exclusively through Cloudflare Tunnel, and Cilium-based network policies for fine-grained egress control.

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
│  ┌─────────────────────────────────────────────────────────┐    │
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

- **IPv6-only** -- No public IPv4 addresses required, NAT64/DNS64 for transparent IPv4 reachability
- **Cloudflare Tunnel** -- Secure SSH access without open ports
- **Admin Node** -- Temporary jump host with public IPv6 for initial setup (removable)
- **Scalable** -- Master + replica control nodes, 0 to n worker nodes, mixed server types
- **Custom SSH keys** -- Optionally use your own keys, with configurable key file prefix
- **Ansible-ready** -- Playbooks for updates, hardening, NAT64 configuration, and Kubernetes prerequisites
- **Debian 13** -- Stable, Kubernetes-compatible OS
- **kubeadm** -- Standard Kubernetes bootstrapper for CKA certification preparation
- **Cilium CNI** -- eBPF-based networking with FQDN-based egress filtering

## Getting Started

Ready to deploy? Start with the [Requirements](getting-started/requirements.md) page, then follow the [Quick Start](getting-started/quick-start.md) guide.

## How It Works

1. **OpenTofu** provisions the infrastructure: private network, firewalls, SSH keys, and servers on Hetzner Cloud
2. **Cloud-init** configures each server on first boot: SSH hardening, fail2ban, UFW, NAT64/DNS64, and Kubernetes prerequisites
3. **Ansible** handles ongoing server management: updates, security hardening, and configuration changes
4. **kubeadm** bootstraps a standard Kubernetes cluster with Cilium CNI and Hetzner CSI for persistent storage
5. **Cloudflare Tunnel** provides secure, outbound-only SSH access without exposing any ports
