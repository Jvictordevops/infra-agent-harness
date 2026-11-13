#!/usr/bin/env bash
# Secrets backend "bitwarden": each secret is a secure note named iah-<name> (IAH_BW_PREFIX changes the prefix;
# end-to-end encrypted, HTTPS).
# Usage: bitwarden.sh get <name>   secret on stdout; exit 1 if there is no such note
#        bitwarden.sh put <name>   secret from stdin (creates or updates the note)
#        bitwarden.sh status       login state of the bw CLI
#        bitwarden.sh lock         lock the vault and forget the cached session
# Needs the Bitwarden CLI (bw) and jq. The unlocked session is cached in a 600 file for CLIP_SESSION_TTL_MIN
# minutes (default 480). Never prints a secret anywhere but stdout of "get".
# 'cond && x || die' is intended: die exits.
# shellcheck disable=SC2015
set -euo pipefail

CONF="$HOME/.config/infra-agent-harness"
SESSION_FILE="$CONF/bw-session"
TTL_MIN="${CLIP_SESSION_TTL_MIN:-480}"
MAX=9000                                 # Bitwarden notes hold up to 10.000 characters
die() { echo "bitwarden: $*" >&2; exit 1; }
valid() { [[ "${1:-}" =~ ^[a-z0-9-]+$ ]] || die "invalid secret name '${1:-}' (use a-z, 0-9 and -)"; }
note_name() { printf '%s%s' "${IAH_BW_PREFIX-iah-}" "$1"; }   # prefix avoids clashing with the user's own notes
encode() { base64 | tr -d '\n'; }        # each bw call starts Node (~2 s): avoid `bw encode`
id_file() { printf '%s/bw-note-id-%s' "$CONF" "$1"; }

need_tools() {
  command -v bw >/dev/null || die "Bitwarden CLI (bw) not installed"
  command -v jq >/dev/null || die "jq not installed"
}
bw_ready() {
  need_tools
  if [ -s "$SESSION_FILE" ] && [ -z "$(find "$SESSION_FILE" -mmin +"$TTL_MIN" 2>/dev/null)" ]; then
    BW_SESSION="$(cat "$SESSION_FILE")"; export BW_SESSION; return 0   # trusted while fresh; if rejected: lock
  fi
  [ "$(bw status | jq -r .status)" = unauthenticated ] && die "not logged in: bw config server <your server url> && bw login"
  # The prompt of 'bw unlock --raw' is lost when its output is captured (it looks like a hang, and with key-backup the
  # secret is on stdin): ask on the terminal ourselves and pass the password by environment variable, never in argv.
  local tty="${IAH_BW_TTY:-/dev/tty}" pw=""
  { [ -r "$tty" ] && [ -w "$tty" ]; } 2>/dev/null || die "no terminal to ask the master password: run 'bw unlock' yourself, or run this command from a terminal"
  printf 'bitwarden: master password (the vault stays unlocked %s min): ' "$TTL_MIN" >> "$tty"
  IFS= read -rs pw < "$tty" || true
  printf '\n' >> "$tty"
  [ -n "$pw" ] || die "no password given"
  BW_SESSION="$(BW_PASSWORD="$pw" bw unlock --passwordenv BW_PASSWORD --raw)" || { pw=""; die "unlock failed (wrong password?)"; }
  pw=""; export BW_SESSION
  ( umask 077; mkdir -p "$CONF"; printf '%s' "$BW_SESSION" > "$SESSION_FILE" )
}
get_note() { # $1 name -> note JSON (empty if missing); caches its id
  local name="$1" id json
  id="$(cat "$(id_file "$name")" 2>/dev/null || true)"
  if [ -n "$id" ] && json="$(bw get item "$id" 2>/dev/null)"; then printf '%s' "$json"; return 0; fi
  json="$(bw list items --search "$(note_name "$name")" | jq --arg n "$(note_name "$name")" '[.[] | select(.name == $n and .type == 2)][0] // empty')"
  [ -n "$json" ] && ( umask 077; mkdir -p "$CONF"; printf '%s' "$json" | jq -r .id > "$(id_file "$name")" )
  printf '%s' "$json"
}

cmd_get() {
  local json
  valid "${1:-}"; bw_ready; bw sync >/dev/null
  json="$(get_note "$1")"; [ -n "$json" ] || exit 1
  printf '%s' "$json" | jq -j '.notes // ""'
}
cmd_put() {
  local name="${1:-}" text json
  valid "$name"; need_tools
  text="$(cat)"
  [ "${#text}" -le "$MAX" ] || die "secret too long (${#text} chars, max $MAX)"
  bw_ready; bw sync >/dev/null; json="$(get_note "$name")"
  if [ -z "$json" ]; then
    ( umask 077; mkdir -p "$CONF"
      bw get template item | jq --arg n "$(note_name "$name")" --arg t "$text" '.type = 2 | .secureNote = {type: 0} | .name = $n | .notes = $t | .login = null' \
        | encode | bw create item | jq -r .id > "$(id_file "$name")" )
  else
    printf '%s' "$json" | jq --arg t "$text" '.notes = $t' | encode | bw edit item "$(printf '%s' "$json" | jq -r .id)" >/dev/null
  fi
}
cmd_lock() { command -v bw >/dev/null && bw lock >/dev/null 2>&1 || true; rm -f "$SESSION_FILE"; echo "bitwarden: locked" >&2; }
cmd_status() {
  command -v bw >/dev/null && command -v jq >/dev/null || { echo "bitwarden: bw or jq not installed"; return 0; }
  echo "bitwarden: $(BW_SESSION="$(cat "$SESSION_FILE" 2>/dev/null || true)" bw status 2>/dev/null | jq -r '.status + " @ " + (.serverUrl // "?")' || echo 'unknown')"
}

case "${1:-}" in
  get) shift; cmd_get "$@" ;;
  put) shift; cmd_put "$@" ;;
  status) cmd_status ;;
  lock) cmd_lock ;;
  *) echo "usage: bitwarden.sh get <name> | put <name> | status | lock" >&2; exit 2 ;;
esac
