# shellcheck shell=bash
# Evidence module: checks. Sourced by bin/doctor when "modules=evidence" is active; uses its ok/warn/fail,
# HARNESS and MODULE_DIR. Never prints keys or tokens. Must not exit.
# 'cond && ok … || warn …' is safe: ok/warn/fail only append to an array and never fail.
# shellcheck disable=SC2015
# shellcheck source-path=SCRIPTDIR source=lib/config.sh
. "$MODULE_DIR/lib/config.sh"

# Tools
for ev_t in openssl curl zstd tar jq; do
  if command -v "$ev_t" >/dev/null; then ok "evidence: $ev_t present"; else fail "evidence: $ev_t missing"; fi
done

# Settings
if [ -f "$EV_CONF_FILE" ]; then ok "evidence: settings in $EV_CONF_FILE"
else warn "evidence: no settings file $EV_CONF_FILE (defaults in use; server_host is needed by init and clip-server)"; fi

# Evidence store / clipboard server reachable with this machine's client config?
ev_cc="$(ev_client_dir)"
if [ -s "$ev_cc/url" ] && [ -s "$ev_cc/server.crt" ]; then
  curl -s -m 6 --cacert "$ev_cc/server.crt" "$(cat "$ev_cc/url")/health" 2>/dev/null | grep -q ok \
    && ok "evidence: store / clipboard server reachable ($(cat "$ev_cc/url"))" \
    || warn "evidence: store / clipboard server not reachable now ($(cat "$ev_cc/url")): other network, VPN or host asleep"
else warn "evidence: no client config for the store (server host: bin/clip-server up; other machines: clip-server share <ssh-host>)"; fi

# Secrets backend
if ev_be="$(ev_backend_path 2>&1)"; then
  ok "evidence: secrets backend $(basename "$ev_be" .sh)"
  if [ "$(basename "$ev_be" .sh)" = bitwarden ]; then
    if command -v bw >/dev/null; then
      ev_st="$("$ev_be" status 2>/dev/null || true)"
      case "$ev_st" in *unauthenticated*) warn "evidence: bw not logged in: bw config server <your server url> && bw login" ;; *) ok "evidence: $ev_st" ;; esac
    else warn "evidence: secrets_backend is bitwarden but bw is not installed"; fi
  fi
else warn "evidence: $ev_be"; fi

[ -L "$HOME/.local/bin/cpush" ] && ok "evidence: cpush / cpull installed" || fail "evidence: cpush / cpull not installed (bin/link-harness)"

# Key
ev_key="$(ev_key_path)"
if [ -s "$ev_key" ]; then
  ev_fpr="$(ev_sha12 "$ev_key")"; ev_want="$(ev_conf_get key_fingerprint)"
  if [ -z "$ev_want" ]; then ok "evidence: key present, fingerprint $ev_fpr (set key_fingerprint to pin it)"
  elif [ "$ev_fpr" = "$ev_want" ]; then ok "evidence: key present, fingerprint $ev_fpr"
  else fail "evidence: key fingerprint $ev_fpr does NOT match key_fingerprint $ev_want"; fi
  ev_perm="$(stat -c %a "$ev_key" 2>/dev/null || stat -f %Lp "$ev_key")"
  if [ "$ev_perm" = 600 ]; then ok "evidence: key permissions 600"; else chmod 600 "$ev_key" && ok "evidence: key permissions fixed to 600"; fi
else
  fail "evidence: key missing at $ev_key (bin/evidence key-restore, or key-new on the first machine)"
fi
