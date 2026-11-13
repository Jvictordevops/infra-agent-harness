#!/usr/bin/env bash
# Tests for the secrets backends of the evidence module, in a throwaway HOME. Touches nothing real.
# The bitwarden backend is syntax-checked, shown to fail cleanly without bw, and its unlock flow runs against a fake bw.
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

# --- bitwarden unlock: the password is asked on the terminal (the prompt of 'bw unlock' is lost when its output is
# captured), passed to bw by environment variable, never in argv, never printed or stored. A fake bw, a fake terminal.
FB="$TMP/fakebw"; mkdir -p "$FB"
cat > "$FB/bw" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_BW_LOG"
case "$1" in
  status) echo '{"status":"locked","serverUrl":"https://bw.example.com"}' ;;
  unlock) [ "$2" = "--passwordenv" ] && [ "${!3-}" = "correct-pw" ] && echo "SESSION123" || { echo "Invalid master password." >&2; exit 1; } ;;
  sync) ;;
  list) echo '[]' ;;
  get) echo '{"type":1,"name":"","notes":"","login":{}}' ;;
  create) cat >/dev/null; echo '{"id":"note-1"}' ;;
  edit) cat >/dev/null ;;
esac
FAKE
chmod +x "$FB/bw"
export FAKE_BW_LOG="$TMP/bw.log" CLIP_SESSION_TTL_MIN=480
SF="$HOME/.config/infra-agent-harness/bw-session"; TTY="$TMP/tty"
bwput() { printf 'S3CR3T-VALUE' | PATH="$FB:$PATH" IAH_BW_TTY="$TTY" "$BW" put evidence-key >"$TMP/out" 2>&1; }
rm -f "$SF" "$FAKE_BW_LOG"; printf 'correct-pw\n' > "$TTY"
check "unlock: put with the right password works"     'bwput || { cat "$TMP/out"; false; }'
check "unlock: the question is shown on the terminal" 'grep -q "master password" "$TTY"'
check "unlock: the session is cached (600)"           '[ "$(cat "$SF")" = SESSION123 ] && [ "$(mode "$SF")" = 600 ]'
check "unlock: password not in argv"                  '! grep -q "correct-pw" "$FAKE_BW_LOG" && grep -q -- "--passwordenv BW_PASSWORD" "$FAKE_BW_LOG"'
check "unlock: password and secret not printed"       '! grep -q "correct-pw" "$TMP/out" && ! grep -q "S3CR3T" "$TMP/out"'
: > "$TTY"
check "unlock: a fresh session is not asked again"    'bwput'
rm -f "$SF"; printf 'wrong\n' > "$TTY"
check "unlock: wrong password fails cleanly"          '! bwput && grep -q "unlock failed" "$TMP/out" && [ ! -s "$SF" ]'
rm -f "$SF"; printf '\n' > "$TTY"
check "unlock: empty password fails cleanly"          '! bwput && grep -q "no password given" "$TMP/out"'
rm -f "$SF"; rm -f "$TTY"
check "unlock: no terminal fails with a message"      '! bwput && grep -q "no terminal" "$TMP/out"'

if [ "$fail" = 0 ]; then echo "evidence backends: all tests passed"; else echo "evidence backends: tests FAILED"; exit 1; fi
