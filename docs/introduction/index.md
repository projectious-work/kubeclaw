# Introduction

> Understand KubeClaw's architecture, network model, and security boundaries.

---

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

Start here to understand the design decisions behind KubeClaw before provisioning
infrastructure.

---

Section pages:

- [Architecture](/kubeclaw/docs/introduction/architecture/): Node roles, private network layout, and how traffic reaches an IPv6-only cluster.
- [Security Model](/kubeclaw/docs/introduction/security-model/): The three security layers: Hetzner firewalls, host hardening, and Kubernetes network policies.
- [DNS and NAT64](/kubeclaw/docs/introduction/dns-and-nat64/): How DNS64 and NAT64 give IPv6-only nodes and pods transparent access to IPv4-only services.
