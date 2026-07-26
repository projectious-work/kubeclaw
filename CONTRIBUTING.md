# Contributing to KubeClaw

Thanks for looking. Before anything else, please read
[Project Status](https://projectious-work.github.io/kubeclaw/docs/project-status/):
KubeClaw is a prototype and a learning project, not production software. That
shapes what changes make sense here.

The bar for a change is **"does it teach something or make the project more
honest"**, not "is it needed in production". Simplifications, corrections, and
"this assumption is wrong because…" are all more valuable than new features.

## Ways to help

- **Corrections.** If the documentation claims something the code does not do,
  that is a bug worth reporting. Several such gaps have already been found this
  way.
- **Security observations.** The design has not been audited. If you can see a
  way the isolation boundary fails, please say so — see [SECURITY.md](SECURITY.md).
- **Cost and provider drift.** Hetzner's catalogue and pricing change; the
  documented figures go stale.
- **Clarity.** If an explanation did not land for you, that is useful feedback.

## Development setup

All work happens inside the Dev Container — no host tooling beyond Docker and
an IDE with Dev Container support.

```bash
git clone https://github.com/projectious-work/kubeclaw.git
cd kubeclaw
mkdir -p .aibox-home/.ssh && chmod 700 .aibox-home/.ssh
# Reopen in Dev Container
```

Full detail: [Development Setup](https://projectious-work.github.io/kubeclaw/docs/contributing/development/).

### Documentation

```bash
./scripts/serve-docs.sh    # preview at http://localhost:1313
./scripts/build-docs.sh    # build the site
./scripts/deploy-docs.sh   # publish to the gh-pages branch
```

### Infrastructure

```bash
tofu fmt      # format
tofu validate # validate
tofu plan     # preview — needs a Hetzner API token
```

`tofu apply` creates **billable** infrastructure. Check
[Cost Estimate](https://projectious-work.github.io/kubeclaw/docs/reference/cost-estimate/)
first.

## Conventions

These are enforced by review rather than tooling:

- **English** for all code, comments, and documentation.
- **Resource naming.** Prefix every Hetzner resource with `var.cluster_name`.
- **Resource labels.** Include `cluster`, `role`, and `managed = "opentofu"`.
- **Firewall rules.** Every rule needs a `description`.
- **Conditional creation.** Put boolean logic in `locals`, then use `count` on
  the resource.
- **Cloud-init.** Templates are `.tpl` files rendered via `templatefile()`;
  variables are injected from `main.tf`, never hardcoded.
- **Ansible inventory is generated.** Never hand-edit `ansible/inventory.ini`;
  rerun `./scripts/generate-ansible-inventory.sh`.
- **Documentation pages** need a `title`, `weight`, and `description` in front
  matter. The weight sets sidebar order; the description doubles as the search
  excerpt.
- **Internal links** use `{{< relref >}}`, never hardcoded absolute URLs — those
  break local previews and versioned builds.

## Pull requests

1. Branch from `main`.
2. Keep the change focused; unrelated fixes are easier to review separately.
3. Run `./scripts/build-docs.sh` if you touched documentation, and
   `tofu fmt && tofu validate` if you touched infrastructure.
4. Update [CHANGELOG.md](CHANGELOG.md) under `## [Unreleased]`.
5. Describe **why**, not just what. If you found a wrong assumption, say which.

Commit messages use a `type: summary` first line (`feat:`, `fix:`, `docs:`,
`chore:`), with the body explaining the reasoning.

## Code of conduct

Participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Contributions are accepted under the [MIT License](LICENSE).
