# =============================================================================
# Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Network Information
# -----------------------------------------------------------------------------

output "network_id" {
  description = "ID of the private network"
  value       = hcloud_network.cluster_network.id
}

output "network_name" {
  description = "Name of the private network"
  value       = hcloud_network.cluster_network.name
}

# -----------------------------------------------------------------------------
# Cluster Name and SSH Key Prefix (used by scripts)
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "Name of the cluster"
  value       = var.cluster_name
}

output "admin_user" {
  description = "Admin user name"
  value       = var.admin_user
}

output "ssh_key_prefix" {
  description = "Prefix used for SSH key filenames"
  value       = local.ssh_key_prefix
}

# -----------------------------------------------------------------------------
# Master Control Node Information
# -----------------------------------------------------------------------------

output "master_control_node_id" {
  description = "ID of the master control node"
  value       = hcloud_server.master_control_node.id
}

output "master_control_node_name" {
  description = "Name of the master control node"
  value       = hcloud_server.master_control_node.name
}

output "master_control_node_private_ip" {
  description = "Private IP of the master control node"
  value       = hcloud_server_network.master_control_node.ip
}

# -----------------------------------------------------------------------------
# All Control Nodes Information (master + replicas)
# -----------------------------------------------------------------------------

output "control_node_count" {
  description = "Total number of control nodes (master + replicas)"
  value       = local.control_node_count
}

output "control_node_ids" {
  description = "IDs of all control nodes (master + replicas)"
  value       = concat([hcloud_server.master_control_node.id], hcloud_server.control_node_replica[*].id)
}

output "control_node_names" {
  description = "Names of all control nodes (master + replicas)"
  value       = concat([hcloud_server.master_control_node.name], hcloud_server.control_node_replica[*].name)
}

output "control_node_private_ips" {
  description = "Private IPs of all control nodes (master + replicas)"
  value       = concat([hcloud_server_network.master_control_node.ip], hcloud_server_network.control_node_replica[*].ip)
}

# -----------------------------------------------------------------------------
# Worker Nodes Information
# -----------------------------------------------------------------------------

output "worker_node_count" {
  description = "Number of worker nodes"
  value       = local.worker_node_count
}

output "worker_node_ids" {
  description = "IDs of worker nodes"
  value       = hcloud_server.worker_node[*].id
}

output "worker_node_names" {
  description = "Names of worker nodes"
  value       = hcloud_server.worker_node[*].name
}

output "worker_node_private_ips" {
  description = "Private IPs of worker nodes"
  value       = hcloud_server_network.worker_node[*].ip
}

# -----------------------------------------------------------------------------
# Admin Node Information
# -----------------------------------------------------------------------------

output "admin_node_id" {
  description = "ID of the admin node"
  value       = var.enable_admin_node ? hcloud_server.admin_node[0].id : null
}

output "admin_node_name" {
  description = "Name of the admin node"
  value       = var.enable_admin_node ? hcloud_server.admin_node[0].name : null
}

output "admin_node_ipv6" {
  description = "Public IPv6 address of the admin node"
  value       = var.enable_admin_node ? hcloud_server.admin_node[0].ipv6_address : null
}

output "admin_node_private_ip" {
  description = "Private IP of the admin node"
  value       = var.enable_admin_node ? hcloud_server_network.admin_node[0].ip : null
}

# -----------------------------------------------------------------------------
# SSH Keys (Private - Handle with care!)
# Only available when auto-generated (not with custom keys)
# -----------------------------------------------------------------------------

output "control_node_ssh_private_key" {
  description = "Private SSH key for control nodes (only if auto-generated)"
  value       = length(tls_private_key.control_node) > 0 ? tls_private_key.control_node[0].private_key_openssh : "Using custom key - manage privately"
  sensitive   = true
}

output "control_node_ssh_public_key" {
  description = "Public SSH key for control nodes"
  value       = local.control_node_public_key
}

output "worker_node_ssh_private_key" {
  description = "Private SSH key for worker nodes (only if auto-generated)"
  value       = length(tls_private_key.worker_node) > 0 ? tls_private_key.worker_node[0].private_key_openssh : (local.worker_node_count > 0 ? "Using custom key - manage privately" : "No workers configured")
  sensitive   = true
}

output "worker_node_ssh_public_key" {
  description = "Public SSH key for worker nodes"
  value       = local.worker_node_count > 0 ? local.worker_node_public_key : "No workers configured"
}

output "admin_node_ssh_private_key" {
  description = "Private SSH key for admin node (only if auto-generated)"
  value       = length(tls_private_key.admin_node) > 0 ? tls_private_key.admin_node[0].private_key_openssh : (var.enable_admin_node ? "Using custom key - manage privately" : "Admin node disabled")
  sensitive   = true
}

output "admin_node_ssh_public_key" {
  description = "Public SSH key for admin node"
  value       = var.enable_admin_node ? local.admin_node_public_key : "Admin node disabled"
}

output "using_custom_keys" {
  description = "Whether custom SSH keys are being used"
  value = {
    control_node = var.control_node_public_key != ""
    worker_node  = var.worker_node_public_key != ""
    admin_node   = var.admin_node_public_key != ""
  }
}

# -----------------------------------------------------------------------------
# SSH Config Snippet
# -----------------------------------------------------------------------------

