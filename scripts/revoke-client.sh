#!/usr/bin/env bash
# =============================================================================
# revoke-client.sh - Revoke an OpenVPN client certificate
#
# Usage:
#   ./scripts/revoke-client.sh <client_name>
#   ./scripts/revoke-client.sh myphone
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
ANSIBLE_DIR="${PROJECT_DIR}/ansible"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") <client_name> [--yes]

Revokes an OpenVPN client certificate, immediately disconnecting the client
and preventing future connections.

Arguments:
  client_name    Name of the client to revoke
  --yes          Skip confirmation prompt

Examples:
  $(basename "$0") myphone
  $(basename "$0") stolen-laptop --yes

EOF
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

CLIENT_NAME="$1"
AUTO_CONFIRM=false

if [[ "${2:-}" == "--yes" ]]; then
    AUTO_CONFIRM=true
fi

if [[ ! "${AUTO_CONFIRM}" == true ]]; then
    log_warn "You are about to revoke client: ${CLIENT_NAME}"
    log_warn "This will immediately disconnect and permanently block this client."
    read -r -p "Are you sure? (yes/no): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Revocation cancelled."
        exit 0
    fi
fi

log_info "Revoking client: ${CLIENT_NAME}"

cd "${ANSIBLE_DIR}"
ansible-playbook revoke-client.yml \
    --extra-vars "client_name=${CLIENT_NAME} auto_confirm=true"

log_success "Client '${CLIENT_NAME}' has been revoked."
log_info "The client config file (if saved locally) is now useless."
