---
title: OpenClaw Deployment
weight: 60
description: Deploy OpenClaw into an egress-restricted namespace with Cilium FQDN policies.
---


A step-by-step guide to deploying OpenClaw as an isolated AI assistant on the KubeClaw cluster, accessible via Telegram, WhatsApp, or Signal, with a web-based Control UI exposed through Cloudflare Tunnel.

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
│  │     └─ OpenClaw (Cilium FQDN egress whitelist)             │    │
│  │          ├─ Telegram / WhatsApp / Signal                   │    │
│  │          └─ Control UI (:18789)                            │    │
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
                    ┌─────────┼─────────┐
                    │         │         │
                    ▼         ▼         ▼
               [Telegram] [WhatsApp] [Signal]
                    │
                    ▼
             [Control UI]
          (browser dashboard)
```

## Prerequisites

- A running KubeClaw cluster (see [Kubernetes guide]({{< relref "/docs/guide/kubernetes" >}}))
- Anthropic API key ([console.anthropic.com](https://console.anthropic.com))
- At least one messaging channel:

| Channel | What You Need |
|---------|--------------|
| **Telegram** | Bot Token from [@BotFather](https://t.me/BotFather), your Telegram User ID |
| **WhatsApp** | A phone number with WhatsApp, access to scan a QR code |
| **Signal** | A dedicated phone number, `signal-cli` installed in the container |

{{< alert title="Start with Telegram" >}}
Telegram is the simplest channel to set up — it only requires a bot token and user ID, with no interactive pairing or additional dependencies.

{{< /alert >}}
## Step 1: Infrastructure Setup

If you haven't already set up the Hetzner Cloud infrastructure, follow the [Quick Start]({{< relref "/docs/quick-start" >}}) and [Kubernetes guide]({{< relref "/docs/guide/kubernetes" >}}).

This guide assumes you have:

- A running Kubernetes cluster with Cilium CNI
- Hetzner CSI driver installed
- Namespaces created (`system-unrestricted`, `apps-restricted`)
- CoreDNS forwarding to DNS64 resolvers (see [Kubernetes guide, Step 4]({{< relref "/docs/guide/kubernetes" >}}))
- Cloudflare Tunnel configured on the master control node

## Step 2: Deploy OpenClaw

### 2.1 Create OpenClaw Configuration

OpenClaw uses [JSON5](https://json5.org/) configuration (supports comments and trailing commas). Create a ConfigMap with the base configuration:

{{< tabpane >}}
{{< tab header="Telegram" >}}

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  namespace: apps-restricted
data:
  openclaw.json: |
    {
      // Model configuration
      "agents": {
        "defaults": {
          "model": {
            // Primary model for conversations
            "primary": "anthropic/claude-sonnet-4-5-20250929",
            // Fallback chain: tried in order if the primary fails
            // (rate limit, auth error, timeout, outage)
            "fallbacks": [
              "anthropic/claude-haiku-4-5-20251001"
            ]
          },
          // Aliases appear in the Control UI model selector
          "models": {
            "anthropic/claude-sonnet-4-5-20250929": { "alias": "Sonnet" },
            "anthropic/claude-haiku-4-5-20251001": { "alias": "Haiku" },
            "anthropic/claude-opus-4-6": { "alias": "Opus" }
          }
        }
      },

      // Provider credentials
      "models": {
        "providers": {
          "anthropic": { "apiKey": "$ANTHROPIC_API_KEY" }
        }
      },

      // Messaging channel
      "channels": {
        "telegram": {
          "enabled": true,
          "dmPolicy": "allowlist",
          "allowFrom": ["<YOUR_TELEGRAM_USER_ID>"]
        }
      },

      // Gateway authentication (required for Control UI)
      "gateway": {
        "port": 18789,
        "bind": "lan",
        "auth": {
          "mode": "token"
        },
        "controlUi": {
          "enabled": true
        }
      }
    }
```

