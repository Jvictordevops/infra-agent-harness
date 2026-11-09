#!/usr/bin/env bash
# Tests for the secrets backends of the evidence module, in a throwaway HOME. Touches nothing real.
# The bitwarden backend is only syntax-checked and shown to fail cleanly without bw.
# Checks are strings evaluated by check(): single quotes and variables used only there are intended.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

MOD="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=../../../tests/lib/portable.sh
. "$MOD/../../tests/lib/portable.sh"   # grep_q
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: macOS temp dirs sit behind the /var -> /private/var link
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FILE="$MOD/backends/file.sh"; BW="$MOD/backends/bitwarden.sh"
D="$HOME/.config/infra-agent-harness/secrets"
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# --- file backend ----------------------------------------------------------------------
check "get of a missing secret exits 1"        '"$FILE" get nothing-here >/dev/null 2>&1; [ $? = 1 ]'
check "put stores stdin"                       'printf "s3cr3t\nline2" | "$FILE" put my-key && [ "$("$FILE" get my-key)" = "$(printf "s3cr3t\nline2")" ]'
check "secrets dir is 700"                     '[ "$(mode "$D")" = 700 ]'
check "secret file is 600"                     '[ "$(mode "$D/my-key")" = 600 ]'
check "put replaces the previous value"        'printf new | "$FILE" put my-key && [ "$("$FILE" get my-key)" = new ]'
check "no temp files left behind"              '[ "$(find "$D" -type f | wc -l | tr -d " ")" = 1 ]'
check "empty secret is allowed"                'printf "" | "$FILE" put empty-one && [ -z "$("$FILE" get empty-one)" ] && "$FILE" get empty-one'
for bad in "Bad" "a_b" "../x" "a/b" "a.b" "" "sp ace"; do
  check "name '$bad' rejected (put)"           '! printf x | "$FILE" put "$bad" >/dev/null 2>&1'
  check "name '$bad' rejected (get)"           '! "$FILE" get "$bad" >/dev/null 2>&1'
done
check "nothing written outside the secrets dir" '[ ! -e "$HOME/.config/infra-agent-harness/x" ] && [ ! -e "$TMP/x" ]'
check "lock is not supported (exit 3)"         '"$FILE" lock >/dev/null 2>&1; [ $? = 3 ]'
check "status names the dir"                   '"$FILE" status | grep_q "secrets"'
check "unknown action: usage, exit 2"          '"$FILE" nope >/dev/null 2>&1; [ $? = 2 ]'
check "secrets never in status output"        '! "$FILE" status | grep_q new'

# --- bitwarden backend -----------------------------------------------------------------
check "bitwarden.sh: bash -n"                  'bash -n "$BW"'
check "bitwarden.sh: executable"               '[ -x "$BW" ]'
NOBW="$TMP/nobw"; mkdir -p "$NOBW"
for t in bash cat jq base64 tr find sed mkdir rm; do p="$(command -v "$t")" && ln -s "$p" "$NOBW/$t"; done
check "bitwarden get without bw fails cleanly" 'out="$(PATH="$NOBW" "$BW" get some-key 2>&1)"; rc=$?; [ "$rc" = 1 ] && grep -q "not installed" <<<"$out"'
check "bitwarden put without bw fails cleanly" 'out="$(printf x | PATH="$NOBW" "$BW" put some-key 2>&1)"; rc=$?; [ "$rc" = 1 ] && grep -q "not installed" <<<"$out"'
check "bitwarden rejects bad names"            '! PATH="$NOBW" "$BW" get "../x" >/dev/null 2>&1'
check "bitwarden lock without bw: no error"    'PATH="$NOBW" "$BW" lock >/dev/null 2>&1'
check "bitwarden status without bw: no error"  'PATH="$NOBW" "$BW" status | grep_q "not installed"'

if [ "$fail" = 0 ]; then echo "evidence backends: all tests passed"; else echo "evidence backends: tests FAILED"; exit 1; fi
