---
title: Security Model
---


KubeClaw's security is layered across three levels: Hetzner Cloud firewalls, host-level hardening, and Kubernetes network policies. See [Architecture]({{< relref "/docs/introduction/architecture" >}}) for the overall network design.

## Firewall Rules (Hetzner)

Hetzner Cloud firewalls are the first line of defense. Each node role has its own firewall:

- **Control nodes**: SSH from private network + localhost (for tunnel), ICMP from private network
- **Worker nodes**: SSH from private network, ICMP from private network
- **Admin node**: SSH from anywhere (temporary), ICMP from private network

Kubernetes ports (6443, 10250, 2379-2380, 30000-32767) are intentionally excluded from the Hetzner firewall and added only when deploying Kubernetes.

## Host-Level Security

- **SSH hardening**: key-only auth, no root login, limited retries, no TCP forwarding on workers
- **fail2ban**: SSH brute-force protection on all nodes
- **UFW**: host-level firewall enforcing the same rules as the Hetzner firewall

For operational security details (SSH configuration directives, monitoring, security auditing), see [Operations: Security]({{< relref "/docs/operations/security" >}}).

## Kubernetes-Level Security

- **Cilium CNI**: eBPF-based network policies with FQDN egress filtering
- **Namespace isolation**: `system-unrestricted` (full egress) and `apps-restricted` (whitelist-only egress)
- **Container hardening**: non-root users, dropped capabilities, resource limits
