---
title: Project Status
weight: 1
description: "What KubeClaw is, what it is not, and what you should not do with it."
---

## KubeClaw is a prototype

KubeClaw is a **learning project**. Its objective is to explore what a secure,
scalable environment for running AI agents on Kubernetes actually requires --
by building one end to end and finding out where the difficulties are.

It is **not production ready**. It is **not beta**. There is no supported
release, no stability guarantee, and no security review.

## What that means concretely

| | Status |
|---|--------|
| Maturity | Prototype / experiment |
| Suitable for production | **No** |
| Suitable for handling real secrets or customer data | **No** |
| Security reviewed or audited | **No** |
| API / variable stability | None -- variables and layouts change without notice |
| Support | None -- issues may go unanswered |
| Breaking changes | Expected, without a deprecation period |

## Why it exists

Agentic AI workloads execute arbitrary code with tool access. Running them
without an isolation boundary is genuinely risky, and the interesting question
is what a *correct* boundary looks like: which network controls actually hold,
how much egress restriction is practical, what the operational cost is, and
where the design breaks under load.

KubeClaw is an attempt to answer those questions by construction. It combines
IPv6-only Hetzner infrastructure, OpenTofu and Ansible provisioning, kubeadm,
Cilium network policies with FQDN egress filtering, and Cloudflare Tunnel
access. Building the whole path surfaces problems that reading about it does
not.

A secondary objective is preparation for the CKA certification, which is why
the cluster uses kubeadm rather than a turnkey distribution.

## What it is not

- **Not a product.** There is no roadmap commitment and no support channel.
- **Not a reference architecture.** Several decisions are made to be
  instructive rather than optimal.
- **Not hardened.** The security model documented here describes the *intent*
  of the design. It has not been adversarially tested, and you should assume
  gaps exist.
- **Not a template to fork for production.** More mature approaches are
  expected to follow in separate projects, informed by what this one gets
  wrong.

{{< alert title="If you are evaluating this for real work" color="warning" >}}
Please do not deploy KubeClaw to handle production traffic, real credentials,
or third-party data. Read it, take the ideas, and build something you have
reviewed yourself. The infrastructure it provisions is real and costs real
money -- see [Cost Estimate]({{< relref "/docs/reference/cost-estimate" >}})
before running `tofu apply`.
{{< /alert >}}

## Current state

The infrastructure layer is functional: network, firewalls, SSH key handling,
cloud-init, and the admin/control/worker node roles all provision and come up.
NAT64/DNS64, the Ansible playbooks, and the documentation site are in place.

The Kubernetes and OpenClaw layers are documented as guides but are not yet
automated, and the Kubernetes-specific firewall rules are deliberately still
excluded from the OpenTofu configuration. See the
[Roadmap]({{< relref "/docs/roadmap" >}}) for what comes next.

The dated [Validation and Learning Ledger]({{< relref
"/docs/validation-ledger" >}}) records what has been exercised, what is only
implemented, and what remains untested.

## Versioning

Releases use `v0.x` and follow semantic versioning only loosely. While the
major version is `0`, **any release may break any interface**. See the
[changelog](https://github.com/projectious-work/kubeclaw/blob/main/CHANGELOG.md)
for what changed.
