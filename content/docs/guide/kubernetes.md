---
title: Kubernetes (kubeadm)
---


After provisioning the infrastructure with OpenTofu and configuring SSH access, deploy a standard Kubernetes cluster using [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) with [Cilium](https://cilium.io/) as the CNI.

## Why kubeadm + Cilium?

- **kubeadm**: The official Kubernetes bootstrapper. Produces a standard, upstream cluster -- exactly what the CKA exam expects. Full control over every component (etcd, kube-apiserver, kube-scheduler, kube-controller-manager).
- **Cilium**: eBPF-based CNI providing advanced network policies with FQDN-based egress filtering -- critical for restricting outbound traffic per namespace.

## Step 1: Initialize the Control Plane (Dual-Stack)

SSH into the master control node. Prerequisites (containerd, kubeadm, kubelet, kubectl) are already installed via cloud-init when `enable_k8s_prereqs = true` (default).

First, determine the master's private IP (default: `10.0.0.2`, depends on `subnet_ip_range`):

```bash
# From the Dev Container:
tofu output -raw master_control_node_private_ip
```

The commands below use `$MASTER_IP`. Set it on the master node before proceeding:

```bash
MASTER_IP=10.0.0.2
```

{{< alert title="Do not use `hostname -I`" >}}
`hostname -I` may return Hetzner's CGNAT address (`100.64.x.x`) as the first IP instead of the private network IP. Always set `MASTER_IP` explicitly to the private network address from your `subnet_ip_range` (default: `10.0.0.2`).

{{< /alert >}}
### 1.1 Verify prerequisites

**IPv6 forwarding**

```bash
sudo sysctl net.ipv6.conf.all.forwarding
```

Expected output: `net.ipv6.conf.all.forwarding = 1`

If not set, enable it:

```bash
echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo sysctl --system
```

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

**Container runtime**

{{< tabpane >}}
{{< tab header="containerd (default)" >}}

```bash
systemctl is-active containerd
```

Expected output: `active`

{{< /tab >}}
{{< tab header="CRI-O" >}}

```bash
systemctl is-active crio
```

Expected output: `active`

{{< alert title="CRI-O CNI path" >}}
CRI-O uses `/opt/cni/bin` for CNI binaries (the upstream default), unlike Debian's containerd which uses `/usr/lib/cni`. When installing Cilium with CRI-O, use `--set cni.binPath=/opt/cni/bin` (or omit the flag, since `/opt/cni/bin` is Cilium's default).

{{< /alert >}}
{{< /tab >}}
{{< /tabpane >}}
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

### 1.2 Determine the node's IPv6 address

Each node needs both an IPv4 and IPv6 address for dual-stack. The IPv4 is the private network IP (`10.0.0.2`). For IPv6, use the node's public IPv6 address:

```bash
NODE_IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[\da-f:]+' | head -1)
echo $NODE_IPV6
```

This should print a public IPv6 address like `2a01:4f8:xxxx:xxxx::1`. Save this -- you'll need it for kubelet configuration.

### 1.3 Initialize with kubeadm (dual-stack)

{{< alert title="Verify MASTER_IP before proceeding" >}}
Run `echo $MASTER_IP` -- it **must** print `10.0.0.2` (or your custom subnet IP). If it's empty, go back and set it. Running `kubeadm init` with an empty or wrong `--apiserver-advertise-address` will bind the API server to the wrong interface and generate TLS certificates with incorrect SANs. Fixing this requires a full `kubeadm reset` and re-init.

{{< /alert >}}
```bash
sudo kubeadm init \
  --apiserver-advertise-address=$MASTER_IP \
  --pod-network-cidr=10.244.0.0/16,fd00:10:244::/48 \
  --service-cidr=10.96.0.0/12,fd00:10:96::/108 \
  --skip-phases=addon/kube-proxy
```

Flags explained:

- `--apiserver-advertise-address=$MASTER_IP` -- Bind the API server to the private network IP (single address, not dual-stack)
- `--pod-network-cidr=10.244.0.0/16,fd00:10:244::/48` -- **Dual-stack pod CIDRs**: IPv4 for internal cluster communication + IPv6 for external connectivity via DNS64/NAT64
- `--service-cidr=10.96.0.0/12,fd00:10:96::/108` -- **Dual-stack service CIDRs**: existing IPv4 services continue to work; new services can opt into dual-stack
- `--skip-phases=addon/kube-proxy` -- Cilium replaces kube-proxy with eBPF datapath

