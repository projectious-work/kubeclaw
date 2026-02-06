# Hetzner Cloud IPv6-Only Cluster mit Cloudflare Tunnel

Eine Schritt-für-Schritt-Anleitung zum Aufbau eines sicheren, IPv6-only Server-Clusters bei Hetzner Cloud mit SSH-Zugang über Cloudflare Tunnel.

## Übersicht

Dieses Setup erstellt eine sichere Server-Infrastruktur mit folgenden Eigenschaften:

- **Keine öffentlichen IPv4/IPv6-Adressen** (nach Einrichtung)
- **SSH-Zugang ausschließlich über Cloudflare Tunnel**
- **Interne Kommunikation über Hetzner Private Network**
- **Gehärtete SSH-Konfiguration mit fail2ban und UFW**

### Architektur

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloudflare Tunnel                             │
│                 console.bernhard-gerlach.org                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Hetzner Cloud                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Private Network (10.0.0.0/8)               │    │
│  │                                                         │    │
│  │   ┌─────────────────┐       ┌─────────────────┐        │    │
│  │   │  control-node   │       │  worker-node    │        │    │
│  │   │    10.0.0.2     │◄─────►│    10.0.0.3     │        │    │
│  │   │  (cloudflared)  │       │  (isoliert)     │        │    │
│  │   └─────────────────┘       └─────────────────┘        │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Voraussetzungen

- Hetzner Cloud Account
- Cloudflare Account mit eigener Domain
- macOS/Linux Rechner mit SSH
- `cloudflared` lokal installiert (`brew install cloudflared`)

## Schritt 1: Hetzner Private Network erstellen

