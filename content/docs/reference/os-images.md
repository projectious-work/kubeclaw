---
title: OS Images
weight: 50
description: Hetzner Cloud OS images available for cluster nodes, and why the default is Debian 13.
---


Hetzner Cloud offers the following Debian/Ubuntu images:

| Image | Name | Recommendation |
|-------|------|----------------|
| `debian-13` | Debian 13 Trixie | **Recommended for K8s** |
| `debian-12` | Debian 12 Bookworm | Stable, well-proven |
| `ubuntu-24.04` | Ubuntu 24.04 LTS | Good for K8s |
| `ubuntu-22.04` | Ubuntu 22.04 LTS | Well-proven |

## Why Debian 13?

- **Stability**: long support cycles
- **Compatibility**: the `pkgs.k8s.io` apt repository used for kubeadm, kubelet, and kubectl ships Debian packages
- **Small footprint**: leaner than Ubuntu, but not as small as Alpine
- **No glibc/musl issues**: unlike Alpine, no compatibility problems

Hetzner Cloud doesn't provide dedicated "slim" or "minimal" variants. The standard images are fairly compact already.
