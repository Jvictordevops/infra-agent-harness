#!/usr/bin/env bash
# Tests for the guard-hook checks of bin/doctor in plugin mode (the plugin's hooks/hooks.json registers the
# guards), and for its check of the ask rules against the security profile. Throwaway HOME and harness copy;
# touches nothing real.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: macOS temp dirs sit behind the /var -> /private/var link
trap 'rm -rf "$TMP"' EXIT
fail=0
ko() { echo "FAIL: $1"; fail=1; }
export GIT_CONFIG_NOSYSTEM=1 IAH_NO_FETCH=1 IAH_PLUGIN=1 IAH_STABLE_LINK="$TMP/share/current" IAH_HOOK_LOG="$TMP/hook.log"
unset IAH_REPO IAH_MODULES

H="$TMP/home"; mkdir -p "$H/.claude"
doc() { (cd "$TMP" && HOME="$H" "$1/bin/doctor" 2>&1); }   # $1 = harness root

# 1. Plugin registers both guards, settings.json has none: OK, no warning about them
out="$(doc "$ROOT")"
for g in ro-guard block-destructive-platform credential-guard; do
  grep -q "^OK    hook $g registered by the plugin\$" <<<"$out" || ko "no OK line for $g"
  ! grep -q "hook $g also in settings.json" <<<"$out" || ko "unexpected duplicate warning for $g"
  ! grep -q "^FAIL  hook $g" <<<"$out" || ko "unexpected FAIL for $g"
done

# 2. A foreign entry in settings.json: WARN (runs twice)
FOREIGN="/home/x/other-harness/hooks/ro-guard/ro-guard.sh"
printf '{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "%s" } ] } ] } }\n' "$FOREIGN" > "$H/.claude/settings.json"
out="$(doc "$ROOT")"
grep -qF "WARN  hook ro-guard also in settings.json ($FOREIGN): runs twice" <<<"$out" || ko "no duplicate WARN for the foreign entry"
grep -q "^OK    hook ro-guard registered by the plugin\$" <<<"$out" || ko "ro-guard no longer OK with a duplicate"
! grep -q "hook block-destructive-platform also in settings.json" <<<"$out" || ko "warned about a guard that is not duplicated"
before="$(cat "$H/.claude/settings.json")"; doc "$ROOT" >/dev/null
[ "$(cat "$H/.claude/settings.json")" = "$before" ] || ko "doctor changed settings.json"

# 3. The plugin's hooks.json lacks a guard and settings.json has none: FAIL
rm -f "$H/.claude/settings.json"
C="$TMP/copy"; mkdir -p "$C"; (cd "$ROOT" && tar -c --exclude=.git .) | tar -x -C "$C"
jq 'del(.hooks.PreToolUse)' "$ROOT/hooks/hooks.json" > "$C/hooks/hooks.json"
out="$(doc "$C")"
grep -q "^FAIL  hook ro-guard registered nowhere" <<<"$out" || ko "no FAIL for ro-guard missing from hooks.json"
grep -q "^FAIL  hook block-destructive-platform registered nowhere" <<<"$out" || ko "no FAIL for block-destructive-platform missing from hooks.json"
grep -q "^FAIL  hook credential-guard registered nowhere" <<<"$out" || ko "no FAIL for credential-guard missing from hooks.json"

# 4. Manual mode unchanged: guards must be in settings.json
out="$(cd "$TMP" && IAH_PLUGIN=0 HOME="$H" "$ROOT/bin/doctor" 2>&1)"
# The tests of the guards run only with --tests (they take minutes on WSL)
case "$out" in *"tests/ro.sh green"*) echo "FAIL: doctor ran the guard tests without --tests"; fail=1 ;; esac
case "$out" in *"not run (doctor --tests runs them)"*) ;; *) echo "FAIL: doctor does not say the guard tests were not run"; fail=1 ;; esac
tout="$(cd "$TMP" && IAH_PLUGIN=0 HOME="$H" IAH_NO_FETCH=1 "$ROOT/bin/doctor" --tests 2>&1)"
for t in tests/fail-closed.sh tests/floor.sh tests/ro.sh packs/aws/tests.sh; do
  case "$tout" in *"OK    $t green"*) ;; *) echo "FAIL: doctor --tests does not report $t green"; fail=1 ;; esac
done
(cd "$TMP" && HOME="$H" "$ROOT/bin/doctor" --bogus >/dev/null 2>&1); [ $? = 2 ] || { echo "FAIL: doctor --bogus should end with 2"; fail=1; }
grep -q "^FAIL  hook ro-guard.sh not registered in ~/.claude/settings.json" <<<"$out" || ko "manual mode: no FAIL without settings hooks"