output "ssh_config_snippet" {
  description = "SSH config snippet for ~/.ssh/config"
  value       = <<-EOT
    # =============================================================================
    # ${var.cluster_name} - Generated by OpenTofu
    # =============================================================================

    %{if var.enable_admin_node~}
    # Admin Node (temporary jump host)
    Host admin-node
        HostName ${hcloud_server.admin_node[0].ipv6_address}
        User ${var.admin_user}
        IdentityFile ~/.ssh/${local.ssh_key_prefix}_admin-node_key

    %{endif~}
    # Master Control Node (control-01)%{if var.cloudflare_tunnel_domain != ""} via Cloudflare Tunnel%{endif}
    Host ${var.cloudflare_tunnel_domain != "" ? var.cloudflare_tunnel_domain : "control-node"}
        HostName ${var.cloudflare_tunnel_domain != "" ? var.cloudflare_tunnel_domain : hcloud_server_network.master_control_node.ip}
        User ${var.admin_user}
        IdentityFile ~/.ssh/${local.ssh_key_prefix}_control-node_key
        %{if var.cloudflare_tunnel_domain != ""}ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h%{endif}
        %{if var.cloudflare_tunnel_domain == "" && var.enable_admin_node}ProxyJump admin-node%{endif}

    %{for i, ip in hcloud_server_network.control_node_replica[*].ip~}
    # Replica Control Node ${format("%02d", i + 2)}
    Host control-${format("%02d", i + 2)}
        HostName ${ip}
        User ${var.admin_user}
        IdentityFile ~/.ssh/${local.ssh_key_prefix}_control-node_key
        ProxyJump ${var.cloudflare_tunnel_domain != "" ? var.cloudflare_tunnel_domain : (var.enable_admin_node ? "admin-node" : "control-node")}

    %{endfor~}
    %{for i, ip in hcloud_server_network.worker_node[*].ip~}
    # Worker Node ${format("%02d", i + 1)}
    Host worker-${format("%02d", i + 1)}
        HostName ${ip}
        User ${var.admin_user}
        IdentityFile ~/.ssh/${local.ssh_key_prefix}_worker-node_key
        ProxyJump ${var.cloudflare_tunnel_domain != "" ? var.cloudflare_tunnel_domain : (var.enable_admin_node ? "admin-node" : "control-node")}

    %{endfor~}
  EOT
}

# -----------------------------------------------------------------------------
# Cloudflare Tunnel Domain (used by scripts)
# -----------------------------------------------------------------------------

output "cloudflare_tunnel_domain" {
  description = "Configured Cloudflare Tunnel domain"
  value       = var.cloudflare_tunnel_domain
}

# -----------------------------------------------------------------------------
# Admin Node Enabled (used by scripts)
# -----------------------------------------------------------------------------

output "enable_admin_node" {
  description = "Whether the admin node is enabled"
  value       = var.enable_admin_node
}

# -----------------------------------------------------------------------------
# Next Steps
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Instructions for completing the setup"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                              NEXT STEPS                                       ║
    ╠══════════════════════════════════════════════════════════════════════════════╣
    %{if var.control_node_public_key == "" || (var.enable_admin_node && var.admin_node_public_key == "")}
    ║  1. Export SSH Keys (auto-generated):                                         ║
    %{if var.control_node_public_key == ""}
    ║     tofu output -raw control_node_ssh_private_key > ~/.ssh/${local.ssh_key_prefix}_control-node_key
    %{endif}
    %{if local.worker_node_count > 0 && var.worker_node_public_key == ""}
    ║     tofu output -raw worker_node_ssh_private_key > ~/.ssh/${local.ssh_key_prefix}_worker-node_key
    %{endif}
    %{if var.enable_admin_node && var.admin_node_public_key == ""}
    ║     tofu output -raw admin_node_ssh_private_key > ~/.ssh/${local.ssh_key_prefix}_admin-node_key
    %{endif}
    ║     chmod 600 ~/.ssh/${local.ssh_key_prefix}_*_key
    %{else}
    ║  1. SSH Keys: Using your custom keys - ensure they are in ~/.ssh/            ║
    %{endif}
    ║                                                                               ║
    ║  2. Add SSH Config:                                                           ║
    ║     tofu output -raw ssh_config_snippet >> ~/.ssh/config                      ║
    ║                                                                               ║
    %{if var.enable_admin_node}
    ║  3. Connect to Master Control Node (via admin node):                          ║
    ║     ssh -J admin-node -i ~/.ssh/${local.ssh_key_prefix}_control-node_key ${var.admin_user}@${hcloud_server_network.master_control_node.ip}
    %{else}
    ║  3. Connect to Master Control Node (via Cloudflare Tunnel):                   ║
    ║     ssh ${var.cloudflare_tunnel_domain != "" ? var.cloudflare_tunnel_domain : "control-node"}
    %{endif}
    ║                                                                               ║
    ║  4. Install Cloudflare Tunnel on Master Control Node:                         ║
    ║     sudo cloudflared service install <YOUR_TUNNEL_TOKEN>                      ║
    ║                                                                               ║
    ║  5. Disable Admin Node and Public IPs (after Tunnel works):                   ║
    ║     Set enable_admin_node = false in terraform.tfvars                         ║
    ║     Set enable_public_ipv6 = false in terraform.tfvars                        ║
    ║     Run: tofu apply                                                           ║
    ║                                                                               ║
    ╚══════════════════════════════════════════════════════════════════════════════╝

  EOT
}
