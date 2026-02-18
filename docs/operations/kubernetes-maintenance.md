# Kubernetes Maintenance

Operational procedures for upgrading and managing the Kubernetes cluster. For initial cluster setup, see the [Kubernetes (kubeadm)](../guide/kubernetes.md) guide.

## Upgrade Kubernetes

Kubernetes upgrades follow a strict order: **control plane first, then workers**. This is the standard CKA upgrade workflow.

### Upgrade control plane

```bash
# 1. Unhold packages
sudo apt-mark unhold kubeadm

# 2. Upgrade kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.33.*-*

# 3. Check available upgrade
sudo kubeadm upgrade plan

# 4. Apply the upgrade
sudo kubeadm upgrade apply v1.33.0

# 5. Drain the control node (if running workloads)
kubectl drain $(hostname) --ignore-daemonsets --delete-emptydir-data

# 6. Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.33.*-* kubectl=1.33.*-*
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 7. Uncordon the node
kubectl uncordon $(hostname)
```

### Upgrade worker nodes

On each worker node:

```bash
# 1. From the control plane: drain the worker
kubectl drain <worker-name> --ignore-daemonsets --delete-emptydir-data

# 2. On the worker: upgrade packages
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get update && sudo apt-get install -y kubeadm=1.33.*-* kubelet=1.33.*-* kubectl=1.33.*-*
sudo apt-mark hold kubeadm kubelet kubectl

# 3. Upgrade node config
sudo kubeadm upgrade node

# 4. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 5. From the control plane: uncordon the worker
kubectl uncordon <worker-name>
```

### Backup PVC data

```bash
# Create snapshot via Hetzner Console or API
# Hetzner Console → Volumes → Select volume → Create Snapshot
```

## Useful kubectl commands

```bash
# Check nodes (dual-stack IPs visible)
kubectl get nodes -o wide

# Check all pods across namespaces
kubectl get pods -A

# Check pod IPs (should show both IPv4 and IPv6)
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}: {.status.podIPs}{"\n"}{end}'

# Check storage
kubectl get pvc -A
kubectl get pv

# Check CSI driver
kubectl get pods -n kube-system | grep hcloud

# Check Cilium status
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status

# Check network policies
kubectl get ciliumnetworkpolicies -A

# Check FQDN DNS cache (verify DNS64 synthesized addresses are cached)
kubectl exec -n kube-system -it \
  $(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -1) \
  -- cilium fqdn cache list

# Logs for cloudflared (if running as K8s workload)
kubectl logs -n system-unrestricted -l app=cloudflared

# Restart a workload
kubectl rollout restart deployment/my-app -n apps-restricted
```
