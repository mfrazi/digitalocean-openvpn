#!/usr/bin/env bash
# =============================================================================
# destroy.sh - Destroy the DigitalOcean VPS and all resources
#
# WARNING: This will permanently delete your VPS and all data on it!
# Client configs in the local 'clients/' directory will be preserved.
#
# Usage:
#   ./scripts/destroy.sh [--yes]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TERRAFORM_DIR="${PROJECT_DIR}/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

AUTO_CONFIRM=false
if [[ "${1:-}" == "--yes" ]]; then
    AUTO_CONFIRM=true
fi

echo -e "${RED}"
echo "=============================================="
echo " WARNING: DESTRUCTIVE OPERATION"
echo "=============================================="
echo -e "${NC}"
log_warn "This will PERMANENTLY DELETE:"
log_warn "  - The DigitalOcean droplet"
log_warn "  - The SSH key from DigitalOcean"
log_warn "  - The firewall rules"
log_warn "  - Any reserved IP (if used)"
log_warn ""
log_warn "Local client configs in 'clients/' will be preserved."
log_warn ""

if [[ "${AUTO_CONFIRM}" == false ]]; then
    read -r -p "Type 'destroy' to confirm: " confirm
    if [[ "${confirm}" != "destroy" ]]; then
        log_info "Destruction cancelled."
        exit 0
    fi
fi

log_info "Destroying infrastructure..."
cd "${TERRAFORM_DIR}"

terraform destroy -auto-approve

# Clean up generated inventory
INVENTORY="${PROJECT_DIR}/ansible/inventory/hosts.ini"
if [[ -f "${INVENTORY}" ]]; then
    rm -f "${INVENTORY}"
    log_info "Removed Ansible inventory file"
fi

log_success "Infrastructure destroyed successfully."
log_info "Note: Client .ovpn files in 'clients/' still exist but are now useless."
