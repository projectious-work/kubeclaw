---
title: Cost Estimate
---


## Example: 2-node cluster

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| Node 1 (CX22, IPv6-only) | 2 vCPU / 4 GB RAM | ~€3.29 |
| Node 2 (CX22, IPv6-only) | 2 vCPU / 4 GB RAM | ~€3.29 |
| Block Volumes (10 GB each) | Hetzner CSI | ~€0.96 |
| Private Network | -- | Free |
| Cloudflare Tunnel + Access | Up to 50 users | Free |
| **Total** | | **~€7.54/month** |

## Notes

- Costs vary with server types and volume count
- IPv6-only nodes are cheaper (no IPv4 address surcharge)
- The admin node (CX22, ~€3.29/month) is temporary and should be deleted after tunnel setup
- Block volumes are billed per GB per month (~€0.048/GB)
- See [Hetzner Cloud pricing](https://www.hetzner.com/cloud/) for current prices

## Scaling costs

| Configuration | Nodes | Estimated Monthly Cost |
|--------------|-------|----------------------|
| Master-only (dev/learning) | 1 | ~€3.29 |
| Master + 1 worker | 2 | ~€6.58 + volumes |
| 3 control + 2 workers (HA) | 5 | ~€16.45 + volumes |