{{< alert title="CKA note" >}}
The CKA exam typically uses kube-proxy. This cluster skips it because Cilium provides a more efficient replacement. On the exam, omit `--skip-phases=addon/kube-proxy`.

{{< /alert >}}
{{< alert title="Why dual-stack?" >}}
The nodes are IPv6-only with NAT64/DNS64 for IPv4 reachability. By giving pods IPv6 addresses alongside IPv4, they can reach external services via DNS64/NAT64 natively -- no `hostNetwork` workarounds needed. This means Cilium's FQDN-based egress policies apply to **all** pods, including CoreDNS, the CSI controller, and application workloads like OpenClaw.

{{< /alert >}}
{{< alert title="CIDRs cannot be changed after init" >}}
kubeadm does not support modifying pod or service CIDRs after initialization. If you need different ranges, you must `kubeadm reset` and re-init.

{{< /alert >}}
Expected output (abbreviated, IPs and hashes will differ):

```
[init] Using Kubernetes version: v1.32.x
[preflight] Running pre-flight checks
...
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

{{< alert title="Expected warnings" >}}
**"remote version is much newer"** -- This is normal when pinning `kubernetes_version` (e.g., `1.32`). kubeadm detects a newer stable release exists but correctly falls back to the pinned version. No action needed.

**"sandbox image is inconsistent"** -- The containerd default config ships `pause:3.8` but kubeadm 1.32 expects `pause:3.10`. The cloud-init and Ansible prerequisites already fix this. If you see this warning, update the sandbox image manually: `sudo sed -i 's|registry.k8s.io/pause:3.8|registry.k8s.io/pause:3.10|' /etc/containerd/config.toml && sudo systemctl restart containerd`

{{< /alert >}}
**What `kubeadm init` does behind the scenes:**

1. Generates PKI certificates (CA, API server, kubelet, etc.) in `/etc/kubernetes/pki/`
2. Writes static pod manifests for etcd, kube-apiserver, kube-controller-manager, kube-scheduler in `/etc/kubernetes/manifests/`
3. Bootstraps etcd and starts the API server
4. Configures RBAC and creates bootstrap tokens
5. Generates `admin.conf` kubeconfig for cluster administration

### 1.4 Set up kubeconfig

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 1.5 Configure kubelet for dual-stack

Set the kubelet's `--node-ip` to both the IPv4 private network address and the node's IPv6 address. This ensures endpoints are registered with both addresses:

```bash
sudo sed -i "s/KUBELET_KUBEADM_ARGS=\"/KUBELET_KUBEADM_ARGS=\"--node-ip=$MASTER_IP,$NODE_IPV6 /" /var/lib/kubelet/kubeadm-flags.env
sudo systemctl restart kubelet
```

Verify:

```bash
kubectl get nodes -o wide
```

The `INTERNAL-IP` column should show the IPv4 address. Check that both addresses are registered:

```bash
kubectl get nodes -o jsonpath='{.items[0].status.addresses}' | python3 -m json.tool
```

You should see both `InternalIP` entries (IPv4 and IPv6).

### 1.6 Save join command

```bash
# Print the join command (token valid for 24h)
kubeadm token create --print-join-command
```

Save this output -- you'll need it for worker nodes.

### 1.7 Verify

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

SSH into each worker node and run the join command from Step 1.6. Before joining, configure the kubelet for dual-stack on the worker:

```bash
# On the worker node, determine its IPs
WORKER_IPV4=10.0.0.X   # Replace with the worker's private IP
WORKER_IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[\da-f:]+' | head -1)
```

Then join:

```bash
sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

After joining, set the worker's dual-stack node IP:

```bash
sudo sed -i "s/KUBELET_KUBEADM_ARGS=\"/KUBELET_KUBEADM_ARGS=\"--node-ip=$WORKER_IPV4,$WORKER_IPV6 /" /var/lib/kubelet/kubeadm-flags.env
sudo systemctl restart kubelet
```

{{< alert title="CKA explainer -- TLS bootstrap" >}}
The worker uses the bootstrap token to authenticate with the API server, then requests a kubelet client certificate. The API server validates the token, signs the certificate, and the kubelet starts using it for all subsequent communication. This is the TLS bootstrap process.

