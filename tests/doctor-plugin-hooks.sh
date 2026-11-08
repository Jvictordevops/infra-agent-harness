#!/usr/bin/env bash
# Tests for the guard-hook checks of bin/doctor in plugin mode (the plugin's hooks/hooks.json registers the
# guards). Throwaway HOME and harness copy; touches nothing real.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ko() { echo "FAIL: $1"; fail=1; }
export GIT_CONFIG_NOSYSTEM=1 IAH_NO_FETCH=1 IAH_PLUGIN=1 IAH_STABLE_LINK="$TMP/share/current" IAH_HOOK_LOG="$TMP/hook.log"
unset IAH_REPO IAH_MODULES

H="$TMP/home"; mkdir -p "$H/.claude"
doc() { (cd "$TMP" && HOME="$H" "$1/bin/doctor" 2>&1); }   # $1 = harness root

# 1. Plugin registers both guards, settings.json has none: OK, no warning about them
out="$(doc "$ROOT")"
for g in ro-guard block-destructive-platform; do
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

# 4. Manual mode unchanged: guards must be in settings.json
out="$(cd "$TMP" && IAH_PLUGIN=0 HOME="$H" "$ROOT/bin/doctor" 2>&1)"
grep -q "^FAIL  hook ro-guard.sh not registered in ~/.claude/settings.json" <<<"$out" || ko "manual mode: no FAIL without settings hooks"

if [ "$fail" = 0 ]; then echo "doctor plugin hooks: all tests passed"; else echo "doctor plugin hooks: tests FAILED"; exit 1; fi
