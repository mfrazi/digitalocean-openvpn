# DigitalOcean OpenVPN Automation

Automated deployment of a production-ready OpenVPN server on DigitalOcean using **Terraform** (infrastructure provisioning) and **Ansible** (configuration management).

## Features

- **One-command deployment** — provision VPS and install OpenVPN automatically
- **Automatic PKI** — EasyRSA 3 manages CA, server, and client certificates
- **Client management** — add and revoke clients with a single command
- **Cloudflare DNS** — automatically creates/updates a subdomain A record after VPS provisioning
- **Custom domain support** — use your own domain or fall back to the server IP
- **Inline .ovpn files** — all certificates embedded for easy distribution
- **OpenVPN updates** — update to the latest version with one command
- **Firewall configured** — UFW with NAT masquerade set up automatically
- **Secure defaults** — AES-256-GCM, TLS 1.2+, tls-crypt, SHA256

---

## Prerequisites

Install these tools on your local machine:

| Tool | Version | Install |
|------|---------|---------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | ≥ 1.3 | `brew install terraform` |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | ≥ 2.12 | `pip install ansible` |

You also need:
- A **DigitalOcean account** with an API token ([create one here](https://cloud.digitalocean.com/account/api/tokens))
- An **SSH key pair** (`~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub` by default)

---

## Quick Start

### 1. Clone the repository

```bash
git clone <repository-url>
cd digitalocean-openvpn
```

### 2. Configure settings

```bash
# Copy and edit the Terraform config
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` with your values:

```hcl
do_token             = "your_digitalocean_api_token"
droplet_region       = "sgp1"         # See regions below
droplet_size         = "s-1vcpu-1gb"
ssh_public_key_path  = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"
```

> **Optional**: Set a custom domain in `ansible/group_vars/all.yml`:
> ```yaml
> openvpn_server_domain: "vpn.example.com"
> ```
> Point an A record at your server's IP after deployment. If left empty, the server IP is used.

### 3. Deploy

```bash
make deploy
```

This will:
1. Provision a DigitalOcean VPS with Terraform
2. Wait for it to boot
3. Install and configure OpenVPN with Ansible
4. Set up firewall rules and enable IP forwarding

### 4. Create your first client

```bash
make add-client CLIENT=myphone
```

The `.ovpn` file is saved to `clients/myphone/myphone.ovpn`.

Import it into your VPN client app and connect!

---

## Directory Structure

```
digitalocean-openvpn/
├── Makefile                        # Main entry point (make help)
├── terraform/
│   ├── main.tf                     # Droplet, firewall, SSH key resources
│   ├── variables.tf                # All configurable variables
│   ├── outputs.tf                  # Server IP, SSH command, etc.
│   ├── inventory.tpl               # Template for Ansible inventory
│   └── terraform.tfvars.example    # Copy & edit this file
├── ansible/
│   ├── ansible.cfg                 # Ansible configuration
│   ├── group_vars/
│   │   └── all.yml                 # Global variables (domain, ports, etc.)
│   ├── roles/
│   │   ├── openvpn_server/         # Server installation and configuration
│   │   └── openvpn_client/         # Client cert generation
│   ├── setup.yml                   # Main setup playbook
│   ├── add-client.yml              # Add a new client
│   ├── revoke-client.yml           # Revoke a client
│   ├── list-clients.yml            # List all clients
│   └── update-openvpn.yml          # Update OpenVPN version
├── scripts/
│   ├── deploy.sh                   # Full deployment orchestration
│   ├── add-client.sh               # Create a new client
│   ├── revoke-client.sh            # Revoke a client
│   ├── update-openvpn.sh           # Update OpenVPN
│   └── destroy.sh                  # Destroy infrastructure
└── clients/                        # Generated client .ovpn files (gitignored)
    └── <client_name>/
        └── <client_name>.ovpn
```

---

## Available Commands

Run `make help` to see all commands. Common ones:

| Command | Description |
|---------|-------------|
| `make deploy` | Full deployment (Terraform + Ansible) |
| `make deploy DOMAIN=vpn.example.com` | Deploy with custom domain |
| `make add-client CLIENT=myphone` | Create a new VPN client |
| `make revoke-client CLIENT=myphone` | Revoke a client's access |
| `make list-clients` | List all clients and their cert status |
| `make update` | Update OpenVPN to latest version |
| `make update-easyrsa EASYRSA_VER=3.1.7` | Update EasyRSA |
| `make status` | Check OpenVPN service status |
| `make logs` | View OpenVPN server logs |
| `make ssh` | SSH into the server |
| `make destroy` | Destroy all infrastructure |

---

## Configuration Reference

### Terraform Variables (`terraform/terraform.tfvars`)

| Variable | Default | Description |
|----------|---------|-------------|
| `do_token` | — | **Required.** DigitalOcean API token |
| `project_name` | `openvpn` | Prefix for all resource names |
| `droplet_region` | `sgp1` | DigitalOcean region |
| `droplet_size` | `s-1vcpu-1gb` | Droplet size slug |
| `droplet_image` | `ubuntu-22-04-x64` | OS image |
| `ssh_public_key_path` | `~/.ssh/id_rsa.pub` | SSH public key |
| `ssh_private_key_path` | `~/.ssh/id_rsa` | SSH private key |
| `openvpn_port` | `1194` | OpenVPN UDP port |
| `openvpn_enable_tcp` | `false` | Enable TCP listener |
| `openvpn_port_tcp` | `443` | OpenVPN TCP port |
| `use_reserved_ip` | `false` | Use DigitalOcean reserved IP |

### Ansible Variables (`ansible/group_vars/all.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `openvpn_server_domain` | `""` | Custom domain (uses IP if empty) |
| `openvpn_port` | `1194` | OpenVPN UDP port |
| `openvpn_proto` | `udp` | Protocol |
| `openvpn_server_network` | `10.8.0.0` | VPN subnet |
| `openvpn_dns_servers` | Cloudflare | DNS pushed to clients |
| `openvpn_cipher` | `AES-256-GCM` | Encryption cipher |
| `openvpn_redirect_gateway` | `true` | Route all traffic through VPN |
| `openvpn_max_clients` | `100` | Max concurrent clients |
| `easyrsa_version` | `3.1.7` | EasyRSA version |

### DigitalOcean Regions

| Slug | Location |
|------|----------|
| `nyc3` | New York City, USA |
| `sfo3` | San Francisco, USA |
| `ams3` | Amsterdam, Netherlands |
| `fra1` | Frankfurt, Germany |
| `lon1` | London, UK |
| `sgp1` | Singapore |
| `blr1` | Bangalore, India |
| `tor1` | Toronto, Canada |
| `syd1` | Sydney, Australia |

### Droplet Sizes (Cost Guide)

| Slug | vCPU | RAM | Monthly Cost | Recommended For |
|------|------|-----|-------------|-----------------|
| `s-1vcpu-1gb` | 1 | 1GB | ~$6 | 1-5 users |
| `s-1vcpu-2gb` | 1 | 2GB | ~$12 | 5-20 users |
| `s-2vcpu-2gb` | 2 | 2GB | ~$18 | 20-50 users |

---

## Cloudflare DNS Integration

Automatically point a subdomain of your existing Cloudflare-managed domain at the new VPS.

### How It Works

1. Terraform provisions the Droplet and gets its IP
2. Terraform calls the Cloudflare API to create/update an A record: `<subdomain>.<domain>` → server IP
3. The FQDN is injected into the Ansible inventory automatically
4. Ansible uses the domain in `server.conf` and all generated client `.ovpn` files
5. All clients connect via domain name — no need to update configs if you recreate the VPS

### Setup

1. **Create a Cloudflare API token** with `Zone:DNS:Edit` permission:
   - Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
   - Click "Create Token" → use the "Edit zone DNS" template
   - Scope it to your specific zone (recommended over Global API Key)

2. **Get your Zone ID**:
   - Open your domain in Cloudflare dashboard
   - Look at the right sidebar of the Overview page → "Zone ID"

3. **Configure `terraform/terraform.tfvars`**:
   ```hcl
   cloudflare_enabled   = true
   cloudflare_api_token = "your_token_here"
   cloudflare_zone_id   = "your_zone_id_here"
   cloudflare_domain    = "example.com"
   cloudflare_subdomain = "vpn"       # → creates vpn.example.com
   ```

4. **Deploy as normal**:
   ```bash
   make deploy
   ```
   The DNS record is created automatically. The completion message will confirm:
   ```
   [OK]   Cloudflare DNS record created: vpn.example.com → 1.2.3.4
   ```

### Important Notes

- **Do not enable Cloudflare proxying** (orange cloud) — OpenVPN uses raw UDP which cannot pass through Cloudflare's HTTP proxy. The A record is always created with `proxied = false`.
- **DNS propagation**: Allow ~1 minute after deployment before connecting with the domain-based config (TTL is set to 60 seconds).
- **Recreating the VPS**: Run `terraform apply` — the A record updates automatically to the new IP.
- **Changing the subdomain**: Update `cloudflare_subdomain` in `terraform.tfvars` and run `terraform apply`. The old record is deleted and the new one created in one step.

---

## Client Management

### Adding a Client

```bash
# Using make
make add-client CLIENT=myphone

# Using the script directly
./scripts/add-client.sh laptop-work

# Using ansible-playbook directly
cd ansible
ansible-playbook add-client.yml --extra-vars "client_name=tablet"
```

The `.ovpn` file is saved locally to `clients/<name>/<name>.ovpn`.

### Connecting to VPN

Import the `.ovpn` file into:
- **iOS/Android**: [OpenVPN Connect](https://openvpn.net/client/)
- **macOS**: [Tunnelblick](https://tunnelblick.net/) or OpenVPN Connect
- **Windows**: [OpenVPN Connect](https://openvpn.net/client/) or OpenVPN GUI
- **Linux**: `sudo openvpn --config myphone.ovpn` or NetworkManager

### Revoking a Client

```bash
make revoke-client CLIENT=myphone
```

The client is immediately disconnected and cannot reconnect. The CRL is updated and OpenVPN reloads automatically.

### Listing Clients

```bash
make list-clients
```

---

## Updating OpenVPN

### Update to Latest Available Version

```bash
make update
```

This updates OpenVPN via `apt`, restarts the service, and verifies it's running.

### Update EasyRSA

```bash
make update-easyrsa EASYRSA_VER=3.1.7
```

Check the [EasyRSA releases page](https://github.com/OpenVPN/easy-rsa/releases) for the latest version.

### Manual Update via Ansible

```bash
# Update only OpenVPN
cd ansible
ansible-playbook update-openvpn.yml

# Update OpenVPN + EasyRSA
ansible-playbook update-openvpn.yml --extra-vars "update_easyrsa=true new_easyrsa_version=3.1.7"
```

---

## Deploying to Existing Server

If you already have a VPS and just want to install OpenVPN:

1. Create the inventory file manually:
   ```ini
   # ansible/inventory/hosts.ini
   [openvpn_servers]
   my-server ansible_host=1.2.3.4 ansible_user=root ansible_ssh_private_key_file=~/.ssh/id_rsa
   ```

2. Run the Ansible setup:
   ```bash
   make deploy-skip-terraform
   # or with domain:
   make deploy-skip-terraform DOMAIN=vpn.example.com
   ```

---

## Security Notes

- **Keep `clients/` private** — `.ovpn` files contain private keys
- **Keep `terraform.tfvars` private** — it contains your DO API token
- Both are in `.gitignore` to prevent accidental commits
- The server uses `tls-crypt` for additional protection against unauthenticated access
- Certificates use AES-256-GCM encryption and SHA256 digest
- TLS minimum version is enforced to 1.2
- IP forwarding and NAT masquerade are configured for full tunnel mode

---

## Troubleshooting

### Connection Issues

```bash
# Check service status
make status

# View recent logs
make logs

# SSH into server for manual inspection
make ssh
```

### Common Problems

**OpenVPN service won't start:**
```bash
# On the server:
journalctl -u openvpn-server@server -n 100
cat /var/log/openvpn.log
```

**Client can't connect:**
- Verify the server's firewall allows UDP 1194 (check DigitalOcean firewall + UFW)
- Check that the `.ovpn` file has the correct server IP/domain
- Try TCP mode: set `openvpn_enable_tcp: true` in `group_vars/all.yml`

**Ansible can't reach server:**
```bash
# Test connectivity
cd ansible && ansible openvpn_servers -m ping
```

---

## License

MIT
