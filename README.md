# Hetzner Cloud Kubernetes Cluster mit OpenTofu

Dieses Projekt erstellt automatisiert einen sicheren, IPv6-only Kubernetes-Cluster auf Hetzner Cloud mit SSH-Zugang über Cloudflare Tunnel.

## Architektur

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloudflare Tunnel                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Hetzner Cloud                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Private Network (10.0.0.0/24)              │    │
│  │                                                         │    │
│  │   ┌─────────────────┐       ┌─────────────────┐        │    │
│  │   │  control-node   │       │  worker-node    │        │    │
│  │   │    10.0.0.2     │◄─────►│    10.0.0.3+    │        │    │
│  │   │  (cloudflared)  │       │  (isoliert)     │        │    │
│  │   └─────────────────┘       └─────────────────┘        │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Voraussetzungen

- [OpenTofu](https://opentofu.org/) >= 1.6.0 (oder Terraform >= 1.5.0)
- Hetzner Cloud Account mit API Token
- Cloudflare Account mit konfigurierter Domain
- `cloudflared` auf dem lokalen Rechner installiert

## Quick Start

### 1. Repository klonen / Dateien kopieren

```bash
git clone <repository-url>
cd tofu-hetzner-cluster
```

### 2. Konfiguration anpassen

```bash
cp terraform.tfvars.example terraform.tfvars
# Bearbeite terraform.tfvars mit deinen Werten
```

**Wichtig:** Ersetze mindestens:
- `hcloud_token` - Dein Hetzner API Token
- `cloudflare_tunnel_domain` - Deine Domain (z.B. `console.example.org`)
- `root_password` - Ein sicheres Passwort

### 3. Infrastruktur erstellen

```bash
# Initialisieren
tofu init

# Plan prüfen
tofu plan

# Anwenden
tofu apply
```

### 4. SSH-Keys exportieren

```bash
# Private Keys exportieren
tofu output -raw control_node_ssh_private_key > ~/.ssh/k3s-cluster_control-node_key
tofu output -raw worker_node_ssh_private_key > ~/.ssh/k3s-cluster_worker-node_key

# Berechtigungen setzen
chmod 600 ~/.ssh/k3s-cluster_*_key
```

### 5. SSH-Config einrichten

```bash
tofu output -raw ssh_config_snippet >> ~/.ssh/config
```

### 6. Mit Control-Node verbinden (IPv6)

```bash
# IPv6-Adresse aus Output verwenden
ssh -i ~/.ssh/k3s-cluster_control-node_key kubernetes-admin@<ipv6-adresse>
```

### 7. Cloudflare Tunnel installieren

Auf dem Control-Node:

```bash
sudo cloudflared service install <DEIN_TUNNEL_TOKEN>
sudo systemctl status cloudflared
```

### 8. Öffentliche IPs deaktivieren

Nach erfolgreicher Tunnel-Einrichtung:

```bash
# In terraform.tfvars ändern:
# enable_public_ipv6 = false

tofu apply
```

## Cloudflare Tunnel einrichten

### Im Cloudflare Zero Trust Dashboard

1. **Networks → Tunnels → Create a tunnel**
2. Name vergeben, Token kopieren
3. **Public Hostname hinzufügen:**
   - Subdomain: `console`
   - Domain: Deine Domain
   - Type: `SSH`
   - URL: `localhost:22`

4. **Access → Applications → Add application**
   - Self-hosted
   - Domain: `console.example.org`
   - Policy erstellen (z.B. E-Mail-Allowlist)

## Variablen

| Variable | Beschreibung | Default |
|----------|--------------|---------|
| `hcloud_token` | Hetzner API Token | - |
| `cluster_name` | Prefix für alle Ressourcen | `k3s-cluster` |
| `location` | Hetzner Datacenter | `fsn1` |
| `control_node_type` | Server-Typ Control-Node | `cx22` |
| `worker_node_type` | Server-Typ Worker-Nodes | `cx22` |
| `worker_node_count` | Anzahl Worker-Nodes | `1` |
| `enable_public_ipv6` | IPv6 aktivieren | `true` |
| `admin_user` | SSH-Benutzername | `kubernetes-admin` |
| `cloudflare_tunnel_domain` | Domain für Tunnel | `` |

## Outputs

| Output | Beschreibung |
|--------|--------------|
| `control_node_ipv6` | IPv6-Adresse des Control-Node |
| `control_node_private_ip` | Private IP des Control-Node |
| `worker_node_private_ips` | Private IPs der Worker-Nodes |
| `control_node_ssh_private_key` | SSH Private Key (sensitiv) |
| `ssh_config_snippet` | Fertige SSH-Config |
| `next_steps` | Anleitung für nächste Schritte |

## Dateien

```
.
├── main.tf                     # Hauptkonfiguration
├── variables.tf                # Variablen-Definitionen
├── outputs.tf                  # Output-Definitionen
├── terraform.tfvars.example    # Beispiel-Konfiguration
├── .gitignore                  # Git-Ignore-Regeln
├── README.md                   # Diese Datei
└── cloud-init/
    ├── control-node.yaml.tpl   # Cloud-Init Template Control-Node
    └── worker-node.yaml.tpl    # Cloud-Init Template Worker-Node
```

## Sicherheitshinweise

- **API Token:** Niemals in Git einchecken
- **terraform.tfvars:** Enthält sensible Daten, nicht committen
- **SSH-Keys:** Werden automatisch generiert, sicher aufbewahren
- **Root-Passwort:** Nur für Notfall-Zugang via Web-Console

## Ressourcen löschen

```bash
tofu destroy
```

**Achtung:** Dies löscht alle erstellten Server, Netzwerke und Firewalls unwiderruflich!

## Troubleshooting

### Cloudflared startet nicht

Prüfe ob `/etc/cloudflared/config.yml` enthält:
```yaml
edge-ip-version: "6"
```

### SSH-Verbindung schlägt fehl

1. Prüfe ob `cloudflared` lokal installiert ist
2. Prüfe den Pfad in der SSH-Config (`/opt/homebrew/bin/cloudflared` für Apple Silicon)
3. Prüfe ob der Tunnel in Cloudflare als "Connected" angezeigt wird

### Worker-Node nicht erreichbar

1. Prüfe ob der Control-Node läuft
2. Prüfe ob ProxyJump in SSH-Config korrekt ist
3. Teste Ping vom Control-Node: `ping 10.0.0.3`

## Lizenz

MIT