{{< /tab >}}
{{< tab header="WhatsApp" >}}

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  namespace: apps-restricted
data:
  openclaw.json: |
    {
      "agents": {
        "defaults": {
          "model": {
            "primary": "anthropic/claude-sonnet-4-5-20250929",
            "fallbacks": [
              "anthropic/claude-haiku-4-5-20251001"
            ]
          },
          "models": {
            "anthropic/claude-sonnet-4-5-20250929": { "alias": "Sonnet" },
            "anthropic/claude-haiku-4-5-20251001": { "alias": "Haiku" },
            "anthropic/claude-opus-4-6": { "alias": "Opus" }
          }
        }
      },

      "models": {
        "providers": {
          "anthropic": { "apiKey": "$ANTHROPIC_API_KEY" }
        }
      },

      "channels": {
        "whatsapp": {
          "enabled": true,
          "dmPolicy": "allowlist",
          "allowFrom": ["<YOUR_PHONE_E164>"]
        }
      },

      "gateway": {
        "port": 18789,
        "bind": "lan",
        "auth": {
          "mode": "token"
        },
        "controlUi": {
          "enabled": true
        }
      }
    }
```

{{< alert title="Phone number format" >}}
Use E.164 format for `allowFrom`, e.g. `"+15551234567"` (with country code, no spaces).

{{< /alert >}}
{{< /tab >}}
{{< tab header="Signal" >}}

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  namespace: apps-restricted
data:
  openclaw.json: |
    {
      "agents": {
        "defaults": {
          "model": {
            "primary": "anthropic/claude-sonnet-4-5-20250929",
            "fallbacks": [
              "anthropic/claude-haiku-4-5-20251001"
            ]
          },
          "models": {
            "anthropic/claude-sonnet-4-5-20250929": { "alias": "Sonnet" },
            "anthropic/claude-haiku-4-5-20251001": { "alias": "Haiku" },
            "anthropic/claude-opus-4-6": { "alias": "Opus" }
          }
        }
      },

      "models": {
        "providers": {
          "anthropic": { "apiKey": "$ANTHROPIC_API_KEY" }
        }
      },

      "channels": {
        "signal": {
          "enabled": true,
          "account": "<BOT_PHONE_E164>",
          "cliPath": "signal-cli",
          "dmPolicy": "allowlist",
          "allowFrom": ["<YOUR_PHONE_E164>"]
        }
      },

      "gateway": {
        "port": 18789,
        "bind": "lan",
        "auth": {
          "mode": "token"
        },
        "controlUi": {
          "enabled": true
        }
      }
    }
```

