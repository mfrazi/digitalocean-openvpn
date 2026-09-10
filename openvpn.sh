#!/usr/bin/env bash
#
# openvpn.sh — self-contained OpenVPN server setup and client manager.
#
# Copy this single file to your server and run it as root:
#   ./openvpn.sh setup                  # install + configure + start the VPN
#   ./openvpn.sh adduser alice          # create a client and its .ovpn file
#   ./openvpn.sh edituser alice         # rotate a client's certificate
#   ./openvpn.sh deluser alice          # revoke and remove a client
#   ./openvpn.sh listusers              # list clients and their status
#   ./openvpn.sh download alice         # print alice's .ovpn to stdout
#   ./openvpn.sh status                 # service status + connected clients
#   ./openvpn.sh update                 # upgrade the openvpn package
#
set -euo pipefail

# =============================================================================
# Paths
# =============================================================================
SERVER_DIR="/etc/openvpn/server"
PKI_DIR="/etc/openvpn/pki"
CLIENTS_DIR="/etc/openvpn/clients"
VARS_FILE="/etc/openvpn/easyrsa-vars"
STATE_FILE="/etc/openvpn/openvpn-manager.conf"
EASYRSA_BIN="/usr/share/easy-rsa/easyrsa"

# =============================================================================
# Defaults (overridden by flags on `setup`, then persisted to STATE_FILE and
# reused by every other command)
# =============================================================================
PORT=1194
PROTO=udp
NETWORK=10.8.0.0
NETMASK=255.255.255.0
DNS_SERVERS="1.1.1.1 1.0.0.1"
CIPHER=AES-256-GCM
AUTH_DIGEST=SHA256
TLS_MIN=1.2
MAX_CLIENTS=100
DOMAIN=""
SERVER_ADDR=""
ASSUME_YES=0

# =============================================================================
# Logging helpers
# =============================================================================
color() { local c=$1; shift; printf '\033[%sm%s\033[0m\n' "$c" "$*"; }
info()  { color '0;36' "[*] $*"; }
ok()    { color '0;32' "[OK] $*"; }
warn()  { color '1;33' "[!] $*"; }
err()   { color '0;31' "[ERROR] $*" >&2; }
die()   { err "$*"; exit 1; }

# =============================================================================
# Environment checks
# =============================================================================
require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run this script as root (sudo ./openvpn.sh $*)."
}

require_os() {
  command -v apt-get >/dev/null 2>&1 || die "This script supports Debian/Ubuntu (apt-get) only."
}

require_setup() {
  [ -f "$STATE_FILE" ] || die "OpenVPN is not set up yet. Run: ./openvpn.sh setup"
}

# =============================================================================
# State (persisted server configuration)
# =============================================================================
load_state() {
  # shellcheck disable=SC1090
  [ -f "$STATE_FILE" ] && source "$STATE_FILE"
}

save_state() {
  cat > "$STATE_FILE" <<EOF
PORT=${PORT}
PROTO=${PROTO}
NETWORK=${NETWORK}
NETMASK=${NETMASK}
DNS_SERVERS="${DNS_SERVERS}"
CIPHER=${CIPHER}
AUTH_DIGEST=${AUTH_DIGEST}
TLS_MIN=${TLS_MIN}
MAX_CLIENTS=${MAX_CLIENTS}
DOMAIN="${DOMAIN}"
SERVER_ADDR="${SERVER_ADDR}"
EOF
  chmod 600 "$STATE_FILE"
}

detect_public_ip() {
  local ip
  ip=$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null) || true
  [ -z "$ip" ] && ip=$(curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null) || true
  [ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true
  [ -n "$ip" ] || die "Could not auto-detect the server's public IP. Re-run with --domain <your-domain-or-ip>."
  echo "$ip"
}

# =============================================================================
# EasyRSA helpers
# =============================================================================
easyrsa() {
  "$EASYRSA_BIN" --batch --pki-dir="$PKI_DIR" --vars="$VARS_FILE" "$@"
}

