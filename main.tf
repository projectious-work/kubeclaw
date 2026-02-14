# =============================================================================
# Hetzner Cloud Kubernetes Cluster - OpenTofu Configuration
# =============================================================================
# This project creates:
# - A private network
# - A control node with Cloudflare Tunnel (IPv6-only)
# - Zero or more worker nodes (IPv6-only, internal only)
# - Firewall rules for all servers
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
  # Use custom keys if provided, otherwise use generated ones
  use_custom_control_key = var.control_node_public_key != ""
  use_custom_worker_key  = var.worker_node_public_key != ""
  use_custom_admin_key   = var.admin_node_public_key != ""

  # Replica control nodes (flattened from type specs)
  control_node_replicas = flatten([
    for spec in var.control_node_types : [
      for i in range(spec.count) : { type = spec.type }
    ]
  ])
  control_node_replica_count = length(local.control_node_replicas)
  # Total includes master
  control_node_count = 1 + local.control_node_replica_count

  # Worker nodes (flattened from type specs)
  worker_nodes = flatten([
    for spec in var.worker_node_types : [
      for i in range(spec.count) : { type = spec.type }
    ]
  ])
  worker_node_count = length(local.worker_nodes)

  control_node_public_key = local.use_custom_control_key ? var.control_node_public_key : tls_private_key.control_node[0].public_key_openssh
  worker_node_public_key  = local.use_custom_worker_key ? var.worker_node_public_key : (local.worker_node_count > 0 ? tls_private_key.worker_node[0].public_key_openssh : "")
  admin_node_public_key   = local.use_custom_admin_key ? var.admin_node_public_key : (var.enable_admin_node ? tls_private_key.admin_node[0].public_key_openssh : "")

  # SSH key file prefix (defaults to cluster_name)
  ssh_key_prefix = var.ssh_key_prefix != "" ? var.ssh_key_prefix : var.cluster_name
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
# SSH Keys - Generated (only when no custom keys are provided)
# =============================================================================

# Control Node SSH Key (only generated when no custom key is provided)
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

# Worker Node SSH Key (only generated when workers exist AND no custom key is provided)
resource "tls_private_key" "worker_node" {
  count     = (local.worker_node_count > 0 && !local.use_custom_worker_key) ? 1 : 0
  algorithm = "ED25519"
}

