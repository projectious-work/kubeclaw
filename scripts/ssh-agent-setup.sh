#!/bin/bash

# =============================================================================
# SSH-Agent Setup for K3s Cluster
# =============================================================================
# This script sets up ssh-agent and loads the SSH keys.
#
# Usage:
#   source ./scripts/ssh-agent-setup.sh
#
# IMPORTANT: Run with "source" so environment variables are set in the
#            current shell!
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-k3s-cluster}"
SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
CONTROL_KEY="${SSH_DIR}/${CLUSTER_NAME}_control-node_key"
WORKER_KEY="${SSH_DIR}/${CLUSTER_NAME}_worker-node_key"

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on macOS
is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

# Check if ssh-agent is running
agent_is_running() {
    [[ -n "${SSH_AUTH_SOCK}" ]] && ssh-add -l &>/dev/null
    return $?
}

# Check if a key is already loaded in the agent
key_is_loaded() {
    local key_file="$1"
    local public_key
    
    if [[ ! -f "${key_file}.pub" ]]; then
        return 1
    fi
    
    public_key=$(cat "${key_file}.pub" | awk '{print $2}')
    ssh-add -l 2>/dev/null | grep -q "$public_key"
}

# -----------------------------------------------------------------------------
# Main logic
# -----------------------------------------------------------------------------

main() {
    echo ""
    echo "=========================================="
    echo "  SSH-Agent Setup for ${CLUSTER_NAME}"
    echo "=========================================="
    echo ""
    
    # 1. Start ssh-agent if needed
    if ! agent_is_running; then
        info "Starting ssh-agent..."
        eval "$(ssh-agent -s)"
        info "SSH_AUTH_SOCK=${SSH_AUTH_SOCK}"
    else
        info "ssh-agent is already running (SSH_AUTH_SOCK=${SSH_AUTH_SOCK})"
    fi
    
    # 2. Check macOS Keychain configuration
    if is_macos; then
        info "macOS detected — Keychain integration available"
        
        # Check if ~/.ssh/config has Keychain entries
        if [[ -f "${SSH_DIR}/config" ]]; then
            if ! grep -q "UseKeychain yes" "${SSH_DIR}/config" 2>/dev/null; then
                warn "Recommendation: Add the following to ~/.ssh/config:"
                echo ""
                echo "    Host *"
                echo "        UseKeychain yes"
                echo "        AddKeysToAgent yes"
                echo ""
            fi
        else
            warn "No ~/.ssh/config found. Consider creating one with:"
            echo ""
            echo "    Host *"
            echo "        UseKeychain yes"
            echo "        AddKeysToAgent yes"
            echo ""
        fi
    fi
    
    # 3. Load keys
    local keys_added=0
    
    for key_file in "$CONTROL_KEY" "$WORKER_KEY"; do
        if [[ ! -f "$key_file" ]]; then
            warn "Key not found: $key_file"
            continue
        fi
        
        if key_is_loaded "$key_file"; then
            info "Key already loaded: $(basename "$key_file")"
            continue
        fi
        
        info "Loading key: $(basename "$key_file")"
        
        if is_macos; then
            # macOS: With Keychain integration
            if ssh-add --apple-use-keychain "$key_file" 2>/dev/null; then
                info "Key loaded and passphrase stored in Keychain"
                ((keys_added++))
            elif ssh-add "$key_file"; then
                # Fallback without Keychain (e.g. for keys without passphrase)
                ((keys_added++))
            else
                error "Failed to load: $key_file"
            fi
        else
            # Linux: Standard ssh-add
            if ssh-add "$key_file"; then
                ((keys_added++))
            else
                error "Failed to load: $key_file"
            fi
        fi
    done
    
    # 4. Show status
    echo ""
    echo "=========================================="
    echo "  Loaded keys:"
    echo "=========================================="
    ssh-add -l || echo "  (no keys loaded)"
    echo ""
    
    if [[ $keys_added -gt 0 ]]; then
        info "Setup complete. SSH and Ansible are ready."
    else
        info "No new keys added."
    fi
    
    # Hint for source invocation
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        echo ""
        warn "This script should be run with 'source':"
        echo "    source $0"
        echo ""
        warn "Otherwise the environment variables will not be available in the current shell."
    fi
}

# Run script
main "$@"