write_vars_file() {
  cat > "$VARS_FILE" <<EOF
set_var EASYRSA_DN            "cn_only"
set_var EASYRSA_REQ_COUNTRY   "US"
set_var EASYRSA_REQ_PROVINCE  "CA"
set_var EASYRSA_REQ_CITY      "San Francisco"
set_var EASYRSA_REQ_ORG       "OpenVPN"
set_var EASYRSA_REQ_EMAIL     "admin@example.com"
set_var EASYRSA_REQ_OU        "VPN"
set_var EASYRSA_ALGO          "rsa"
set_var EASYRSA_KEY_SIZE      2048
set_var EASYRSA_CA_EXPIRE     3650
set_var EASYRSA_CERT_EXPIRE   1080
set_var EASYRSA_CERT_RENEW    30
set_var EASYRSA_CRL_DAYS      3650
set_var EASYRSA_DIGEST        "sha256"
EOF
}

# =============================================================================
# setup
# =============================================================================
usage_setup() {
  cat <<EOF
Usage: $0 setup [options]

Options:
  --domain <fqdn>       Public domain/hostname clients connect to (default: auto-detected public IP)
  --port <port>         OpenVPN port (default: ${PORT})
  --proto udp|tcp       OpenVPN protocol (default: ${PROTO})
  --network <cidr-base> VPN subnet base, e.g. 10.8.0.0 (default: ${NETWORK})
  --dns "<ip> [<ip>]"   DNS servers pushed to clients (default: "${DNS_SERVERS}")
  --max-clients <n>     Maximum concurrent clients (default: ${MAX_CLIENTS})
  -y, --yes             Don't prompt for confirmation
EOF
}

cmd_setup() {
  require_root setup
  require_os
  load_state

  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) DOMAIN="$2"; shift 2 ;;
      --port) PORT="$2"; shift 2 ;;
      --proto) PROTO="$2"; shift 2 ;;
      --network) NETWORK="$2"; shift 2 ;;
      --dns) DNS_SERVERS="$2"; shift 2 ;;
      --max-clients) MAX_CLIENTS="$2"; shift 2 ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      -h|--help) usage_setup; exit 0 ;;
      *) die "Unknown setup option: $1 (see --help)" ;;
    esac
  done

  [[ "$PROTO" == "udp" || "$PROTO" == "tcp" ]] || die "--proto must be udp or tcp"

  if [ -n "$DOMAIN" ]; then
    SERVER_ADDR="$DOMAIN"
  elif [ -z "$SERVER_ADDR" ]; then
    info "Detecting public IP address..."
    SERVER_ADDR=$(detect_public_ip)
  fi
  info "Server address for clients: ${SERVER_ADDR}"

  install_packages
  mkdir -p "$SERVER_DIR" "$CLIENTS_DIR"
  chmod 700 "$SERVER_DIR" "$CLIENTS_DIR"
  [ -f "$VARS_FILE" ] || write_vars_file

  init_pki
  gen_server_cert
  gen_dh
  gen_ta_key
  copy_server_certs
  gen_crl

  write_server_conf
  configure_sysctl
  configure_firewall
  start_service

  save_state

  ok "OpenVPN is set up and running."
  echo ""
  echo "  Server address : ${SERVER_ADDR}"
  echo "  Port / proto   : ${PORT}/${PROTO}"
  echo ""
  echo "Add your first client with:"
  echo "  ./openvpn.sh adduser <name>"
}

install_packages() {
  info "Installing packages (openvpn, easy-rsa, ufw)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq openvpn easy-rsa ufw openssl curl >/dev/null
  [ -x "$EASYRSA_BIN" ] || die "easy-rsa package did not install $EASYRSA_BIN as expected."
}

init_pki() {
  if [ ! -f "$PKI_DIR/ca.crt" ]; then
    info "Initializing PKI and CA..."
    easyrsa init-pki
    EASYRSA_REQ_CN="OpenVPN-CA" easyrsa build-ca nopass
  else
    info "PKI already initialized, skipping."
  fi
}

gen_server_cert() {
  if [ ! -f "$PKI_DIR/issued/server.crt" ]; then
    info "Generating server certificate..."
    EASYRSA_REQ_CN="server" easyrsa gen-req server nopass
    easyrsa sign-req server server
  else
    info "Server certificate already exists, skipping."
  fi
}

gen_dh() {
  if [ ! -f "$PKI_DIR/dh.pem" ]; then
    info "Generating Diffie-Hellman parameters (this can take a minute)..."
    easyrsa gen-dh
  else
    info "DH parameters already exist, skipping."
  fi
}

