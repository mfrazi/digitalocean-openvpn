variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "openvpn"
}

variable "droplet_region" {
  description = "DigitalOcean region for the droplet (e.g. sgp1, nyc3, ams3, fra1)"
  type        = string
  default     = "sgp1"
}

variable "droplet_size" {
  description = "DigitalOcean droplet size slug"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "droplet_image" {
  description = "Droplet OS image slug (Ubuntu 22.04 LTS recommended)"
  type        = string
  default     = "ubuntu-22-04-x64"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to your SSH private key file (used in Ansible inventory)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_user" {
  description = "SSH user for connecting to the droplet"
  type        = string
  default     = "root"
}

variable "openvpn_port" {
  description = "UDP port for OpenVPN (default 1194)"
  type        = number
  default     = 1194
}

variable "openvpn_port_tcp" {
  description = "TCP port for OpenVPN (used when openvpn_enable_tcp is true)"
  type        = number
  default     = 443
}

variable "openvpn_enable_tcp" {
  description = "Whether to also open a TCP port for OpenVPN (useful for restrictive networks)"
  type        = bool
  default     = false
}

variable "use_reserved_ip" {
  description = "Whether to assign a DigitalOcean reserved (floating) IP to the droplet"
  type        = bool
  default     = false
}
