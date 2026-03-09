#!/usr/bin/env bash
# =============================================================================
# deploy.sh - Full deployment script
# Provisions the DigitalOcean VPS with Terraform and configures OpenVPN
# with Ansible.
#
# Usage:
#   ./scripts/deploy.sh [OPTIONS]
#
# Options:
#   --domain DOMAIN       Set OpenVPN server domain (optional, uses IP if not set)
#   --client NAME         Create an initial client after setup (optional)
#   --skip-terraform      Skip Terraform (use existing infrastructure)
#   --skip-ansible        Skip Ansible (only run Terraform)
#   --help                Show this help message
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TERRAFORM_DIR="${PROJECT_DIR}/terraform"
ANSIBLE_DIR="${PROJECT_DIR}/ansible"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DOMAIN=""
INITIAL_CLIENT=""
SKIP_TERRAFORM=false
SKIP_ANSIBLE=false

# ─── Helper Functions ──────────────────────────────────────────────────────────

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Full deployment: Provisions VPS on DigitalOcean and sets up OpenVPN.

Options:
  --domain DOMAIN       Set OpenVPN server domain/hostname (optional)
  --client NAME         Create an initial client after setup (optional)
  --skip-terraform      Skip Terraform provisioning (use existing server)
  --skip-ansible        Skip Ansible configuration
  -h, --help            Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --domain vpn.example.com --client myphone
  $(basename "$0") --skip-terraform --domain vpn.example.com

EOF
}

check_dependencies() {
    local missing=()

    command -v terraform &>/dev/null || missing+=("terraform")
    command -v ansible-playbook &>/dev/null || missing+=("ansible")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Install them before running this script."
        exit 1
    fi

    log_success "All dependencies found"
}

check_terraform_vars() {
    if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
        log_error "terraform.tfvars not found!"
        log_info "Copy the example and fill in your values:"
        log_info "  cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
        log_info "  # Edit terraform/terraform.tfvars with your DigitalOcean token and settings"
        exit 1
    fi
}

run_terraform() {
    log_info "Running Terraform to provision DigitalOcean VPS..."
    cd "${TERRAFORM_DIR}"

    terraform init -upgrade
    terraform plan -out=tfplan
    terraform apply tfplan
    rm -f tfplan

    SERVER_IP=$(terraform output -raw server_ip)
    log_success "VPS provisioned at: ${SERVER_IP}"

    # Auto-read FQDN from Terraform if Cloudflare was enabled and no --domain flag given
    if [[ -z "${DOMAIN}" ]]; then
        DOMAIN=$(terraform output -raw server_fqdn 2>/dev/null || true)
        if [[ -n "${DOMAIN}" ]]; then
            log_success "Cloudflare DNS record created: ${DOMAIN} → ${SERVER_IP}"
            log_info "Auto-using domain for OpenVPN config: ${DOMAIN}"
        fi
    fi

    log_info "Waiting 30 seconds for server to fully boot..."
    sleep 30

    cd "${PROJECT_DIR}"
}

run_ansible() {
    log_info "Running Ansible to configure OpenVPN..."
    cd "${ANSIBLE_DIR}"

    # Domain is already injected into the inventory as a host var by Terraform
    # when Cloudflare is enabled. Pass via --extra-vars only when set via --domain flag
    # (overrides the inventory value, useful for manual runs without Terraform).
    local ansible_args=("setup.yml")
    if [[ -n "${DOMAIN}" ]]; then
        log_info "Using server domain: ${DOMAIN}"
        ansible_args+=("--extra-vars" "openvpn_server_domain=${DOMAIN}")
    fi

    ansible-playbook "${ansible_args[@]}"

    cd "${PROJECT_DIR}"
}

create_initial_client() {
    if [[ -n "${INITIAL_CLIENT}" ]]; then
        log_info "Creating initial client: ${INITIAL_CLIENT}"
        "${SCRIPT_DIR}/add-client.sh" "${INITIAL_CLIENT}"
    fi
}

# ─── Argument Parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --client)
            INITIAL_CLIENT="$2"
            shift 2
            ;;
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-ansible)
            SKIP_ANSIBLE=true
            shift
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

# ─── Main ──────────────────────────────────────────────────────────────────────

echo -e "${BLUE}"
echo "=============================================="
echo " DigitalOcean OpenVPN Deployment"
echo "=============================================="
echo -e "${NC}"

check_dependencies

if [[ "${SKIP_TERRAFORM}" == false ]]; then
    check_terraform_vars
    run_terraform
else
    log_warn "Skipping Terraform (--skip-terraform flag set)"
fi

if [[ "${SKIP_ANSIBLE}" == false ]]; then
    run_ansible
else
    log_warn "Skipping Ansible (--skip-ansible flag set)"
fi

create_initial_client

echo -e "${GREEN}"
echo "=============================================="
echo " Deployment Complete!"
echo "=============================================="
echo -e "${NC}"
log_success "OpenVPN server is ready!"
if [[ -n "${DOMAIN}" ]]; then
    log_info "Server domain: ${DOMAIN}"
    log_info "Note: Allow 1-2 minutes for DNS propagation before connecting."
fi
log_info "To add a client: make add-client CLIENT=mydevice"
log_info "         or:     ./scripts/add-client.sh mydevice"
