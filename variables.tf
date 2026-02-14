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

variable "master_control_node_type" {
  description = "Server type for the master control node (runs cloudflared)"
  type        = string
  default     = "cx22"
}

variable "control_node_types" {
  description = "Server types and counts for replica control nodes. Set to [] for master-only."
  type = list(object({
    type  = string
    count = number
  }))
  default = []
}

variable "worker_node_types" {
  description = "Server types and counts for worker nodes. Set to [] for no workers."
  type = list(object({
    type  = string
    count = number
  }))
  default = []
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

# -----------------------------------------------------------------------------
# Admin Node (temporary jump host for initial setup)
# -----------------------------------------------------------------------------

variable "enable_admin_node" {
  description = "Enable a temporary admin node with public IPv6 for initial SSH access. Disable after Cloudflare Tunnel is configured."
  type        = bool
  default     = true
}

variable "admin_node_type" {
  description = "Server type for admin node"
  type        = string
  default     = "cx22"
}

variable "admin_node_public_key" {
  description = "Public SSH key for admin node. Leave empty to auto-generate."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# NAT64/DNS64 (IPv4 reachability for IPv6-only nodes)
# -----------------------------------------------------------------------------

variable "enable_nat64" {
  description = "Enable NAT64/DNS64 for IPv4 reachability on IPv6-only nodes. Required to download binaries, container images, etc. from IPv4-only hosts."
  type        = bool
  default     = true
}

variable "dns64_resolvers" {
  description = "DNS64 resolver addresses (must be from a provider that also runs a NAT64 gateway). Default: nat64.net resolvers in Nuremberg, Helsinki, Amsterdam."
  type        = list(string)
  default     = ["2a01:4f8:c2c:123f::1", "2a01:4f9:c010:3f02::1", "2a00:1098:2b::1"]
}

# -----------------------------------------------------------------------------
# SSH Key File Prefix
# -----------------------------------------------------------------------------

variable "ssh_key_prefix" {
  description = "Prefix for SSH key filenames (e.g., '2026-02-05_k8s-cluster'). Defaults to cluster_name if empty."
  type        = string
  default     = ""
}
