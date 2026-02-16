# OpenClaw Deployment

A step-by-step guide to deploying OpenClaw as an isolated AI problem-solving assistant on the KubeClaw cluster with Cloudflare Tunnel access.

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
│  │   │  (control plane)│◄─────►│  (worker node)  │            │    │
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

## Prerequisites

- A running KubeClaw cluster (see [Kubernetes guide](kubernetes.md))
- Anthropic API key
- Telegram Bot Token (create via @BotFather)
- Your Telegram User ID

## Step 1: Infrastructure Setup

If you haven't already set up the Hetzner Cloud infrastructure, follow the [Quick Start](../getting-started/quick-start.md) and [Kubernetes guide](kubernetes.md).

This guide assumes you have:

- A running Kubernetes cluster with Cilium CNI
- Hetzner CSI driver installed
- Namespaces created (`system-unrestricted`, `apps-restricted`)

## Step 2: Create Network Policies

### OpenClaw Egress Whitelist (Cilium)

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

```bash
kubectl apply -f openclaw-egress.yaml
```

## Step 3: Deploy OpenClaw

### 3.1 Create OpenClaw Configuration

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

### 3.2 Create OpenClaw Secrets

```bash
kubectl create secret generic openclaw-secrets \
  --namespace apps-restricted \
  --from-literal=ANTHROPIC_API_KEY=<YOUR_ANTHROPIC_API_KEY> \
  --from-literal=TELEGRAM_BOT_TOKEN=<YOUR_TELEGRAM_BOT_TOKEN>
```

### 3.3 Deploy OpenClaw StatefulSet

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

### 3.4 Verify Deployment

```bash
# Check pod status
kubectl get pods -n apps-restricted

# Check logs
kubectl logs -n apps-restricted -l app=openclaw -f

# Check PVC
kubectl get pvc -n apps-restricted
```

## Step 4: Configure Cloudflare Tunnel Route (Optional)

If you want web access to OpenClaw's control UI:

1. Go to **Cloudflare Zero Trust** > **Tunnels** > **your tunnel** > **Public Hostnames**
2. Add:

| Hostname | Service |
|----------|---------|
| `openclaw.yourdomain.com` | `http://openclaw.apps-restricted.svc.cluster.local:18789` |

3. Add Cloudflare Access policy to restrict access

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

### Useful Commands

```bash
# Logs for OpenClaw
kubectl logs -n apps-restricted -l app=openclaw -f

# Restart OpenClaw
kubectl rollout restart statefulset/openclaw -n apps-restricted

# Check Cilium endpoint status
cilium endpoint list

# Check if FQDN rules are resolving
kubectl exec -n kube-system -it \
  $(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -1) \
  -- cilium fqdn cache list
```
