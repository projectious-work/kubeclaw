---
title: KubeClaw
description: Secure, IPv6-first Kubernetes infrastructure for OpenClaw on Hetzner Cloud.
params:
  body_class: td-navbar-links-all-active
  ui:
    navbar_theme: dark
---

{{% blocks/cover
  title="Run OpenClaw with room to breathe."
  image_anchor="top"
  height="full td-below-navbar"
%}}

Kubernetes infrastructure with strict network boundaries, outbound-only access,
and repeatable operations on Hetzner Cloud.
{.lead .display-6}

<div class="td-cta-buttons my-5">
  <a class="btn btn-lg btn-primary me-3" href="{{< relref "/docs/quick-start" >}}">
    Get started
  </a>
  <a class="btn btn-lg btn-secondary" href="{{< relref "/docs/" >}}">
    Explore the docs
  </a>
</div>

{{% /blocks/cover %}}

{{% blocks/lead color="white" %}}

KubeClaw gives agentic workloads a dedicated Kubernetes boundary. OpenTofu
provisions the infrastructure, Ansible keeps it maintained, and Cilium limits
egress to the services each workload actually needs.

{{% /blocks/lead %}}

{{% blocks/section color="light" type="row" %}}

{{% blocks/feature icon="fa-shield-halved" title="Contain the blast radius" %}}

Run OpenClaw in isolated Kubernetes workloads with host hardening, private
networking, and explicit Cilium egress policies.

[Read the security model]({{< relref "/docs/introduction/security-model" >}})

{{% /blocks/feature %}}

{{% blocks/feature icon="fa-network-wired" title="IPv6-first infrastructure" %}}

Provision Hetzner nodes without public IPv4 addresses and use NAT64/DNS64 when
IPv4-only services are unavoidable.

[Read the architecture]({{< relref "/docs/introduction/architecture" >}})

{{% /blocks/feature %}}

{{% blocks/feature icon="fa-arrows-rotate" title="Operate with confidence" %}}

Use repeatable OpenTofu, Ansible, kubeadm, and Cloudflare Tunnel workflows for
day-two operations.

[Read the operations guides]({{< relref "/docs/operations" >}})

{{% /blocks/feature %}}

{{% /blocks/section %}}

{{% blocks/section color="primary" type="row" %}}

<div class="col-lg-8">
<h2>Start with a secure baseline</h2>
<p class="lead">The documentation is organized around the decisions you need to make, the commands you need to run, and the checks that tell you the cluster is ready.</p>
</div>
<div class="col-lg-4 d-flex align-items-center justify-content-lg-end">
<a class="btn btn-lg btn-light" href="{{< relref "/docs/quick-start" >}}">Read the Quick Start</a>
</div>

{{% /blocks/section %}}
