---
title: SSH Key Rotation
weight: 20
description: Rotate auto-generated or custom SSH keys without losing access.
---


## When to rotate

- Periodically (e.g. annually)
- If compromise is suspected
- When personnel changes occur

## With auto-generated keys

```bash
# 1. Mark old key resources for recreation
tofu taint 'tls_private_key.control_node[0]'
tofu taint 'tls_private_key.worker_node[0]'

# 2. Generate new keys and update servers
tofu apply

# 3. Export new keys
./scripts/setup-ssh.sh
```

{{< alert title="Warning" >}}
During rotation SSH access may be briefly interrupted. Keep Hetzner web console root access available as a fallback.

{{< /alert >}}
## With custom keys

```bash
# 1. Create new keys
ssh-keygen -t ed25519 -f ~/.ssh/k8s-control-new -C "control-node-new"

# 2. Add the new public key to the server (before removing the old one)
ssh control-node
echo "ssh-ed25519 AAAA... control-node-new" >> ~/.ssh/authorized_keys

# 3. Test the new key
ssh -i ~/.ssh/k8s-control-new kubernetes-admin@<node-ip>

# 4. Remove the old key from authorized_keys
ssh -i ~/.ssh/k8s-control-new control-node
# Edit ~/.ssh/authorized_keys and remove the old key line

# 5. Update terraform.tfvars with the new public key
# control_node_public_key = "ssh-ed25519 AAAA... (new key)"

# 6. Sync OpenTofu state
tofu apply
```

Repeat for worker node keys if applicable.
