# =============================================================================
# Hetzner Cloud Kubernetes Cluster - OpenTofu Configuration
# =============================================================================
# Dieses Projekt erstellt:
# - Ein privates Netzwerk
# - Einen Control-Node mit Cloudflare Tunnel (IPv6-only)
# - Null oder mehrere Worker-Nodes (IPv6-only, nur intern erreichbar)
# - Firewall-Regeln für alle Server
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "hcloud" {
  token = var.hcloud_token
}

# =============================================================================
# Locals - SSH Key Logic
# =============================================================================

locals {
  # Verwende eigene Keys wenn angegeben, sonst generierte
  use_custom_control_key = var.control_node_public_key != ""
  use_custom_worker_key  = var.worker_node_public_key != ""
  
  control_node_public_key = local.use_custom_control_key ? var.control_node_public_key : tls_private_key.control_node[0].public_key_openssh
  worker_node_public_key  = local.use_custom_worker_key ? var.worker_node_public_key : (var.worker_node_count > 0 ? tls_private_key.worker_node[0].public_key_openssh : "")
}

# =============================================================================
# Data Sources
# =============================================================================

data "hcloud_locations" "available" {}

# =============================================================================
# Private Network
# =============================================================================

resource "hcloud_network" "cluster_network" {
  name     = "${var.cluster_name}-network"
  ip_range = var.network_ip_range

  labels = {
    cluster = var.cluster_name
    managed = "opentofu"
  }
}

resource "hcloud_network_subnet" "cluster_subnet" {
  network_id   = hcloud_network.cluster_network.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_ip_range
}

# =============================================================================
# SSH Keys - Generiert (nur wenn keine eigenen angegeben)
# =============================================================================

# Control Node SSH Key (nur generieren wenn kein eigener Key angegeben)
resource "tls_private_key" "control_node" {
  count     = local.use_custom_control_key ? 0 : 1
  algorithm = "ED25519"
}

resource "hcloud_ssh_key" "control_node" {
  name       = "${var.cluster_name}-control-node-key"
  public_key = local.control_node_public_key

  labels = {
    cluster = var.cluster_name
    role    = "control-node"
  }
}

# Worker Node SSH Key (nur generieren wenn Worker vorhanden UND kein eigener Key)
resource "tls_private_key" "worker_node" {
  count     = (var.worker_node_count > 0 && !local.use_custom_worker_key) ? 1 : 0
  algorithm = "ED25519"
}

resource "hcloud_ssh_key" "worker_node" {
  count      = var.worker_node_count > 0 ? 1 : 0
  name       = "${var.cluster_name}-worker-node-key"
  public_key = local.worker_node_public_key

  labels = {
    cluster = var.cluster_name
    role    = "worker-node"
  }
}

# =============================================================================
# Firewalls
# =============================================================================

# Firewall für Control-Node
resource "hcloud_firewall" "control_node" {
  name = "${var.cluster_name}-control-node-fw"

  labels = {
    cluster = var.cluster_name
    role    = "control-node"
  }

  # SSH vom internen Netzwerk
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.network_ip_range]
  }

  # SSH von localhost (für Cloudflare Tunnel)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["127.0.0.1/32", "::1/128"]
  }

  # ICMP vom internen Netzwerk
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = [var.network_ip_range]
  }

  # Kubernetes API (falls später benötigt)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = [var.network_ip_range]
  }
}

# Firewall für Worker-Nodes (nur erstellen wenn Worker vorhanden)
resource "hcloud_firewall" "worker_node" {
  count = var.worker_node_count > 0 ? 1 : 0
  name  = "${var.cluster_name}-worker-node-fw"

  labels = {
    cluster = var.cluster_name
    role    = "worker-node"
  }

  # SSH nur vom internen Netzwerk
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.network_ip_range]
  }

  # ICMP vom internen Netzwerk
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = [var.network_ip_range]
  }

  # Kubelet API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = [var.network_ip_range]
  }

  # NodePort Services Range
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "30000-32767"
    source_ips = [var.network_ip_range]
  }
}

# =============================================================================
# Control Node
# =============================================================================

resource "hcloud_server" "control_node" {
  name        = "${var.cluster_name}-control-01"
  image       = var.server_image
  server_type = var.control_node_type
  location    = var.location

  ssh_keys = [hcloud_ssh_key.control_node.id]

  firewall_ids = [hcloud_firewall.control_node.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = var.enable_public_ipv6
  }

  user_data = templatefile("${path.module}/cloud-init/control-node.yaml.tpl", {
    ssh_public_key   = local.control_node_public_key
    root_password    = var.root_password
    admin_user       = var.admin_user
    keyboard_layout  = var.keyboard_layout
  })

  labels = {
    cluster = var.cluster_name
    role    = "control-node"
    managed = "opentofu"
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [hcloud_network_subnet.cluster_subnet]
}

resource "hcloud_server_network" "control_node" {
  server_id  = hcloud_server.control_node.id
  network_id = hcloud_network.cluster_network.id
  ip         = cidrhost(var.subnet_ip_range, 2)
}

# =============================================================================
# Worker Nodes
# =============================================================================

resource "hcloud_server" "worker_node" {
  count = var.worker_node_count

  name        = "${var.cluster_name}-worker-${format("%02d", count.index + 1)}"
  image       = var.server_image
  server_type = var.worker_node_type
  location    = var.location

  ssh_keys = [hcloud_ssh_key.worker_node[0].id]

  firewall_ids = [hcloud_firewall.worker_node[0].id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = var.enable_public_ipv6
  }

  user_data = templatefile("${path.module}/cloud-init/worker-node.yaml.tpl", {
    ssh_public_key   = local.worker_node_public_key
    root_password    = var.root_password
    admin_user       = var.admin_user
    keyboard_layout  = var.keyboard_layout
  })

  labels = {
    cluster = var.cluster_name
    role    = "worker-node"
    managed = "opentofu"
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [hcloud_network_subnet.cluster_subnet]
}

resource "hcloud_server_network" "worker_node" {
  count = var.worker_node_count

  server_id  = hcloud_server.worker_node[count.index].id
  network_id = hcloud_network.cluster_network.id
  ip         = cidrhost(var.subnet_ip_range, 3 + count.index)
}
