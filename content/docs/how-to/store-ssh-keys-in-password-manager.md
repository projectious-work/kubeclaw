---
title: Store SSH Keys in Password Manager
weight: 20
description: Back up and restore cluster SSH keys using a password manager.
---


Storing SSH keys in a password manager provides a secure backup that survives hardware failures and makes it easy to restore access from a new machine.

## General workflow

This workflow applies to any password manager that supports secure notes or file attachments (Dashlane, 1Password, Bitwarden, etc.).

### 1. Create keys locally

```bash
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_control-node_key -C "control-node"
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_worker-node_key -C "worker-node"
```

### 2. Save to your password manager

Create a secure note or vault entry:

- **Name**: "K8s Cluster SSH Keys" (or similar)
- **Private key**: paste the contents of `~/.ssh/k8s-cluster_control-node_key`
- **Public key**: paste the contents of `~/.ssh/k8s-cluster_control-node_key.pub`

{{< alert title="Tip" >}}
Most password managers support file attachments -- you can attach the key files directly instead of pasting.

{{< /alert >}}
### 3. Add public key to terraform.tfvars

```hcl
control_node_public_key = "ssh-ed25519 AAAA... control-node"
worker_node_public_key  = "ssh-ed25519 AAAA... worker-node"
```

### 4. Restore when needed

When setting up on a new machine:

1. Copy the private key from your password manager
2. Save it to `~/.ssh/k8s-cluster_control-node_key`
3. Fix permissions: `chmod 600 ~/.ssh/k8s-cluster_control-node_key`

## Example: Dashlane

1. Create a **Secure Note** in Dashlane
2. Name: "K8s Cluster SSH Keys"
3. Content: paste the private key (`cat ~/.ssh/k8s-cluster_control-node_key`)
4. Add the public key as an additional field
5. Optionally attach the key files directly to the secure note
