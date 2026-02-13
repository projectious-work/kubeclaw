# Secure OpenClaw Deployment on Hetzner Cloud

A step-by-step guide to deploying OpenClaw as an isolated AI problem-solving assistant on a secure, cost-effective Hetzner Cloud Kubernetes cluster with Cloudflare Tunnel access.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Hetzner Private Network                          │
│                        (10.0.0.0/24)                                │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                  K3s Cluster + Cilium                       │    │
│  │                                                             │    │
│  │   ┌─────────────────┐       ┌─────────────────┐            │    │
│  │   │     Node 1      │       │     Node 2      │            │    │
│  │   │  (K3s Server)   │◀─────▶│  (K3s Agent)    │            │    │
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
   - **Name:** `k3s-internal`
   - **IP Range:** `10.0.0.0/24`
   - **Subnet:** `10.0.0.0/24`
   - **Zone:** `eu-central` (or your preferred region)

### 1.2 Create Firewall

1. Go to **Firewalls** → **Create Firewall**
2. **Name:** `k3s-lockdown`
3. **Inbound Rules:** None (drop all by default)
4. **Outbound Rules:**

| Protocol | Port | Destination | Action |
|----------|------|-------------|--------|
| TCP | Any | `0.0.0.0/0` | Allow |
| UDP | Any | `0.0.0.0/0` | Allow |

### 1.3 Create API Token for CSI Driver

1. Go to **Security** → **API Tokens** → **Generate API Token**
2. **Name:** `k3s-csi`
3. **Permissions:** Read & Write
4. **Save the token securely** — you'll need it later

### 1.4 Create Server Nodes

Create two CX22 instances with these settings:

| Setting | Node 1 | Node 2 |
|---------|--------|--------|
| **Name** | `k3s-server` | `k3s-agent` |
| **Image** | Ubuntu 24.04 | Ubuntu 24.04 |
| **Type** | CX22 | CX22 |
| **Location** | Falkenstein (fsn1) | Falkenstein (fsn1) |
| **Networking** | IPv6 only ✓ | IPv6 only ✓ |
| **Private Network** | `k3s-internal` | `k3s-internal` |
| **Firewall** | `k3s-lockdown` | `k3s-lockdown` |
| **SSH Key** | Add your key | Add your key |

After creation, note the private IPs (should be `10.0.0.2` and `10.0.0.3`).

---

## Step 2: Install K3s with Cilium

Access both servers via **Hetzner Cloud Console** → **Server** → **Console (>_)**.

### 2.1 Node 1 (K3s Server)

```bash
# Update system
apt update && apt upgrade -y

# Install K3s server without Flannel (we'll use Cilium)
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --disable servicelb \
  --flannel-backend=none \
  --disable-network-policy \
  --node-ip 10.0.0.2 \
  --advertise-address 10.0.0.2 \
  --tls-san 10.0.0.2

# Get the token for joining agents
cat /var/lib/rancher/k3s/server/node-token
# Save this token!

# Verify K3s is running
kubectl get nodes
```

### 2.2 Node 2 (K3s Agent)

```bash
# Update system
apt update && apt upgrade -y

# Install K3s agent (replace <TOKEN> with token from Node 1)
curl -sfL https://get.k3s.io | K3S_URL=https://10.0.0.2:6443 \
  K3S_TOKEN=<TOKEN> sh -s - agent \
  --node-ip 10.0.0.3
```

### 2.3 Install Cilium (on Node 1)

```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
tar xzvf cilium-linux-${CLI_ARCH}.tar.gz
mv cilium /usr/local/bin/
rm cilium-linux-${CLI_ARCH}.tar.gz

# Install Cilium
cilium install --version 1.16.5

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
NAME         STATUS   ROLES                  AGE   VERSION
k3s-server   Ready    control-plane,master   5m    v1.31.x+k3s1
k3s-agent    Ready    <none>                 3m    v1.31.x+k3s1
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

# Set hcloud-volumes as default
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass hcloud-volumes -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
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
3. **Name:** `k3s-cluster`
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

### Upgrade K3s

```bash
# On each node
curl -sfL https://get.k3s.io | sh -
```

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
- [K3s](https://k3s.io/)
- [Cilium](https://cilium.io/)
- [OpenClaw](https://github.com/openclaw/openclaw)
