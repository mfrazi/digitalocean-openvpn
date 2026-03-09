#!/usr/bin/env bash
# =============================================================================
# update-openvpn.sh - Update OpenVPN to the latest available version
#
# Usage:
#   ./scripts/update-openvpn.sh [--easyrsa VERSION]
#
# Options:
#   --easyrsa VERSION    Also update EasyRSA to the specified version
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
Usage: $(basename "$0") [OPTIONS]

Updates OpenVPN to the latest version available in the system package manager.
Optionally updates EasyRSA as well.

Options:
  --easyrsa VERSION    Also update EasyRSA to the given version
                       Example: --easyrsa 3.1.7
  -h, --help           Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --easyrsa 3.1.7

EOF
}

UPDATE_EASYRSA=false
NEW_EASYRSA_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --easyrsa)
            UPDATE_EASYRSA=true
            NEW_EASYRSA_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ ! -f "${ANSIBLE_DIR}/inventory/hosts.ini" ]]; then
    log_error "Ansible inventory not found at ansible/inventory/hosts.ini"
    log_error "Run the deployment first: ./scripts/deploy.sh"
    exit 1
fi

log_info "Updating OpenVPN..."

cd "${ANSIBLE_DIR}"

EXTRA_VARS="update_easyrsa=${UPDATE_EASYRSA}"
if [[ -n "${NEW_EASYRSA_VERSION}" ]]; then
    EXTRA_VARS="${EXTRA_VARS} new_easyrsa_version=${NEW_EASYRSA_VERSION}"
fi

ansible-playbook update-openvpn.yml --extra-vars "${EXTRA_VARS}"

log_success "OpenVPN update complete!"
