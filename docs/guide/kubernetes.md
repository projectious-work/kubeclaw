# Kubernetes (kubeadm)

After provisioning the infrastructure with OpenTofu and configuring SSH access, deploy a standard Kubernetes cluster using [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) with [Cilium](https://cilium.io/) as the CNI.

## Why kubeadm + Cilium?

- **kubeadm**: The official Kubernetes bootstrapper. Produces a standard, upstream cluster -- exactly what the CKA exam expects. Full control over every component (etcd, kube-apiserver, kube-scheduler, kube-controller-manager).
- **Cilium**: eBPF-based CNI providing advanced network policies with FQDN-based egress filtering -- critical for restricting outbound traffic per namespace.

## Step 1: Initialize the Control Plane

SSH into the master control node. Prerequisites (containerd, kubeadm, kubelet, kubectl) are already installed via cloud-init when `enable_k8s_prereqs = true` (default).

First, determine the master's private IP (default: `10.0.0.2`, depends on `subnet_ip_range`):

```bash
# From the Dev Container:
tofu output -raw master_control_node_private_ip

# Or on the master node itself:
MASTER_IP=$(hostname -I | awk '{print $1}')
```

The commands below use `$MASTER_IP`. Set it before proceeding:

```bash
MASTER_IP=$(hostname -I | awk '{print $1}')
```

### 1.1 Verify prerequisites

**Kernel modules**

```bash
lsmod | grep -E 'overlay|br_netfilter'
```

Expected output (both modules present):

```
br_netfilter           ...
overlay                ...
```

**Sysctl parameters**

```bash
sudo sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

Expected output:

```
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

**containerd**

```bash
systemctl is-active containerd
```

Expected output: `active`

**kubeadm**

```bash
kubeadm version -o yaml
```

Expected output (version numbers will vary):

```yaml
clientVersion:
  gitVersion: v1.32.x
  platform: linux/amd64
  ...
```

### 1.2 Initialize with kubeadm

```bash
sudo kubeadm init \
  --apiserver-advertise-address=$MASTER_IP \
  --pod-network-cidr=10.244.0.0/16 \
  --skip-phases=addon/kube-proxy
```

Flags explained:

- `--apiserver-advertise-address=$MASTER_IP` -- Bind the API server to the private network IP
- `--pod-network-cidr=10.244.0.0/16` -- Pod CIDR for Cilium
- `--skip-phases=addon/kube-proxy` -- Cilium replaces kube-proxy with eBPF datapath

!!! note "CKA note"
    The CKA exam typically uses kube-proxy. This cluster skips it because Cilium provides a more efficient replacement. On the exam, omit `--skip-phases=addon/kube-proxy`.

Expected output (abbreviated, IPs and hashes will differ):

```
[init] Using Kubernetes version: v1.32.x
[preflight] Running pre-flight checks
[preflight] Pulling images required for setting up a Kubernetes cluster
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [...] and IPs [...]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] Generating "etcd/peer" certificate and key
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "super-admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests"
[kubelet-check] The kubelet is healthy after 1.xxxs
[api-check] The API server is healthy after x.xxxs
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system
[mark-control-plane] Marking the node as control-plane by adding labels and taints
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join <MASTER_IP>:6443 --token <TOKEN> \
        --discovery-token-ca-cert-hash sha256:<HASH>
```

!!! info "Expected warnings"
    **"remote version is much newer"** -- This is normal when pinning `kubernetes_version` (e.g., `1.32`). kubeadm detects a newer stable release exists but correctly falls back to the pinned version. No action needed.

    **"sandbox image is inconsistent"** -- The containerd default config ships `pause:3.8` but kubeadm 1.32 expects `pause:3.10`. The cloud-init and Ansible prerequisites already fix this. If you see this warning, update the sandbox image manually: `sudo sed -i 's|registry.k8s.io/pause:3.8|registry.k8s.io/pause:3.10|' /etc/containerd/config.toml && sudo systemctl restart containerd`

**What `kubeadm init` does behind the scenes:**

1. Generates PKI certificates (CA, API server, kubelet, etc.) in `/etc/kubernetes/pki/`
2. Writes static pod manifests for etcd, kube-apiserver, kube-controller-manager, kube-scheduler in `/etc/kubernetes/manifests/`
3. Bootstraps etcd and starts the API server
4. Configures RBAC and creates bootstrap tokens
5. Generates `admin.conf` kubeconfig for cluster administration

### 1.3 Set up kubeconfig

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 1.4 Save join command

```bash
# Print the join command (token valid for 24h)
kubeadm token create --print-join-command
```

Save this output -- you'll need it for worker nodes.

### 1.5 Verify

**Node status**

```bash
kubectl get nodes
```

The node shows `NotReady` until the CNI (Cilium) is installed in Step 3:

```
NAME                      STATUS     ROLES           AGE   VERSION
<cluster>-control-01      NotReady   control-plane   XXm   v1.32.x
```

**System pods**

```bash
kubectl get pods -n kube-system
```

Core control plane pods should be `Running`. CoreDNS pods remain `Pending` until the CNI is installed:

```
NAME                                          READY   STATUS    RESTARTS   AGE
coredns-xxxxxxxxxx-xxxxx                      0/1     Pending   0          XXm
coredns-xxxxxxxxxx-xxxxx                      0/1     Pending   0          XXm
etcd-<cluster>-control-01                     1/1     Running   0          XXm
kube-apiserver-<cluster>-control-01           1/1     Running   0          XXm
kube-controller-manager-<cluster>-control-01  1/1     Running   0          XXm
kube-scheduler-<cluster>-control-01           1/1     Running   0          XXm
```

## Step 2: Join Worker Nodes and Further Control Nodes

**Worker Nodes**

SSH into each worker node and run the join command from Step 1.4. The join command already contains the master's IP and port:

```bash
sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

!!! info "CKA explainer -- TLS bootstrap"
    The worker uses the bootstrap token to authenticate with the API server, then requests a kubelet client certificate. The API server validates the token, signs the certificate, and the kubelet starts using it for all subsequent communication. This is the TLS bootstrap process.

**For HA control plane (replica control nodes):**

```bash
sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane --certificate-key <CERT_KEY>
```

Generate the certificate key on the master: `sudo kubeadm init phase upload-certs --upload-certs`

## Step 3: Install Cilium CNI

### 3.1 Install Helm

On the control node, install Helm via the official install script:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

!!! note "NAT64 and GitHub"
    The install script downloads from GitHub via NAT64. This generally works but connections can be flaky. If the download times out, simply retry the command.

### 3.2 Install Cilium via Helm

Install Cilium using the OCI chart from quay.io, which has native IPv6 support (no NAT64 needed):

```bash
helm install cilium oci://quay.io/cilium-charts/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$MASTER_IP \
  --set k8sServicePort=6443
```

Flags explained:

- `--version 1.16.5` -- Pin the Cilium version for reproducibility
- `--set kubeProxyReplacement=true` -- Replace kube-proxy with Cilium's eBPF datapath (matches `--skip-phases=addon/kube-proxy` from Step 1)
- `--set k8sServiceHost` / `k8sServicePort` -- Required when kube-proxy is skipped, so Cilium knows how to reach the API server

### 3.3 Wait and verify

```bash
# Wait for the Cilium DaemonSet to roll out
kubectl -n kube-system rollout status daemonset/cilium --timeout=120s

# Verify Cilium pods are running
kubectl get pods -n kube-system -l k8s-app=cilium
```

After Cilium is ready, all nodes should show `Ready`:

```bash
kubectl get nodes
```

## Step 4: Install Hetzner CSI Driver

The Hetzner CSI driver enables persistent storage via Hetzner Block Volumes.

### 4.1 Create a dedicated API token

In the Hetzner Cloud Console: **Security** > **API Tokens** > **Generate API Token** (Read & Write). Name it `k8s-csi`.

### 4.2 Deploy the CSI driver

```bash
# Create secret with API token
kubectl create secret generic hcloud \
  --namespace kube-system \
  --from-literal=token=<YOUR_HETZNER_CSI_API_TOKEN>

# Deploy CSI driver
kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/main/deploy/kubernetes/hcloud-csi.yml

# Set hcloud-volumes as default storage class
kubectl patch storageclass hcloud-volumes \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify
kubectl get storageclass
kubectl get pods -n kube-system | grep hcloud
```

## Step 5: Namespace Isolation and Network Policies

Use namespaces with Cilium network policies to isolate workloads and control egress traffic.

### 5.1 Create namespaces

```yaml
# namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: system-unrestricted
  labels:
    egress-policy: unrestricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: apps-restricted
  labels:
    egress-policy: restricted
```

```bash
kubectl apply -f namespaces.yaml
```

- **system-unrestricted**: For infrastructure services (cloudflared, monitoring) that need full network access.
- **apps-restricted**: For application workloads with egress locked down to specific destinations.

### 5.2 Default deny egress for restricted namespace

```yaml
# default-deny-egress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: apps-restricted
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress: []
```

```bash
kubectl apply -f default-deny-egress.yaml
```

### 5.3 Whitelist specific egress with Cilium

Cilium supports FQDN-based egress rules, allowing fine-grained control over which external services an application can reach:

```yaml
# example-app-egress.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: example-app-egress
  namespace: apps-restricted
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  egress:
    # DNS resolution (required for FQDN rules)
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP

    # Allow internal cluster communication
    - toEntities:
        - cluster

    # Allow specific external API (example)
    - toFQDNs:
        - matchName: "api.example.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

### 5.4 Unrestricted egress for system namespace

```yaml
# system-unrestricted-egress.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-all-egress
  namespace: system-unrestricted
spec:
  endpointSelector: {}
  egress:
    - toEntities:
        - all
```

```bash
kubectl apply -f system-unrestricted-egress.yaml
```

### 5.5 Verify network policies

```bash
# Start a test pod in the restricted namespace
kubectl run test --namespace apps-restricted --rm -it --image=alpine -- sh

# Inside the pod:
apk add curl

# Should FAIL (no egress policy for this pod)
curl -v https://google.com

# Exit test pod
exit
```

## Step 6: Cloudflare Tunnel as Kubernetes Workload

The infrastructure provisioning installs `cloudflared` on the master control node as a system service via cloud-init. Alternatively, you can run cloudflared as a Kubernetes deployment for better integration with the cluster:

```yaml
# cloudflared.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-token
  namespace: system-unrestricted
type: Opaque
stringData:
  token: "<YOUR_CLOUDFLARE_TUNNEL_TOKEN>"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: system-unrestricted
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:latest
          args:
            - tunnel
            - --no-autoupdate
            - run
            - --token
            - $(TUNNEL_TOKEN)
          env:
            - name: TUNNEL_TOKEN
              valueFrom:
                secretKeyRef:
                  name: cloudflared-token
                  key: token
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "200m"
```

```bash
kubectl apply -f cloudflared.yaml
```

Advantages over system-level cloudflared:

- Multiple replicas for high availability
- Managed by Kubernetes (auto-restart, resource limits)
- Network policies control its egress

If using this approach, disable the system-level cloudflared installed via cloud-init:

```bash
ssh control-node sudo systemctl stop cloudflared
ssh control-node sudo systemctl disable cloudflared
```

## Step 7: Configure Cloudflare Access

1. Go to **Cloudflare Zero Trust** > **Networks** > **Tunnels** > your tunnel > **Public Hostnames**
2. Map hostnames to internal Kubernetes services:

| Hostname | Service |
|----------|---------|
| `app.yourdomain.com` | `http://my-app.apps-restricted.svc.cluster.local:8080` |

3. Add authentication policies under **Access** > **Applications** to restrict who can reach the services

## Maintenance: Upgrade Kubernetes

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
# Check nodes
kubectl get nodes -o wide

# Check all pods across namespaces
kubectl get pods -A

# Check storage
kubectl get pvc -A
kubectl get pv

# Check CSI driver
kubectl get pods -n kube-system | grep hcloud

# Check Cilium status
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status

# Check network policies
kubectl get ciliumnetworkpolicies -A

# Logs for cloudflared (if running as K8s workload)
kubectl logs -n system-unrestricted -l app=cloudflared

# Restart a workload
kubectl rollout restart deployment/my-app -n apps-restricted
```
