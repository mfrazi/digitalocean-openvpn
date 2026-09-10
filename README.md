# openvpn.sh

A single self-contained Bash script that sets up an OpenVPN server on a
Debian/Ubuntu VPS and manages clients — no Terraform, no Ansible, nothing
to install on your local machine. Copy the script to the server and run it.

## Features

- **One command setup** — installs OpenVPN + EasyRSA, builds the PKI, writes
  the server config, configures IP forwarding, UFW (with NAT masquerade),
  and starts the service
- **Client management** — add, rotate ("edit"), and delete client
  certificates with single commands
- **Inline `.ovpn` files** — CA, cert, key and tls-crypt key embedded, ready
  to import into any OpenVPN client
- **Idempotent** — safe to re-run `setup`; existing certs/keys are never
  regenerated unnecessarily
- **Secure defaults** — AES-256-GCM, SHA256, TLS 1.2+, tls-crypt

## Quick Start

Copy `openvpn.sh` to your server (e.g. `scp openvpn.sh root@your-server:~/`),
then as root:

```bash
./openvpn.sh setup
```

By default this uses the server's auto-detected public IP as the address
clients connect to, UDP port 1194, and the `10.8.0.0/24` VPN subnet. To use
your own domain instead:

```bash
./openvpn.sh setup --domain vpn.example.com
```

Run `./openvpn.sh setup --help` for all options (port, protocol, subnet,
DNS servers, max clients).

### Add a client

```bash
./openvpn.sh adduser alice
```

The config is written to `/etc/openvpn/clients/alice/alice.ovpn` on the
server. Download it with:

```bash
scp root@your-server:/etc/openvpn/clients/alice/alice.ovpn ./
# or, without a separate scp step:
ssh root@your-server ./openvpn.sh download alice > alice.ovpn
```

Import the `.ovpn` file into:
- **iOS/Android/Windows/macOS**: [OpenVPN Connect](https://openvpn.net/client/)
- **macOS**: [Tunnelblick](https://tunnelblick.net/)
- **Linux**: `sudo openvpn --config alice.ovpn` or NetworkManager

## Commands

| Command | Description |
|---|---|
| `./openvpn.sh setup [options]` | Install and configure the OpenVPN server |
| `./openvpn.sh adduser <name>` | Create a new client certificate and `.ovpn` file |
| `./openvpn.sh edituser <name>` | Rotate a client's certificate (revoke old, issue new) |
| `./openvpn.sh deluser <name>` | Revoke and remove a client |
| `./openvpn.sh listusers` | List all clients and their status (active/revoked) |
| `./openvpn.sh download <name>` | Print a client's `.ovpn` file to stdout |
| `./openvpn.sh status` | Show service status and connected clients |
| `./openvpn.sh update` | Upgrade the `openvpn` package and restart |
| `./openvpn.sh help` | Show usage |

Pass `-y`/`--yes` to `adduser`, `edituser`, or `deluser` to skip confirmation
prompts (useful for automation).

## Setup Options

| Flag | Default | Description |
|---|---|---|
| `--domain <fqdn>` | auto-detected public IP | Address clients connect to |
| `--port <port>` | `1194` | OpenVPN port |
| `--proto udp\|tcp` | `udp` | OpenVPN protocol |
| `--network <base>` | `10.8.0.0` | VPN subnet base (netmask is always `/24`) |
| `--dns "<ip> [<ip>]"` | `"1.1.1.1 1.0.0.1"` | DNS servers pushed to clients |
| `--max-clients <n>` | `100` | Maximum concurrent clients |

Settings are saved to `/etc/openvpn/openvpn-manager.conf` and reused by every
other command, so you only need to pass them once, on `setup`.

## On-Server File Layout

```
/etc/openvpn/
├── server/                     # server cert, key, CA, DH params, ta.key, server.conf
├── pki/                        # EasyRSA PKI (CA, issued certs, private keys, CRL)
├── clients/<name>/<name>.ovpn  # generated client configs
├── easyrsa-vars                # EasyRSA vars file
└── openvpn-manager.conf        # persisted server settings (port, proto, domain, ...)
```

## Security Notes

- `/etc/openvpn/clients/`, `/etc/openvpn/pki/private/`, and
  `/etc/openvpn/openvpn-manager.conf` contain private key material — keep
  server access (SSH/root) tightly controlled.
- The server uses `tls-crypt` to authenticate and encrypt the control
  channel against unauthenticated probing.
- Certificates use RSA 2048 with SHA256; data channel uses AES-256-GCM.
- TLS minimum version is enforced to 1.2.

## Troubleshooting

```bash
./openvpn.sh status
journalctl -u openvpn-server@server -n 100 --no-pager
cat /var/log/openvpn.log
```

If a client can't connect, verify your cloud provider's firewall (not just
UFW) allows the chosen port/protocol inbound, and that the `.ovpn` file has
the correct server address.

## License

MIT