gen_ta_key() {
  if [ ! -f "$SERVER_DIR/ta.key" ]; then
    info "Generating tls-crypt key..."
    openvpn --genkey secret "$SERVER_DIR/ta.key"
  else
    info "tls-crypt key already exists, skipping."
  fi
}

copy_server_certs() {
  install -m 644 "$PKI_DIR/ca.crt" "$SERVER_DIR/ca.crt"
  install -m 644 "$PKI_DIR/issued/server.crt" "$SERVER_DIR/server.crt"
  install -m 600 "$PKI_DIR/private/server.key" "$SERVER_DIR/server.key"
  install -m 644 "$PKI_DIR/dh.pem" "$SERVER_DIR/dh.pem"
}

gen_crl() {
  easyrsa gen-crl
  install -m 644 "$PKI_DIR/crl.pem" "$SERVER_DIR/crl.pem"
}

write_server_conf() {
  info "Writing server configuration..."
  {
    echo "port ${PORT}"
    echo "proto ${PROTO}"
    echo "dev tun"
    echo ""
    echo "ca   ${SERVER_DIR}/ca.crt"
    echo "cert ${SERVER_DIR}/server.crt"
    echo "key  ${SERVER_DIR}/server.key"
    echo "dh   ${SERVER_DIR}/dh.pem"
    echo ""
    echo "crl-verify ${SERVER_DIR}/crl.pem"
    echo "tls-crypt ${SERVER_DIR}/ta.key"
    echo ""
    echo "server ${NETWORK} ${NETMASK}"
    echo ""
    echo 'push "redirect-gateway def1 bypass-dhcp"'
    for dns in $DNS_SERVERS; do
      echo "push \"dhcp-option DNS ${dns}\""
    done
    echo ""
    echo "keepalive 10 120"
    echo ""
    echo "cipher ${CIPHER}"
    echo "auth ${AUTH_DIGEST}"
    echo "tls-version-min ${TLS_MIN}"
    echo "tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-GCM-SHA384"
    echo ""
    echo "persist-key"
    echo "persist-tun"
    echo ""
    echo "status /var/log/openvpn-status.log"
    echo "log-append /var/log/openvpn.log"
    echo "verb 3"
    echo "mute 20"
    echo ""
    echo "max-clients ${MAX_CLIENTS}"
    echo "explicit-exit-notify 1"
  } > "$SERVER_DIR/server.conf"
}

configure_sysctl() {
  info "Enabling IP forwarding..."
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
  sysctl -q --system
}

configure_firewall() {
  info "Configuring firewall (ufw)..."
  local iface
  iface=$(ip route show default | awk '/default/ {for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1); exit}')
  [ -n "$iface" ] || die "Could not determine the default network interface."

  ufw allow 22/tcp comment 'SSH' >/dev/null
  ufw allow "${PORT}/${PROTO}" comment 'OpenVPN' >/dev/null

  local marker="# openvpn.sh NAT masquerade"
  if ! grep -qF "$marker" /etc/ufw/before.rules 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk -v net="${NETWORK}/24" -v iface="$iface" -v marker="$marker" '
      /^\*filter/ && !done {
        print marker
        print "*nat"
        print ":POSTROUTING ACCEPT [0:0]"
        print "-A POSTROUTING -s " net " -o " iface " -j MASQUERADE"
        print "COMMIT"
        print ""
        done = 1
      }
      { print }
    ' /etc/ufw/before.rules > "$tmp"
    install -m 640 "$tmp" /etc/ufw/before.rules
    rm -f "$tmp"
  fi

  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw default allow routed >/dev/null
  ufw --force enable >/dev/null
  ufw reload >/dev/null
}

start_service() {
  info "Starting OpenVPN service..."
  systemctl daemon-reload
  systemctl enable --now "openvpn-server@server" >/dev/null
  sleep 2
  systemctl is-active --quiet "openvpn-server@server" || die "OpenVPN failed to start. Check: journalctl -u openvpn-server@server -n 50"
}

