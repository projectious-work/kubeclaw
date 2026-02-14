#!/bin/bash

# =============================================================================
# SSH-Agent Setup for K8s Cluster
# =============================================================================
# This script sets up ssh-agent and loads the SSH keys.
# It auto-detects key names from OpenTofu state when available.
#
# Usage:
#   source ./scripts/ssh-agent-setup.sh
#
# IMPORTANT: Run with "source" so environment variables are set in the
#            current shell!
# =============================================================================

# Note: no "set -e" here — this script is sourced, so set -e would apply to
# the user's shell and kill it on any non-zero exit (e.g. arithmetic returning 0).

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect project directory (script may be sourced from anywhere)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROJECT_DIR="$(dirname "$_SCRIPT_DIR")"

# Auto-detect configuration from OpenTofu state if available
if [[ -z "$SSH_KEY_PREFIX" ]] && command -v tofu &>/dev/null && [[ -f "$_PROJECT_DIR/main.tf" ]]; then
    SSH_KEY_PREFIX=$(cd "$_PROJECT_DIR" && tofu output -raw ssh_key_prefix 2>/dev/null || echo "")
    CLUSTER_NAME=$(cd "$_PROJECT_DIR" && tofu output -raw cluster_name 2>/dev/null || echo "")
fi

# Configuration (env vars override auto-detection)
CLUSTER_NAME="${CLUSTER_NAME:-k8s-cluster}"
SSH_KEY_PREFIX="${SSH_KEY_PREFIX:-$CLUSTER_NAME}"
SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
ADMIN_KEY="${SSH_DIR}/${SSH_KEY_PREFIX}_admin-node_key"
CONTROL_KEY="${SSH_DIR}/${SSH_KEY_PREFIX}_control-node_key"
WORKER_KEY="${SSH_DIR}/${SSH_KEY_PREFIX}_worker-node_key"

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

    # 1. Fix SSH permissions (needed for bind-mounted .root/.ssh/ in Dev Container)
    if [[ -d "$SSH_DIR" ]]; then
        local perms_fixed=0

        # Directory must be 700
        if [[ "$(stat -c '%a' "$SSH_DIR" 2>/dev/null)" != "700" ]]; then
            chmod 700 "$SSH_DIR"
            perms_fixed=$((perms_fixed + 1))
        fi

        # Config must be 600
        if [[ -f "$SSH_DIR/config" && "$(stat -c '%a' "$SSH_DIR/config" 2>/dev/null)" != "600" ]]; then
            chmod 600 "$SSH_DIR/config"
            perms_fixed=$((perms_fixed + 1))
        fi

        # Private keys must be 600, public keys 644
        for key_file in "$SSH_DIR"/*_key "$SSH_DIR"/id_*; do
            [[ -f "$key_file" ]] || continue
            if [[ "$key_file" == *.pub ]]; then
                if [[ "$(stat -c '%a' "$key_file" 2>/dev/null)" != "644" ]]; then
                    chmod 644 "$key_file"
                    perms_fixed=$((perms_fixed + 1))
                fi
            else
                if [[ "$(stat -c '%a' "$key_file" 2>/dev/null)" != "600" ]]; then
                    chmod 600 "$key_file"
                    perms_fixed=$((perms_fixed + 1))
                fi
            fi
        done

        if [[ $perms_fixed -gt 0 ]]; then
            info "Fixed SSH permissions ($perms_fixed items — bind-mount override)"
        fi
    fi

    # 2. Start ssh-agent if needed
    if ! agent_is_running; then
        info "Starting ssh-agent..."
        eval "$(ssh-agent -s)"
        info "SSH_AUTH_SOCK=${SSH_AUTH_SOCK}"
    else
        info "ssh-agent is already running (SSH_AUTH_SOCK=${SSH_AUTH_SOCK})"
    fi
    
    # 3. Check macOS Keychain configuration
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
    
    # 4. Load keys
    local keys_added=0
    
    for key_file in "$ADMIN_KEY" "$CONTROL_KEY" "$WORKER_KEY"; do
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
                keys_added=$((keys_added + 1))
            elif ssh-add "$key_file"; then
                # Fallback without Keychain (e.g. for keys without passphrase)
                keys_added=$((keys_added + 1))
            else
                error "Failed to load: $key_file"
            fi
        else
            # Linux: Standard ssh-add
            if ssh-add "$key_file"; then
                keys_added=$((keys_added + 1))
            else
                error "Failed to load: $key_file"
            fi
        fi
    done
    
    # 5. Show status
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
