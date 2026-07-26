# Development Setup

> Local development workflow for infrastructure changes and the documentation site.

---

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

## Getting started

Follow the [Dev Container guide](/kubeclaw/docs/guide/dev-container/) to set up your
development environment. The aibox Dev Container includes OpenTofu, Ansible,
`cloudflared`, Hugo, Node.js, Kubernetes clients, and AI assistants.

## Documentation development

Preview the documentation site locally:

```bash
./scripts/serve-docs.sh
# Open http://localhost:1313
```

When using a remote Dev Container environment, forward port 1313 from your
editor to view the preview.

Build the site:

```bash
./scripts/build-docs.sh
```

The build uses Hugo's strict template and content validation. The first run
installs the pinned Docsy asset dependencies locally and initializes the pinned
Docsy theme submodule when needed.

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

See [How to Contribute](/kubeclaw/docs/contributing/) for code conventions and the contribution workflow.

## Deploy documentation

To deploy the documentation to GitHub Pages:

```bash
./scripts/deploy-docs.sh
```

This is the standard documentation deployment. It builds the Hugo site locally
and pushes the generated `public/` directory to the root of the `gh-pages`
branch. GitHub Pages must be configured to serve `gh-pages` from `/`; no GitHub
Actions workflow is required or used.

The build and deployment scripts create an empty `.nojekyll` marker in the
generated site and at the branch root, so GitHub Pages always serves the
prebuilt output directly instead of processing it with Jekyll.

The same script can publish an archived documentation snapshot under a version
path. For example:

```bash
DOCS_VERSION=v0.1 ./scripts/deploy-docs.sh
```

Add the corresponding entry to `params.versions` in `hugo.yaml` when a release
is ready. The versioned build is published below the matching version path and
uses that path as its canonical base URL.
