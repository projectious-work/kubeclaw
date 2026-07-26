# Scale Up/Down

> Add or remove control and worker nodes at the infrastructure and Kubernetes levels.

---

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

This guide covers scaling your cluster at both the infrastructure and Kubernetes levels.

## Scale Infrastructure

### Add worker nodes

1. Edit `terraform.tfvars` -- update `worker_node_types`:

    ```hcl
    worker_node_types = [
      { type = "cx23", count = 2 },
      { type = "cx33", count = 1 },  # 3 workers total, mixed types
    ]
    ```

2. Apply changes:

    ```bash
    tofu apply
    ```

3. Regenerate Ansible inventory:

    ```bash
    ./scripts/generate-ansible-inventory.sh
    ```

4. Run Ansible playbooks on the new nodes -- see [Server Management (Ansible)](/kubeclaw/docs/guide/ansible/) for the full workflow.

### Add replica control nodes

Same pattern using `control_node_types`:

```hcl
control_node_types = [
  { type = "cx23", count = 2 },  # 2 replicas → 3 total control nodes
]
```

Then `tofu apply`, regenerate inventory, and run Ansible playbooks.

### Remove nodes

1. **Drain and remove from Kubernetes first** (see [Remove nodes from Kubernetes](#remove-nodes-from-kubernetes) below)
2. Update `terraform.tfvars` to reduce node counts
3. Run `tofu apply`

## Scale Kubernetes

### Join new worker nodes

After provisioning and running Ansible playbooks on new nodes, join them to the cluster. Follow [Step 2 of the Kubernetes guide](/kubeclaw/docs/guide/kubernetes/#step-2-join-worker-nodes-and-further-control-nodes) to run the `kubeadm join` command.

### Remove nodes from Kubernetes

Before removing infrastructure, drain and delete the node from Kubernetes:

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node-name>
```

Then update `terraform.tfvars` and run `tofu apply` to remove the infrastructure.

## Examples

### Master-only (no replicas, no workers)

```hcl
# terraform.tfvars
master_control_node_type = "cx23"
control_node_types = []
worker_node_types  = []
```

### Add 2 workers

```hcl
# terraform.tfvars
worker_node_types = [
  { type = "cx23", count = 2 },
]
```

### Mixed server types

```hcl
# terraform.tfvars
control_node_types = [
  { type = "cx23", count = 2 },
]
worker_node_types = [
  { type = "cx23", count = 2 },
  { type = "cx33", count = 1 },
]
```
