# =============================================================================
# Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Cluster Configuration
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "k8s-cluster"
}

variable "location" {
  description = "Hetzner Cloud location (fsn1, nbg1, hel1, ash, hil)"
  type        = string
  default     = "fsn1"
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "network_ip_range" {
  description = "IP range for the private network"
  type        = string
  default     = "10.0.0.0/8"
}

variable "subnet_ip_range" {
  description = "IP range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "network_zone" {
  description = "Network zone (eu-central, us-east, us-west)"
  type        = string
  default     = "eu-central"
}

variable "enable_public_ipv6" {
  description = "Enable public IPv6 for servers (needed for initial setup, can be disabled later)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Server Configuration
# -----------------------------------------------------------------------------

variable "server_image" {
  description = "Server image to use"
  type        = string
  default     = "debian-13"
}

variable "control_node_type" {
  description = "Server type for control node"
  type        = string
  default     = "cx22"
}

variable "worker_node_type" {
  description = "Server type for worker nodes"
  type        = string
  default     = "cx22"
}

variable "worker_node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Authentication
# -----------------------------------------------------------------------------

variable "root_password" {
  description = "Root password for emergency Web-Console access"
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

variable "admin_user" {
  description = "Admin user name for SSH access"
  type        = string
  default     = "kubernetes-admin"
}

variable "keyboard_layout" {
  description = "Keyboard layout"
  type        = string
  default     = "de"
}

# -----------------------------------------------------------------------------
# SSH Keys (Optional - custom keys)
# -----------------------------------------------------------------------------
# If left empty, new keys will be auto-generated.
# When using custom keys: manage private keys yourself!

variable "control_node_public_key" {
  description = "Public SSH key for control node. Leave empty to auto-generate."
  type        = string
  default     = ""
}

variable "worker_node_public_key" {
  description = "Public SSH key for worker nodes. Leave empty to auto-generate."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Cloudflare Configuration
# -----------------------------------------------------------------------------

variable "cloudflare_tunnel_domain" {
  description = "Domain for Cloudflare Tunnel SSH access (e.g., console.example.org)"
  type        = string
  default     = ""
}
