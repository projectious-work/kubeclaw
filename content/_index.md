---
title: KubeClaw
description: "A prototype: exploring a secure, scalable Kubernetes environment for AI agents. A learning project, not a production system."
params:
  body_class: td-navbar-links-all-active
  ui:
    navbar_theme: dark
---

{{% blocks/cover
  title="What does a safe home for AI agents look like?"
  image_anchor="top"
  height="full td-below-navbar"
%}}

<div class="kc-prototype-banner" role="note">
  <span class="kc-prototype-banner__tag">Prototype</span>
  <span class="kc-prototype-banner__text">
    A learning project, not production software. Not beta, not supported,
    not security reviewed.
  </span>
</div>

KubeClaw builds an IPv6-only Kubernetes cluster with strict network boundaries
and outbound-only access, to find out what containing an agentic workload
actually takes.
{.lead .display-6}

<div class="td-cta-buttons my-5">
  <a class="btn btn-lg btn-primary me-3" href="{{< relref "/docs/quick-start" >}}">
    Get started
  </a>
  <a class="btn btn-lg btn-secondary" href="{{< relref "/docs/project-status" >}}">
    Read the project status
  </a>
</div>

{{% /blocks/cover %}}

{{% blocks/lead color="white" %}}

Agentic AI runs arbitrary code with tool access. The interesting question is not
whether that needs a boundary, but which boundary actually holds. KubeClaw is an
attempt to answer that by building one end to end -- OpenTofu provisions the
infrastructure, Ansible maintains it, and Cilium restricts egress to the
services each workload genuinely needs.

{{% /blocks/lead %}}

{{% blocks/section color="light" type="row" %}}

{{% blocks/feature icon="fa-shield-halved" title="Contain the blast radius" %}}

Run agent workloads in isolated Kubernetes namespaces with host hardening,
private networking, and explicit Cilium egress policies.

[Read the security model]({{< relref "/docs/introduction/security-model" >}})

{{% /blocks/feature %}}

{{% blocks/feature icon="fa-network-wired" title="IPv6-first infrastructure" %}}

Provision Hetzner nodes without public IPv4 addresses and use NAT64/DNS64 when
IPv4-only services are unavoidable.

[Read the architecture]({{< relref "/docs/introduction/architecture" >}})

{{% /blocks/feature %}}

{{% blocks/feature icon="fa-flask" title="Built to be taken apart" %}}

Every decision is written down, including the ones that turned out to be wrong.
Read it, disagree with it, and build something better.

[Read the project status]({{< relref "/docs/project-status" >}})

{{% /blocks/feature %}}

{{% /blocks/section %}}

{{% blocks/section color="primary" type="row" %}}

<div class="col-lg-8">
<h2>Take the ideas, not the cluster</h2>
<p class="lead">The documentation is organized around the decisions behind the design, the commands that build it, and the checks that tell you it works. Use it to learn the shape of the problem -- then build a version you have reviewed yourself.</p>
</div>
<div class="col-lg-4 d-flex align-items-center justify-content-lg-end">
<a class="btn btn-lg btn-light" href="{{< relref "/docs/quick-start" >}}">Read the Quick Start</a>
</div>

{{% /blocks/section %}}
