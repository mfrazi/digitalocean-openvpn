output "server_ipv4" {
  description = "Public IPv4 address of the OpenVPN server"
  value       = digitalocean_droplet.openvpn.ipv4_address
}

output "server_ip" {
  description = "Effective IP address (reserved IP if enabled, otherwise droplet IP)"
  value       = var.use_reserved_ip ? digitalocean_reserved_ip.openvpn[0].ip_address : digitalocean_droplet.openvpn.ipv4_address
}

output "server_name" {
  description = "Droplet name"
  value       = digitalocean_droplet.openvpn.name
}

output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.openvpn.id
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${var.use_reserved_ip ? digitalocean_reserved_ip.openvpn[0].ip_address : digitalocean_droplet.openvpn.ipv4_address}"
}

output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = "${path.module}/../ansible/inventory/hosts.ini"
}
