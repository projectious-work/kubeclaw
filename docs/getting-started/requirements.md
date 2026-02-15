# Requirements

## Accounts

- **Hetzner Cloud account** with an API token ([console.hetzner.cloud](https://console.hetzner.cloud))
- **Cloudflare account** with a configured domain (free tier is sufficient)

## Local Machine

- **Docker** and an IDE with Dev Container support (e.g. VS Code + Dev Containers extension)

That's it. All tools (OpenTofu, Ansible, SSH, cloudflared, AI assistants) are pre-installed in the Dev Container -- no local installation needed beyond Docker and your IDE.

## Optional

- **cloudflared** on your local machine for SSH via Cloudflare Tunnel (`brew install cloudflared` on macOS). This is included in the Dev Container but also useful on the host.
- **Dashlane** or another password manager for storing SSH keys and API tokens securely.
