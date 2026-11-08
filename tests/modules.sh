#!/usr/bin/env bash
# Tests for the optional-module hooks of bin/link-harness, bin/doctor and conf_modules, in a throwaway HOME.
# Touches nothing real. Network is cut for the doctor's git fetch.
# Checks are strings evaluated by check(): single quotes and variables used only there are intended.
# shellcheck disable=SC2016,SC2034,SC2119,SC2120
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset IAH_MODULES IAH_REPO IAH_LANG IAH_METHOD IAH_EVIDENCE_CONF EVIDENCE_KEY EVIDENCE_CLIENT_CONF
export LINK_HARNESS_WINDOWS=0 GIT_SSH_COMMAND=false GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }

# --- conf_modules ----------------------------------------------------------------------
# shellcheck source-path=SCRIPTDIR source=../bin/lib/conf.sh
. "$ROOT/bin/lib/conf.sh"
R="$TMP/repo"; git init -q "$R"
check "conf_modules: none without .harness.conf"  '[ -z "$(conf_modules "$R")" ]'
printf 'language=en\nmodules=evidence,other-mod\n' > "$R/.harness.conf"
check "conf_modules: comma list, one per line"    '[ "$(conf_modules "$R" | tr "\n" " ")" = "evidence other-mod " ]'
check "conf_modules: IAH_MODULES overrides"       '[ "$(IAH_MODULES=x conf_modules "$R")" = x ]'
check "conf_modules: empty IAH_MODULES disables"  '[ -z "$(IAH_MODULES= conf_modules "$R")" ]'
rm "$R/.harness.conf"

# --- link-harness ----------------------------------------------------------------------
run_link() { (cd "$TMP" && "$ROOT/bin/link-harness" "$@" 2>&1); }
out="$(run_link)"
check "link-harness without modules: no cpush"          '[ ! -e "$HOME/.local/bin/cpush" ]'
check "link-harness without modules: no module output"  '! grep -qi "evidence\|cpush\|module" <<<"$out"'
out="$(IAH_MODULES=evidence run_link)"
check "link-harness + evidence: cpush linked to the module" '[ "$(readlink "$HOME/.local/bin/cpush")" = "$ROOT/modules/evidence/bin/clip" ]'
check "link-harness + evidence: cpull linked"           '[ "$(readlink "$HOME/.local/bin/cpull")" = "$ROOT/modules/evidence/bin/clip" ]'
out2="$(IAH_MODULES=evidence run_link)"
check "link-harness + evidence: second run is quiet about links" '! grep -q "linked .*cpush" <<<"$out2"'
out="$(IAH_MODULES=nope run_link)"
check "link-harness: unknown module warns"              'grep -q "unknown module .nope." <<<"$out"'
check "link-harness: unknown module is not fatal"       '(cd "$TMP" && IAH_MODULES=nope "$ROOT/bin/link-harness" --quiet >/dev/null 2>&1)'
out="$(IAH_MODULES='../x' run_link)"
check "link-harness: path-like module name warns"       'grep -q "unknown module" <<<"$out"'
printf 'modules=evidence\n' > "$R/.harness.conf"; rm -f "$HOME/.local/bin/cpush" "$HOME/.local/bin/cpull"
( cd "$R" && "$ROOT/bin/link-harness" --quiet >/dev/null 2>&1 )
check "link-harness: modules= in the repo's .harness.conf" '[ -L "$HOME/.local/bin/cpush" ]'
rm "$R/.harness.conf"
out="$(IAH_MODULES=two-machine run_link)"
check "link-harness + two-machine: known module, no warning" '! grep -q "unknown module" <<<"$out"'
check "link-harness + two-machine: role skill linked"        '[ -L "$HOME/.claude/skills/role" ]'

# --- doctor ----------------------------------------------------------------------------
doc() { (cd "$TMP" && "$ROOT/bin/doctor" 2>&1) || true; }
out="$(doc)"
check "doctor without modules: no evidence lines" '! grep -q "evidence:" <<<"$out"'
out="$(IAH_MODULES=evidence doc)"
check "doctor + evidence: key check present"      'grep -q "evidence: key missing" <<<"$out"'
check "doctor + evidence: backend check present"  'grep -q "evidence: secrets backend file" <<<"$out"'
check "doctor + evidence: cpush installed"        'grep -q "OK    evidence: cpush / cpull installed" <<<"$out"'
check "doctor + evidence: points to key-restore"  'grep -q "key-restore" <<<"$out"'
mkdir -p "$HOME/.config/infra-agent-harness"; head -c 64 /dev/urandom > "$TMP/key"; chmod 644 "$TMP/key"
out="$(IAH_MODULES=evidence EVIDENCE_KEY="$TMP/key" doc)"
check "doctor + evidence: key present, perms fixed" 'grep -q "evidence: key present" <<<"$out" && grep -q "permissions fixed to 600" <<<"$out"'
printf 'key_fingerprint=000000000000\n' > "$HOME/.config/infra-agent-harness/evidence.conf"
out="$(IAH_MODULES=evidence EVIDENCE_KEY="$TMP/key" doc)"
check "doctor + evidence: fingerprint mismatch fails" 'grep -q "FAIL  evidence: key fingerprint .* does NOT match" <<<"$out"'
out="$(IAH_MODULES=two-machine IAH_MACHINE=box doc)"
check "doctor + two-machine: machine name"        'grep -q "OK    two-machine: this machine is .box." <<<"$out"'
check "doctor + two-machine: role skill linked"   'grep -q "OK    two-machine: role skill linked" <<<"$out"'
check "doctor + two-machine: ssh and RO_REMOTE_BIN lines" 'grep -q "two-machine: ssh" <<<"$out" && grep -q "two-machine: RO_REMOTE_BIN" <<<"$out"'
check "doctor without evidence module: no evidence lines" '! grep -q "evidence:" <<<"$out"'
out="$(IAH_MODULES=nope doc)"
check "doctor: unknown module warns"              'grep -q "WARN  module .nope." <<<"$out"'
printf '' > "$HOME/.config/infra-agent-harness/evidence.conf"
check "doctor never prints key material"          '! grep -q "$(base64 -w0 "$TMP/key" 2>/dev/null | cut -c1-20)" <<<"$out"'

if [ "$fail" = 0 ]; then echo "modules: all tests passed"; else echo "modules: tests FAILED"; exit 1; fi