{{< /alert >}}
**For HA control plane (replica control nodes):**

```bash
sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane --certificate-key <CERT_KEY>
```

Generate the certificate key on the master: `sudo kubeadm init phase upload-certs --upload-certs`

Then configure `--node-ip` the same way as for workers.

## Step 3: Install Cilium CNI (Dual-Stack)

### 3.1 Install Helm

On the control node, install Helm via the official install script:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

{{< alert title="NAT64 and GitHub" >}}
The install script downloads from GitHub via NAT64. This generally works but connections can be flaky. If the download times out, simply retry the command.

{{< /alert >}}
### 3.2 Install Cilium via Helm

Add the Cilium Helm repository and install. Make sure `$MASTER_IP` is still set (`echo $MASTER_IP`) -- if not, re-export it (see Step 1):

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$MASTER_IP \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set ipv4.enabled=true \
  --set ipv6.enabled=true \
  --set enableIPv6Masquerade=true \
  --set operator.replicas=1 \
  --set cni.binPath=/usr/lib/cni
```

Flags explained:

- `--version 1.16.5` -- Pin the Cilium version for reproducibility
- `--set kubeProxyReplacement=true` -- Replace kube-proxy with Cilium's eBPF datapath (matches `--skip-phases=addon/kube-proxy` from Step 1)
- `--set k8sServiceHost` / `k8sServicePort` -- Required when kube-proxy is skipped, so Cilium knows how to reach the API server
- `--set ipam.mode=kubernetes` -- Use the Kubernetes host-scope IPAM. Without this, Cilium defaults to its own `cluster-pool` allocator with CIDRs `10.0.0.0/8` and `fd00::/104`, ignoring kubeadm's `--pod-network-cidr`. This causes pod IPs to overlap with the Hetzner private network (`10.0.0.0/24`)
- `--set ipv4.enabled=true` -- Enable IPv4 pod networking (cluster-internal communication)
- `--set ipv6.enabled=true` -- Enable IPv6 pod networking (external access via DNS64/NAT64)
- `--set enableIPv6Masquerade=true` -- Masquerade pod IPv6 traffic to the node's public IPv6 when leaving the cluster. This is what allows pods to reach external services via NAT64
- `--set operator.replicas=1` -- Cilium defaults to 2 operator replicas, but since the operator uses a host port, only one can run per node. Set to 1 for single-node clusters; increase when adding worker nodes
- `--set cni.binPath=/usr/lib/cni` -- Debian's containerd package looks for CNI binaries in `/usr/lib/cni` instead of the default `/opt/cni/bin/`. Without this, kubelet reports `cni plugin not initialized`. If using CRI-O, omit this flag (CRI-O uses the default `/opt/cni/bin`)

{{< alert title="Restart containerd after Cilium install" >}}
After Cilium deploys the CNI plugin, containerd may have cached the "not initialized" state. Restart it to pick up the new CNI:

```bash
sudo systemctl restart containerd
```

Wait a few seconds, then verify the node becomes `Ready` with `kubectl get nodes`.

{{< /alert >}}
### 3.3 Wait and verify

```bash
# Wait for the Cilium DaemonSet to roll out
kubectl -n kube-system rollout status daemonset/cilium --timeout=120s

# Verify Cilium pods are running
kubectl get pods -n kube-system -l k8s-app=cilium
```

After containerd restarts and Cilium is ready, all nodes should show `Ready`:

```bash
kubectl get nodes
```

{{< alert title="Single-node cluster: removing the control-plane taint" >}}
By default, kubeadm applies a `NoSchedule` taint to control-plane nodes. This prevents regular workloads from running on nodes dedicated to the Kubernetes control plane (API server, etcd, scheduler), reserving their resources for cluster management. On a multi-node cluster this is the correct behavior.

On a single control-plane node without workers, this taint prevents **all** pod scheduling (including CoreDNS), so it must be removed:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
```

If you later add worker nodes and want to restore the taint to keep workloads off the control plane:

```bash
kubectl taint nodes <control-node-name> node-role.kubernetes.io/control-plane:NoSchedule
```

{{< /alert >}}
### 3.4 Verify dual-stack pod connectivity

