---
title: Validation and Learning Ledger
weight: 2
description: "Dated evidence separating implemented, exercised, partial, and untested KubeClaw claims."
---

KubeClaw is a prototype, not production software. This ledger distinguishes
code that exists from behaviour that has actually been observed. A claim is
not considered validated merely because its configuration looks plausible.

Last reviewed: **26 July 2026**. The reviewed topology is the repository's
default learning topology: one temporary admin node, one master control node,
optional replicas and workers, no public IPv4, and no production workload.

## Status vocabulary

- **Exercised**: a dated run produced an observed result.
- **Partially tested**: some layers were exercised, but not the complete path.
- **Implemented**: code or documentation exists; runtime behaviour is untested.
- **Untested**: no credible evidence has been recorded.

## Validation matrix

| Capability or assumption | Status | Method and date | Observed result | Unresolved risk / next experiment |
|---|---|---|---|---|
| Local OpenTofu configuration | Exercised | `tofu fmt -check main.tf variables.tf outputs.tf` and `tofu validate`, 26 July 2026, dev container | Formatting and static validation completed successfully | A successful validate does not exercise provider APIs or create infrastructure |
| Ansible playbook syntax | Exercised | `ansible-playbook --syntax-check` for the four shipped playbooks, 26 July 2026, dev container | All four syntax checks completed successfully without a live inventory | Syntax checks do not exercise remote hosts, role behaviour, or idempotency |
| Documentation build | Exercised | `./scripts/build-docs.sh`, 26 July 2026, dev container | Hugo completed a local production build | Browser behaviour and external links remain outside this check |
| Hetzner provisioning | Implemented | Review of OpenTofu resources and cloud-init templates, 26 July 2026 | Network, firewall, key, and node definitions are present | Run `tofu plan`, apply an isolated test topology, redact the plan, and record resource results |
| Cluster bootstrap | Partially tested | Infrastructure and Ansible code review, 26 July 2026 | Node preparation exists; kubeadm deployment remains a guide | Bootstrap a disposable cluster and record node readiness and failure recovery |
| Cloudflare Tunnel access | Implemented | Template and guide review, 26 July 2026 | Token and manual installation paths exist | Verify login, tunnel restart, node replacement, and loss of the temporary admin node |
| No public IPv4 | Implemented | OpenTofu configuration review, 26 July 2026 | Server resources disable public IPv4 | Apply and inspect provider/network state; test that no alternate public IPv4 is attached |
| NAT64/DNS64 | Implemented | Cloud-init and Ansible review, 26 July 2026 | Resolver and `64:ff9b::/96` routing configuration exists | Test IPv4-only package and registry destinations, gateway failure, and DNSSEC-sensitive cases |
| Cilium policy enforcement | Untested | Documentation review, 26 July 2026 | Intended policies are documented but not automated | Deploy policies and record allowed, denied, DNS-changing, and direct-IP egress tests |
| Node replacement and updates | Untested | Operations guide review, 26 July 2026 | Procedures exist | Replace each node role, rotate keys, reboot during updates, and record recovery time |
| State recovery | Untested | State-handling review, 26 July 2026 | Sensitive state and key risks are documented | Test encrypted backup/restore with a disposable state file; never publish state contents |
| Teardown and cost | Implemented | Resource graph and price review, 26 July 2026 | `tofu destroy` path and dated estimates exist | Apply and destroy a disposable topology; compare billed hours and verify no residual resources |

The local OpenTofu and documentation checks are the first reproducible
end-to-end evidence in this ledger. They validate the repository-to-tooling
path only; they do **not** validate a running cluster or its security boundary.

## Reproduce the local evidence

Run these commands inside the project dev container:

```bash
tofu init -backend=false
tofu fmt -check main.tf variables.tf outputs.tf
tofu validate
ansible-playbook --syntax-check ansible/playbooks/update-system.yml
ansible-playbook --syntax-check ansible/playbooks/security-hardening.yml
ansible-playbook --syntax-check ansible/playbooks/configure-nat64.yml
ansible-playbook --syntax-check ansible/playbooks/prepare-k8s-nodes.yml
./scripts/build-docs.sh
```

`tofu init` may contact provider registries. The remaining commands are local
once their dependencies are installed. Redact usernames, hostnames, addresses,
tokens, state, inventories, and endpoints before attaching output to an issue.

## Threat-model boundary

The current design explores network and host isolation for a disposable
learning cluster. It does not claim protection against:

- a malicious cloud, DNS64/NAT64, identity, image, or package provider;
- compromised firmware, hypervisor, workstation, dev container, or maintainer;
- Kubernetes or container-runtime escape vulnerabilities;
- denial of service, billing abuse, traffic analysis, or supply-chain attacks;
- a privileged workload, cluster administrator, or leaked state/credentials.

Controls not yet validated include Cloudflare Access policy enforcement,
Cilium FQDN behaviour under DNS changes, direct-IP bypass resistance,
credential rotation, backup restoration, audit-log completeness, and
adversarial node/workload tests. Do not infer security from the presence of
configuration alone.

## Cost boundary

The [cost estimate]({{< relref "/docs/reference/cost-estimate" >}}) is dated
and describes the default topology. It excludes VAT, traffic overages,
snapshots, backups, domains, paid identity features, developer time, incident
response, and resources accidentally left behind. No billing observation has
yet been recorded; the table is a price-model estimate.

## Learning agenda

The next useful experiments, in order, are:

1. Apply and destroy the smallest disposable topology, recording redacted
   provider results and billed duration.
2. Verify the tunnel path, then remove the temporary admin node and confirm no
   inbound SSH path remains.
3. Bootstrap Kubernetes and test NAT64/DNS64 against representative IPv4-only
   dependencies.
4. Apply Cilium policy and test allowed FQDN, denied FQDN, direct IP, DNS
   change, and policy-restart cases.
5. Replace a node and restore state from an encrypted backup.

## Relationship to ainfra-templates

KubeClaw is donor material and a learning project for
[`projectious-work/ainfra-templates#1`](https://github.com/projectious-work/ainfra-templates/issues/1).
It is **not** the reusable secure template collection. A pattern should move
there only after that project independently reviews it against its stricter
security, portability, testing, and maintenance contract.
