# Architecture

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

Nodes have no public IPv4 addresses. The master control node always has public IPv6 (required for cloudflared). Replica control nodes and workers can optionally have public IPv6 disabled via `enable_public_ipv6 = false` to air-gap them from the internet. [NAT64/DNS64](nat64.md) provides transparent IPv4 reachability for accessing IPv4-only services (GitHub, container registries, package repos).

### Traffic Flow

1. **SSH access**: Internet → Cloudflare Tunnel → Master control node (localhost:22) → Private network → Other nodes
2. **Outbound (control nodes)**: Full outbound connectivity via IPv6 + NAT64
3. **Outbound (workers)**: Restricted to DNS, HTTP/S only

## DNS Architecture

DNS on this cluster involves three layers that work together: **DNS64** for translating IPv4 destinations into IPv6-routable addresses, **CoreDNS** for in-cluster service discovery, and **NAT64** for the actual packet translation. Understanding how these interact is essential for debugging connectivity issues.

### The Problem: IPv4 Internet from IPv6-Only Nodes

The nodes have no public IPv4 addresses. Most internet services (GitHub, Docker Hub, package repos) have IPv4 addresses. How does an IPv6-only node reach them?

```
┌──────────────────────────────────────────────────────────────────┐
│  The Problem                                                      │
│                                                                    │
│  Node (IPv6 only)  ──────╳──────►  github.com (140.82.121.3)    │
│  2a01:4f8:...              │        IPv4 address                  │
│                     No IPv4 route!                                 │
└──────────────────────────────────────────────────────────────────┘
```

The answer is **DNS64 + NAT64**, a standard mechanism (RFC 6146/6147) that gives IPv6-only clients transparent access to IPv4 servers.

### How DNS64 + NAT64 Works (Node Level)

When a node needs to reach an IPv4-only service, the DNS64 resolver synthesizes a special IPv6 address that embeds the IPv4 address:

```
┌──────────────────────────────────────────────────────────────────┐
│  Step 1: DNS64 Resolution                                         │
│                                                                    │
│  Node                    DNS64 Resolver              Authoritative │
│  ┌──────┐               ┌──────────────┐             DNS Server   │
│  │      │──"github.com"─►│              │──"github.com"──►┌─────┐ │
│  │      │  "AAAA?"       │  2001:67c:   │  "AAAA?"        │     │ │
│  │      │                │  2b0::4      │◄── no AAAA ─────│     │ │
│  │      │                │              │──"github.com"──►│     │ │
│  │      │                │              │  "A?"            │     │ │
│  │      │                │              │◄── 140.82.121.3 ─│     │ │
│  │      │                │              │                  └─────┘ │
│  │      │                │  Synthesize: │                          │
│  │      │◄───────────────│  64:ff9b::   │                          │
│  │      │  AAAA record:  │  8c52:7903   │                          │
│  └──────┘  64:ff9b::     └──────────────┘                          │
│            8c52:7903                                               │
│                                                                    │
│  The DNS64 resolver embeds the IPv4 address (140.82.121.3 =       │
│  0x8c527903) into the well-known NAT64 prefix 64:ff9b::/96.      │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  Step 2: NAT64 Translation                                        │
│                                                                    │
│  Node                   NAT64 Gateway              github.com     │
│  ┌──────┐              (nat64.net)                 ┌──────────┐  │
│  │      │──IPv6 pkt───►┌──────────────┐──IPv4 pkt─►│          │  │
│  │      │  dst:        │  Recognizes   │  dst:      │140.82.   │  │
│  │      │  64:ff9b::   │  64:ff9b::    │  140.82.   │121.3     │  │
│  │      │  8c52:7903   │  prefix,      │  121.3     │          │  │
│  │      │              │  extracts     │            │          │  │
│  │      │◄─IPv6 pkt───│  IPv4 addr,   │◄─IPv4 pkt──│          │  │
│  └──────┘              │  translates   │            └──────────┘  │
│                        └──────────────┘                           │
│                                                                    │
│  The node sends IPv6 traffic to 64:ff9b::8c52:7903. The NAT64   │
│  gateway strips the prefix, extracts 140.82.121.3, and forwards  │
│  the packet as regular IPv4. Responses are translated back.      │
└──────────────────────────────────────────────────────────────────┘
```

**Key detail**: DNS64 only synthesizes AAAA records for domains that have **no native AAAA record**. If a domain already has an IPv6 address (like `google.com`), the DNS64 resolver returns the real AAAA record and no synthesis happens.

### DNS Inside the Kubernetes Cluster

Inside the cluster, DNS is more complex because there are two networks and three types of consumers:

