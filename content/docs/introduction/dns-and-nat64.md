---
title: DNS and NAT64
---


The cluster is IPv6-only -- but many services (GitHub CDN, container registries, package repos) are IPv4-only. **NAT64/DNS64** provides transparent IPv4 reachability at the network layer, no application changes needed. This page covers how DNS64/NAT64 works, how it integrates with Kubernetes CoreDNS, and how to configure it.

## The Problem: IPv4 Internet from IPv6-Only Nodes

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

## How DNS64 + NAT64 Works (Node Level)

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

## DNS Inside the Kubernetes Cluster (Dual-Stack)

With dual-stack networking, every pod gets both an IPv4 address (for internal cluster communication) and an IPv6 address (for external access via DNS64/NAT64). This eliminates the need for `hostNetwork` workarounds:

```
┌──────────────────────────────────────────────────────────────────┐
│  DNS Consumers and Their Resolvers                                │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  Host processes (cloudflared, apt, curl)                     │  │
│  │  /etc/resolv.conf:                                           │  │
│  │    nameserver 10.96.0.10 ◄── CoreDNS ClusterIP              │  │
│  │    nameserver 2a01:4ff:ff00::add:2 ◄── Hetzner DNS          │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  All pods (CoreDNS, CSI, OpenClaw, nginx, ...)              │  │
│  │  /etc/resolv.conf:                                           │  │
│  │    nameserver 10.96.0.10  ◄── CoreDNS ClusterIP             │  │
│  │    search apps-restricted.svc.cluster.local                  │  │
│  │           svc.cluster.local cluster.local                    │  │
│  │                                                               │  │
│  │  Pod IPs: 10.244.x.x (IPv4) + fd00:10:244::x (IPv6)        │  │
│  │  External access: via IPv6 → DNS64/NAT64 → IPv4 internet    │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### CoreDNS: The Bridge Between Cluster and External DNS

CoreDNS runs as a regular pod with dual-stack addresses. It forwards external queries to **DNS64 resolvers**, which synthesize AAAA records for IPv4-only domains. This allows all pods to reach external services via NAT64:

```
┌──────────────────────────────────────────────────────────────────┐
│  CoreDNS Query Flow                                               │
│                                                                    │
│                        CoreDNS (10.96.0.10)                       │
│                        dual-stack pod                              │
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
│                        │  DNS64 resolvers   │──► DNS64 resolver   │
│                        │  2001:67c:2b0::4   │    2001:67c:2b0::4 │
│                        └────────────────────┘    ↓                │
│                                                  Synthesizes AAAA │
│                                                  64:ff9b::8c52:..│
└──────────────────────────────────────────────────────────────────┘
```

### How Pods Reach External Services (Dual-Stack + NAT64)

With dual-stack, pods have IPv6 addresses and can route to the NAT64 prefix. Cilium's IPv6 masquerading translates pod source addresses to the node's public IPv6:

```
┌──────────────────────────────────────────────────────────────────┐
│  Pod Network Connectivity (Dual-Stack)                            │
│                                                                    │
│  Pod (10.244.0.5 + fd00:10:244::5)                               │
│  ├── ✅ → 10.96.0.10 (CoreDNS ClusterIP) ── DNS works            │
│  ├── ✅ → 10.111.194.145 (nginx ClusterIP) ── service routing    │
│  ├── ✅ → 10.0.0.2 (node private IP) ── host reachable           │
│  ├── ✅ → 64:ff9b::8c52:7903 (github.com via NAT64) ── works!   │
│  └── ✅ → 2a00:1450:... (google.com native IPv6) ── works!       │
│                                                                    │
│  Flow for IPv4-only destinations (e.g., api.anthropic.com):      │
│  1. Pod queries CoreDNS → forwards to DNS64 resolver              │
│  2. DNS64 synthesizes: api.anthropic.com → 64:ff9b::6812:0000   │
│  3. Cilium DNS proxy records the FQDN→IP mapping                 │
│  4. Pod sends IPv6 to 64:ff9b::6812:0000                        │
│  5. Cilium masquerades src to node's public IPv6                  │
│  6. NAT64 gateway translates to IPv4 → reaches api.anthropic.com │
│                                                                    │
│  Cilium FQDN policies enforce egress at every step:              │
│  toFQDNs: "api.anthropic.com" → allows 64:ff9b::6812:0000       │
│  All other external traffic is DENIED.                            │
└──────────────────────────────────────────────────────────────────┘
```

### Full DNS Resolution Example: Pod Resolves an External Name

Here's the complete flow when a pod in `apps-restricted` queries `api.anthropic.com`:

```
┌──────────────────────────────────────────────────────────────────┐
│  Complete DNS Flow: Pod → CoreDNS → DNS64 → NAT64                │
│                                                                    │
│  1. Pod sends DNS query                                           │
│     src: 10.244.0.5 → dst: 10.96.0.10:53                        │
│     "What is api.anthropic.com?"                                  │
│          │                                                        │
│          ▼                                                        │
│  2. Cilium DNS proxy intercepts the query                        │
│     Records the FQDN for policy matching                         │
│     Forwards to CoreDNS                                           │
│          │                                                        │
│          ▼                                                        │
│  3. CoreDNS receives query                                        │
│     kubernetes plugin: "api.anthropic.com" ≠ cluster.local        │
│     forward plugin: forward to DNS64 resolver (2001:67c:2b0::4)  │
│          │                                                        │
│          ▼                                                        │
│  4. DNS64 resolver synthesizes AAAA record                        │
│     api.anthropic.com has only A records (104.18.x.x)            │
│     Synthesizes: AAAA 64:ff9b::6812:0000                         │
│          │                                                        │
│          ▼                                                        │
│  5. Cilium DNS proxy records the mapping                          │
│     api.anthropic.com → 64:ff9b::6812:0000                       │
│     toFQDNs rule "api.anthropic.com" now allows this IP          │
│          │                                                        │
│          ▼                                                        │
│  6. Pod connects to 64:ff9b::6812:0000:443                       │
│     Cilium checks egress policy → ALLOWED (FQDN match)           │
│     IPv6 masquerade: src becomes node's public IPv6              │
│     NAT64 gateway translates to IPv4 104.18.x.x                  │
│     ✅ SUCCESS -- pod reaches api.anthropic.com                   │
└──────────────────────────────────────────────────────────────────┘
```

### Full DNS Resolution Example: Host Resolves a Cluster Service

Here's the flow when `cloudflared` (system service on the host) needs to reach a Kubernetes service:

```
┌──────────────────────────────────────────────────────────────────┐
│  Complete DNS Flow: cloudflared → CoreDNS → Kubernetes API        │
│                                                                    │
│  1. cloudflared queries the host's DNS                            │
│     /etc/resolv.conf: nameserver 10.96.0.10 (CoreDNS ClusterIP)  │
│     "What is nginx.apps-restricted.svc.cluster.local?"            │
│          │                                                        │
│          ▼                                                        │
│  2. CoreDNS receives query                                        │
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
| **Host processes** (cloudflared, apt) | CoreDNS (ClusterIP) + Hetzner DNS | Yes (via CoreDNS) | Yes (via Hetzner DNS) | Full (IPv6 + NAT64) |
| **All pods** (CoreDNS, CSI, OpenClaw, etc.) | CoreDNS (10.96.0.10 ClusterIP) | Yes | Yes (AAAA synthesized via DNS64) | Full (IPv6 + NAT64 via masquerade) |
| **Node itself** (DNS64 configured) | DNS64 resolvers (2001:67c:2b0::4) | No | Yes (AAAA synthesized) | Full (IPv6 + NAT64) |

