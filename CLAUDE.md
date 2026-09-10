# CLAUDE.md — AI Assistant Guide for setup-openvpn

This file provides context for Claude (or any AI assistant) to understand the project and make changes safely.

---

## Project Overview

This project is a **single self-contained Bash script**, `openvpn.sh`, that:
1. Installs and configures an OpenVPN server on a Debian/Ubuntu host (EasyRSA
   PKI, server config, UFW firewall with NAT masquerade, systemd service)
2. Manages VPN clients: add, rotate ("edit"), delete, list
3. Produces ready-to-import `.ovpn` client configs with all certificates
   embedded inline

There is no local orchestration layer (no Terraform, no Ansible, nothing to
install on the operator's machine). The script is copied to the target
server and run there directly:

```
User → scp openvpn.sh to server → ssh in → ./openvpn.sh <command>
```

---

## File Layout

| Path | Purpose |
|------|---------|
| `openvpn.sh` | The entire project — setup, client management, everything |
| `README.md` | User-facing usage docs |

### On the target server (created by the script, not in this repo)

```
/etc/openvpn/
├── server/                     # server.conf, ca.crt, server.crt/key, dh.pem, ta.key, crl.pem
├── pki/                        # EasyRSA PKI: ca.key, issued/, private/, index.txt, crl.pem
├── clients/<name>/<name>.ovpn  # generated client configs
├── easyrsa-vars                # EasyRSA vars file (written once by `setup`)
└── openvpn-manager.conf        # persisted settings: PORT, PROTO, NETWORK, NETMASK,
                                 # DNS_SERVERS, CIPHER, AUTH_DIGEST, TLS_MIN, MAX_CLIENTS,
                                 # DOMAIN, SERVER_ADDR
```

`openvpn-manager.conf` is sourced (`load_state`) by every command after
`setup` so port/protocol/domain/etc. don't need to be re-specified.

---

## Script Structure (`openvpn.sh`)

Organized top to bottom as:

1. **Paths & defaults** — constants and the tunable defaults (port 1194/udp,
   `10.8.0.0/24`, AES-256-GCM, SHA256, TLS 1.2, EasyRSA RSA-2048)
2. **Logging helpers** — `info`/`ok`/`warn`/`err`/`die`
3. **Environment checks** — `require_root`, `require_os` (apt-based only),
   `require_setup` (checks `openvpn-manager.conf` exists)
4. **State** — `load_state` / `save_state` (source/write `openvpn-manager.conf`),
   `detect_public_ip` (ipify → ifconfig.me → `hostname -I` fallback chain)
5. **EasyRSA helpers** — `easyrsa()` wraps the real `easyrsa` binary with
   `--batch --pki-dir --vars`; `write_vars_file` writes the EasyRSA vars once
6. **`cmd_setup`** and its sub-steps: `install_packages`, `init_pki`,
   `gen_server_cert`, `gen_dh`, `gen_ta_key`, `copy_server_certs`, `gen_crl`,
   `write_server_conf`, `configure_sysctl`, `configure_firewall`, `start_service`
7. **Client helpers** — `validate_name`, `client_exists`, `client_status`
   (parses EasyRSA's `pki/index.txt`), `render_ovpn`, `reload_service`, `confirm`
8. **`cmd_adduser` / `cmd_edituser` / `cmd_deluser` / `cmd_listusers` / `cmd_download`**
9. **`cmd_status` / `cmd_update`**
10. **`usage` / `main`** — command dispatch

All steps in `cmd_setup` are idempotent (each checks whether its output file
already exists before doing work), so re-running `setup` — including with
new flags, e.g. a different `--port` — safely reconfigures and restarts the
service without regenerating the PKI/certs.

---

## Conventions

- **Strict mode**: the script runs under `set -euo pipefail`. When adding a
  new command, be careful with `test && action` as the *last* statement in a
  function — if the test is false and nothing follows, the function's (and
  possibly the whole script's) exit status becomes non-zero. Prefer an
  explicit `if/fi` for anything that isn't meant to signal failure.
- **Client names**: validated against `^[a-zA-Z0-9_-]+$` via `validate_name`;
  `server` is reserved.
- **Certificates**: RSA 2048, SHA256 digest, CA valid 10 years, leaf certs
  3 years (`easyrsa-vars`, written by `write_vars_file`).
- **"Editing" a user** means rotating their certificate (revoke the old one,
  issue a new one under the same CN) — there's no mutable per-client config
  beyond the cert itself; server-wide settings (port, cipher, DNS, ...) are
  changed by re-running `setup` with new flags.
- **Firewall**: NAT masquerade is inserted into `/etc/ufw/before.rules`
  guarded by a `# openvpn.sh NAT masquerade` marker comment so re-running
  `setup` never duplicates the block.

## Common Changes

- **Change a default** (port, cipher, subnet, ...): edit the variable near
  the top of `openvpn.sh` under "Defaults", or just pass the corresponding
  flag to `setup` on a running server to reconfigure it in place.
- **Add a new subcommand**: add a `cmd_<name>()` function following the
  existing pattern (`require_root`, `require_setup`, `load_state`, do the
  work, print a short summary), then add a case to the `main()` dispatcher
  and a line to `usage()`.
- **Add a new `setup` flag**: add it to the `while`/`case` flag parser in
  `cmd_setup`, its default near the top, and include it in `save_state`/
  `load_state` if other commands need to see it.

## Testing Changes

There's no CI/test suite — this is a script meant to run on a real VPS.
Before trusting a change:

```bash
bash -n openvpn.sh        # syntax check
shellcheck openvpn.sh     # lint (apt-get install shellcheck if missing)
```

For logic changes to certificate/config rendering (`render_ovpn`,
`write_server_conf`, the UFW NAT insertion in `configure_firewall`), it's
often fastest to `source` a copy of the script with the trailing `main "$@"`
line stripped, override the relevant path/config variables to a scratch
directory, and call the function directly against fabricated inputs (dummy
certs via `openssl req -x509 ...`, a hand-written `pki/index.txt`, etc.)
rather than running `setup` for real. A genuine end-to-end run needs a real
Debian/Ubuntu host — it installs packages, edits `/etc/ufw/before.rules`,
enables UFW, and starts a systemd service, none of which is safe or
reliably testable in a sandboxed container.

## Gotchas

1. **EasyRSA PKI path** — the PKI lives at `/etc/openvpn/pki`, separate from
   the EasyRSA program itself (`/usr/share/easy-rsa/easyrsa`, from the apt
   package). Always invoke it through the `easyrsa()` wrapper, which passes
   `--pki-dir` and `--vars` explicitly — never rely on `cwd`-relative lookup.
2. **`pki/index.txt` column count varies** — a revoked (`R`) line has an
   extra revocation-date column that a valid (`V`) line doesn't. Use `$NF`
   in awk (last field) to get the subject, not a fixed column index.
3. **Client cert PEM extraction** — EasyRSA's `issued/<name>.crt` can have
   extra text before `-----BEGIN CERTIFICATE-----`; `render_ovpn` strips it
   with an awk range pattern rather than concatenating the raw file.
4. **DH generation is slow** — `easyrsa gen-dh` can take a minute or more on
   a small VPS; this runs synchronously and is expected to be slow.
5. **One process, one proto** — the server listens on a single port/protocol
   (`--proto udp` or `--proto tcp`, not both). There's no dual UDP+TCP
   listener; don't half-implement one without also running a second OpenVPN
   instance and load-balancing config to match.
6. **UFW before.rules NAT block** — must be inserted before the `*filter`
   table, not via `ufw route`/`ufw allow`, because UFW's normal rule
   interface can't express NAT/MASQUERADE. Idempotency depends on the
   marker comment `# openvpn.sh NAT masquerade` — don't rename it without
   also handling the old marker on already-configured servers.
