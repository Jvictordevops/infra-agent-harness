# shellcheck shell=bash
# Per-machine configuration of the evidence module. Sourced by bin/evidence, bin/clip, bin/clip-server,
# link.sh and doctor.sh.
#
# File: ~/.config/infra-agent-harness/evidence.conf (IAH_EVIDENCE_CONF overrides), lines "key=value".
# It is parsed as data: nothing in it is executed. Keys:
#   server_host      name clients use to reach the server (also the certificate name)
#   server_port      published port of the server (default 443)
#   archive_dir      where encrypted archives go (default ~/evidence-archive)
#   key_fingerprint  first 12 hex of sha256 of the key file (optional; checked by key-restore and doctor)
#   secrets_backend  file (default) | bitwarden | any backends/<name>.sh

EV_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EV_CONF_FILE="${IAH_EVIDENCE_CONF:-$HOME/.config/infra-agent-harness/evidence.conf}"

# ev_conf_get <key> -> last value, or empty ("~/" at the start is expanded)
ev_conf_get() {
  local v
  [ -f "$EV_CONF_FILE" ] || return 0
  v="$(sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]#]*).*\$/\\1/p" "$EV_CONF_FILE" | tail -1)"
  # shellcheck disable=SC2088
  case "$v" in '~/'*) v="$HOME/${v:2}" ;; esac
  printf '%s' "$v"
}

ev_server_host() { ev_conf_get server_host; }
ev_server_port() { local p; p="$(ev_conf_get server_port)"; printf '%s' "${p:-443}"; }
ev_key_path() { printf '%s' "${EVIDENCE_KEY:-$HOME/.config/infra-agent-harness/evidence.key}"; }
ev_client_dir() { printf '%s' "${EVIDENCE_CLIENT_CONF:-$HOME/.config/infra-agent-harness/clip}"; }
ev_archive_dir() {
  local d; d="$(ev_conf_get archive_dir)"
  printf '%s' "${EVIDENCE_ARCHIVE:-${d:-$HOME/evidence-archive}}"
}

# ev_url <host> [port] -> https://host, or https://host:port when the port is not 443
ev_url() {
  local port="${2:-443}"
  if [ "$port" = 443 ]; then printf 'https://%s' "$1"; else printf 'https://%s:%s' "$1" "$port"; fi
}

# ev_backend_path -> path of the configured secrets backend script (returns 1 with a message if unusable)
ev_backend_path() {
  local b p; b="$(ev_conf_get secrets_backend)"; b="${b:-file}"
  if [[ ! "$b" =~ ^[a-z0-9-]+$ ]]; then echo "secrets_backend '$b' is not a valid name" >&2; return 1; fi
  p="$EV_MODULE_DIR/backends/$b.sh"
  if [ ! -x "$p" ]; then echo "secrets backend '$b' not found (no executable $p)" >&2; return 1; fi
  printf '%s' "$p"
}

ev_is_wsl() { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; }

ev_sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -c1-64; }
ev_sha12() { ev_sha "$1" | cut -c1-12; }
