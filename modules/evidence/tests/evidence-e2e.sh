#!/usr/bin/env bash
# End-to-end test of the evidence module (bin/evidence, bin/clip, server/server.py) on this machine.
# Throwaway server on 127.0.0.1, throwaway HOME, key and token; two simulated machines A and B.
# Touches nothing real: not your HOME, not a real store, not a real key. Usage: bash tests/evidence-e2e.sh
# 'cond && ok || ko' is intended: ko exits.
# shellcheck disable=SC2015
set -euo pipefail
MOD="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$(cd "$MOD/../.." && pwd)"
T="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: macOS temp dirs sit behind the /var -> /private/var link; SRV_PID=""
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
[ -d "$HOME/.local/share/mise/shims" ] && export PATH="$HOME/.local/share/mise/shims:$PATH"
export HOME="$T/home"; mkdir -p "$HOME"
unset EVIDENCE_KEY EVIDENCE_CLIENT_CONF EVIDENCE_ARCHIVE IAH_EVIDENCE_CONF IAH_REPO IAH_MODULES IAH_LANG IAH_METHOD
export GIT_AUTHOR_NAME="Dana Doe" GIT_AUTHOR_EMAIL="dana@example.com" GIT_COMMITTER_NAME="Dana Doe" GIT_COMMITTER_EMAIL="dana@example.com"
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
ok() { printf '  OK   %s\n' "$*"; }
ko() { printf '  FAIL %s\n' "$*"; exit 1; }
EV="$MOD/bin/evidence"; CLIP="$MOD/bin/clip"
PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"

# Throwaway server
CONF="$HOME/.config/infra-agent-harness"; CLI="$CONF/clip"
mkdir -p "$T/conf" "$T/data" "$CLI"
openssl rand -hex 32 > "$T/conf/token"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -keyout "$T/conf/server.key" -out "$T/conf/server.crt" 2>/dev/null
cp "$T/conf/server.crt" "$T/conf/token" "$CLI/"; echo "https://localhost:$PORT" > "$CLI/url"
CLIP_CONF="$T/conf" CLIP_DATA="$T/data" CLIP_BIND=127.0.0.1 CLIP_PORT="$PORT" python3 "$MOD/server/server.py" 2>/dev/null &
SRV_PID=$!
for _ in $(seq 20); do curl -s --cacert "$CLI/server.crt" "https://localhost:$PORT/health" | grep -q ok && break; sleep 0.3; done
printf 'server_host=localhost\nserver_port=%s\narchive_dir=%s\n' "$PORT" "$T/archive" > "$CONF/evidence.conf"
export EVIDENCE_KEY="$T/key"

newrepo() { git init -q "$1"; }
mkdir -p "$T/a" "$T/b"; newrepo "$T/a"; newrepo "$T/b"
cd "$T/a"                                                          # machine A (first machine)
"$EV" key-new >/dev/null && ok "key-new" || ko "key-new"
"$HARNESS/bin/new-work" global inv evidence-store-e2e --date 2030-01-02 >/dev/null
W="$(ls -d work/global/*.evidence-store-e2e)"; ok "new-work $W"
"$EV" init "$W" >/dev/null && grep -q '^evidence_store: localhost$' "$W/README.md" && ok "init: evidence_store: <server_host>" || ko "init"
"$HARNESS/bin/check-work" "$W" >/dev/null && ok "check-work accepts the work" || ko "check-work"
mkdir -p "$W/evidence/2026-11-02.cpu" && echo '{"cpu_p95": 87, "nota": "ñ €"}' > "$W/evidence/2026-11-02.cpu/data.json"
"$EV" sync "$W" | grep -q "1 uploaded" && ok "A uploads its folder" || ko "A upload"

mkdir -p "$T/b/$W"; cp "$W/README.md" "$T/b/$W/"; cd "$T/b"        # machine B, after a git pull
"$EV" sync "$W" | grep -q "1 downloaded" && ok "B downloads it" || ko "B download"
cmp -s "$T/a/$W/evidence/2026-11-02.cpu/data.json" "$W/evidence/2026-11-02.cpu/data.json" && ok "identical content (ñ €)" || ko "content"
mkdir -p "$W/evidence/2026-11-02.mem" && head -c 2000000 /dev/urandom | base64 > "$W/evidence/2026-11-02.mem/big.txt"
"$EV" sync "$W" | grep -q "1 uploaded" && ok "B uploads a 2.7 MB folder" || ko "B upload"
cd "$T/a"; "$EV" sync "$W" | grep -q "1 downloaded" && cmp -s "$T/b/$W/evidence/2026-11-02.mem/big.txt" "$W/evidence/2026-11-02.mem/big.txt" \
  && ok "A receives it intact" || ko "A sync"
"$EV" sync "$W" | grep -q "0 uploaded, 0 downloaded" && ok "second sync: nothing to do" || ko "idempotent"

