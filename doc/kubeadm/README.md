# Secure OpenClaw Deployment on Hetzner Cloud

A step-by-step guide to deploying OpenClaw as an isolated AI problem-solving assistant on a secure, cost-effective Hetzner Cloud Kubernetes cluster with Cloudflare Tunnel access.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Hetzner Private Network                          │
│                        (10.0.0.0/24)                                │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │            Kubernetes Cluster (kubeadm) + Cilium             │    │
│  │                                                             │    │
│  │   ┌─────────────────┐       ┌─────────────────┐            │    │
│  │   │   control-01    │       │   worker-01     │            │    │
│  │   │  (control plane)│◀─────▶│  (worker node)  │            │    │
│  │   │   10.0.0.2      │       │   10.0.0.3      │            │    │
│  │   │                 │       │                 │            │    │
│  │   │  ┌───────────┐  │       │  ┌───────────┐  │            │    │
│  │   │  │Block Vol  │  │       │  │Block Vol  │  │            │    │
│  │   │  │  10 GB    │  │       │  │  10 GB    │  │            │    │
│  │   │  └───────────┘  │       │  └───────────┘  │            │    │
│  │   └────────┬────────┘       └─────────────────┘            │    │
│  │            │                                                │    │
│  │   system-unrestricted namespace:                           │    │
│  │     └─ cloudflared (egress: ANY)                           │    │
│  │                                                             │    │
│  │   apps-restricted namespace:                                │    │
│  │     └─ OpenClaw (egress: Anthropic + Telegram ONLY)        │    │
│  │                                                             │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                      │
│                      cloudflared                                    │
│                    (outbound only)                                  │
└──────────────────────────────┼──────────────────────────────────────┘
                               │
                               ▼
                    ┌───────────────────┐
                    │    Cloudflare     │
                    │  Edge + Access    │
                    └─────────┬─────────┘
                              │
                              ▼
                          [You]
                     (via Telegram)
```

## Cost Summary

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| Node 1 (CX22, IPv6-only) | 2 vCPU / 4 GB RAM | €3.29 |
| Node 2 (CX22, IPv6-only) | 2 vCPU / 4 GB RAM | €3.29 |
| Block Volume × 2 | 10 GB each | €0.96 |
| Private Network | — | Free |
| Cloudflare Tunnel + Access | Up to 50 users | Free |
| **Total** | | **~€7.54/month** |

## Prerequisites

- Hetzner Cloud account
- Cloudflare account with a domain (can be free tier)
- Anthropic API key
- Telegram Bot Token (create via @BotFather)
- Your Telegram User ID

---

## Step 1: Hetzner Cloud Infrastructure Setup

### 1.1 Create Private Network

1. Go to **Hetzner Cloud Console** → **Networks** → **Create Network**
2. Configure:
   - **Name:** `k8s-internal`
   - **IP Range:** `10.0.0.0/24`
   - **Subnet:** `10.0.0.0/24`
   - **Zone:** `eu-central` (or your preferred region)

### 1.2 Create Firewall

1. Go to **Firewalls** → **Create Firewall**
2. **Name:** `k8s-lockdown`
3. **Inbound Rules:** None (drop all by default)
4. **Outbound Rules:**

| Protocol | Port | Destination | Action |
|----------|------|-------------|--------|
| TCP | Any | `0.0.0.0/0` | Allow |
| UDP | Any | `0.0.0.0/0` | Allow |

### 1.3 Create API Token for CSI Driver

1. Go to **Security** → **API Tokens** → **Generate API Token**
2. **Name:** `k8s-csi`
3. **Permissions:** Read & Write
4. **Save the token securely** — you'll need it later

### 1.4 Create Server Nodes

Create two CX22 instances with these settings:

| Setting | Node 1 | Node 2 |
|---------|--------|--------|
| **Name** | `k8s-control-01` | `k8s-worker-01` |
| **Image** | Debian 13 | Debian 13 |
| **Type** | CX22 | CX22 |
| **Location** | Falkenstein (fsn1) | Falkenstein (fsn1) |
| **Networking** | IPv6 only ✓ | IPv6 only ✓ |
| **Private Network** | `k8s-internal` | `k8s-internal` |
| **Firewall** | `k8s-lockdown` | `k8s-lockdown` |
| **SSH Key** | Add your key | Add your key |

After creation, note the private IPs (should be `10.0.0.2` and `10.0.0.3`).

---

## Step 2: Initialize Kubernetes with kubeadm

Prerequisites (containerd, kubeadm, kubelet, kubectl) are installed automatically via cloud-init when `enable_k8s_prereqs = true`. For details on the full kubeadm workflow, see the [main README](../../README.md#kubernetes-deployment-with-kubeadm).

### 2.1 Initialize the Control Plane (control-01)

```bash
# Initialize the control plane
sudo kubeadm init \
  --apiserver-advertise-address=10.0.0.2 \
  --pod-network-cidr=10.244.0.0/16 \
  --skip-phases=addon/kube-proxy

# Set up kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Save the join command for worker nodes
kubeadm token create --print-join-command
```

### 2.2 Join Worker Nodes (worker-01)

```bash
# Run the join command from Step 2.1
sudo kubeadm join 10.0.0.2:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

