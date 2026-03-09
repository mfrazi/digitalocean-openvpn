# =============================================================================
# Makefile - DigitalOcean OpenVPN Automation
# =============================================================================
# Usage:
#   make deploy                        # Full deployment
#   make deploy DOMAIN=vpn.example.com # With custom domain
#   make add-client CLIENT=myphone     # Add a client
#   make revoke-client CLIENT=myphone  # Revoke a client
#   make update                        # Update OpenVPN
#   make destroy                       # Destroy infrastructure
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Variables
DOMAIN     ?=
CLIENT     ?=
EASYRSA_VER ?=

# Directories
TERRAFORM_DIR := terraform
ANSIBLE_DIR   := ansible
SCRIPTS_DIR   := scripts

# Terraform flags
TF_FLAGS :=
ifdef DOMAIN
  TF_FLAGS += --domain $(DOMAIN)
endif

ifdef CLIENT
  TF_FLAGS += --client $(CLIENT)
endif

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "DigitalOcean OpenVPN Automation"
	@echo "================================"
	@echo ""
	@echo "Usage: make <target> [VARIABLE=value]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  DOMAIN=<domain>      Server domain/hostname (e.g. vpn.example.com)"
	@echo "  CLIENT=<name>        Client name for add-client/revoke-client"
	@echo "  EASYRSA_VER=<ver>    EasyRSA version for update-easyrsa"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy DOMAIN=vpn.example.com"
	@echo "  make add-client CLIENT=myphone"
	@echo "  make update"

.PHONY: check-deps
check-deps: ## Check that required tools are installed
	@echo "Checking dependencies..."
	@command -v terraform    &>/dev/null || (echo "ERROR: terraform not found" && exit 1)
	@command -v ansible      &>/dev/null || (echo "ERROR: ansible not found" && exit 1)
	@command -v ansible-playbook &>/dev/null || (echo "ERROR: ansible-playbook not found" && exit 1)
	@echo "All dependencies found."

.PHONY: setup-config
setup-config: ## Copy example config files (run this first!)
	@if [ ! -f $(TERRAFORM_DIR)/terraform.tfvars ]; then \
		cp $(TERRAFORM_DIR)/terraform.tfvars.example $(TERRAFORM_DIR)/terraform.tfvars; \
		echo "Created terraform/terraform.tfvars - EDIT THIS FILE with your settings!"; \
	else \
		echo "terraform/terraform.tfvars already exists."; \
	fi

.PHONY: init
init: check-deps ## Initialize Terraform
	cd $(TERRAFORM_DIR) && terraform init -upgrade

.PHONY: plan
plan: ## Show Terraform plan (no changes applied)
	cd $(TERRAFORM_DIR) && terraform plan

.PHONY: deploy
deploy: check-deps ## Full deployment: provision VPS and configure OpenVPN
	$(SCRIPTS_DIR)/deploy.sh $(TF_FLAGS)

.PHONY: deploy-skip-terraform
deploy-skip-terraform: check-deps ## Configure OpenVPN on existing VPS (skip Terraform)
	$(SCRIPTS_DIR)/deploy.sh --skip-terraform $(if $(DOMAIN),--domain $(DOMAIN),)

.PHONY: add-client
add-client: ## Create a new OpenVPN client (requires CLIENT=name)
	@if [ -z "$(CLIENT)" ]; then \
		echo "ERROR: CLIENT variable is required."; \
		echo "Usage: make add-client CLIENT=mydevice"; \
		exit 1; \
	fi
	$(SCRIPTS_DIR)/add-client.sh $(CLIENT)

.PHONY: revoke-client
revoke-client: ## Revoke an OpenVPN client (requires CLIENT=name)
	@if [ -z "$(CLIENT)" ]; then \
		echo "ERROR: CLIENT variable is required."; \
		echo "Usage: make revoke-client CLIENT=mydevice"; \
		exit 1; \
	fi
	$(SCRIPTS_DIR)/revoke-client.sh $(CLIENT)

.PHONY: list-clients
list-clients: ## List all OpenVPN clients and their status
	cd $(ANSIBLE_DIR) && ansible-playbook list-clients.yml

.PHONY: update
update: ## Update OpenVPN to the latest available version
	$(SCRIPTS_DIR)/update-openvpn.sh

.PHONY: update-easyrsa
update-easyrsa: ## Update EasyRSA to a specific version (requires EASYRSA_VER=x.x.x)
	@if [ -z "$(EASYRSA_VER)" ]; then \
		echo "ERROR: EASYRSA_VER variable is required."; \
		echo "Usage: make update-easyrsa EASYRSA_VER=3.1.7"; \
		exit 1; \
	fi
	$(SCRIPTS_DIR)/update-openvpn.sh --easyrsa $(EASYRSA_VER)

.PHONY: status
status: ## Show OpenVPN server status
	cd $(ANSIBLE_DIR) && ansible openvpn_servers -a "systemctl status openvpn-server@server" --become

.PHONY: logs
logs: ## Show OpenVPN server logs (last 50 lines)
	cd $(ANSIBLE_DIR) && ansible openvpn_servers -a "journalctl -u openvpn-server@server -n 50 --no-pager" --become

.PHONY: ssh
ssh: ## SSH into the OpenVPN server
	@SERVER_IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw server_ip 2>/dev/null) && \
	SSH_KEY=$$(cd $(TERRAFORM_DIR) && terraform output -raw server_ip 2>/dev/null || echo "~/.ssh/id_rsa") && \
	echo "Connecting to $${SERVER_IP}..." && \
	ssh -i ~/.ssh/id_rsa root@$${SERVER_IP}

.PHONY: destroy
destroy: ## DESTROY all infrastructure (WARNING: irreversible!)
	$(SCRIPTS_DIR)/destroy.sh

.PHONY: terraform-output
terraform-output: ## Show Terraform outputs (server IP, SSH command, etc.)
	cd $(TERRAFORM_DIR) && terraform output