cp "$CLI/url" "$T/url.on"; echo "https://localhost:1" > "$CLI/url"
"$EV" sync "$W" | grep -q "pending" && ok "store unreachable: pending, no error" || ko "offline"
cp "$T/url.on" "$CLI/url"
[ "$(curl -s -o /dev/null -w '%{http_code}' --cacert "$CLI/server.crt" "https://localhost:$PORT/ev/global.$(basename "$W")/")" = 401 ] \
  && ok "store refuses requests without token" || ko "auth"

# Key backup / restore through the file backend (default)
"$EV" key-backup | grep -q "backed up" && ok "key-backup" || ko "key-backup"
S="$CONF/secrets/evidence-key"
[ "$(stat -c %a "$S" 2>/dev/null || stat -f %Lp "$S")" = 600 ] && ok "backup file is 600" || ko "backup permissions"
"$EV" key-backup | grep -q "already backed up" && ok "key-backup again: nothing to do" || ko "key-backup idempotent"

"$EV" archive "$W" >/dev/null && A="$(ls "$T"/archive/*.enc)" && ok "archive $(basename "$A")" || ko "archive"
[ "$(head -c 8 "$A")" = "Salted__" ] && ok "archive is encrypted" || ko "archive in clear"
[ -z "$(ls "$T/data/global.$(basename "$W")" 2>/dev/null)" ] && ok "deleted from the store" || ko "store not empty"
[ -z "$(ls "$W/evidence")" ] && ok "deleted locally on A" || ko "A local not empty"
grep -q '^evidence_archive: ' "$W/README.md" && ok "README: evidence_archive" || ko "frontmatter"
cp "$W/README.md" "$T/b/$W/README.md"; cd "$T/b"
"$EV" sync "$W" | grep -q "local copy kept" && [ -f "$W/evidence/2026-11-02.mem/big.txt" ] && ok "B keeps its copy after the close" || ko "B keeps copy"
"$EV" restore "$A" "$T/r2" >/dev/null && grep -q '"cpu_p95": 87' "$T/r2/evidence/2026-11-02.cpu/data.json" && ok "restore with the key" || ko "restore"

# A machine that only has the backup: restore the key from it, then open the archive
export EVIDENCE_KEY="$T/key2"
"$EV" key-restore >/dev/null && cmp -s "$T/key" "$T/key2" && ok "key-restore gives the same key" || ko "key-restore"
[ "$(stat -c %a "$T/key2" 2>/dev/null || stat -f %Lp "$T/key2")" = 600 ] && ok "restored key is 600" || ko "key permissions"
"$EV" key-restore 2>/dev/null && ko "key-restore overwrote an existing key" || ok "key-restore refuses to overwrite"
"$EV" restore "$A" "$T/r3" >/dev/null && cmp -s "$T/r2/evidence/2026-11-02.cpu/data.json" "$T/r3/evidence/2026-11-02.cpu/data.json" \
  && ok "archive opens with the restored key" || ko "restore with restored key"
rm -f "$T/key2"
good="$(sha256sum "$T/key" 2>/dev/null || shasum -a 256 "$T/key")"; good="${good:0:12}"
echo "key_fingerprint=000000000000" >> "$CONF/evidence.conf"
"$EV" key-restore 2>/dev/null && ko "wrong fingerprint accepted" || { [ ! -e "$T/key2" ] && ok "wrong fingerprint: restore refused, no key kept" || ko "key kept"; }
echo "key_fingerprint=$good" >> "$CONF/evidence.conf"
"$EV" key-restore | grep -q "fingerprint matches" && ok "right fingerprint accepted" || ko "fingerprint"

# Compatibility: an archive built with the plain openssl pipeline (as the tool always did) opens, and vice versa
pw="$(sha256sum "$T/key" 2>/dev/null || shasum -a 256 "$T/key")"; pw="${pw:0:64}"
mkdir -p "$T/c/evidence/2026-11-03.x" && echo compat > "$T/c/evidence/2026-11-03.x/f.txt"
tar -C "$T/c" -cf - evidence | zstd -q -19 -T0 -c | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "pass:$pw" -out "$T/plain.enc"
"$EV" restore "$T/plain.enc" "$T/r4" >/dev/null && [ "$(cat "$T/r4/evidence/2026-11-03.x/f.txt")" = compat ] && ok "archive made with plain openssl opens" || ko "compat (openssl -> tool)"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass "pass:$pw" -in "$A" | zstd -dc | tar -tf - | grep -q 'data.json' \
  && ok "archive made by the tool opens with plain openssl" || ko "compat (tool -> openssl)"

# Clipboard: LAN server and secrets backend, with fake local clipboard tools
printf '#!/bin/sh\ncat "%s/clipboard"\n' "$T" > "$T/paste"; printf '#!/bin/sh\ncat > "%s/clipboard"\n' "$T" > "$T/copy"; chmod +x "$T/paste" "$T/copy"
export CLIP_PASTE_CMD="$T/paste" CLIP_COPY_CMD="$T/copy"
printf 'hello ñ €' > "$T/clipboard"
s='hello ñ €'; n=${#s}   # 9 in a UTF-8 locale, 12 (bytes) in the C locale: count like clip does
"$CLIP" push | grep -q "sent $n characters" && ok "clip push (server)" || ko "clip push"
printf 'x' > "$T/clipboard"
"$CLIP" pull | grep -q "$n characters" && [ "$(cat "$T/clipboard")" = 'hello ñ €' ] && ok "clip pull (server)" || ko "clip pull"
"$CLIP" pull >/dev/null 2>&1 && ko "second pull should find the slot empty" || ok "clip pull empties the slot"
printf 'remote text' > "$T/clipboard"
"$CLIP" --remote push | grep -q "sent 11 characters" && ok "clip --remote push (file backend)" || ko "remote push"
printf 'x' > "$T/clipboard"
"$CLIP" --remote pull | grep -q "11 characters" && [ "$(cat "$T/clipboard")" = 'remote text' ] && ok "clip --remote pull" || ko "remote pull"
"$CLIP" --remote pull >/dev/null 2>&1 && ko "second remote pull should be empty" || ok "clip --remote pull empties the secret"
echo "ALL TESTS PASSED"
