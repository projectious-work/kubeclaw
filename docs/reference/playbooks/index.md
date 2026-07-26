# Ansible Playbooks Reference

> Purpose, variables, and task list for each Ansible playbook.

---

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

All playbooks are in `ansible/playbooks/` and target the `k8s_cluster` host group by default.

## update-system.yml

**Purpose**: Run `apt update && apt upgrade` on all nodes.

**Usage**:

```bash
cd ansible
ansible-playbook playbooks/update-system.yml
ansible-playbook playbooks/update-system.yml --limit control_nodes
ansible-playbook playbooks/update-system.yml -e "reboot_after_update=true"
```

**Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `reboot_after_update` | `false` | Reboot after update if the system requires it |
| `reboot_timeout` | `300` | Timeout (seconds) to wait for reboot |

**Tasks**:

1. Update apt cache
2. Upgrade all packages (dist-upgrade with autoremove)
3. Check if reboot is required (`/var/run/reboot-required`)
4. Reboot if required and enabled
5. Wait for system to come back online

## security-hardening.yml

**Purpose**: Apply security measures on all nodes.

**Usage**:

```bash
cd ansible
ansible-playbook playbooks/security-hardening.yml
```

**Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_unattended_upgrades` | `true` | Install and configure unattended-upgrades |
| `configure_fail2ban` | `true` | Verify fail2ban is running |

**Tasks**:

1. Install and configure unattended-upgrades (security updates only)
2. Enable automatic update checks (daily)
3. Verify fail2ban is running and monitoring SSH
4. Set secure permissions on `/etc/shadow`
5. Disable core dumps
6. Apply sysctl hardening (reverse path filtering, source route rejection, ASLR)

## configure-nat64.yml

**Purpose**: Configure DNS64 resolvers and NAT64 routing on already-running nodes. Cloud-init only runs at first boot -- use this playbook for existing nodes or to reconfigure.

**Usage**:

```bash
cd ansible
ansible-playbook playbooks/configure-nat64.yml
ansible-playbook playbooks/configure-nat64.yml --limit control_nodes
ansible-playbook playbooks/configure-nat64.yml -e '{"dns64_resolvers":["2a01:4f8:c2c:123f::1"]}'
```

**Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `dns64_resolvers` | `["2a01:4f8:c2c:123f::1", "2a01:4f9:c010:3f02::1", "2a00:1098:2b::1"]` | DNS64 resolver addresses |
| `nat64_prefix` | `"64:ff9b::/96"` | NAT64 prefix |

**Tasks**:

1. Configure DNS64 resolvers in systemd-resolved
2. Add NAT64 route via default IPv6 gateway
3. Create networkd-dispatcher script for persistent route
4. Update UFW rules on worker nodes (remove Hetzner DNS, add DNS64 + NAT64 rules)
5. Verify DNS64 resolution and NAT64 connectivity

## prepare-k8s-nodes.yml

**Purpose**: Install container runtime (containerd or CRI-O), kubeadm, kubelet, and kubectl on already-running nodes. Cloud-init only runs at first boot -- use this playbook for existing nodes.

**Usage**:

```bash
cd ansible
ansible-playbook playbooks/prepare-k8s-nodes.yml
ansible-playbook playbooks/prepare-k8s-nodes.yml --limit control_nodes
ansible-playbook playbooks/prepare-k8s-nodes.yml -e "kubernetes_version=1.32"
ansible-playbook playbooks/prepare-k8s-nodes.yml -e "container_runtime=cri-o"
```

**Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `kubernetes_version` | `"1.32"` | Kubernetes minor version for apt repo |
| `container_runtime` | `"containerd"` | Container runtime: `"containerd"` or `"cri-o"` |

**Tasks**:

1. Load kernel modules (`overlay`, `br_netfilter`)
2. Set sysctl parameters (`bridge-nf-call-iptables`, `ip_forward`)
3. Disable swap
4. Install and configure container runtime (containerd with SystemdCgroup, or CRI-O from OBS repo)
5. Add Kubernetes apt repository
6. Install kubelet, kubeadm, kubectl (held at current version)
7. Open UFW ports on control nodes (kubelet 10250, etcd 2379-2380)
8. Verify kubeadm version and container runtime status

## Ansible configuration

The `ansible.cfg` file configures:

- **Remote user**: `kubernetes-admin`
- **Host key checking**: disabled (nodes are ephemeral)
- **Privilege escalation**: sudo NOPASSWD
- **SSH args**: ForwardAgent, ControlMaster, ControlPersist for fast connections
- **Pipelining**: enabled for performance
