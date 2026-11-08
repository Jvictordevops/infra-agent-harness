#!/usr/bin/env bash
# Secrets backend "file": one file per secret in ~/.config/infra-agent-harness/secrets (dir 700, files 600).
# Usage: file.sh get <name>   secret on stdout; exit 1 if it does not exist
#        file.sh put <name>   secret from stdin (replaces the previous one)
#        file.sh status | lock
# <name> is restricted to [a-z0-9-]. Never prints a secret anywhere but stdout of "get".
set -euo pipefail

DIR="$HOME/.config/infra-agent-harness/secrets"
die() { echo "file backend: $*" >&2; exit 1; }
valid() { [[ "${1:-}" =~ ^[a-z0-9-]+$ ]] || die "invalid secret name '${1:-}' (use a-z, 0-9 and -)"; }

case "${1:-}" in
  get)
    valid "${2:-}"
    [ -f "$DIR/$2" ] || exit 1
    cat "$DIR/$2"
    ;;
  put)
    valid "${2:-}"
    ( umask 077; mkdir -p "$DIR" ); chmod 700 "$DIR"
    tmp="$DIR/.$2.$$"
    ( umask 077; cat > "$tmp" ) || { rm -f "$tmp"; die "cannot write the secret"; }
    mv "$tmp" "$DIR/$2"; chmod 600 "$DIR/$2"
    ;;
  status) echo "file: $DIR" ;;
  lock) echo "file backend: nothing to lock" >&2; exit 3 ;;
  *) echo "usage: file.sh get <name> | put <name> | status | lock" >&2; exit 2 ;;
esac
