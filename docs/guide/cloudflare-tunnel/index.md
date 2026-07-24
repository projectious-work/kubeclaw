# Cloudflare Tunnel Setup

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

This guide walks through creating and configuring a Cloudflare Tunnel that provides secure SSH access to your KubeClaw cluster. The tunnel replaces the temporary admin node as the permanent access path -- no open ports, no public SSH, outbound-only connectivity.

## Why Cloudflare Tunnel?

KubeClaw nodes have no public IPv4 and no inbound SSH ports. Access works through one of two paths:

| Path | When to use | How it works |
|------|-------------|--------------|
| **Admin node** (temporary) | Initial setup, before tunnel is ready | Jump host with public IPv6; SSH via `ProxyJump` |
| **Cloudflare Tunnel** (permanent) | After tunnel is configured | `cloudflared` on the master node connects outbound to Cloudflare's edge; SSH proxied via `ProxyCommand cloudflared access ssh` on your local machine |

After the tunnel is working, you disable the admin node (`enable_admin_node = false` in `terraform.tfvars`) and all SSH flows through Cloudflare.

<div class="alert alert-primary" role="alert"><div class="h4 alert-heading" role="heading">cloudflared on both sides</div>


`cloudflared` runs in two places, because there is no direct SSH path to the cluster. The hostname `console.yourdomain.org` points to Cloudflare's edge servers, which only speak HTTPS -- a plain `ssh console.yourdomain.org` on port 22 would be refused. Instead, the SSH byte stream is wrapped inside HTTPS and carried through the tunnel:

1. **Your machine / Dev Container** (client side): The SSH config uses `ProxyCommand cloudflared access ssh --hostname %h`. Instead of opening a TCP connection, SSH pipes its traffic through this subprocess. `cloudflared` connects to Cloudflare's edge over HTTPS (port 443), handles Cloudflare Access authentication (browser-based, if configured), and forwards the SSH bytes.
2. **Cloudflare edge**: Validates the Access JWT, looks up which tunnel serves the hostname, and forwards the traffic to the matching tunnel connector.
3. **Master control node** (server side): The server-side `cloudflared` maintains a persistent outbound connection to Cloudflare's edge. It receives the forwarded traffic and proxies it to `localhost:22`, where sshd handles normal key-based authentication.

The full chain: `ssh` ↔ `cloudflared (local)` ↔ `Cloudflare edge (HTTPS)` ↔ `cloudflared (server)` ↔ `sshd`.

The Dev Container includes cloudflared. On macOS, install it with `brew install cloudflared`.

</div>

## Prerequisites

- A Cloudflare account (free tier is sufficient)
- A domain added to Cloudflare (Cloudflare must be the DNS provider)
- Infrastructure provisioned with `tofu apply` (the master control node must be running)

## Step 1: Open Zero Trust Dashboard

