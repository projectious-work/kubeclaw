# Security

> What the setup protects against, what to monitor, and the exact SSH hardening applied.

---

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

<div class="alert alert-warning" role="alert"><div class="h4 alert-heading" role="heading">Design intent, not a security guarantee</div>


This page describes what the design *intends* to protect against. KubeClaw is
a [prototype](/kubeclaw/docs/project-status/) and has not been
adversarially tested or audited -- assume gaps exist. Treat the table below as
a statement of intent, not of assurance.
</div>


## Security Summary

| Layer | Protection |
|-------|------------|
| **Network (Hetzner)** | Firewall blocks all inbound; IPv6-only, no public IPv4 |
| **Network (K8s)** | Cilium egress whitelist per namespace/app (FQDN-based) |
| **Access** | Cloudflare Tunnel (outbound-only connection, no open ports) |
| **Authentication** | Cloudflare Access policies + SSH key-only auth |
| **Container** | Non-root user, dropped capabilities, resource limits |
| **SSH** | Key-only auth, fail2ban, no TCP forwarding on workers |
| **Storage** | Isolated PVCs per workload |

## What this setup protects against

- **Direct server attacks** -- no public IPs, no open inbound ports
- **Unauthorized access** -- Cloudflare Access + SSH key-only auth
- **Data exfiltration** -- FQDN-based egress whitelist per application
- **Lateral movement** -- namespace isolation, per-pod network policies
- **Resource abuse** -- container resource limits

## What to monitor

- **API key and token compromise** -- rotate regularly
- **Cloudflare Tunnel health** -- monitor via Zero Trust dashboard
- **Node resource utilization** -- watch for memory pressure on small instances

## Security notes

- **Passwords in cloud-init** are visible in cloud-init logs. Change them after first login.
- **SSH keys** should be different for each server role.
- **Root password** is only intended for emergency access via Hetzner Web Console.
- **Terraform state** contains sensitive data (private keys when auto-generated). Protect state files.
- **UFW rules** for HTTP/HTTPS on worker nodes can be removed after initial setup:
  ```bash
  sudo ufw delete allow out to any port 80 proto tcp
  sudo ufw delete allow out to any port 443 proto tcp
  ```

## OpenClaw-specific security

When running OpenClaw:

| Concern | Mitigation |
|---------|------------|
| Anthropic API key compromise | Rotate regularly, monitor usage |
| Telegram bot token leak | Monitor bot activity |
| Claude providing incorrect information | Human review of responses |

## SSH hardening details

All nodes are configured with:

- `PermitRootLogin no`
- `PasswordAuthentication no`
- `KbdInteractiveAuthentication no`
- `MaxAuthTries 3`
- `X11Forwarding no`
- `AllowAgentForwarding no`
- `AllowUsers kubernetes-admin`
- `ClientAliveInterval 300`
- `ClientAliveCountMax 2`

Control nodes additionally allow `AllowTcpForwarding yes` (needed for ProxyJump and tunnel). Worker nodes set `AllowTcpForwarding no`.
