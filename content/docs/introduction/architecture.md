---
title: Architecture
weight: 10
description: Node roles, private network layout, and how traffic reaches an IPv6-only cluster.
---


## Overview

KubeClaw creates a secure, IPv6-only Kubernetes cluster on Hetzner Cloud. The design prioritizes security through network isolation: no public IPv4 addresses, SSH access exclusively via Cloudflare Tunnel, and per-namespace egress control with Cilium network policies.

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
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              Private Network (10.0.0.0/24)                  │ │
│  │                                                             │ │
│  │   ┌─────────────────┐  ┌─────────────────┐                 │ │
│  │   │  control-01     │  │  control-02+    │                 │ │
│  │   │    10.0.0.2     │  │   10.0.0.3+     │                 │ │
│  │   │  (master,       │◄►│  (replicas,     │                 │ │
│  │   │   cloudflared)  │  │   0-n instances) │                 │ │
│  │   └────────┬────────┘  └─────────────────┘                 │ │
│  │            │                                                │ │
│  │            ▼                                                │ │
│  │   ┌─────────────────┐                                       │ │
│  │   │  worker-nodes   │                                       │ │
│  │   │  (0-n instances) │                                       │ │
│  │   └─────────────────┘                                       │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Node Roles

### Master Control Node (control-01, 10.0.0.2)

The master control node always exists and serves as:

- **Kubernetes control plane** -- runs etcd, kube-apiserver, kube-scheduler, kube-controller-manager
- **Cloudflare Tunnel endpoint** -- runs `cloudflared` for SSH access from the internet
- **SSH gateway** -- all other nodes are reached through this node

The master node always has public IPv6 (required for cloudflared outbound connections) and accepts SSH from the private network and from localhost (for the Cloudflare Tunnel). The tunnel can be auto-configured via `cloudflare_tunnel_token` or installed manually.

### Replica Control Nodes (control-02+, 10.0.0.3+)

Optional nodes for high-availability control plane. Same configuration as the master, minus `cloudflared`. IPs start at `10.0.0.3` and increment.

### Worker Nodes (10.0.0.x, offset after replicas)

Optional compute nodes for running workloads. Workers have restricted connectivity:

- **Inbound**: SSH from private network only
- **Outbound**: DNS (port 53), HTTP (port 80), HTTPS (port 443), internal network only
- **No TCP forwarding** -- prevents workers from being used as jump hosts

Worker IPs start after the last replica control node.

### Admin Node (10.0.0.254, temporary)

A temporary jump host with public IPv6, used only during initial setup before the Cloudflare Tunnel is configured. Created by default (`enable_admin_node = true`) and should be disabled after tunnel setup.

## Network Design

### Private Network (10.0.0.0/24)

All nodes communicate via a Hetzner private network. IP assignments:

| Address | Node |
|---------|------|
| `10.0.0.2` | Master control node |
| `10.0.0.3+` | Replica control nodes |
| `10.0.0.x` | Worker nodes (offset after replicas) |
| `10.0.0.254` | Admin node (temporary) |

### IPv6-Only

Nodes have no public IPv4 addresses. The master control node always has public IPv6 (required for cloudflared). Replica control nodes and workers can optionally have public IPv6 disabled via `enable_public_ipv6 = false` to air-gap them from the internet. [NAT64/DNS64]({{< relref "/docs/introduction/dns-and-nat64" >}}) provides transparent IPv4 reachability for accessing IPv4-only services (GitHub, container registries, package repos).

### Traffic Flow

1. **SSH access**: Internet → Cloudflare Tunnel → Master control node (localhost:22) → Private network → Other nodes
2. **Outbound (control nodes)**: Full outbound connectivity via IPv6 + NAT64
3. **Outbound (workers)**: Restricted to DNS, HTTP/S only

## Further Reading

- [DNS and NAT64]({{< relref "/docs/introduction/dns-and-nat64" >}}) -- how IPv6-only nodes reach IPv4 services, CoreDNS configuration, and Kubernetes DNS architecture
- [Security Model]({{< relref "/docs/introduction/security-model" >}}) -- firewall rules, SSH hardening, and Kubernetes-level security
