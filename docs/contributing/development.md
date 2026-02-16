# Development Setup

## Prerequisites

- Docker and an IDE with Dev Container support (e.g. VS Code + Dev Containers extension)
- Git

## Getting started

```bash
# Clone the repository
git clone <repo-url>
cd kubeclaw

# Create persistent directories
mkdir -p .root/.ssh
chmod 700 .root/.ssh

# Open in Dev Container (VS Code: "Reopen in Container")
```

The Dev Container includes all tools: OpenTofu, Ansible, cloudflared, MkDocs Material, and AI assistants.

## Documentation development

Preview the documentation site locally:

```bash
mkdocs serve
# Open http://localhost:8000
```

The Dev Container forwards port 8000 automatically.

Build the site:

```bash
mkdocs build --strict
```

The `--strict` flag treats warnings as errors (broken links, missing pages, etc.).

## Infrastructure development

If you have a Hetzner Cloud account and want to test infrastructure changes:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your API token

tofu init
tofu plan    # Preview changes
tofu apply   # Apply changes
```

## Project conventions

See [How to Contribute](index.md) for code conventions and the contribution workflow.

## Deploy documentation

To deploy the documentation to Codeberg Pages:

```bash
./scripts/deploy-docs.sh
```

This builds the MkDocs site and pushes it to the `pages` branch.