# =============================================================================
# Client helpers
# =============================================================================
validate_name() {
  local name="$1"
  [ -n "$name" ] || die "A client name is required."
  [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Client name '${name}' is invalid. Use only letters, digits, hyphens and underscores."
  [ "$name" != "server" ] || die "'server' is a reserved name."
}

client_exists() {
  [ -f "$PKI_DIR/issued/$1.crt" ]
}

client_status() {
  # prints "active" or "revoked" for an issued client, or nothing if unknown
  awk -F'\t' -v cn="/CN=$1" '$NF==cn {print ($1=="R") ? "revoked" : "active"}' "$PKI_DIR/index.txt" | tail -n1
}

render_ovpn() {
  local name="$1" out_dir="$CLIENTS_DIR/$1" out="$CLIENTS_DIR/$1/$1.ovpn"
  mkdir -p "$out_dir"
  chmod 700 "$out_dir"
  {
    echo "client"
    echo "dev tun"
    echo "proto ${PROTO}"
    echo "remote ${SERVER_ADDR} ${PORT}"
    echo "nobind"
    echo "persist-key"
    echo "persist-tun"
    echo "cipher ${CIPHER}"
    echo "auth ${AUTH_DIGEST}"
    echo "tls-version-min ${TLS_MIN}"
    echo "tls-client"
    echo "key-direction 1"
    echo "remote-cert-tls server"
    echo "verb 3"
    echo ""
    echo "<ca>"
    cat "$PKI_DIR/ca.crt"
    echo "</ca>"
    echo ""
    echo "<cert>"
    awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' "$PKI_DIR/issued/$name.crt"
    echo "</cert>"
    echo ""
    echo "<key>"
    cat "$PKI_DIR/private/$name.key"
    echo "</key>"
    echo ""
    echo "<tls-crypt>"
    cat "$SERVER_DIR/ta.key"
    echo "</tls-crypt>"
  } > "$out"
  chmod 600 "$out"
  echo "$out"
}

reload_service() {
  systemctl reload "openvpn-server@server" 2>/dev/null || systemctl restart "openvpn-server@server"
}

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local prompt="$1" reply
  read -r -p "${prompt} [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# =============================================================================
# adduser
# =============================================================================
cmd_adduser() {
  require_root adduser
  require_setup
  load_state
  local name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) ASSUME_YES=1; shift ;;
      *) name="$1"; shift ;;
    esac
  done
  validate_name "$name"

  if client_exists "$name"; then
    die "Client '${name}' already exists. Use 'edituser ${name}' to rotate its certificate, or 'deluser ${name}' first."
  fi

  info "Generating certificate for '${name}'..."
  EASYRSA_REQ_CN="$name" easyrsa gen-req "$name" nopass
  easyrsa sign-req client "$name"

  local out
  out=$(render_ovpn "$name")

  ok "Client '${name}' created."
  echo ""
  echo "  Config file : ${out}"
  echo ""
  echo "Download it with:"
  echo "  scp $(whoami)@${SERVER_ADDR}:${out} ./"
  echo "or:"
  echo "  ssh $(whoami)@${SERVER_ADDR} ./openvpn.sh download ${name} > ${name}.ovpn"
}

# =============================================================================
# edituser — rotate a client's certificate (revoke old, issue new, same name)
# =============================================================================
cmd_edituser() {
  require_root edituser
  require_setup
  load_state
  local name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) ASSUME_YES=1; shift ;;
      *) name="$1"; shift ;;
    esac
  done
  validate_name "$name"

  client_exists "$name" || die "Client '${name}' does not exist. Use 'adduser ${name}' to create it."

  confirm "This will revoke the current certificate for '${name}' and issue a new one. Continue?" || { warn "Aborted."; exit 1; }

  if [ "$(client_status "$name")" = "active" ]; then
    info "Revoking current certificate for '${name}'..."
    easyrsa revoke "$name"
    gen_crl
  fi

  rm -f "$PKI_DIR/reqs/$name.req" "$PKI_DIR/private/$name.key" "$PKI_DIR/issued/$name.crt"

  info "Issuing new certificate for '${name}'..."
  EASYRSA_REQ_CN="$name" easyrsa gen-req "$name" nopass
  easyrsa sign-req client "$name"

  local out
  out=$(render_ovpn "$name")
  reload_service

  ok "Client '${name}' certificate rotated."
  echo "  Config file : ${out}"
}

