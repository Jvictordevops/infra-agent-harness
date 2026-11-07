#!/usr/bin/env bash
# Tests for the settings merge of bin/link-harness, in a throwaway HOME. Touches nothing real.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
S="$TMP/.claude/settings.json"
fail=0
check() { if jq -e "$1" "$S" >/dev/null; then :; else echo "FAIL: $2"; fail=1; fi; }
run() { HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet; }
backups() { find "$TMP/.claude" -name 'settings.json.bak-*' | wc -l | tr -d ' '; }

# 1. No settings yet
run
check '.permissions.deny | index("Bash(kubectl * delete *)")' "deny rules installed"
check '.permissions.ask | index("Bash(git push --force*)")' "ask rules installed"
check '[.hooks.PreToolUse[].hooks[].command] | length == 2' "two hooks registered"
check "[.hooks.PreToolUse[].hooks[].command] | all(startswith(\"$ROOT/hooks/\"))" "hook paths point to the repo"

# 2. Existing settings: keep everything, no duplicates
cat > "$S" <<EOF
{ "permissions": { "additionalDirectories": ["~/code"], "deny": ["Bash(kubectl delete *)", "Read(./.env)"] },
  "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
    { "type": "command", "command": "/home/x/other-tool/hooks/block-git-write.sh" },
    { "type": "command", "command": "/home/x/infra-agent-harness/hooks/block-destructive-platform/block-destructive-platform.sh" } ] } ] },
  "model": "opus" }
EOF
sleep 1; run
check '.permissions.additionalDirectories == ["~/code"]' "additionalDirectories kept"
check '.model == "opus"' "other keys kept"
check '.permissions.deny | index("Read(./.env)")' "own deny rule kept"
check '[.permissions.deny[] | select(. == "Bash(kubectl delete *)")] | length == 1' "no duplicate deny rule"
check '[.hooks.PreToolUse[].hooks[].command | select(endswith("block-destructive-platform.sh"))] | length == 1' "block-destructive not duplicated"
check '[.hooks.PreToolUse[].hooks[].command | select(endswith("ro-guard.sh"))] | length == 1' "ro-guard added"
check '[.hooks.PreToolUse[].hooks[].command | select(endswith("block-git-write.sh"))] | length == 1' "other hook kept"
[ "$(backups)" = 1 ] || { echo "FAIL: one backup expected, got $(backups)"; fail=1; }

# 3. Idempotent
before="$(cat "$S")"; sleep 1; run
[ "$(cat "$S")" = "$before" ] || { echo "FAIL: second run changed the file"; fail=1; }
[ "$(backups)" = 1 ] || { echo "FAIL: second run made a backup"; fail=1; }

if [ "$fail" = 0 ]; then echo "link-harness settings: all tests passed"; else echo "link-harness settings: tests FAILED"; exit 1; fi