## Configuration

NAT64/DNS64 is **enabled by default** (`enable_nat64 = true`). Cloud-init configures it on new nodes automatically. Default resolvers are from [nat64.net](https://nat64.net/public-providers) (Nuremberg, Helsinki, Amsterdam) -- close to Hetzner's `fsn1` datacenter.

### For existing nodes

Run the Ansible playbook:

```bash
cd ansible
ansible-playbook playbooks/configure-nat64.yml
```

Limit to specific node groups:

```bash
ansible-playbook playbooks/configure-nat64.yml --limit control_nodes
```

Override resolvers:

```bash
ansible-playbook playbooks/configure-nat64.yml \
  -e '{"dns64_resolvers":["2a01:4f8:c2c:123f::1"]}'
```

### Disabling NAT64

If you set up your own DNS infrastructure:

```hcl
# terraform.tfvars
enable_nat64 = false
```

## Verification

```bash
# DNS64 synthesis (should show AAAA record with 64:ff9b:: prefix)
resolvectl query github.com

# End-to-end connectivity
curl -6 https://github.com
```

## Technical Details

### What cloud-init configures

- DNS64 resolvers in `/etc/systemd/resolved.conf.d/dns64.conf`
- NAT64 route: `64:ff9b::/96` via the default IPv6 gateway
- `networkd-dispatcher` script to persist the route across reboots

### What the Ansible playbook configures

The same as cloud-init, plus:

- Removes old Hetzner DNS UFW rules on worker nodes
- Adds DNS64 resolver allow rules in UFW (workers only)
- Adds NAT64 prefix UFW rule (workers only)
- Verifies DNS64 resolution and NAT64 connectivity

### Worker node specifics

Worker nodes have restricted outbound access. The NAT64 configuration adds:

- UFW rules allowing DNS to DNS64 resolvers (instead of Hetzner DNS)
- UFW rule allowing traffic to the `64:ff9b::/96` prefix