### 2.3 Install Cilium (on control-01)

```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
tar xzvf cilium-linux-${CLI_ARCH}.tar.gz
sudo mv cilium /usr/local/bin/
rm cilium-linux-${CLI_ARCH}.tar.gz

# Install Cilium (with kube-proxy replacement since we skipped it)
cilium install --version 1.16.5 --set kubeProxyReplacement=true

# Wait for Cilium to be ready
cilium status --wait

# Verify
kubectl get pods -n kube-system | grep cilium
```

### 2.4 Verify Cluster

```bash
kubectl get nodes
```

Expected output:
```
NAME                    STATUS   ROLES           AGE   VERSION
k8s-cluster-control-01  Ready    control-plane   5m    v1.32.x
k8s-cluster-worker-01   Ready    <none>          3m    v1.32.x
```

---

## Step 3: Install Hetzner CSI Driver

All commands on **Node 1**.

### 3.1 Create Secret with API Token

```bash
kubectl create secret generic hcloud \
  --namespace kube-system \
  --from-literal=token=<YOUR_HETZNER_API_TOKEN>
```

### 3.2 Deploy CSI Driver

```bash
kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/main/deploy/kubernetes/hcloud-csi.yml
```

### 3.3 Verify and Set Default Storage Class

```bash
# Check CSI pods
kubectl get pods -n kube-system | grep hcloud

# Check storage classes
kubectl get storageclass

# Set hcloud-volumes as default storage class
kubectl patch storageclass hcloud-volumes \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

---

## Step 4: Create Namespaces and Network Policies

### 4.1 Create Namespaces

Create file `namespaces.yaml`:

```yaml
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

Apply:
```bash
kubectl apply -f namespaces.yaml
```

### 4.2 Default Deny Egress for Restricted Namespace

Create file `default-deny-egress.yaml`:

```yaml
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

Apply:
```bash
kubectl apply -f default-deny-egress.yaml
```

### 4.3 OpenClaw Egress Whitelist (Cilium)

Create file `openclaw-egress.yaml`:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: openclaw-egress
  namespace: apps-restricted
spec:
  endpointSelector:
    matchLabels:
      app: openclaw
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

    # Anthropic API
    - toFQDNs:
        - matchName: "api.anthropic.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP

    # Telegram API
    - toFQDNs:
        - matchName: "api.telegram.org"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

Apply:
```bash
kubectl apply -f openclaw-egress.yaml
```

### 4.4 Unrestricted Egress for System Namespace

Create file `system-unrestricted-egress.yaml`:

```yaml
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

Apply:
```bash
kubectl apply -f system-unrestricted-egress.yaml
```

---

## Step 5: Set Up Cloudflare Tunnel

### 5.1 Create Tunnel in Cloudflare Dashboard

1. Go to **Cloudflare Zero Trust** → **Networks** → **Tunnels**
2. Click **Create a tunnel**
3. **Name:** `k8s-cluster`
4. Copy the **tunnel token**

### 5.2 Deploy cloudflared

Create file `cloudflared.yaml`:

```yaml
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

Apply:
```bash
kubectl apply -f cloudflared.yaml
```

### 5.3 Configure Cloudflare Access (Optional)

1. Go to **Cloudflare Zero Trust** → **Access** → **Applications**
2. Create an application for your service
3. Add authentication policies as needed

---

## Step 6: Deploy OpenClaw

### 6.1 Create OpenClaw Configuration

Create file `openclaw-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  namespace: apps-restricted
data:
  openclaw.json: |
    {
      "agent": {
        "model": "anthropic/claude-opus-4-5"
      },
      "channels": {
        "telegram": {
          "allowFrom": ["<YOUR_TELEGRAM_USER_ID>"],
          "dmPolicy": "pairing"
        }
      }
    }
```

### 6.2 Create OpenClaw Secrets

```bash
kubectl create secret generic openclaw-secrets \
  --namespace apps-restricted \
  --from-literal=ANTHROPIC_API_KEY=<YOUR_ANTHROPIC_API_KEY> \
  --from-literal=TELEGRAM_BOT_TOKEN=<YOUR_TELEGRAM_BOT_TOKEN>
```

### 6.3 Deploy OpenClaw StatefulSet

Create file `openclaw-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openclaw
  namespace: apps-restricted
spec:
  serviceName: openclaw
  replicas: 1
  selector:
    matchLabels:
      app: openclaw
  template:
    metadata:
      labels:
        app: openclaw
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
        - name: openclaw
          image: node:22-slim
          workingDir: /app
          command:
            - /bin/sh
            - -c
            - |
              npm install -g openclaw@latest
              openclaw gateway --port 18789
          env:
            - name: ANTHROPIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: ANTHROPIC_API_KEY
            - name: TELEGRAM_BOT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: TELEGRAM_BOT_TOKEN
          ports:
            - containerPort: 18789
              name: gateway
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "2Gi"
              cpu: "2000m"
          volumeMounts:
            - name: config
              mountPath: /home/node/.openclaw/openclaw.json
              subPath: openclaw.json
            - name: data
              mountPath: /home/node/.openclaw
      volumes:
        - name: config
          configMap:
            name: openclaw-config
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: hcloud-volumes
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: openclaw
  namespace: apps-restricted