# =============================================================================
# deluser
# =============================================================================
cmd_deluser() {
  require_root deluser
  require_setup
  load_state
  local name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) ASSUME_YES=1; shift ;;
      *) name="$1"; shift ;;
    esac
  done
  validate_name "$name"

  client_exists "$name" || die "Client '${name}' does not exist."

  confirm "This will revoke '${name}' and permanently disconnect it. Continue?" || { warn "Aborted."; exit 1; }

  if [ "$(client_status "$name")" = "active" ]; then
    info "Revoking '${name}'..."
    easyrsa revoke "$name"
    gen_crl
  fi

  rm -rf "${CLIENTS_DIR:?}/${name}"
  reload_service

  ok "Client '${name}' revoked and removed."
}

# =============================================================================
# listusers
# =============================================================================
cmd_listusers() {
  require_root listusers
  require_setup
  load_state

  [ -f "$PKI_DIR/index.txt" ] || { info "No clients yet."; return; }

  info "OpenVPN clients:"
  local count=0
  while IFS=$'\t' read -r -a fields; do
    local status="${fields[0]}"
    [[ "$status" =~ ^(V|R|E)$ ]] || continue
    local subj="${fields[-1]}"
    local name="${subj#/CN=}"
    [ "$name" = "server" ] && continue
    local label
    case "$status" in
      V) label="active" ;;
      R) label="revoked" ;;
      E) label="expired" ;;
    esac
    printf "  %-24s %s\n" "$name" "$label"
    count=$((count + 1))
  done < "$PKI_DIR/index.txt"
  if [ "$count" -eq 0 ]; then
    info "No clients yet. Add one with: ./openvpn.sh adduser <name>"
  fi
}

# =============================================================================
# download
# =============================================================================
cmd_download() {
  require_root download
  require_setup
  load_state
  local name="${1:-}"
  validate_name "$name"
  local file="$CLIENTS_DIR/$name/$name.ovpn"
  [ -f "$file" ] || die "No config found for '${name}'. Run: ./openvpn.sh adduser ${name}"
  cat "$file"
}

# =============================================================================
# status
# =============================================================================
cmd_status() {
  require_root status
  require_setup
  systemctl status "openvpn-server@server" --no-pager || true
  echo ""
  if [ -f /var/log/openvpn-status.log ]; then
    info "Connected clients:"
    awk '/^CLIENT LIST/,/^ROUTING TABLE/' /var/log/openvpn-status.log | sed -n '3,$p' | grep -v '^ROUTING TABLE' || echo "  (none)"
  fi
}

# =============================================================================
# update
# =============================================================================
cmd_update() {
  require_root update
  require_setup
  local before after
  before=$(openvpn --version | head -n1)
  info "Updating OpenVPN package..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --only-upgrade openvpn >/dev/null
  systemctl restart "openvpn-server@server"
  after=$(openvpn --version | head -n1)
  ok "Update complete."
  echo "  Before: ${before}"
  echo "  After:  ${after}"
}

# =============================================================================
# usage / dispatch
# =============================================================================
usage() {
  cat <<EOF
openvpn.sh — set up and manage an OpenVPN server from a single script.

Usage: $0 <command> [args]

Commands:
  setup [options]        Install and configure the OpenVPN server (see 'setup --help')
  adduser <name>          Create a new client certificate and .ovpn file
  edituser <name>         Rotate a client's certificate (revoke old, issue new)
  deluser <name>          Revoke and remove a client
  listusers                List all clients and their status
  download <name>         Print a client's .ovpn file to stdout (for scp/ssh download)
  status                   Show service status and connected clients
  update                   Upgrade the openvpn package and restart the service
  help                     Show this help

Examples:
  ./openvpn.sh setup --domain vpn.example.com
  ./openvpn.sh adduser alice
  ./openvpn.sh download alice > alice.ovpn
  ./openvpn.sh deluser alice
EOF
}

main() {
  local cmd="${1:-help}"
  [ $# -gt 0 ] && shift || true
  case "$cmd" in
    setup) cmd_setup "$@" ;;
    adduser|add) cmd_adduser "$@" ;;
    edituser|edit) cmd_edituser "$@" ;;
    deluser|del|delete|revoke) cmd_deluser "$@" ;;
    listusers|list) cmd_listusers "$@" ;;
    download|export|getclient) cmd_download "$@" ;;
    status) cmd_status "$@" ;;
    update) cmd_update "$@" ;;
    help|-h|--help) usage ;;
    *) err "Unknown command: ${cmd}"; usage; exit 1 ;;
  esac
}

main "$@"
