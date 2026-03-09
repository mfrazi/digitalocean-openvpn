terraform {
  required_version = ">= 1.3.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# SSH Key for the droplet
resource "digitalocean_ssh_key" "openvpn" {
  name       = "${var.project_name}-key"
  public_key = file(var.ssh_public_key_path)
}

# Computed values
locals {
  # Effective IP: reserved IP if enabled, otherwise droplet's IP
  server_ip = var.use_reserved_ip ? digitalocean_reserved_ip.openvpn[0].ip_address : digitalocean_droplet.openvpn.ipv4_address

  # Full domain name when Cloudflare is enabled
  server_fqdn = var.cloudflare_enabled ? "${var.cloudflare_subdomain}.${var.cloudflare_domain}" : ""
}

# Cloud-init script to bootstrap the droplet
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Update and install basic dependencies
    apt-get update -y
    apt-get install -y python3 python3-pip openssh-server

    # Ensure SSH is enabled and running
    systemctl enable ssh
    systemctl start ssh

    # Signal that the droplet is ready
    touch /tmp/droplet-ready
  EOF
}

# DigitalOcean Droplet for OpenVPN server
resource "digitalocean_droplet" "openvpn" {
  name      = "${var.project_name}-server"
  image     = var.droplet_image
  size      = var.droplet_size
  region    = var.droplet_region
  ssh_keys  = [digitalocean_ssh_key.openvpn.fingerprint]
  user_data = local.user_data
  tags      = ["openvpn", var.project_name]
}

# Firewall rules for the OpenVPN droplet
resource "digitalocean_firewall" "openvpn" {
  name        = "${var.project_name}-firewall"
  droplet_ids = [digitalocean_droplet.openvpn.id]

  # Allow SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow OpenVPN UDP (primary)
  inbound_rule {
    protocol         = "udp"
    port_range       = tostring(var.openvpn_port)
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow OpenVPN TCP (fallback)
  dynamic "inbound_rule" {
    for_each = var.openvpn_enable_tcp ? [1] : []
    content {
      protocol         = "tcp"
      port_range       = tostring(var.openvpn_port_tcp)
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  # Allow ICMP (ping)
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound TCP
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound UDP
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow outbound ICMP
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Optional: Assign a reserved/floating IP
resource "digitalocean_reserved_ip" "openvpn" {
  count  = var.use_reserved_ip ? 1 : 0
  region = var.droplet_region
}

resource "digitalocean_reserved_ip_assignment" "openvpn" {
  count      = var.use_reserved_ip ? 1 : 0
  ip_address = digitalocean_reserved_ip.openvpn[0].ip_address
  droplet_id = digitalocean_droplet.openvpn.id
}

# Dependency: Cloudflare record must wait for reserved IP assignment if both are enabled
# (handled implicitly via local.server_ip referencing the reserved IP resource)

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    server_ip     = local.server_ip
    server_name   = digitalocean_droplet.openvpn.name
    ssh_user      = var.ssh_user
    ssh_key       = var.ssh_private_key_path
    server_domain = local.server_fqdn
  })
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"
}

# ─── Cloudflare DNS Record ────────────────────────────────────────────────────

resource "cloudflare_record" "openvpn" {
  count   = var.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.cloudflare_subdomain
  content = local.server_ip
  type    = "A"
  ttl     = 60      # Low TTL for fast propagation on recreate
  proxied = false   # Must be false — Cloudflare cannot proxy UDP/OpenVPN traffic

  comment = "Managed by Terraform — OpenVPN server"
}
