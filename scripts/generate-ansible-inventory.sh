#!/bin/bash

# =============================================================================
# Generate Ansible Inventory from OpenTofu State
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="$PROJECT_DIR/ansible"

# Check if we're in the right directory
if [[ ! -f "$PROJECT_DIR/main.tf" ]]; then
    echo "Error: main.tf not found. Run this script from the project directory."
    exit 1
fi

# Check for tofu/terraform
if command -v tofu &> /dev/null; then
    TF_CMD="tofu"
elif command -v terraform &> /dev/null; then
    TF_CMD="terraform"
else
    echo "Error: Neither 'tofu' nor 'terraform' found."
    exit 1
fi

cd "$PROJECT_DIR"

# Get values from Terraform output
CLUSTER_NAME=$($TF_CMD output -raw cluster_name 2>/dev/null || echo "k8s-cluster")
SSH_KEY_PREFIX=$($TF_CMD output -raw ssh_key_prefix 2>/dev/null || echo "$CLUSTER_NAME")
ADMIN_USER=$($TF_CMD output -raw admin_user 2>/dev/null || echo "kubernetes-admin")
CONTROL_IPS=$($TF_CMD output -json control_node_private_ips 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
WORKER_IPS=$($TF_CMD output -json worker_node_private_ips 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
TUNNEL_DOMAIN=$($TF_CMD output -raw cloudflare_tunnel_domain 2>/dev/null || echo "")
ADMIN_NODE_ENABLED=$($TF_CMD output -raw enable_admin_node 2>/dev/null || echo "false")

# Generate inventory
cat > "$ANSIBLE_DIR/inventory.ini" << EOF
# =============================================================================
# Ansible Inventory - Generated from OpenTofu State
# Generated: $(date)
# =============================================================================

[control_nodes]
EOF

# Add control nodes
i=1
for ip in $CONTROL_IPS; do
    printf "control-%02d ansible_host=%s\n" $i "$ip" >> "$ANSIBLE_DIR/inventory.ini"
    ((i++))
done

cat >> "$ANSIBLE_DIR/inventory.ini" << 'EOF'

[worker_nodes]
EOF

# Add worker nodes
i=1
for ip in $WORKER_IPS; do
    printf "worker-%02d ansible_host=%s\n" $i "$ip" >> "$ANSIBLE_DIR/inventory.ini"
    ((i++))
done

# Determine proxy configuration
# Prefer admin node when available (simpler: direct access to all private IPs)
# Fall back to Cloudflare Tunnel when admin node is disabled
if [[ "$ADMIN_NODE_ENABLED" == "true" ]]; then
    ADMIN_IPV6=$($TF_CMD output -raw admin_node_ipv6 2>/dev/null || echo "")
    ALL_PROXY_ARGS="ansible_ssh_common_args='-o ProxyJump=${ADMIN_USER}@${ADMIN_IPV6}'"
    WORKER_PROXY_ARGS=""
elif [[ -n "$TUNNEL_DOMAIN" && "$TUNNEL_DOMAIN" != "" ]]; then
    # Control nodes: ProxyCommand via cloudflared (tunnel lands directly on control node SSH)
    ALL_PROXY_ARGS="ansible_ssh_common_args='-o ProxyCommand=\"cloudflared access ssh --hostname ${TUNNEL_DOMAIN}\"'"
    # Workers: ProxyJump through tunnel host (cloudflared → control node → worker private IP)
    WORKER_PROXY_ARGS="ansible_ssh_common_args='-o ProxyJump=${TUNNEL_DOMAIN}'"
else
    ALL_PROXY_ARGS="# ansible_ssh_common_args='-o ProxyJump=control-01'"
    WORKER_PROXY_ARGS=""
fi

cat >> "$ANSIBLE_DIR/inventory.ini" << EOF

[k8s_cluster:children]
control_nodes
worker_nodes

[all:vars]
ansible_user=${ADMIN_USER}
ansible_ssh_private_key_file=~/.ssh/${SSH_KEY_PREFIX}_control-node_key
${ALL_PROXY_ARGS}

[worker_nodes:vars]
ansible_ssh_private_key_file=~/.ssh/${SSH_KEY_PREFIX}_worker-node_key
EOF

if [[ -n "$WORKER_PROXY_ARGS" ]]; then
    echo "$WORKER_PROXY_ARGS" >> "$ANSIBLE_DIR/inventory.ini"
fi

echo ""
echo "Inventory generated: $ANSIBLE_DIR/inventory.ini"
echo ""
echo "Test with:"
echo "  cd $ANSIBLE_DIR"
echo "  ansible all -m ping"