1. Öffne die [Hetzner Cloud Console](https://console.hetzner.cloud)
2. Wähle dein Projekt
3. Gehe zu **Networks** → **Create Network**
4. Konfiguriere:
   - **Name**: `k3s-network` (oder beliebig)
   - **IP Range**: `10.0.0.0/8`
5. **Create Network** klicken

## Schritt 2: SSH-Keys generieren

Erstelle für jeden Server einen eigenen SSH-Key:

```bash
# Control Node Key
ssh-keygen -t ed25519 -f ~/.ssh/2026-02-05_k3s-cluster_control-node_key -C "control-node"

# Worker Node Key
ssh-keygen -t ed25519 -f ~/.ssh/2026-02-05_k3s-cluster_worker-node_key -C "worker-node"

# Temporärer Admin Node Key (für initiale Einrichtung)
ssh-keygen -t ed25519 -f ~/.ssh/2026-02-05_k3s-cluster_admin-node_key -C "admin-node"
```

## Schritt 3: Temporären Admin-Node erstellen

Da die Hetzner Web-Console (VNC) Probleme mit Copy/Paste hat (besonders unter Firefox/macOS), erstellen wir einen temporären Admin-Server mit öffentlicher IPv6-Adresse für die initiale Einrichtung.

### Cloud-Init für Admin-Node

```yaml
#cloud-config

users:
  - name: kubernetes-admin
    groups: users, admin, sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... DEIN_ADMIN_NODE_PUBLIC_KEY

keyboard:
  layout: de
  variant: mac

packages:
  - fail2ban
  - ufw

package_update: true
package_upgrade: true

write_files:
  - path: /etc/ssh/sshd_config.d/ssh-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      ChallengeResponseAuthentication no
      MaxAuthTries 3
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding no
      AllowUsers kubernetes-admin
      ClientAliveInterval 300
      ClientAliveCountMax 2

  - path: /etc/fail2ban/jail.local
    content: |
      [sshd]
      enabled = true
      port = 22
      banaction = iptables-multiport
      maxretry = 3
      findtime = 600
      bantime = 3600

runcmd:
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - ufw allow 22
  - ufw --force enable
  - reboot
```

### Server erstellen

1. **Servers** → **Add Server**
2. **Location**: Beliebig (z.B. Falkenstein)
3. **Image**: Ubuntu 24.04
4. **Type**: CX22 (kleinste Größe reicht)
5. **Networking**: 
   - Public IPv6 aktiviert
   - Private Network: `k3s-network` hinzufügen
6. **SSH Keys**: Admin-Node Key hinzufügen
7. **Cloud config**: Obige YAML einfügen
8. **Create & Buy now**

### IPv6-Adresse ermitteln

Die IPv6-Adresse wird in Hetzner nur als Subnetz angezeigt (z.B. `2a01:4f8:1c19:c886::/64`). Die tatsächliche Server-Adresse ist typischerweise `::1` angehängt:

```
2a01:4f8:1c19:c886::1
```

### Verbindung testen

```bash
ssh -i ~/.ssh/2026-02-05_k3s-cluster_admin-node_key kubernetes-admin@2a01:4f8:1c19:c886::1
```

> **Hinweis**: Dein lokaler Rechner benötigt IPv6-Konnektivität. Teste mit `ping6 google.com`.

## Schritt 4: Control-Node erstellen (mit Cloudflare Tunnel)

### Cloud-Init für Control-Node

```yaml
#cloud-config

users:
  - name: root
    plain_text_passwd: 'SICHERES_PASSWORT_HIER'
    lock_passwd: false
  - name: kubernetes-admin
    groups: users, admin, sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... DEIN_CONTROL_NODE_PUBLIC_KEY

keyboard:
  layout: de
  variant: mac

packages:
  - fail2ban
  - ufw
  - curl
  - wget

package_update: true
package_upgrade: true

write_files:
  - path: /etc/ssh/sshd_config.d/ssh-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      ChallengeResponseAuthentication no
      MaxAuthTries 3
      X11Forwarding no
      AllowAgentForwarding no
      AllowTcpForwarding yes
      AllowUsers kubernetes-admin
      ClientAliveInterval 300
      ClientAliveCountMax 2

  - path: /etc/fail2ban/jail.local
    content: |
      [sshd]
      enabled = true
      port = 22
      banaction = iptables-multiport
      maxretry = 3
      findtime = 600
      bantime = 3600

  - path: /etc/cloudflared/config.yml
    content: |
      edge-ip-version: "6"

runcmd:
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment 'SSH intern'
  - ufw allow from 127.0.0.1 to any port 22 proto tcp comment 'SSH via Tunnel'
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw --force enable
  - mkdir -p --mode=0755 /usr/share/keyrings
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
  - echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
  - mkdir -p /etc/cloudflared
  - apt-get update && apt-get install -y cloudflared
  - reboot
```

### Server erstellen

1. **Servers** → **Add Server**
2. **Image**: Ubuntu 24.04
3. **Type**: Nach Bedarf (z.B. CX22 oder größer)
4. **Networking**:
   - **Public IPv4**: Deaktiviert
   - **Public IPv6**: Aktiviert (temporär, für Installation)
   - **Private Network**: `k3s-network` hinzufügen
5. **SSH Keys**: Control-Node Key hinzufügen
6. **Cloud config**: Obige YAML einfügen
7. **Create & Buy now**

> **Wichtig**: Die `edge-ip-version: "6"` Einstellung ist essentiell! Cloudflared versucht standardmäßig IPv4-Verbindungen zu Cloudflare's Edge-Servern. Da der Server IPv6-only ist, muss dies auf `"6"` (als String!) gesetzt werden.

## Schritt 5: Worker-Node erstellen (isoliert)

### Cloud-Init für Worker-Node

```yaml
#cloud-config

users:
  - name: root
    plain_text_passwd: 'SICHERES_PASSWORT_HIER'
    lock_passwd: false
  - name: kubernetes-admin
    groups: users, admin, sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... DEIN_WORKER_NODE_PUBLIC_KEY

keyboard:
  layout: de
  variant: mac

packages:
  - fail2ban
  - ufw

package_update: true
package_upgrade: true

write_files:
  - path: /etc/ssh/sshd_config.d/ssh-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      ChallengeResponseAuthentication no
      MaxAuthTries 3
      AllowTcpForwarding no
      X11Forwarding no
      AllowAgentForwarding no
      AllowUsers kubernetes-admin
      ClientAliveInterval 300
      ClientAliveCountMax 2

  - path: /etc/fail2ban/jail.local
    content: |
      [sshd]
      enabled = true
      port = 22
      banaction = iptables-multiport
      maxretry = 3
      findtime = 600
      bantime = 3600

runcmd:
  - systemctl enable fail2ban
  - systemctl start fail2ban
  - ufw default deny incoming
  - ufw default deny outgoing
  - ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment 'SSH intern'
  - ufw allow from 10.0.0.0/8 proto icmp comment 'ICMP intern'
  - ufw allow out to 10.0.0.0/8 comment 'Ausgehend intern'
  - ufw allow out to 185.12.64.1 port 53 proto udp comment 'DNS Hetzner'
  - ufw allow out to 185.12.64.2 port 53 proto udp comment 'DNS Hetzner'
  - ufw allow out to any port 80 proto tcp comment 'HTTP Updates'
  - ufw allow out to any port 443 proto tcp comment 'HTTPS Updates'
  - ufw --force enable
  - reboot
```

### Server erstellen

1. **Servers** → **Add Server**
2. **Image**: Ubuntu 24.04
3. **Type**: Nach Bedarf
4. **Networking**:
   - **Public IPv4**: Deaktiviert
   - **Public IPv6**: Aktiviert (temporär)
   - **Private Network**: `k3s-network` hinzufügen
5. **SSH Keys**: Worker-Node Key hinzufügen
6. **Cloud config**: Obige YAML einfügen
7. **Create & Buy now**

## Schritt 6: Cloudflare Tunnel einrichten

### 6.1 Tunnel in Cloudflare erstellen

1. Öffne das [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com)
2. Gehe zu **Networks** → **Tunnels**
3. Klicke **Create a tunnel**
4. Wähle **Cloudflared** als Connector
5. **Tunnel name**: z.B. `hetzner-cluster`
6. **Save tunnel**
7. **Kopiere den Install-Token** (wird im nächsten Schritt benötigt)

### 6.2 Cloudflared auf Control-Node installieren

Verbinde dich über den Admin-Node mit dem Control-Node:

```bash
# Zuerst zum Admin-Node
ssh admin-node

# Dann zum Control-Node (über internes Netzwerk)
ssh kubernetes-admin@10.0.0.2
```

Auf dem Control-Node:

```bash
# Tunnel mit Token installieren
sudo cloudflared service install <DEIN_TUNNEL_TOKEN>

# Status prüfen
sudo systemctl status cloudflared
```

Der Tunnel sollte jetzt in Cloudflare als "Connected" angezeigt werden.

### 6.3 SSH-Zugang in Cloudflare konfigurieren

1. Im Cloudflare Zero Trust Dashboard → **Networks** → **Tunnels**
2. Klicke auf deinen Tunnel → **Configure**
3. Gehe zum Tab **Public Hostname**
4. Klicke **Add a public hostname**
5. Konfiguriere:
   - **Subdomain**: `console`
   - **Domain**: `bernhard-gerlach.org` (deine Domain)
   - **Type**: `SSH`
   - **URL**: `localhost:22`
6. **Save hostname**

### 6.4 Access Application erstellen

1. Gehe zu **Access** → **Applications**
2. Klicke **Add an application**
3. Wähle **Self-hosted**
4. Konfiguriere:
   - **Application name**: `SSH Console`
   - **Session Duration**: Nach Bedarf (z.B. 24 hours)
   - **Application domain**: `console.bernhard-gerlach.org`
5. Klicke **Next**
6. Erstelle eine **Policy**:
   - **Policy name**: z.B. `Allow Admin`
   - **Action**: `Allow`
   - **Include**: Deine E-Mail-Adresse oder Identity Provider
7. **Save**

## Schritt 7: Lokale SSH-Konfiguration

### Cloudflared auf dem lokalen Mac installieren

```bash
brew install cloudflared
```

### SSH-Config erstellen/erweitern

Füge folgendes zu `~/.ssh/config` hinzu:

```
# Temporärer Admin-Node (kann nach Einrichtung entfernt werden)
Host admin-node
    HostName 2a01:4f8:1c19:c886::1
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/2026-02-05_k3s-cluster_admin-node_key
    PreferredAuthentications publickey

# Control-Node via Admin-Node (temporär)
Host control-node-01
    HostName 10.0.0.2
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/2026-02-05_k3s-cluster_control-node_key
    PreferredAuthentications publickey
    ProxyJump admin-node

# Worker-Node via Admin-Node (temporär)
Host worker-node-01
    HostName 10.0.0.3
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/2026-02-05_k3s-cluster_worker-node_key
    PreferredAuthentications publickey
    ProxyJump admin-node

# Control-Node via Cloudflare Tunnel (permanent)
Host console.bernhard-gerlach.org
    HostName console.bernhard-gerlach.org
    User kubernetes-admin
    IdentityFile ~/.ssh/2026-02-05_k3s-cluster_control-node_key
    ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h
```

> **Hinweis für Intel Macs**: Ersetze `/opt/homebrew/bin/cloudflared` durch `/usr/local/bin/cloudflared`

### Verbindung testen

```bash
# Via Cloudflare Tunnel
ssh console.bernhard-gerlach.org
```

Beim ersten Mal öffnet sich ein Browser-Fenster für die Cloudflare Access Authentifizierung.

## Schritt 8: Öffentliche IPs deaktivieren

Nachdem der Cloudflare Tunnel funktioniert:

1. **Hetzner Console** → **Servers** → **control-node-01**
2. **Networking** → **Public Network** → **Disable**
3. Wiederhole für **worker-node-01**

Die Server sind jetzt nur noch über den Cloudflare Tunnel (Control-Node) bzw. das interne Netzwerk (Worker-Node) erreichbar.

## Schritt 9: Admin-Node entfernen

Der temporäre Admin-Node wird nicht mehr benötigt:

1. **Hetzner Console** → **Servers** → **admin-node**
2. **Delete** → Bestätigen

Entferne auch die entsprechenden Einträge aus `~/.ssh/config` und passe die `ProxyJump`-Einträge an:

```
# Worker-Node via Cloudflare Tunnel (über Control-Node)
Host worker-node-01
    HostName 10.0.0.3
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/2026-02-05_k3s-cluster_worker-node_key
    PreferredAuthentications publickey
    ProxyJump console.bernhard-gerlach.org
```

## Finale SSH-Konfiguration

Nach Abschluss aller Schritte:

```
# Control-Node via Cloudflare Tunnel
Host control-node-01
    HostName console.bernhard-gerlach.org
    User kubernetes-admin
    IdentityFile ~/.ssh/2026-02-05_k3s-cluster_control-node_key
    ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h

# Worker-Node via Cloudflare Tunnel → Control-Node → Internes Netzwerk
Host worker-node-01
    HostName 10.0.0.3
    User kubernetes-admin
    Port 22
    IdentityFile ~/.ssh/2026-02-05_k3s-cluster_worker-node_key
    PreferredAuthentications publickey
    ProxyJump control-node-01
```

## Troubleshooting

### Cloudflared startet nicht (IPv6-only Server)

**Problem**: `network is unreachable` Fehler im Log

**Lösung**: Stelle sicher, dass `/etc/cloudflared/config.yml` enthält:

```yaml
edge-ip-version: "6"
```

> **Wichtig**: Der Wert muss als String in Anführungszeichen stehen!

### Hetzner Web-Console funktioniert nicht

**Problem**: Copy/Paste funktioniert nicht, TTY hängt sich auf

**Lösung**: 
- Nutze den "Send Clipboard" Button oberhalb der Console
- Verwende ein einfaches Passwort ohne Sonderzeichen für den initialen Login
- Alternative: Temporären Admin-Node mit öffentlicher IP erstellen

### SSH-Verbindung über Tunnel schlägt fehl

**Problem**: Keine Antwort beim SSH-Versuch

**Checkliste**:
1. `cloudflared` lokal installiert? (`brew install cloudflared`)
2. ProxyCommand-Pfad korrekt? (`which cloudflared`)
3. Cloudflare Access Application konfiguriert?
4. Tunnel in Cloudflare als "Connected" angezeigt?

### Cloud-Init Passwort funktioniert nicht

**Problem**: Login mit gesetztem Passwort schlägt fehl

**Ursache**: Die alte `chpasswd.list` Syntax ist deprecated.

**Lösung**: Nutze die neue Syntax:

```yaml
users:
  - name: root
    plain_text_passwd: 'dein-passwort'
    lock_passwd: false
```

## Sicherheitshinweise

- **Passwörter in Cloud-Init** sind in Logs sichtbar. Ändere sie nach dem ersten Login.
- **SSH-Keys** sollten pro Server unterschiedlich sein.
- **Root-Passwort** ist nur für Notfall-Zugang via Web-Console gedacht.
- **UFW-Regeln** für HTTP/HTTPS auf dem Worker-Node können nach der Einrichtung entfernt werden:
  ```bash
  sudo ufw delete allow out to any port 80 proto tcp
  sudo ufw delete allow out to any port 443 proto tcp
  ```

## Referenzen

- [Hetzner Cloud-Init Tutorial](https://community.hetzner.com/tutorials/basic-cloud-config/de)
- [Cloudflare Tunnel Dokumentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare SSH Access](https://developers.cloudflare.com/cloudflare-one/applications/non-http/ssh/)
- [Video-Tutorial: Cloudflare Tunnel SSH Setup](https://www.youtube.com/watch?v=YVJYFpUSCH4) (ab 22:20)
