---
title: SSH Keys with Passphrase
---


## Why use a passphrase?

An SSH key without a passphrase is like a house key without a lock on the key cabinet. If your laptop or key file is stolen, the attacker gains immediate access to your cluster.

## Creating keys with a passphrase

```bash
# Control node key
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_control-node_key -C "k8s-control"
# Enter a strong passphrase when prompted

# Worker node key
ssh-keygen -t ed25519 -f ~/.ssh/k8s-cluster_worker-node_key -C "k8s-worker"
# Enter a passphrase when prompted
```

## Using ssh-agent

Since Terraform and Ansible cannot directly use encrypted keys, you must use ssh-agent:

```bash
# Start agent (if not already running)
eval "$(ssh-agent -s)"

# Add keys (prompts for passphrase)
ssh-add ~/.ssh/k8s-cluster_control-node_key
ssh-add ~/.ssh/k8s-cluster_worker-node_key

# Check which keys are loaded
ssh-add -l
```

## macOS: Keychain integration

On macOS you can store the passphrase in the system Keychain so the key is automatically available after a reboot:

```bash
# Add key AND store passphrase in Keychain
ssh-add --apple-use-keychain ~/.ssh/k8s-cluster_control-node_key
ssh-add --apple-use-keychain ~/.ssh/k8s-cluster_worker-node_key
```

Also add the following to `~/.ssh/config`:

```
Host *
    UseKeychain yes
    AddKeysToAgent yes
```

## Helper script

The project includes a script that sets up ssh-agent correctly:

```bash
# Run once before using SSH/Ansible
source ./scripts/ssh-agent-setup.sh

# Afterwards SSH and Ansible work without further passphrase prompts
ssh control-node
ansible all -m ping
```

## Encrypting auto-generated keys after export

If you use auto-generated keys from OpenTofu, you can add a passphrase afterwards:

```bash
# Export key (unencrypted from state)
tofu output -raw control_node_ssh_private_key > ~/.ssh/k8s-cluster_control-node_key
chmod 600 ~/.ssh/k8s-cluster_control-node_key

# Add passphrase
ssh-keygen -p -f ~/.ssh/k8s-cluster_control-node_key
# Old passphrase: [Enter] (empty)
# New passphrase: [enter passphrase]
# Confirm: [repeat]
```

{{< alert title="Note" >}}
After encryption, `tofu output` still returns the unencrypted key from the state. However, your local key file is now protected.
{{< /alert >}}