resource "hcloud_ssh_key" "worker_node" {
  count      = local.worker_node_count > 0 ? 1 : 0
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

# Firewall for Control Node
resource "hcloud_firewall" "control_node" {
  name = "${var.cluster_name}-control-node-fw"

  labels = {
    cluster = var.cluster_name
    role    = "control-node"
  }

  rule {
    description = "SSH from private network"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = [var.network_ip_range]
  }

  rule {
    description = "SSH from localhost for Cloudflare Tunnel"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["127.0.0.1/32", "::1/128"]
  }

  rule {
    description = "ICMP from private network"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = [var.network_ip_range]
  }
}

# Firewall for Worker Nodes (only created when workers exist)
resource "hcloud_firewall" "worker_node" {
  count = local.worker_node_count > 0 ? 1 : 0
  name  = "${var.cluster_name}-worker-node-fw"

  labels = {
    cluster = var.cluster_name
    role    = "worker-node"
  }

  rule {
    description = "SSH from private network"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = [var.network_ip_range]
  }

  rule {
    description = "ICMP from private network"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = [var.network_ip_range]
  }

  # NOTE: When deploying K3s, add these rules:
  # - Kubelet API (port 10250) from var.network_ip_range
  # - NodePort Services (ports 30000-32767) from var.network_ip_range
  # - K8s API (port 6443) on control node firewall from var.network_ip_range
}

# =============================================================================
# Master Control Node (runs cloudflared)
# =============================================================================

resource "hcloud_server" "master_control_node" {
  name        = "${var.cluster_name}-control-01"
  image       = var.server_image
  server_type = var.master_control_node_type
  location    = var.location

  ssh_keys = [hcloud_ssh_key.control_node.id]

  firewall_ids = [hcloud_firewall.control_node.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = var.enable_public_ipv6
  }

  user_data = templatefile("${path.module}/cloud-init/control-node.yaml.tpl", {
    ssh_public_key  = local.control_node_public_key
    root_password   = var.root_password
    admin_user      = var.admin_user
    keyboard_layout = var.keyboard_layout
    is_master       = true
    enable_nat64    = var.enable_nat64
    dns64_resolvers = var.dns64_resolvers
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

resource "hcloud_server_network" "master_control_node" {
  server_id  = hcloud_server.master_control_node.id
  network_id = hcloud_network.cluster_network.id
  ip         = cidrhost(var.subnet_ip_range, 2)
}

# =============================================================================
# Replica Control Nodes (no cloudflared)
# =============================================================================

resource "hcloud_server" "control_node_replica" {
  count = local.control_node_replica_count

  name        = "${var.cluster_name}-control-${format("%02d", count.index + 2)}"
  image       = var.server_image
  server_type = local.control_node_replicas[count.index].type
  location    = var.location

  ssh_keys = [hcloud_ssh_key.control_node.id]

  firewall_ids = [hcloud_firewall.control_node.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = var.enable_public_ipv6
  }

  user_data = templatefile("${path.module}/cloud-init/control-node.yaml.tpl", {
    ssh_public_key  = local.control_node_public_key
    root_password   = var.root_password
    admin_user      = var.admin_user
    keyboard_layout = var.keyboard_layout
    is_master       = false
    enable_nat64    = var.enable_nat64
    dns64_resolvers = var.dns64_resolvers
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

resource "hcloud_server_network" "control_node_replica" {
  count = local.control_node_replica_count

  server_id  = hcloud_server.control_node_replica[count.index].id
  network_id = hcloud_network.cluster_network.id
  ip         = cidrhost(var.subnet_ip_range, 3 + count.index)
}

# =============================================================================
# Worker Nodes
# =============================================================================

resource "hcloud_server" "worker_node" {
  count = local.worker_node_count

  name        = "${var.cluster_name}-worker-${format("%02d", count.index + 1)}"
  image       = var.server_image
  server_type = local.worker_nodes[count.index].type
  location    = var.location

  ssh_keys = [hcloud_ssh_key.worker_node[0].id]

  firewall_ids = [hcloud_firewall.worker_node[0].id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = var.enable_public_ipv6
  }

  user_data = templatefile("${path.module}/cloud-init/worker-node.yaml.tpl", {
    ssh_public_key  = local.worker_node_public_key
    root_password   = var.root_password
    admin_user      = var.admin_user
    keyboard_layout = var.keyboard_layout
    enable_nat64    = var.enable_nat64
    dns64_resolvers = var.dns64_resolvers
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
  count = local.worker_node_count

  server_id  = hcloud_server.worker_node[count.index].id
  network_id = hcloud_network.cluster_network.id
  ip         = cidrhost(var.subnet_ip_range, 3 + local.control_node_replica_count + count.index)
}

# =============================================================================
# Admin Node (temporary jump host for initial setup)
# =============================================================================

# Admin Node SSH Key (only generated when enabled AND no custom key is provided)
resource "tls_private_key" "admin_node" {
  count     = (var.enable_admin_node && !local.use_custom_admin_key) ? 1 : 0
  algorithm = "ED25519"
}

resource "hcloud_ssh_key" "admin_node" {
  count      = var.enable_admin_node ? 1 : 0
  name       = "${var.cluster_name}-admin-node-key"
  public_key = local.admin_node_public_key

  labels = {
    cluster = var.cluster_name
    role    = "admin-node"
  }
}

# Firewall for Admin Node - allows SSH from anywhere (public entry point)
resource "hcloud_firewall" "admin_node" {
  count = var.enable_admin_node ? 1 : 0
  name  = "${var.cluster_name}-admin-node-fw"

  labels = {
    cluster = var.cluster_name
    role    = "admin-node"
    managed = "opentofu"
  }

  rule {
    description = "SSH from anywhere (public entry point for initial setup)"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "ICMP from private network"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = [var.network_ip_range]
  }
}

resource "hcloud_server" "admin_node" {
  count = var.enable_admin_node ? 1 : 0

  name        = "${var.cluster_name}-admin-01"
  image       = var.server_image
  server_type = var.admin_node_type
  location    = var.location

  ssh_keys = [hcloud_ssh_key.admin_node[0].id]

  firewall_ids = [hcloud_firewall.admin_node[0].id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = true  # Always enabled - this is the admin node's purpose
  }

  user_data = templatefile("${path.module}/cloud-init/admin-node.yaml.tpl", {
    ssh_public_key  = local.admin_node_public_key
    root_password   = var.root_password
    admin_user      = var.admin_user
    keyboard_layout = var.keyboard_layout
  })

  labels = {
    cluster = var.cluster_name
    role    = "admin-node"
    managed = "opentofu"
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [hcloud_network_subnet.cluster_subnet]
}

resource "hcloud_server_network" "admin_node" {
  count = var.enable_admin_node ? 1 : 0

  server_id  = hcloud_server.admin_node[0].id
  network_id = hcloud_network.cluster_network.id
  ip         = cidrhost(var.subnet_ip_range, 254)
}
