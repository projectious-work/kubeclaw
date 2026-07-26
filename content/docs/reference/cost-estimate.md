---
title: Cost Estimate
weight: 70
description: Indicative monthly Hetzner Cloud costs for common cluster sizes.
---


All figures are list prices in EUR excluding VAT, current as of the Hetzner
price adjustment of 15 June 2026. Hetzner bills hourly; the monthly figure is
the cap you will not exceed. Always check
[Hetzner Cloud pricing](https://www.hetzner.com/cloud/) before committing --
prices changed several times during 2026.

## Server types

KubeClaw defaults to the cost-optimized **CX** line (shared vCPU, x86). The
**CAX** line offers the same resources on Ampere Arm cores, but is only
available in the German and Finnish locations (`fsn1`, `nbg1`, `hel1`) and
requires `arm64` container images throughout the cluster.

| Type | vCPU | RAM | NVMe | Monthly (excl. IPv4) |
|------|------|-----|------|----------------------|
| `cx23` | 2 | 4 GB | 40 GB | €5.49 |
| `cx33` | 4 | 8 GB | 80 GB | €8.49 |
| `cx43` | 8 | 16 GB | 160 GB | €15.99 |
| `cx53` | 16 | 32 GB | 320 GB | €29.49 |
| `cax11` (Arm) | 2 | 4 GB | 40 GB | €5.99 |
| `cax21` (Arm) | 4 | 8 GB | 80 GB | €10.49 |
| `cax31` (Arm) | 8 | 16 GB | 160 GB | €20.99 |
| `cax41` (Arm) | 16 | 32 GB | 320 GB | €40.99 |

{{< alert title="The CX22 generation is retired" >}}
Earlier revisions of this project defaulted to `cx22`. That generation
(`cx22`/`cx32`/`cx42`/`cx52`) is no longer offered for new orders -- the
current cost-optimized line is `cx23`/`cx33`/`cx43`/`cx53`. Existing servers
keep their original pricing until they are rescaled or recreated.
{{< /alert >}}

The higher-performance **CPX** (dedicated AMD share) and **CCX** (fully
dedicated) lines are considerably more expensive -- `cpx22` is €19.49/month and
`ccx13` is €42.99/month -- and are rarely worth it for a learning or
small-production cluster.

## Additional costs

| Item | Price |
|------|-------|
| Primary IPv4 address | €0.50 per server per month |
| Block storage volume | ~€0.0572 per GB per month |
| Private network | Free |
| Cloudflare Tunnel + Access | Free (up to 50 users) |

{{< alert title="IPv6-only is a real saving" color="success" >}}
KubeClaw provisions every node without a public IPv4 address, which avoids the
€0.50 per server per month primary-IPv4 charge. On a five-node cluster that is
€30/year, and it is the reason [NAT64/DNS64]({{< relref "/docs/introduction/dns-and-nat64" >}})
exists in this project.
{{< /alert >}}

## Example: 2-node cluster

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| Master control node (`cx23`, IPv6-only) | 2 vCPU / 4 GB RAM | €5.49 |
| Worker node (`cx23`, IPv6-only) | 2 vCPU / 4 GB RAM | €5.49 |
| Block volumes (10 GB each) | Hetzner CSI, 20 GB total | ~€1.14 |
| Private network | -- | Free |
| Cloudflare Tunnel + Access | Up to 50 users | Free |
| **Total** | | **~€12.12/month** |

## Scaling costs

Server cost only; add block volumes for any workload that needs persistent
storage.

| Configuration | Nodes | Server cost |
|---------------|-------|-------------|
| Master-only (dev/learning) | 1 | €5.49 |
| Master + 1 worker | 2 | €10.98 |
| 3 control + 2 workers (HA) | 5 | €27.45 |

## Notes

- Estimates exclude VAT, outbound-traffic overages, domains, paid identity
  features, developer time, incident response, and resources accidentally left
  running.
- The admin node (`cx23`, €5.49/month) is temporary. Set
  `enable_admin_node = false` once the Cloudflare Tunnel works, and the charge
  stops -- see [Quick Start]({{< relref "/docs/quick-start" >}}).
- Mixed server types are supported, so workers can be sized independently of
  the control plane. See [Scale Up/Down]({{< relref "/docs/operations/scale-up-down" >}}).
- Snapshots and backups are billed separately and are not included above.
