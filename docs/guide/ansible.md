# Server Management (Ansible)

Ansible handles ongoing server management: system updates, security hardening, NAT64 configuration, and Kubernetes prerequisites. All playbooks run from the Dev Container.

## Step 1: Set Up Ansible

### 1.1 Generate inventory

```bash
./scripts/generate-ansible-inventory.sh
```

The inventory (`ansible/inventory.ini`) is auto-generated. It defines three groups:

- `control_nodes` -- all control plane nodes
- `worker_nodes` -- all worker nodes
- `k8s_cluster` -- union of control and worker nodes

!!! warning
    Never hand-edit `inventory.ini`. Regenerate after infrastructure changes with `./scripts/generate-ansible-inventory.sh`.

### 1.2 Load SSH keys

```bash
source ./scripts/ssh-agent-setup.sh
```

!!! important
    The ssh-agent must be running with the cluster keys loaded before Ansible can connect. Run `source ./scripts/ssh-agent-setup.sh` in every new terminal session.

### 1.3 Test connectivity

```bash
cd ansible
ansible all -m ping
```

## Step 2: Apply System Updates

```bash
ansible-playbook playbooks/update-system.yml
```

Target specific node groups or enable automatic reboots:

```bash
# Only control nodes
ansible-playbook playbooks/update-system.yml --limit control_nodes

# With reboot if kernel was updated
ansible-playbook playbooks/update-system.yml -e "reboot_after_update=true"
```

## Step 3: Apply Security Hardening

```bash
ansible-playbook playbooks/security-hardening.yml
```

This enables:

- Unattended upgrades (automatic security updates)
- fail2ban monitoring
- Kernel security parameters (sysctl hardening)
- Secure permissions on sensitive files
- Core dump disabling

## Step 4: Configure NAT64/DNS64

For existing nodes that weren't configured via cloud-init:

```bash
ansible-playbook playbooks/configure-nat64.yml
```

See [DNS and NAT64](../introduction/dns-and-nat64.md) for details.

## Step 5: Install Kubernetes Prerequisites

```bash
ansible-playbook playbooks/prepare-k8s-nodes.yml
```

This installs containerd, kubeadm, kubelet, and kubectl on all nodes.

## Next Steps

- [Kubernetes (kubeadm)](kubernetes.md) -- deploy the cluster
- [Ansible Playbooks Reference](../reference/playbooks.md) -- detailed playbook documentation