```
┌──────────────────────────────────────────────────────────────────┐
│  DNS Consumers and Their Resolvers                                │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  Host processes (cloudflared, apt, curl)                     │  │
│  │  /etc/resolv.conf:                                           │  │
│  │    nameserver 10.0.0.2  ◄── CoreDNS (for cluster names)     │  │
│  │    nameserver 2a01:4ff:ff00::add:2  ◄── Hetzner DNS         │  │
│  │                                         (for external names) │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  Regular pods (nginx, OpenClaw)                              │  │
│  │  /etc/resolv.conf:                                           │  │
│  │    nameserver 10.96.0.10  ◄── CoreDNS ClusterIP             │  │
│  │    search apps-restricted.svc.cluster.local                  │  │
│  │           svc.cluster.local cluster.local                    │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  hostNetwork pods (CoreDNS, CSI controller)                  │  │
│  │  dnsPolicy: Default → uses the host's /etc/resolv.conf      │  │
│  │  These pods have direct IPv6 connectivity to the internet.   │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### CoreDNS: The Bridge Between Cluster and External DNS

CoreDNS runs with `hostNetwork: true` on the master control node, listening on `10.0.0.2:53`. It handles two types of queries differently:

```
┌──────────────────────────────────────────────────────────────────┐
│  CoreDNS Query Flow                                               │
│                                                                    │
│                        CoreDNS (10.0.0.2:53)                      │
│                        hostNetwork: true                           │
│                        ┌────────────────────┐                     │
│                        │                    │                     │
│  Pod queries           │  1. kubernetes     │                     │
│  "nginx.apps-          │     plugin         │                     │
│   restricted.svc.  ───►│     ↓              │                     │
│   cluster.local"       │  Matches           │  ──► 10.111.194.145│
│                        │  cluster.local?    │      (ClusterIP)    │
│                        │  YES → respond     │                     │
│                        │  from K8s API      │                     │
│                        │                    │                     │
│  Pod queries           │  2. forward        │                     │
│  "github.com"      ───►│     plugin         │                     │
│                        │     ↓              │                     │
│                        │  Matches           │                     │
│                        │  cluster.local?    │                     │
│                        │  NO → forward to   │                     │
│                        │  /etc/resolv.conf  │──► Hetzner DNS      │
│                        │  (Hetzner DNS)     │    2a01:4ff:        │
│                        │                    │    ff00::add:2      │
│                        └────────────────────┘    ↓                │
│                                                  Returns A record │
│                                                  (IPv4 address)   │
└──────────────────────────────────────────────────────────────────┘
```

!!! info "Why Hetzner DNS instead of DNS64?"
    CoreDNS forwards to Hetzner's regular DNS servers (from `/etc/resolv.conf`), **not** to DNS64 resolvers. This is because CoreDNS runs on the host network where it can resolve any address, and the node itself uses DNS64 for its own outbound connections. Switching CoreDNS to DNS64 resolvers was tested but caused issues with cluster DNS resolution from the host (see [Cilium IPv6 roadmap](../roadmap/cilium-ipv6.md) for the long-term fix).

### The IPv4 Pod Network Gap

Pods get IPv4 addresses from the Cilium VXLAN overlay (`10.0.0.0/8` range). They can reach other pods, services (via ClusterIP), and the node's private IP. But they **cannot** reach external services directly:

```
┌──────────────────────────────────────────────────────────────────┐
│  Pod Network Connectivity                                         │
│                                                                    │
│  Pod (10.0.0.185)                                                 │
│  ├── ✅ → 10.96.0.10 (CoreDNS ClusterIP) ── DNS works            │
│  ├── ✅ → 10.111.194.145 (nginx ClusterIP) ── service routing    │
│  ├── ✅ → 10.0.0.2 (node private IP) ── host reachable           │
│  ├── ❌ → 140.82.121.3 (github.com IPv4) ── no IPv4 route        │
│  └── ❌ → 2a00:1450:... (google.com IPv6) ── no IPv6 in overlay  │
│                                                                    │
│  hostNetwork pod (CoreDNS, CSI controller)                        │
│  ├── ✅ → all of the above                                        │
│  ├── ✅ → IPv6 internet (via node's IPv6)                         │
│  └── ✅ → IPv4 via NAT64 (via node's DNS64 + NAT64)              │
│                                                                    │
│  This is why CoreDNS and the CSI controller need hostNetwork.     │
│  Regular pods in apps-restricted don't need external access       │
│  (egress is blocked by Cilium anyway). For pods that DO need      │
│  external access, see the hostNetwork pattern or the              │
│  Cilium IPv6 roadmap item.                                        │
└──────────────────────────────────────────────────────────────────┘
```

### Full DNS Resolution Example: Pod Resolves an External Name

Here's the complete flow when a pod in `apps-restricted` queries `api.anthropic.com`:

```
┌──────────────────────────────────────────────────────────────────┐
│  Complete DNS Flow: Pod → CoreDNS → Hetzner DNS                   │
│                                                                    │
│  1. Pod sends DNS query                                           │
│     src: 10.0.0.185 → dst: 10.96.0.10:53                        │
│     "What is api.anthropic.com?"                                  │
│          │                                                        │
│          ▼                                                        │
│  2. Cilium routes ClusterIP to CoreDNS endpoint                   │
│     10.96.0.10 → 10.0.0.2:53 (DNAT)                             │
│          │                                                        │
│          ▼                                                        │
│  3. CoreDNS receives query (hostNetwork, on node)                 │
│     kubernetes plugin: "api.anthropic.com" ≠ cluster.local        │
│     forward plugin: forward to Hetzner DNS                        │
│          │                                                        │
│          ▼                                                        │
│  4. Hetzner DNS resolves                                          │
│     Returns: A 104.18.0.0 (IPv4)                                 │
│          │                                                        │
│          ▼                                                        │
│  5. CoreDNS returns A record to pod                               │
│     Pod receives: api.anthropic.com → 104.18.0.0                 │
│          │                                                        │
│          ▼                                                        │
│  6. Pod tries to connect to 104.18.0.0:443                       │
│     ❌ FAILS -- pod has no IPv4 internet route                    │
│                                                                    │
│  This is why pods needing external access currently require       │
│  hostNetwork: true (which gives them the node's IPv6 + NAT64).   │
│  The Cilium IPv6 roadmap item would fix this by giving pods      │
│  IPv6 addresses so they can use NAT64 natively.                  │
└──────────────────────────────────────────────────────────────────┘
```

### Full DNS Resolution Example: Host Resolves a Cluster Service

Here's the flow when `cloudflared` (system service on the host) needs to reach a Kubernetes service:

```
┌──────────────────────────────────────────────────────────────────┐
│  Complete DNS Flow: cloudflared → CoreDNS → Kubernetes API        │
│                                                                    │
│  1. cloudflared queries the host's DNS                            │
│     /etc/resolv.conf: nameserver 10.0.0.2 (first entry)          │
│     "What is nginx.apps-restricted.svc.cluster.local?"            │
│          │                                                        │
│          ▼                                                        │
│  2. CoreDNS receives query (listening on 10.0.0.2:53)            │
│     kubernetes plugin: matches *.svc.cluster.local                │
│     Queries Kubernetes API for Service "nginx" in                 │
│     namespace "apps-restricted"                                   │
│          │                                                        │
│          ▼                                                        │
│  3. CoreDNS returns ClusterIP                                     │
│     nginx.apps-restricted.svc.cluster.local → 10.111.194.145     │
│          │                                                        │
│          ▼                                                        │
│  4. cloudflared connects to 10.111.194.145:80                    │
│     Cilium routes the ClusterIP to the nginx pod                  │
│     ✅ SUCCESS -- host can reach ClusterIP via Cilium             │
└──────────────────────────────────────────────────────────────────┘
```

### Summary: Who Resolves What

| Consumer | Resolver | Cluster names | External names | External connectivity |
|----------|----------|--------------|----------------|----------------------|
| **Host processes** (cloudflared, apt) | CoreDNS (10.0.0.2) + Hetzner DNS | Yes (via CoreDNS) | Yes (via Hetzner DNS) | Full (IPv6 + NAT64) |
| **Regular pods** | CoreDNS (10.96.0.10 ClusterIP) | Yes | Yes (A records returned) | No (IPv4-only pod network) |
| **hostNetwork pods** (CoreDNS, CSI) | Host's /etc/resolv.conf | Yes (via CoreDNS) | Yes (via Hetzner DNS) | Full (IPv6 + NAT64) |
| **Node itself** (DNS64 configured) | DNS64 resolvers (2001:67c:2b0::4) | No | Yes (AAAA synthesized) | Full (IPv6 + NAT64) |

## Security Model

### Firewall Rules (Hetzner)

- **Control nodes**: SSH from private network + localhost (for tunnel), ICMP from private network
- **Worker nodes**: SSH from private network, ICMP from private network
- **Admin node**: SSH from anywhere (temporary), ICMP from private network

Kubernetes ports (6443, 10250, 2379-2380, 30000-32767) are intentionally excluded from the Hetzner firewall and added only when deploying Kubernetes.

### Host-Level Security

- **SSH hardening**: key-only auth, no root login, limited retries, no TCP forwarding on workers
- **fail2ban**: SSH brute-force protection on all nodes
- **UFW**: host-level firewall enforcing the same rules as the Hetzner firewall

### Kubernetes-Level Security

- **Cilium CNI**: eBPF-based network policies with FQDN egress filtering
- **Namespace isolation**: `system-unrestricted` (full egress) and `apps-restricted` (whitelist-only egress)
- **Container hardening**: non-root users, dropped capabilities, resource limits
