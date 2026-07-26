# Security Policy

## Read this first

KubeClaw is a **prototype and a learning project**. It has not been security
reviewed or audited, and it carries no assurance of any kind. The
[security model](https://projectious-work.github.io/kubeclaw/docs/introduction/security-model/)
documented on the site describes what the design *intends* to achieve — treat
it as a statement of intent, not a guarantee.

**Do not deploy KubeClaw to handle production traffic, real credentials, or
third-party data.** Assume gaps exist, because they almost certainly do.

## Supported versions

None, in the usual sense. There is no maintained release line and no backported
fixes. Only `main` receives changes.

| Version | Supported |
|---------|-----------|
| `main`  | Best effort |
| `v0.x` tags | No |

## Reporting a vulnerability

Because this is a prototype rather than deployed software, most findings are
best filed as **public issues** — they are more useful as shared learning than
as private disclosures.

Open an issue at
[github.com/projectious-work/kubeclaw/issues](https://github.com/projectious-work/kubeclaw/issues).

If a finding genuinely warrants private handling — for example, it affects
someone who has already deployed this, or it involves a leaked credential in
the repository history — email **bnaard@gmx.net** instead.

Please include:

- What the weakness is and where (file, variable, playbook, or template).
- How it could be exploited, concretely.
- Which assumption in the documented design it breaks.

There is no bounty and no guaranteed response time. This is a personal project
maintained in spare time.

## Known limitations

These are understood and intentional at this stage — reporting them is not
necessary, though improving them is welcome:

- **Kubernetes firewall rules are deliberately absent.** Ports 6443, 10250,
  2379–2380, and 30000–32767 are excluded from the Hetzner firewall until the
  cluster deployment is automated.
- **Auto-generated SSH keys live in OpenTofu state.** State files therefore
  contain private keys and must be protected. Custom keys avoid this.
- **The root password is set through cloud-init** and appears in cloud-init
  logs on the node. It exists only for emergency web-console access.
- **The admin node accepts SSH from anywhere** while enabled. It is intended to
  be temporary — disable it with `enable_admin_node = false` once the
  Cloudflare Tunnel works.
- **Egress policies are documented but not yet automated.** The Cilium FQDN
  policies live in the deployment guides rather than in applied manifests.
- **NAT64 relies on third-party gateways.** The default DNS64 resolvers are
  public services from nat64.net; traffic to IPv4-only destinations transits
  infrastructure this project does not control.

## Secrets in this repository

`terraform.tfvars`, `.aibox-home/`, and generated SSH material are gitignored
and must never be committed. If you believe a secret has been committed, report
it privately using the email above.
