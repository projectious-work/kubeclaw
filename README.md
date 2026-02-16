# KubeClaw

A complete, security-first environment for running [OpenClaw](https://github.com/anthropics/openclaw) safely on remote infrastructure -- because agentic AI workloads should never run uncontained.

## Why KubeClaw?

OpenClaw and similar agentic environments execute arbitrary code with tool access. Running them on a local machine or an unsandboxed server exposes your system to serious risks:

- **Unrestricted filesystem access** -- an agent can read, modify, or delete any file the process can reach, including SSH keys, credentials, and personal data
- **Uncontrolled network egress** -- without enforcement, an agent can exfiltrate data to arbitrary endpoints or download malicious payloads
- **Host-level escape** -- agentic processes that spawn shells or subprocesses inherit host privileges; a single misconfigured permission can compromise the entire machine
- **No blast radius containment** -- on a local machine, there is no isolation boundary; a misbehaving agent affects everything

KubeClaw solves this by providing a fully automated, remote Kubernetes cluster on Hetzner Cloud where OpenClaw runs inside containers with **Cilium network policies** that enforce strict egress rules (e.g., only Anthropic API and Telegram). Infrastructure is provisioned with **OpenTofu**, configured with **Ansible**, and accessed exclusively through a **Cloudflare Tunnel** -- no open ports, no public SSH.

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
│  ┌─────────────────────────────────────────────────────────────┐│
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

- **Container isolation** -- agentic workloads run in Kubernetes pods, never on bare metal or your local machine
- **Cilium network policies** -- eBPF-based FQDN egress filtering limits what an agent can reach on the network
- **Cloudflare Tunnel** -- secure SSH and service access without open ports; outbound-only connectivity
- **IPv6-only** -- no public IPv4, NAT64/DNS64 for transparent IPv4 reachability
- **Scalable** -- master + replica control nodes, 0-n worker nodes, mixed server types
- **kubeadm** -- standard Kubernetes bootstrapper (CKA-ready)
- **Ansible-ready** -- playbooks for updates, hardening, NAT64, K8s prerequisites
- **Dev Container** -- all tools pre-installed, nothing needed on the host

## Requirements

- Hetzner Cloud account with API token
- Cloudflare account with a domain
- Docker + IDE with Dev Container support

## Quick Start

```bash
git clone <repo-url> && cd kubeclaw
mkdir -p .root/.ssh && chmod 700 .root/.ssh
# Open in Dev Container (VS Code: "Reopen in Container")

# Inside the Dev Container:
cp terraform.tfvars.example terraform.tfvars  # edit with your token
# Optional: set cloudflare_tunnel_token in terraform.tfvars for auto-setup
tofu init && tofu apply
./scripts/setup-ssh.sh
ssh control-node
sudo cloudflared service install <TOKEN>  # skip if token is in tfvars
```

See the [full Quick Start guide](docs/getting-started/quick-start.md) for detailed steps.

## Documentation

Full documentation is available via MkDocs:

```bash
mkdocs serve   # http://localhost:8000
```

Key sections:

- [Getting Started](docs/getting-started/quick-start.md) -- requirements, quick start, dev container
- [Architecture](docs/guide/architecture.md) -- network design, node roles, security model
- [Infrastructure](docs/guide/infrastructure.md) -- SSH keys, scaling, OpenTofu workflow
- [Kubernetes](docs/guide/kubernetes.md) -- kubeadm deployment with Cilium and Hetzner CSI
- [Reference](docs/reference/variables.md) -- all variables, outputs, templates, playbooks
- [Operations](docs/operations/troubleshooting.md) -- troubleshooting, security, credentials

## Project Status

**Working**: Infrastructure provisioning (OpenTofu), SSH config generation, NAT64/DNS64, Ansible playbooks (updates, hardening, K8s prerequisites), kubeadm deployment guide, Dev Container, MkDocs documentation.

**Next**: Deploy infrastructure, set up Cloudflare Tunnel, deploy Kubernetes cluster, add K8s firewall rules.

## Contributing

Contributions are welcome. See the [contributing guide](docs/contributing/index.md) for details.

## License

MIT -- see [LICENSE](LICENSE).