Go to [https://one.dash.cloudflare.com](https://one.dash.cloudflare.com) and log in. This opens the **Cloudflare Zero Trust** dashboard (formerly Cloudflare for Teams).

```
┌──────────────────────────────────────────────────────────────────┐
│  Cloudflare | Zero Trust                                         │
├──────────────┬───────────────────────────────────────────────────┤
│              │                                                   │
│  Home        │   Zero Trust Overview                             │
│  Analytics   │                                                   │
│  Risk Score  │   ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│              │   │ Users    │  │ Tunnels  │  │ Policies │      │
│  Access ►    │   │ 0        │  │ 0        │  │ 0        │      │
│  Gateway     │   └──────────┘  └──────────┘  └──────────┘      │
│  Networks ►  │                                                   │
│  ...         │                                                   │
│              │                                                   │
└──────────────┴───────────────────────────────────────────────────┘
```

## Step 2: Create a Tunnel

1. In the left sidebar, navigate to **Networks** > **Tunnels**
2. Click **Create a tunnel**

```
┌──────────────────────────────────────────────────────────────────┐
│  Networks > Tunnels                                              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                   Create a tunnel                          │  │
│  │                                                            │  │
│  │  Select your tunnel type:                                  │  │
│  │                                                            │  │
│  │  ┌─────────────────────┐   ┌─────────────────────┐       │  │
│  │  │ ● Cloudflared       │   │ ○ WARP Connector     │       │  │
│  │  │   (recommended)     │   │                      │       │  │
│  │  └─────────────────────┘   └─────────────────────┘       │  │
│  │                                                  [ Next ] │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

3. Select **Cloudflared** and click **Next**
4. Enter a tunnel name, e.g. `kubeclaw` or `hetzner-cluster`

```
┌──────────────────────────────────────────────────────────────────┐
│  Name your tunnel                                                │
│                                                                  │
│  Tunnel name:  ┌──────────────────────────────┐                 │
│                │ kubeclaw                      │                 │
│                └──────────────────────────────┘                 │
│                                                                  │
│                                               [ Save tunnel ]   │
└──────────────────────────────────────────────────────────────────┘
```

5. Click **Save tunnel**

## Step 3: Copy the Tunnel Token

After saving, Cloudflare shows the connector installation instructions. The page displays install commands for various platforms. You need the **token** value from the install command.

```
┌──────────────────────────────────────────────────────────────────┐
│  Install and run a connector                                     │
│                                                                  │
│  Choose your environment:                                        │
│  [ Debian ] [ Docker ] [ macOS ] [ Windows ]                    │
│                                                                  │
│  Install and run a connector:                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ sudo cloudflared service install eyJhIjoiY2Y...long-token │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                           📋     │
│                                                                  │
│  The token is: eyJhIjoiY2Y...                                   │
│                                                                  │
│                                                    [ Next ]      │
└──────────────────────────────────────────────────────────────────┘
```

Copy the token (the `eyJ...` string). You will need it in two places:

- **`terraform.tfvars`** — so `cloud-init` auto-installs the tunnel on the master node
- **Manual install** — if the infrastructure is already running

<div class="alert alert-primary" role="alert"><div class="h4 alert-heading" role="heading">Save the token securely</div>


The tunnel token is a long-lived credential. Store it in your password manager alongside the Hetzner API token.

</div>

Click **Next** to proceed to the hostname configuration.

## Step 4: Add a Public Hostname for SSH

This step maps a subdomain to the SSH service on your master control node.

1. You should now be on the **Route tunnel** screen, or navigate to your tunnel's **Public Hostname** tab
2. Click **Add a public hostname**
3. Fill in the hostname configuration:

```
┌──────────────────────────────────────────────────────────────────┐
│  Public Hostnames > Add a public hostname                        │
│                                                                  │
│  Public hostname                                                 │
│  ┌──────────────┐   ┌─────────────────────────┐                 │
│  │ console      │ . │ yourdomain.org       ▼  │                 │
│  │ (subdomain)  │   │ (domain)                │                 │
│  └──────────────┘   └─────────────────────────┘                 │
│                                                                  │
│  Path (optional):  ┌──────────────────────────┐                 │
│                    │                          │                 │
│                    └──────────────────────────┘                 │
│                                                                  │
│  Service                                                         │
│  ┌──────────────┐   ┌─────────────────────────┐                 │
│  │ SSH       ▼  │   │ localhost:22            │                 │
│  │ (type)       │   │ (URL)                   │                 │
│  └──────────────┘   └─────────────────────────┘                 │
│                                                                  │
│                                              [ Save hostname ]  │
└──────────────────────────────────────────────────────────────────┘
```

| Field | Value | Notes |
|-------|-------|-------|
| **Subdomain** | `console` | Or any name you prefer (e.g. `ssh`, `cluster`) |
| **Domain** | Your Cloudflare-managed domain | Must be a domain with Cloudflare DNS |
| **Path** | _(leave empty)_ | Not used for SSH |
| **Type** | `SSH` | From the dropdown |
| **URL** | `localhost:22` | The tunnel connector runs on the master node, so SSH is on localhost |

4. Click **Save hostname**

The resulting hostname (e.g. `console.yourdomain.org`) is what you'll use as `cloudflare_tunnel_domain` in `terraform.tfvars` and as the SSH Host in your SSH config.

## Step 5: Create an Access Application (Optional but Recommended)

Cloudflare Access adds browser-based authentication before the SSH connection is established. Without it, anyone who knows your tunnel hostname can attempt SSH connections (still protected by SSH keys, but Access adds a second layer).

1. In the left sidebar, go to **Access** > **Applications**
2. Click **Add an application**
3. Select **Self-hosted**

```
┌──────────────────────────────────────────────────────────────────┐
│  Access > Applications > Add an application                      │
│                                                                  │
│  Application Configuration                                       │
│                                                                  │
│  Application name:  ┌─────────────────────────┐                 │
│                     │ KubeClaw SSH Console     │                 │
│                     └─────────────────────────┘                 │
│                                                                  │
│  Session Duration:  ┌─────────────────────────┐                 │
│                     │ 24 hours             ▼  │                 │
│                     └─────────────────────────┘                 │
│                                                                  │
│  Application domain:                                             │
│  ┌──────────────┐   ┌─────────────────────────┐                 │
│  │ console      │ . │ yourdomain.org       ▼  │                 │
│  └──────────────┘   └─────────────────────────┘                 │
│                                                                  │
│                                                    [ Next ]      │
└──────────────────────────────────────────────────────────────────┘
```

4. Click **Next** to configure a policy
5. Create an **Allow** policy:

```
┌──────────────────────────────────────────────────────────────────┐
│  Add Policies                                                    │
│                                                                  │
│  Policy name:  ┌──────────────────────────┐                     │
│                │ Allow Admin              │                     │
│                └──────────────────────────┘                     │
│                                                                  │
│  Action:  ┌──────────────────────────┐                          │
│           │ Allow                 ▼  │                          │
│           └──────────────────────────┘                          │
│                                                                  │
│  Configure rules:                                                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Include                                                   │  │
│  │  Selector:  ┌─────────────────┐  Value: ┌───────────────┐ │  │
│  │             │ Emails       ▼  │         │ you@email.com │ │  │
│  │             └─────────────────┘         └───────────────┘ │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│                                                    [ Next ]      │
└──────────────────────────────────────────────────────────────────┘
```

| Field | Value |
|-------|-------|
| **Policy name** | `Allow Admin` |
| **Action** | `Allow` |
| **Include selector** | `Emails` |
| **Include value** | Your email address |

6. Click **Next**, review, and **Save**

<div class="alert alert-primary" role="alert"><div class="h4 alert-heading" role="heading">Authentication flow</div>


On first SSH connection, `cloudflared access ssh` opens a browser window. You authenticate via Cloudflare Access (email OTP, or your configured identity provider). After authentication, SSH proceeds normally with key-based auth. The browser session lasts for the configured session duration.

</div>

After completing the Cloudflare setup, continue with [Infrastructure (OpenTofu)](/kubeclaw/docs/guide/infrastructure/) to configure the tunnel token and domain in `terraform.tfvars`, provision the cluster, and verify connectivity.

## How SSH Routing Works

After the tunnel is active and the admin node is disabled:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐
│  Your        │     │  Cloudflare  │     │  Master Control Node │
│  machine     │────►│  Edge        │────►│  (cloudflared →      │
│  (cloudflared│     │  Network     │     │   localhost:22)      │
│   access ssh)│     │              │     │                      │
└──────────────┘     └──────────────┘     └──────────┬───────────┘
                                                     │ ProxyJump
                                          ┌──────────▼───────────┐
                                          │  Replicas / Workers  │
                                          │  (10.0.0.3+)         │
                                          └──────────────────────┘
```

| Target | SSH command | Route |
|--------|-------------|-------|
| Master control node | `ssh console.yourdomain.org` | ProxyCommand → Cloudflare → cloudflared → localhost:22 |
| Replica control node | `ssh control-02` | ProxyCommand → Cloudflare → master → ProxyJump → 10.0.0.3 |
| Worker node | `ssh worker-01` | ProxyCommand → Cloudflare → master → ProxyJump → 10.0.0.x |

## Troubleshooting

### Tunnel shows "Inactive" or "Down"

```bash
# On the master control node:
sudo systemctl status cloudflared
sudo journalctl -u cloudflared --no-pager -n 50
```

Common causes:

- Token expired or revoked -- create a new tunnel and update `terraform.tfvars`
- DNS64/NAT64 not working -- cloudflared needs outbound connectivity; check with `curl -6 https://cloudflare.com`

### Browser authentication loop

If `ssh console.yourdomain.org` keeps opening the browser without connecting:

```bash
# Clear cached credentials
cloudflared access login --reset console.yourdomain.org
```

### "connection refused" after authentication

The SSH service on the master node may not be listening on localhost:

```bash
# On the master node, verify SSH listens on 127.0.0.1
sudo ss -tlnp | grep 22
```

The cloud-init template configures UFW to allow SSH from localhost for exactly this reason.

## Next Steps

- [Infrastructure (OpenTofu)](/kubeclaw/docs/guide/infrastructure/) -- provision the cluster (if not done yet)
- [Server Management (Ansible)](/kubeclaw/docs/guide/ansible/) -- apply updates and hardening
- [Kubernetes (kubeadm)](/kubeclaw/docs/guide/kubernetes/) -- deploy the cluster
