# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
loosely: while the major version is `0`, **any release may break any
interface**. KubeClaw is a prototype — see
[Project Status](https://projectious-work.github.io/kubeclaw/docs/project-status/).

## [Unreleased]

Nothing yet.

## [0.1.1] — 2026-07-26

A maintenance release. No infrastructure behaviour changes — the fixes are to
the documentation site and the contributor toolchain.

### Fixed

- The site favicon now updates when the icon changes. `v0.1.0` shipped the new
  KubeClaw mark correctly, but published it at the same URLs as the previous
  icon. Browsers cache favicons far more aggressively than the served
  `Cache-Control` header and key that cache on URL, so visitors kept seeing the
  old mark indefinitely. Favicon URLs are now content-fingerprinted, so any
  future icon change propagates on the next page load rather than requiring a
  hard refresh.
- Favicon requests to the conventional unfingerprinted paths return the
  KubeClaw mark rather than the Docsy theme's default icons.

### Changed

- Documentation asset installs use `npm ci` against the committed lockfile when
  one is present, falling back to the previous behaviour otherwise.
  `package.json` pins only the five direct dependencies; the lockfile pins all
  65, so Docsy builds are now reproducible from a clean checkout.
- The Dev Container tracks aibox 0.28.12, adds the Claude Code CLI, and drops
  the MkDocs toolchain, which was unused after the move to Hugo and Docsy.

## [0.1.0] — 2026-07-26

First tagged pre-release. The infrastructure layer provisions and comes up; the
Kubernetes and OpenClaw layers are documented as guides but are not yet
automated.

### Added

- **Infrastructure (OpenTofu).** Private network and subnet, role-specific
  Hetzner firewalls with described rules, SSH key handling for both
  auto-generated and user-supplied keys, and cloud-init rendering per node
  role. A master control node always exists; replica control nodes and workers
  are optional and support mixed server types.
- **Admin node.** Temporary jump host with public IPv6 for bootstrap SSH
  access, removable once the Cloudflare Tunnel is configured.
- **Cloudflare Tunnel.** Outbound-only SSH access with no open ports.
  Auto-configurable from `cloudflare_tunnel_token`, surviving node recreation.
- **NAT64/DNS64.** Transparent IPv4 reachability for IPv6-only nodes, via
  cloud-init on first boot and an Ansible playbook for running nodes.
- **Kubernetes prerequisites.** Selectable container runtime (containerd or
  CRI-O), kubeadm, kubelet, and kubectl, installed by cloud-init or Ansible.
- **Ansible playbooks.** System updates, security hardening, NAT64
  configuration, and Kubernetes node preparation, against a generated inventory.
- **Deployment guides.** kubeadm with Cilium CNI and the Hetzner CSI driver;
  OpenClaw with per-namespace FQDN egress policies.
- **Documentation site.** Hugo and Docsy with offline search, versioned
  publishing to GitHub Pages, and the full projectious brand system applied.
- **KubeClaw mark.** Kubernetes heptagon with a claw pincer and accent joint,
  in light, dark, and monochrome variants.
- **Project status page** stating prototype scope, plus open-source project
  files: README, changelog, contributing guide, code of conduct, and security
  policy.

### Fixed

- Restored Hugo's default `assets` and `static` module mounts. Declaring any
  `module.mounts` entry drops the default mount for that component, which had
  silently disabled every project-level brand asset in favour of the theme's.
- Repaired text contrast on dark surfaces. Brand heading colours rendered at
  1.00:1 on the midnight cover, making the landing page hero unreadable. All 27
  text and background pairings now meet WCAG AA.
- Raised code-comment contrast above the AA floor. The brand syntax theme
  specifies a value measuring 3.02:1 on its own code surface; reported upstream
  as [projectious-work/brand#2](https://github.com/projectious-work/brand/issues/2).
- Enabled Goldmark block attributes, which had been rendering markdown
  attribute lists as visible literal text.
- Corrected the OpenClaw project link, which pointed at a non-existent
  repository.
- Updated Hetzner server types from the retired `cx22` generation to the
  current `cx23` line, and refreshed all pricing for the 15 June 2026
  adjustment.
- Added explicit page weights so documentation navigation follows the
  deployment path rather than sorting alphabetically.

[Unreleased]: https://github.com/projectious-work/kubeclaw/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/projectious-work/kubeclaw/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/projectious-work/kubeclaw/releases/tag/v0.1.0
