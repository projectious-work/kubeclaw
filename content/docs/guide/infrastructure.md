---
title: Infrastructure (OpenTofu)
---


KubeClaw uses OpenTofu (Terraform-compatible) to provision all infrastructure on Hetzner Cloud. This page walks through the provisioning workflow step by step. See [Variables Reference]({{< relref "/docs/reference/variables" >}}) for all configurable options.

## Step 1: Configure terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your settings:

```hcl
hcloud_token    = "your-hcloud-api-token"
root_password   = "a-strong-root-password"
cluster_name    = "k8s-cluster"

# Optional: auto-configure Cloudflare Tunnel on the master control node
# cloudflare_tunnel_token = "eyJ..."
```

### SSH key options

{{< tabpane >}}
{{< tab header="Option A: Auto-generated keys (default)" >}}

No configuration needed. OpenTofu generates ED25519 keys and stores them in the state file.

| Advantage | Disadvantage |
|-----------|--------------|
| No manual key creation | State file contains private keys |
| Works out of the box | Keys lost if state is lost |

{{< /tab >}}
{{< tab header="Option B: Custom keys" >}}

Create your own keys and reference them in `terraform.tfvars`:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_control-node_key -C "control-node"
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_worker-node_key -C "worker-node"
```

```hcl
control_node_public_key = "ssh-ed25519 AAAA... control-node"
worker_node_public_key  = "ssh-ed25519 AAAA... worker-node"
```

| Advantage | Disadvantage |
|-----------|--------------|
| Full control over key storage | Manual key management |
| State has no private keys | Must create keys before provisioning |
| Easy password manager integration | |

{{< /tab >}}
{{< /tabpane >}}
## Step 2: Provision Infrastructure

```bash
tofu init    # First time only
tofu apply
```

This creates:

- Private network (10.0.0.0/24)
- Role-specific firewalls (control node, worker node, admin node)
- SSH keys (uploaded to Hetzner)
- Admin node at 10.0.0.254 (if `enable_admin_node = true`)
- Master control node at 10.0.0.2 (with cloudflared if tunnel token is set)
- Replica control nodes and workers (if configured)

## Step 3: Set Up SSH Access

```bash
./scripts/setup-ssh.sh
```

This exports SSH private keys from OpenTofu state and generates `~/.ssh/config` entries. Test the connection:

```bash
ssh control-node
```

{{< alert title="Tip" >}}
If you used `cloudflare_tunnel_token`, SSH routes through Cloudflare Tunnel automatically. Otherwise, the admin node serves as a jump host during initial setup.

{{< /alert >}}
## Next Steps

- [Server Management (Ansible)]({{< relref "/docs/guide/ansible" >}}) -- generate the Ansible inventory, apply system updates and security hardening
- [Kubernetes (kubeadm)]({{< relref "/docs/guide/kubernetes" >}}) -- deploy the cluster

## Related

- [SSH Keys with Passphrase]({{< relref "/docs/how-to/ssh-keys-with-passphrase" >}}) -- add passphrase protection to SSH keys
- [Store SSH Keys in Password Manager]({{< relref "/docs/how-to/store-ssh-keys-in-password-manager" >}}) -- backup keys securely
- [SSH Key Rotation]({{< relref "/docs/operations/ssh-key-rotation" >}}) -- rotate keys periodically or after compromise
- [Scale Up/Down]({{< relref "/docs/operations/scale-up-down" >}}) -- add or remove nodes
- [OS Images]({{< relref "/docs/reference/os-images" >}}) -- available Hetzner Cloud images
