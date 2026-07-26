<div align="center">

<img src="static/logo/kubeclaw-light.svg" alt="KubeClaw" width="96" height="96">

# KubeClaw

**A prototype: what does a safe home for AI agents actually look like?**

[![Status: prototype](https://img.shields.io/badge/status-prototype-E05232)](https://projectious-work.github.io/kubeclaw/docs/project-status/)
[![License: MIT](https://img.shields.io/badge/license-MIT-1d3352)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-projectious--work.github.io-1d3352)](https://projectious-work.github.io/kubeclaw/)

</div>

---

> [!WARNING]
> **KubeClaw is a prototype and a learning project. It is not production ready
> and not beta.**
>
> There is no supported release, no stability guarantee, and no security
> review. Interfaces change without notice. Do not use it for production
> traffic, real credentials, or third-party data. More mature approaches are
> expected to follow in separate projects.
>
> Full detail: [Project Status](https://projectious-work.github.io/kubeclaw/docs/project-status/).

---

## What this is

Agentic AI environments like [OpenClaw](https://github.com/openclaw/openclaw)
execute arbitrary code with tool access — they read files, spawn processes, and
make network requests. Running that without an isolation boundary is genuinely
risky. The interesting question is not *whether* it needs a boundary, but
**which boundary actually holds**.

KubeClaw is an attempt to answer that by building one end to end, and writing
down what breaks. It provisions an IPv6-only Kubernetes cluster on Hetzner
Cloud where agent workloads run under strict network controls:

- **No public IPv4.** Nodes are IPv6-only; NAT64/DNS64 provides transparent
  reachability to IPv4-only services.
- **No inbound SSH.** Access runs through a Cloudflare Tunnel — outbound-only,
  no open ports.
- **Egress allowlists.** Cilium enforces per-namespace FQDN egress policies, so
  an agent reaches the endpoints it needs and nothing else.
- **Reproducible.** OpenTofu provisions, cloud-init configures on first boot,
  and Ansible maintains.

A secondary objective is CKA preparation, which is why the cluster uses
`kubeadm` rather than a turnkey distribution.

## What this is not

- Not a product, a reference architecture, or a template to fork for production.
- Not hardened. The documented security model describes *intent*; it has not
  been adversarially tested.
- Not supported. Issues may go unanswered.

## Architecture at a glance

```
Internet
   │
   ├─ Cloudflare Tunnel ──────┐        (permanent access path)
   │                          ▼
   └─ Admin node ────────►  Master control node  (10.0.0.2, public IPv6)
      (temporary,             │  runs cloudflared
       public IPv6)           │
                              ▼
                     Private network 10.0.0.0/24
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
    Replica control nodes            Worker nodes
    (10.0.0.3+, optional)            (offset after replicas, optional)
```

## Quick start

Everything runs inside the Dev Container — no host tooling beyond Docker and an
IDE with Dev Container support.

```bash
git clone https://github.com/projectious-work/kubeclaw.git
cd kubeclaw
mkdir -p .aibox-home/.ssh && chmod 700 .aibox-home/.ssh
# Reopen in Dev Container, then:

cp terraform.tfvars.example terraform.tfvars   # add your Hetzner API token
tofu init && tofu apply

./scripts/setup-ssh.sh
source ./scripts/ssh-agent-setup.sh
./scripts/generate-ansible-inventory.sh
```

This creates billable infrastructure. See
[Cost Estimate](https://projectious-work.github.io/kubeclaw/docs/reference/cost-estimate/)
first, and the full
[Quick Start](https://projectious-work.github.io/kubeclaw/docs/quick-start/)
for the remaining steps.

## Documentation

Full documentation lives at
**[projectious-work.github.io/kubeclaw](https://projectious-work.github.io/kubeclaw/)**.

| Section | Contents |
|---------|----------|
| [Project Status](https://projectious-work.github.io/kubeclaw/docs/project-status/) | What this is and is not — read first |
| [Introduction](https://projectious-work.github.io/kubeclaw/docs/introduction/) | Architecture, security model, DNS/NAT64 |
| [Guide](https://projectious-work.github.io/kubeclaw/docs/guide/) | Ordered path: Dev Container → OpenClaw |
| [How-to](https://projectious-work.github.io/kubeclaw/docs/how-to/) | Focused procedures |
| [Reference](https://projectious-work.github.io/kubeclaw/docs/reference/) | Variables, outputs, templates, playbooks, costs |
| [Operations](https://projectious-work.github.io/kubeclaw/docs/operations/) | Scaling, rotation, upgrades, troubleshooting |

Build the docs locally with `./scripts/serve-docs.sh` (Hugo + Docsy, port 1313).

## Repository layout

```
main.tf variables.tf outputs.tf   OpenTofu infrastructure
cloud-init/                       First-boot templates per node role
ansible/                          Playbooks: updates, hardening, NAT64, k8s prereqs
scripts/                          SSH setup, inventory generation, docs build/deploy
content/ assets/ layouts/ static/ Hugo + Docsy documentation site
```

## Contributing

This is a personal learning project, so the bar for changes is "does it teach
something" rather than "is it needed in production". Issues and pull requests
are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Security

KubeClaw is a prototype and should not hold anything you care about. If you
find a vulnerability, please see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © Bnaard

Brand and design system © [projectious.work](https://github.com/projectious-work/brand).
The KubeClaw mark is derived from that system.
