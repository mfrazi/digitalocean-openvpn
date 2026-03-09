#!/usr/bin/env bash
# =============================================================================
# add-client.sh - Create a new OpenVPN client
#
# Usage:
#   ./scripts/add-client.sh <client_name>
#   ./scripts/add-client.sh myphone
#   ./scripts/add-client.sh laptop-work
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
ANSIBLE_DIR="${PROJECT_DIR}/ansible"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") <client_name>

Creates a new OpenVPN client certificate and generates a .ovpn config file.
The config file will be saved to: clients/<client_name>/<client_name>.ovpn

Arguments:
  client_name    Name for the client (alphanumeric, hyphens, underscores only)

Examples:
  $(basename "$0") myphone
  $(basename "$0") laptop-work
  $(basename "$0") tablet_personal

EOF
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

CLIENT_NAME="$1"

# Validate client name
if [[ ! "${CLIENT_NAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid client name: '${CLIENT_NAME}'"
    log_error "Use only letters, numbers, hyphens, and underscores."
    exit 1
fi

# Check inventory exists
if [[ ! -f "${ANSIBLE_DIR}/inventory/hosts.ini" ]]; then
    log_error "Ansible inventory not found at ansible/inventory/hosts.ini"
    log_error "Run the deployment first: ./scripts/deploy.sh"
    exit 1
fi

log_info "Creating OpenVPN client: ${CLIENT_NAME}"

cd "${ANSIBLE_DIR}"
ansible-playbook add-client.yml --extra-vars "client_name=${CLIENT_NAME}"

OVPN_FILE="${PROJECT_DIR}/clients/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
if [[ -f "${OVPN_FILE}" ]]; then
    log_success "Client created successfully!"
    log_info "Config file: clients/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    log_info ""
    log_info "Import this file into your OpenVPN client:"
    log_info "  - OpenVPN Connect (iOS, Android, Windows, macOS)"
    log_info "  - Tunnelblick (macOS)"
    log_info "  - Network Manager (Linux)"
else
    log_error "Client config file not found. Check Ansible output above for errors."
    exit 1
fi