# 5. Security profile: with permissive, ask rules of the packs left in settings.json are a WARN and are not
#    counted as missing; the core asks still count
mkdir -p "$H/.config/infra-agent-harness"; printf 'profile=permissive\n' > "$H/.config/infra-agent-harness/profile"
printf '{ "permissions": { "ask": ["Bash(kubectl apply *)", "Bash(helm upgrade *)"] } }\n' > "$H/.claude/settings.json"
out="$(doc "$ROOT")"
grep -qF "WARN  2 ask rule(s) of the packs still in settings.json; security profile permissive removes them (bin/link-harness)" <<<"$out" || ko "permissive: no WARN for the ask rules of the packs"
miss="$(sed -n 's/^WARN  \([0-9]*\) deny\/ask rule(s) of the core and packs.*missing.*/\1/p' <<<"$out")"
full="$(cd "$TMP" && HOME="$H" bash -c '. "$1/bin/lib/packs.sh"; packs_permissions "$1"' _ "$ROOT" | jq '(.deny + .ask) | length')"
core_ask="$(jq '.permissions.ask | length' "$ROOT/hooks/settings.base.json")"
pack_ask="$(cd "$TMP" && HOME="$H" bash -c '. "$1/bin/lib/packs.sh"; packs_profile_permissions "$1" permissive' _ "$ROOT" | jq '.drop | length')"
if [ -z "$miss" ] || [ "$miss" != "$((full - pack_ask))" ] || [ "$core_ask" = 0 ]; then
  ko "permissive: missing count $miss, expected $((full - pack_ask)) (the pack asks are not missing)"
fi
printf 'profile=standard\n' > "$H/.config/infra-agent-harness/profile"
out="$(doc "$ROOT")"
! grep -q "ask rule(s) of the packs still in settings.json" <<<"$out" || ko "standard: WARN about the ask rules of the packs"
rm -rf "$H/.config/infra-agent-harness" "$H/.claude/settings.json"

# 6. Sandbox of strict: WARN while settings.json lacks it, OK after link-harness, FAIL without its Linux tools;
#    under standard, the sandbox of strict left on is a WARN
mkdir -p "$H/.config/infra-agent-harness"; printf 'profile=strict\n' > "$H/.config/infra-agent-harness/profile"
printf '{}\n' > "$H/.claude/settings.json"
out="$(IAH_SANDBOX_TOOLS="sh" doc "$ROOT")"
grep -qF "WARN  sandbox of the strict profile: off" <<<"$out" || ko "strict: no WARN with the sandbox off"
(cd "$TMP" && IAH_PLUGIN=0 HOME="$H" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet >/dev/null 2>&1)
out="$(IAH_SANDBOX_TOOLS="sh" doc "$ROOT")"
grep -qF "OK    sandbox of the strict profile on in settings.json" <<<"$out" || ko "strict: no OK after link-harness"
jq '.sandbox.credentials.files |= .[1:]' "$H/.claude/settings.json" > "$TMP/s.json" && mv "$TMP/s.json" "$H/.claude/settings.json"
out="$(IAH_SANDBOX_TOOLS="sh" doc "$ROOT")"
grep -qF "WARN  sandbox of the strict profile: 1 credential file(s) missing" <<<"$out" || ko "strict: no WARN for a credential file missing from the sandbox"
jq 'del(.sandbox.network.strictAllowlist)' "$H/.claude/settings.json" > "$TMP/s.json" && mv "$TMP/s.json" "$H/.claude/settings.json"
out="$(IAH_SANDBOX_TOOLS="sh" doc "$ROOT")"
grep -qF "WARN  sandbox of the strict profile: domains not listed are not refused (strictAllowlist), 1 credential file(s) missing" <<<"$out" || ko "strict: no WARN without strictAllowlist"
if [ "$(uname -s)" = Linux ]; then
  out="$(IAH_SANDBOX_TOOLS="sh no-such-tool-iah" doc "$ROOT")"
  grep -qF "FAIL  strict needs 'no-such-tool-iah' for the sandbox" <<<"$out" || ko "strict: no FAIL without a sandbox tool"
fi
printf 'profile=standard\n' > "$H/.config/infra-agent-harness/profile"
out="$(doc "$ROOT")"
grep -qF "WARN  the sandbox of strict is still on in settings.json; security profile standard turns it off" <<<"$out" || ko "standard: no WARN with the sandbox of strict left on"
! grep -q "sandbox of the strict profile" <<<"$out" || ko "standard: strict sandbox checks shown"
rm -rf "$H/.config/infra-agent-harness" "$H/.claude/settings.json"

if [ "$fail" = 0 ]; then echo "doctor plugin hooks: all tests passed"; else echo "doctor plugin hooks: tests FAILED"; exit 1; fi