spec:
  selector:
    app: openclaw
  ports:
    - port: 18789
      targetPort: 18789
      name: gateway
```

Apply all:
```bash
kubectl apply -f openclaw-config.yaml
kubectl apply -f openclaw-deployment.yaml
```

### 6.4 Verify Deployment

```bash
# Check pod status
kubectl get pods -n apps-restricted

# Check logs
kubectl logs -n apps-restricted -l app=openclaw -f

# Check PVC
kubectl get pvc -n apps-restricted
```

---

## Step 7: Configure Cloudflare Tunnel Route (Optional)

If you want web access to OpenClaw's control UI:

1. Go to **Cloudflare Zero Trust** → **Tunnels** → **your tunnel** → **Public Hostnames**
2. Add:

| Hostname | Service |
|----------|---------|
| `openclaw.yourdomain.com` | `http://openclaw.apps-restricted.svc.cluster.local:18789` |

3. Add Cloudflare Access policy to restrict access

---

## Verification & Testing

### Test Network Policies

```bash
# Start a test pod in restricted namespace
kubectl run test --namespace apps-restricted --rm -it --image=alpine -- sh

# Inside the pod, install curl
apk add curl

# Should SUCCEED (whitelisted)
curl -v https://api.anthropic.com
curl -v https://api.telegram.org

# Should FAIL (not whitelisted)
curl -v https://google.com
curl -v https://github.com
```

### Test OpenClaw via Telegram

1. Find your bot on Telegram
2. Send `/start` or any message
3. OpenClaw should respond (only to your user ID)

---

## Useful Commands Reference

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
cilium status

# Check network policies
kubectl get ciliumnetworkpolicies -A

# Logs for cloudflared
kubectl logs -n system-unrestricted -l app=cloudflared

# Logs for OpenClaw
kubectl logs -n apps-restricted -l app=openclaw -f

# Restart OpenClaw
kubectl rollout restart statefulset/openclaw -n apps-restricted

# Access node via Hetzner (when SSH is blocked)
# Cloud Console → Server → Console (>_)
```

---

## Security Summary

| Layer | Protection |
|-------|------------|
| **Network (Hetzner)** | Firewall blocks all inbound traffic |
| **Network (K8s)** | Cilium egress whitelist (Anthropic + Telegram only) |
| **Access** | Cloudflare Tunnel (outbound-only connection) |
| **Authentication** | Cloudflare Access + Telegram user ID whitelist |
| **Container** | Non-root user, dropped capabilities, resource limits |
| **Storage** | Isolated PVCs per replica |

### What This Setup Protects Against

- ✅ Direct server attacks (no public IPs)
- ✅ Unauthorized access (Cloudflare Access)
- ✅ Data exfiltration (egress whitelist)
- ✅ Lateral movement (namespace isolation)
- ✅ Resource abuse (container limits)

### What This Setup Does NOT Protect Against

- ⚠️ Anthropic API key compromise (rotate regularly)
- ⚠️ Telegram bot token leak (monitor usage)
- ⚠️ Claude providing incorrect information (you review responses)

---

## Maintenance

### Update OpenClaw

```bash
kubectl rollout restart statefulset/openclaw -n apps-restricted
```

### Rotate Secrets

```bash
kubectl delete secret openclaw-secrets -n apps-restricted
kubectl create secret generic openclaw-secrets \
  --namespace apps-restricted \
  --from-literal=ANTHROPIC_API_KEY=<NEW_KEY> \
  --from-literal=TELEGRAM_BOT_TOKEN=<NEW_TOKEN>
kubectl rollout restart statefulset/openclaw -n apps-restricted
```

### Backup PVC Data

```bash
# Create snapshot via Hetzner Console or API
# Volumes → Select volume → Create Snapshot
```

### Upgrade Kubernetes

See the [main README](../../README.md#maintenance--upgrade-kubernetes-with-kubeadm) for the full CKA-style kubeadm upgrade workflow.

---

## Troubleshooting

### OpenClaw Pod Not Starting

```bash
kubectl describe pod -n apps-restricted -l app=openclaw
kubectl logs -n apps-restricted -l app=openclaw --previous
```

### Network Policy Issues

```bash
# Check Cilium endpoint status
cilium endpoint list

# Check if FQDN rules are resolving
kubectl exec -n kube-system -it $(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -1) -- cilium fqdn cache list
```

### Cloudflare Tunnel Not Connecting

```bash
kubectl logs -n system-unrestricted -l app=cloudflared
```

### CSI Volume Not Attaching

```bash
kubectl describe pvc -n apps-restricted
kubectl get events -n apps-restricted
```

---

## License

This guide is provided as-is. Use at your own risk.

## Acknowledgments

- [Hetzner Cloud](https://www.hetzner.com/cloud)
- [Cloudflare Zero Trust](https://www.cloudflare.com/zero-trust/)
- [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [Cilium](https://cilium.io/)
- [OpenClaw](https://github.com/openclaw/openclaw)