Once CoreDNS is running, verify that pods have both IPv4 and IPv6 addresses:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```

Check the pod's IP addresses:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}: {.status.podIPs}{"\n"}{end}'
```

Each pod should have two IPs -- one from `10.244.0.0/16` (IPv4) and one from `fd00:10:244::/48` (IPv6).

## Step 4: Configure CoreDNS for DNS64

With dual-stack pods, CoreDNS has IPv6 connectivity and can reach external DNS servers directly -- no `hostNetwork` needed. However, CoreDNS must forward to **DNS64 resolvers** (not regular DNS) so that IPv4-only domains get synthesized AAAA records that pods can route to via NAT64.

### 4.1 Update CoreDNS ConfigMap

```bash
kubectl -n kube-system edit configmap coredns
```

Replace the `forward` line. Change:

```
forward . /etc/resolv.conf
```

To:

```
forward . 2001:67c:2b0::4 2001:67c:2b0::6
```

These are public DNS64 resolvers from [nat64.net](https://nat64.net/public-providers) (Nuremberg and Helsinki -- close to Hetzner's datacenters). They synthesize AAAA records with the `64:ff9b::/96` prefix for IPv4-only domains.

{{< alert title="Why DNS64 resolvers?" >}}
When a pod queries `api.anthropic.com`, CoreDNS forwards to the DNS64 resolver. If `api.anthropic.com` only has an A record (IPv4), the DNS64 resolver synthesizes an AAAA record like `64:ff9b::6812:0000`. The pod then sends IPv6 traffic to this address, Cilium masquerades it to the node's public IPv6, and the NAT64 gateway translates it to IPv4. This is how pods reach IPv4-only services without `hostNetwork`.

{{< /alert >}}
### 4.2 Restart CoreDNS

```bash
kubectl -n kube-system rollout restart deployment coredns
kubectl -n kube-system rollout status deployment coredns --timeout=60s
```

### 4.3 Verify DNS resolution

Create a long-running test pod (the `--rm -it` pattern tends to hang on IPv6-only clusters):

```bash
kubectl run test --image=alpine --restart=Never -- sleep 3600
```

Test DNS and connectivity:

```bash
# Test internal DNS (cluster service name)
kubectl exec test -- nslookup kubernetes.default.svc.cluster.local

# Test external DNS (should return a synthesized AAAA from the DNS64 resolver)
kubectl exec test -- nslookup github.com

# Install curl and test end-to-end NAT64 connectivity
kubectl exec test -- apk add --no-cache curl
kubectl exec test -- curl -6 -s --max-time 10 -o /dev/null -w "%{http_code}\n" https://github.com
```

Expected results: `nslookup github.com` returns both a synthesized AAAA (e.g. `2001:67c:2b0:db32:...`) and a real A record. The `curl -6` command forces IPv6 and should return `200` (or `301` for domains that redirect, like `google.com`).

{{< alert title="BusyBox wget prefers IPv4" >}}
Alpine's BusyBox wget tries IPv4 first and has no `-6` flag. Since pods have no IPv4 internet route, `wget https://github.com` will fail with "Network unreachable". Use `curl -6` for testing, or note that glibc-based images (like `node:lts`) prefer IPv6 by default per RFC 6724.

{{< /alert >}}
Clean up:

```bash
kubectl delete pod test
```

{{< alert title="Debugging DNS" >}}
If DNS resolution fails, check the CoreDNS logs:

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns -f
```

Verify that CoreDNS pods have IPv6 connectivity to the DNS64 resolvers:

```bash
kubectl run test --image=alpine --restart=Never -- sleep 300
kubectl exec test -- ping6 -c 3 -W 3 2001:67c:2b0::4
kubectl delete pod test
```

{{< /alert >}}
## Step 5: Install Hetzner CSI Driver

The Hetzner CSI driver enables persistent storage via Hetzner Block Volumes. With dual-stack networking, the CSI controller can reach `api.hetzner.cloud` through its pod IPv6 address and NAT64 -- no `hostNetwork` patch needed.

### 5.1 Create a dedicated API token

In the Hetzner Cloud Console: **Security** > **API Tokens** > **Generate API Token** (Read & Write). Name it `k8s-csi`.

### 5.2 Deploy the CSI driver

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
```

### 5.3 Verify

```bash
kubectl get storageclass
kubectl get pods -n kube-system | grep hcloud
# hcloud-csi-controller should show 5/5 Running
# hcloud-csi-node should show 3/3 Running
```

If the CSI controller fails to start with connection errors to `api.hetzner.cloud`, verify that:

1. CoreDNS is forwarding to DNS64 resolvers (Step 4)
2. The pod has an IPv6 address (`kubectl get pods -n kube-system -o wide | grep hcloud-csi-controller`)
3. The NAT64 route exists on the node (`ip -6 route | grep 64:ff9b`)

## Step 6: Namespace Isolation and Network Policies

Use namespaces with Cilium network policies to isolate workloads and control egress traffic. With dual-stack networking, Cilium's FQDN-based egress rules work for all pods -- the DNS proxy intercepts DNS64-synthesized AAAA responses and allows traffic to those addresses.

### 6.1 Create namespaces

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

### 6.2 Default deny egress for restricted namespace

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

### 6.3 Whitelist specific egress with Cilium (optional)

This step is a reference example — apply it when deploying applications that need specific egress rules (see the [OpenClaw guide]({{< relref "/docs/guide/openclaw" >}}) for a real-world example).

Cilium supports FQDN-based egress rules, allowing fine-grained control over which external services an application can reach. With dual-stack, the DNS proxy intercepts DNS64-synthesized AAAA records and maps them to the FQDN, so `toFQDNs` rules work transparently with NAT64:

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

{{< alert title="How FQDN rules work with DNS64/NAT64" >}}
When a pod queries `api.example.com`, Cilium's DNS proxy intercepts the response. If the DNS64 resolver returns a synthesized AAAA record (`64:ff9b::xxxx`), the proxy records the mapping `api.example.com → 64:ff9b::xxxx`. The `toFQDNs` rule then allows traffic to that synthesized address. From Cilium's perspective, a DNS64-synthesized AAAA record is just a regular AAAA record.

{{< /alert >}}
### 6.4 Unrestricted egress for system namespace

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

### 6.5 Verify network policies

Use `wget` (included in Alpine by default) to verify that the default-deny policy blocks all egress, including DNS resolution:

```bash
# Start a test pod in the restricted namespace
kubectl run test --namespace apps-restricted --rm -it --image=alpine -- sh

# Inside the pod -- both should FAIL with DNS or connection errors:
wget -qO- https://google.com
ping -c1 8.8.8.8

# Exit test pod
exit
```

{{< alert title="Why not `curl`?" >}}
You might think to `apk add curl` first, but that itself requires DNS resolution and network access to reach the Alpine package mirror -- which is exactly what the default-deny egress policy blocks. The fact that `apk` fails is already proof that the policy works. Alpine ships with `wget`, so no package installation is needed.

{{< /alert >}}
Then verify that the **unrestricted** namespace allows full egress:

```bash
kubectl run test --namespace system-unrestricted --image=alpine --restart=Never -- sleep 3600

# Install curl and test (BusyBox wget lacks -6 and prefers IPv4 which is unreachable)
kubectl exec --namespace system-unrestricted test -- apk add --no-cache curl
kubectl exec --namespace system-unrestricted test -- curl -6 -s --max-time 10 -o /dev/null -w "%{http_code}\n" https://google.com

# Clean up
kubectl delete pod --namespace system-unrestricted test
```

The `curl -6` command should return `301` (Google redirects to `www.google.com`), confirming full IPv6 egress works.

## Step 7: Expose Services via Cloudflare Tunnel

The Cloudflare Tunnel (installed as a system service on the master control node via cloud-init) can route external traffic to Kubernetes services. This step deploys a test service in the **restricted** namespace to verify the full chain: Internet → Cloudflare → Tunnel → Kubernetes Service → Pod -- with network policies enforced.

### 7.1 Deploy a test service

Apply the following manifest. It creates an Nginx deployment, a ClusterIP service, and a CiliumNetworkPolicy in the `apps-restricted` namespace. The network policy only allows DNS egress (which Nginx doesn't strictly need, but demonstrates the pattern every real application requires):

```yaml
# nginx-test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: apps-restricted
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              memory: "32Mi"
              cpu: "10m"
            limits:
              memory: "64Mi"
              cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  namespace: apps-restricted
spec:
  selector:
    app: nginx-test
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: nginx-test-egress
  namespace: apps-restricted
spec:
  endpointSelector:
    matchLabels:
      app: nginx-test
  egress:
    # DNS resolution (required for most real applications)
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
```

```bash
kubectl apply -f nginx-test.yaml
```

Verify it's running:

```bash
kubectl get pods -n apps-restricted -l app=nginx-test
kubectl get svc nginx-test -n apps-restricted
```

### 7.2 Enable cluster DNS on the host

The `cloudflared` system service runs on the host, not inside the cluster. By default, it cannot resolve Kubernetes service names like `nginx-test.apps-restricted.svc.cluster.local` because the host uses Hetzner's DNS servers, not CoreDNS.

Add CoreDNS as a nameserver on the host. CoreDNS listens on its pod IP (a ClusterIP or node-local address routable via Cilium):

```bash
# Find the CoreDNS ClusterIP
COREDNS_IP=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
echo "CoreDNS ClusterIP: $COREDNS_IP"

sudo sed -i "1s/^/nameserver $COREDNS_IP\n/" /etc/resolv.conf
```

{{< alert title="resolv.conf is managed by resolvconf" >}}
The `/etc/resolv.conf` file is auto-generated and may be overwritten on reboot or network changes. To make this permanent, add the nameserver to `/etc/resolvconf/resolv.conf.d/head`:

```bash
echo "nameserver $COREDNS_IP" | sudo tee /etc/resolvconf/resolv.conf.d/head
sudo resolvconf -u
```

{{< /alert >}}
Verify the host can resolve cluster service names:

```bash
curl http://nginx-test.apps-restricted.svc.cluster.local
```

You should see the Nginx welcome page.

### 7.3 Configure the tunnel hostname

In the Cloudflare dashboard:

1. Go to **Zero Trust** > **Networks** > **Tunnels** > your tunnel > **Public Hostnames**
2. Add a new public hostname:

| Hostname | Service |
|----------|---------|
| `test.yourdomain.com` | `http://nginx-test.apps-restricted.svc.cluster.local:80` |

{{< alert title="SSL/TLS mode" >}}
In the Cloudflare dashboard under **yourdomain.com** > **SSL/TLS** > **Overview**, set the encryption mode to **Full** (not **Full (strict)**). The tunnel terminates TLS at Cloudflare and connects to the origin (Nginx) over plain HTTP.

{{< /alert >}}
### 7.4 Test access

From your local machine (or anywhere on the internet):

```bash
curl https://test.yourdomain.com
```

You should see the Nginx welcome page. This confirms the full chain works:

```
Internet → Cloudflare (TLS termination)
  → Tunnel → cloudflared (system service on host)
    → CoreDNS resolves service name → ClusterIP
      → Nginx pod (apps-restricted namespace, egress restricted by Cilium)
```

{{< alert title="Ingress is allowed by default" >}}
The default-deny policy from Step 6.2 only restricts **egress**. Ingress to pods in `apps-restricted` is allowed, so cloudflared can reach Nginx without an additional ingress rule. For production workloads, consider adding explicit ingress policies as well.

{{< /alert >}}
### 7.5 Clean up

Remove the test resources and the Cloudflare public hostname:

```bash
kubectl delete -f nginx-test.yaml
```

Then in the Cloudflare dashboard: **Zero Trust** > **Networks** > **Tunnels** > your tunnel > **Public Hostnames** > delete the `test.yourdomain.com` entry.

{{< alert title="Authentication" >}}
At this point, the tunnel exposes services without authentication. Adding Cloudflare Access policies (Zero Trust > Access > Applications) to control who can reach your services is covered in the [OpenClaw deployment guide]({{< relref "/docs/guide/openclaw" >}}).

{{< /alert >}}
### 7.6 Optional: Run cloudflared as a Kubernetes workload

The system-level `cloudflared` installed via cloud-init is sufficient for most setups. If you prefer to manage the tunnel as a Kubernetes deployment (for HA with multiple replicas, resource limits, and Kubernetes-native lifecycle management), you can migrate it:

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

Then disable the system-level service:

```bash
ssh control-node sudo systemctl stop cloudflared
ssh control-node sudo systemctl disable cloudflared
```

## Next Steps

For upgrade procedures and operational kubectl commands, see [Kubernetes Maintenance]({{< relref "/docs/operations/kubernetes-maintenance" >}}).