{{< alert title="Signal requires a custom container image" >}}
Signal integration requires `signal-cli` (a Java application) installed in the container. See [Step 3: Signal Setup](#signal-setup) for details.

{{< /alert >}}
{{< /tab >}}
{{< /tabpane >}}
Replace placeholders:

- `<YOUR_TELEGRAM_USER_ID>` — your numeric Telegram user ID (see [Step 3: Telegram Setup](#telegram-setup))
- `<YOUR_PHONE_E164>` — your phone number in E.164 format (e.g. `+15551234567`)
- `<BOT_PHONE_E164>` — dedicated phone number for the Signal bot

{{< alert title="Model configuration" >}}
The config above uses Sonnet as the primary model with Haiku as a fallback. OpenClaw automatically fails over when the primary model hits rate limits, auth errors, or timeouts.

**Customizing models:**

- **`model.primary`** — the default model for all conversations
- **`model.fallbacks`** — ordered list of backup models, tried in sequence on failure
- **`models`** — allowlist with aliases that appear in the Control UI model selector. You can switch models from the UI during a conversation
- **`models.providers`** — provider credentials. Supports Anthropic, OpenAI, Google Gemini, OpenRouter, and local models (Ollama). Add multiple providers to mix models:

```json5
"models": {
  "providers": {
    "anthropic": { "apiKey": "$ANTHROPIC_API_KEY" },
    "openai": { "apiKey": "$OPENAI_API_KEY" }
  }
}
```

- **Per-agent overrides** — individual agents in `agents.list[]` can override the default model. See the [OpenClaw model docs](https://docs.openclaw.ai/concepts/models) for details.

{{< /alert >}}
### 2.2 Create Secrets

Generate a gateway authentication token and create the Kubernetes secret:

{{< tabpane >}}
{{< tab header="Telegram" >}}

```bash
# Generate a strong gateway token
GATEWAY_TOKEN=$(openssl rand -hex 32)
echo "Save this token for Control UI access: $GATEWAY_TOKEN"

kubectl create secret generic openclaw-secrets \
  --namespace apps-restricted \
  --from-literal=ANTHROPIC_API_KEY=<YOUR_ANTHROPIC_API_KEY> \
  --from-literal=TELEGRAM_BOT_TOKEN=<YOUR_TELEGRAM_BOT_TOKEN> \
  --from-literal=OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
```

{{< /tab >}}
{{< tab header="WhatsApp" >}}

```bash
GATEWAY_TOKEN=$(openssl rand -hex 32)
echo "Save this token for Control UI access: $GATEWAY_TOKEN"

kubectl create secret generic openclaw-secrets \
  --namespace apps-restricted \
  --from-literal=ANTHROPIC_API_KEY=<YOUR_ANTHROPIC_API_KEY> \
  --from-literal=OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
```

{{< alert title="No API token needed" >}}
WhatsApp uses QR-code based linking — no API keys or tokens required. You'll pair your account interactively in [Step 3](#whatsapp-setup).

{{< /alert >}}
{{< /tab >}}
{{< tab header="Signal" >}}

```bash
GATEWAY_TOKEN=$(openssl rand -hex 32)
echo "Save this token for Control UI access: $GATEWAY_TOKEN"

kubectl create secret generic openclaw-secrets \
  --namespace apps-restricted \
  --from-literal=ANTHROPIC_API_KEY=<YOUR_ANTHROPIC_API_KEY> \
  --from-literal=OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
```

{{< /tab >}}
{{< /tabpane >}}
{{< alert title="Save the gateway token" >}}
The `GATEWAY_TOKEN` is required to access the Control UI dashboard. Save it securely — you'll need it when logging into the web interface.

{{< /alert >}}
### 2.3 Deploy OpenClaw StatefulSet

Create file `openclaw.yaml`:

{{< tabpane >}}
{{< tab header="Telegram" >}}

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
              npm install -g openclaw@latest &&
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
            - name: OPENCLAW_GATEWAY_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENCLAW_GATEWAY_TOKEN
            - name: OPENCLAW_CONFIG_PATH
              value: /etc/openclaw/openclaw.json
            - name: OPENCLAW_STATE_DIR
              value: /home/node/.openclaw
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
              mountPath: /etc/openclaw/openclaw.json
              subPath: openclaw.json
              readOnly: true
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
---
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

{{< /tab >}}
{{< tab header="WhatsApp" >}}

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
              npm install -g openclaw@latest &&
              openclaw gateway --port 18789
          env:
            - name: ANTHROPIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: ANTHROPIC_API_KEY
            - name: OPENCLAW_GATEWAY_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENCLAW_GATEWAY_TOKEN
            - name: OPENCLAW_CONFIG_PATH
              value: /etc/openclaw/openclaw.json
            - name: OPENCLAW_STATE_DIR
              value: /home/node/.openclaw
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
              mountPath: /etc/openclaw/openclaw.json
              subPath: openclaw.json
              readOnly: true
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
---
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

    # WhatsApp servers
    - toFQDNs:
        - matchName: "web.whatsapp.com"
        - matchPattern: "*.whatsapp.net"
        - matchPattern: "*.whatsapp.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
            - port: "5222"
              protocol: TCP
```

{{< /tab >}}
{{< tab header="Signal" >}}

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
          image: your-registry/openclaw-signal:latest  # Custom image with signal-cli
          env:
            - name: ANTHROPIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: ANTHROPIC_API_KEY
            - name: OPENCLAW_GATEWAY_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENCLAW_GATEWAY_TOKEN
            - name: OPENCLAW_CONFIG_PATH
              value: /etc/openclaw/openclaw.json
            - name: OPENCLAW_STATE_DIR
              value: /home/node/.openclaw
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
              mountPath: /etc/openclaw/openclaw.json
              subPath: openclaw.json
              readOnly: true
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
---
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

    # Signal servers
    - toFQDNs:
        - matchName: "chat.signal.org"
        - matchName: "storage.signal.org"
        - matchName: "cdn.signal.org"
        - matchName: "cdn2.signal.org"
        - matchName: "contentproxy.signal.org"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

{{< /tab >}}
{{< /tabpane >}}
{{< alert title="Cilium FQDN egress whitelist" >}}
Each manifest includes a `CiliumNetworkPolicy` that restricts OpenClaw's outbound traffic to only the Anthropic API and the messaging provider's servers. Combined with the namespace-level default-deny policy from the [Kubernetes guide]({{< relref "/docs/guide/kubernetes" >}}), this means OpenClaw **cannot** reach any other external service. Cilium's DNS proxy intercepts DNS64-synthesized AAAA responses and maps them to the FQDN, so these rules work transparently with NAT64.

{{< /alert >}}
{{< alert title="Startup time" >}}
The pod installs OpenClaw via `npm install -g` on every restart, which takes 1–2 minutes. For faster restarts, build a custom Docker image with OpenClaw baked in (see [Maintenance](#build-a-custom-image-optional)).

{{< /alert >}}
Apply:

```bash
kubectl apply -f openclaw-config.yaml
kubectl apply -f openclaw.yaml
```

### 2.4 Verify Deployment

```bash
# Watch pod status (wait for Running)
kubectl get pods -n apps-restricted -w

# Check logs (wait for "gateway listening" message)
kubectl logs -n apps-restricted -l app=openclaw -f

# Check persistent volume
kubectl get pvc -n apps-restricted
```

The gateway is ready when you see output like:

```
gateway listening on 0.0.0.0:18789
```

## Step 3: Configure Messaging Channel

### Telegram Setup

#### 3.1 Create a Bot

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts
3. Save the bot token (format: `123456789:ABCdefGHI...`)

#### 3.2 Find Your User ID

The safest way (no third-party bots required):

1. Message your new bot (send any message)
2. Check the OpenClaw logs:

```bash
kubectl logs -n apps-restricted -l app=openclaw -f
```

3. Look for your numeric ID in the `from.id` field of the incoming message log

Alternatively, query the Telegram Bot API directly:

```bash
curl "https://api.telegram.org/bot<BOT_TOKEN>/getUpdates"
```

#### 3.3 Update Configuration

Edit the ConfigMap with your actual user ID:

```bash
kubectl edit configmap openclaw-config -n apps-restricted
```

Replace `<YOUR_TELEGRAM_USER_ID>` with your numeric ID, then restart:

```bash
kubectl rollout restart statefulset/openclaw -n apps-restricted
```

#### 3.4 Test

1. Open Telegram and find your bot
2. Send any message
3. If using `dmPolicy: "pairing"`, approve the pairing request:

```bash
kubectl exec -n apps-restricted -it openclaw-0 -- openclaw pairing list telegram
kubectl exec -n apps-restricted -it openclaw-0 -- openclaw pairing approve telegram <CODE>
```

If using `dmPolicy: "allowlist"` (recommended), your user ID is pre-approved and the bot responds immediately.

---

### WhatsApp Setup

#### 3.1 Link Your WhatsApp Account

WhatsApp uses QR-code based pairing — no API keys needed. Exec into the pod and run the login command:

```bash
kubectl exec -n apps-restricted -it openclaw-0 -- openclaw channels login --channel whatsapp
```

This displays a QR code in the terminal. Scan it with your WhatsApp app:

1. Open WhatsApp on your phone
2. Go to **Settings** > **Linked Devices** > **Link a Device**
3. Scan the QR code

{{< alert title="Dedicated number recommended" >}}
Using a separate WhatsApp number (not your personal one) provides cleaner access boundaries and avoids self-chat confusion. If using your personal number, add `"selfChatMode": true` to the WhatsApp channel configuration.

{{< /alert >}}
#### 3.2 Verify Connection

After linking, restart the gateway to pick up the stored credentials:

```bash
kubectl rollout restart statefulset/openclaw -n apps-restricted
```

Check logs for WhatsApp connection:

```bash
kubectl logs -n apps-restricted -l app=openclaw -f
```

#### 3.3 Network Policy Considerations

WhatsApp (via the Baileys library) connects to multiple WhatsApp servers. The key domains include:

- `web.whatsapp.com`
- `*.whatsapp.net` (messaging, media)

{{< alert title="WhatsApp credentials persist" >}}
WhatsApp credentials are stored at `~/.openclaw/credentials/whatsapp/` on the persistent volume. They survive pod restarts — you only need to scan the QR code once.

{{< /alert >}}
---

### Signal Setup

{{< alert title="Advanced setup" >}}
Signal requires `signal-cli`, a Java-based application, installed in the container. This section requires building a custom Docker image.

{{< /alert >}}
#### 3.1 Build a Custom Image with signal-cli

Create a `Dockerfile.openclaw-signal`:

```dockerfile
FROM node:22-slim

# Install signal-cli native build
RUN apt-get update && apt-get install -y curl && \
    VERSION=$(curl -Ls -o /dev/null -w '%{url_effective}' \
      https://github.com/AsamK/signal-cli/releases/latest | \
      sed -e 's/^.*\/v//') && \
    curl -L -O "https://github.com/AsamK/signal-cli/releases/download/v${VERSION}/signal-cli-${VERSION}-Linux-native.tar.gz" && \
    tar xf "signal-cli-${VERSION}-Linux-native.tar.gz" -C /opt && \
    ln -sf /opt/signal-cli /usr/local/bin/signal-cli && \
    rm -f "signal-cli-${VERSION}-Linux-native.tar.gz" && \
    apt-get remove -y curl && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Install OpenClaw globally
RUN npm install -g openclaw@latest

USER 1000
WORKDIR /app

CMD ["openclaw", "gateway", "--port", "18789"]
```

Build and push to a registry accessible from your cluster, then update the StatefulSet `image` field.

#### 3.2 Register the Bot Phone Number

Exec into the pod and register:

```bash
kubectl exec -n apps-restricted -it openclaw-0 -- sh

# Register the bot number (may require captcha)
signal-cli -a +<BOT_PHONE_NUMBER> register

# If captcha required, visit https://signalcaptchas.org/registration/generate.html
# then run:
signal-cli -a +<BOT_PHONE_NUMBER> register --captcha '<CAPTCHA_URL>'

# Verify with the SMS code
signal-cli -a +<BOT_PHONE_NUMBER> verify <CODE>
```

#### 3.3 Alternatively: Link an Existing Account

If you prefer to link to an existing Signal account (not recommended for production):

```bash
kubectl exec -n apps-restricted -it openclaw-0 -- signal-cli link -n "OpenClaw"
```

Scan the QR code in your Signal app under **Settings** > **Linked Devices**.

{{< alert title="Registering deauthenticates" >}}
Registering a phone number with `signal-cli` deauthenticates the main Signal app for that number. Use a **dedicated bot number** to avoid losing access to your personal Signal account.

{{< /alert >}}
## Step 4: Expose Control UI via Cloudflare Tunnel

OpenClaw includes a web-based Control UI (dashboard) for managing sessions, viewing logs, and chatting directly. Since the dashboard is an admin surface, we protect it with two layers: **Cloudflare Access** (identity verification) and **gateway token** (application authentication).

### 4.1 Add Tunnel Route

In **Cloudflare Zero Trust** > **Networks** > **Tunnels** > **your tunnel** > **Public Hostnames**, add:

| Hostname | Service |
|----------|---------|
| `openclaw.yourdomain.com` | `http://openclaw.apps-restricted.svc.cluster.local:18789` |

{{< alert title="SSL/TLS settings" >}}
In Cloudflare dashboard under your domain > **SSL/TLS** > **Overview**, set the mode to **Full** (not "Full (strict)") since the origin (OpenClaw gateway) serves HTTP, not HTTPS. Cloudflare terminates TLS at the edge.

{{< /alert >}}
### 4.2 Create Cloudflare Access Policy

Protect the dashboard route so only authenticated users can reach it:

1. Go to **Cloudflare Zero Trust** > **Access** > **Applications**
2. Click **Add an Application** > **Self-hosted**
3. Configure:

| Field | Value |
|-------|-------|
| **Application name** | OpenClaw Dashboard |
| **Session Duration** | 24 hours |
| **Application domain** | `openclaw.yourdomain.com` |

4. Add a **Policy**:

| Field | Value |
|-------|-------|
| **Policy name** | Allowed Users |
| **Action** | Allow |
| **Include** | Emails — `your-email@example.com` |

5. Under **Authentication**, select your identity provider or use **One-time PIN** (sends a verification code to your email — no IdP setup required)

{{< alert title="Two-layer authentication" >}}
With this setup, accessing `openclaw.yourdomain.com` requires:

1. **Cloudflare Access**: Verifies your identity (email + OTP or IdP login)
2. **Gateway token**: Entered in the Control UI settings panel (the token from [Step 2.2](#22-create-secrets))

Even if someone bypasses Cloudflare Access, they cannot use the dashboard without the gateway token.

{{< /alert >}}
### 4.3 Access the Dashboard

1. Navigate to `https://openclaw.yourdomain.com` in your browser
2. Authenticate with Cloudflare Access (email OTP or your identity provider)
3. The Control UI loads — enter the gateway token when prompted
4. The token is stored in your browser's `localStorage` for future sessions

The Control UI provides:

- **Chat**: Direct conversation with the AI agent
- **Sessions**: View and manage active sessions across all channels
- **Channels**: Status of connected messaging channels (Telegram, WhatsApp, Signal)
- **Logs**: Live gateway log tailing
- **Configuration**: Edit settings with concurrent edit protection
- **Skills**: Install and manage skills

## Step 5: Verify & Test

### Test Messaging

{{< tabpane >}}
{{< tab header="Telegram" >}}

1. Find your bot on Telegram
2. Send any message
3. OpenClaw should respond (only to your user ID)

{{< /tab >}}
{{< tab header="WhatsApp" >}}

1. Send a message to the linked WhatsApp number
2. OpenClaw should respond (only to numbers in `allowFrom`)

{{< /tab >}}
{{< tab header="Signal" >}}

1. Send a message to the bot's Signal number
2. OpenClaw should respond (only to numbers in `allowFrom`)

{{< /tab >}}
{{< /tabpane >}}
### Test Control UI

1. Open `https://openclaw.yourdomain.com`
2. Verify Cloudflare Access prompts for authentication
3. Enter the gateway token in the UI
4. Send a test message in the chat interface

### Check Pod Health

```bash
# Pod status
kubectl get pods -n apps-restricted

# Logs
kubectl logs -n apps-restricted -l app=openclaw -f

# PVC status
kubectl get pvc -n apps-restricted

# Exec into pod for diagnostics
kubectl exec -n apps-restricted -it openclaw-0 -- openclaw doctor
kubectl exec -n apps-restricted -it openclaw-0 -- openclaw status
```

## Maintenance

### Update OpenClaw

The pod installs `openclaw@latest` on every restart, so a simple restart pulls the newest version:

```bash
kubectl rollout restart statefulset/openclaw -n apps-restricted
```

### Rotate Secrets

```bash
# Generate new gateway token
NEW_GATEWAY_TOKEN=$(openssl rand -hex 32)
echo "New gateway token: $NEW_GATEWAY_TOKEN"

# Delete and recreate the secret (adjust for your channel)
kubectl delete secret openclaw-secrets -n apps-restricted
kubectl create secret generic openclaw-secrets \
  --namespace apps-restricted \
  --from-literal=ANTHROPIC_API_KEY=<YOUR_KEY> \
  --from-literal=TELEGRAM_BOT_TOKEN=<YOUR_TOKEN> \
  --from-literal=OPENCLAW_GATEWAY_TOKEN=$NEW_GATEWAY_TOKEN

# Restart to pick up new secrets
kubectl rollout restart statefulset/openclaw -n apps-restricted
```

{{< alert title="Update your browser" >}}
After rotating the gateway token, you'll need to enter the new token in the Control UI settings panel.

{{< /alert >}}
### Build a Custom Image (Optional)

For faster pod restarts (skipping `npm install` on every boot), build a custom image:

```dockerfile
FROM node:22-slim
RUN npm install -g openclaw@latest
USER 1000
WORKDIR /app
CMD ["openclaw", "gateway", "--port", "18789"]
```

{{< alert title="Pin the version" >}}
In production, pin to a specific version (`openclaw@1.2.3`) rather than `@latest` to avoid unexpected breaking changes on restart.

{{< /alert >}}
### Useful Commands

```bash
# OpenClaw logs
kubectl logs -n apps-restricted -l app=openclaw -f

# Restart OpenClaw
kubectl rollout restart statefulset/openclaw -n apps-restricted

# Run diagnostics
kubectl exec -n apps-restricted -it openclaw-0 -- openclaw doctor

# Check channel status
kubectl exec -n apps-restricted -it openclaw-0 -- openclaw channels status --probe

# Interactive shell
kubectl exec -n apps-restricted -it openclaw-0 -- sh

# Check Cilium endpoint status (from control node)
cilium endpoint list

# Check FQDN cache (from control node)
kubectl exec -n kube-system -it \
  $(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -1) \
  -- cilium fqdn cache list
```

### Configuration Changes

To update the OpenClaw configuration:

```bash
# Edit the ConfigMap
kubectl edit configmap openclaw-config -n apps-restricted

# Restart to apply
kubectl rollout restart statefulset/openclaw -n apps-restricted
```

Alternatively, update the YAML file and reapply:

```bash
kubectl apply -f openclaw-config.yaml
kubectl rollout restart statefulset/openclaw -n apps-restricted
```
