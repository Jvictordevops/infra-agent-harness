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

# 4. Non-plugin mode (IAH_PLUGIN=0): skills are linked into ~/.claude/skills
first="$(basename "$(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d | head -1)")"
IAH_PLUGIN=0 run
[ -L "$TMP/.claude/skills/$first" ] || { echo "FAIL: manual mode did not link skills"; fail=1; }

# 5. Plugin mode (IAH_PLUGIN=1): own skill links removed, unrelated ones kept, hooksPath -> stable link
mkdir -p "$TMP/other-skill" "$TMP/work"; ln -s "$TMP/other-skill" "$TMP/.claude/skills/mine"
git init -q "$TMP/work"
export IAH_STABLE_LINK="$TMP/share/current"
(cd "$TMP/work" && IAH_PLUGIN=1 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet)
[ ! -e "$TMP/.claude/skills/$first" ] || { echo "FAIL: plugin mode kept the skill link"; fail=1; }
[ -L "$TMP/.claude/skills/mine" ] || { echo "FAIL: plugin mode removed an unrelated link"; fail=1; }
[ "$(git -C "$TMP/work" config core.hooksPath)" = "$IAH_STABLE_LINK/bin/hooks" ] || { echo "FAIL: hooksPath not set to the stable link"; fail=1; }
[ -L "$TMP/.copilot/skills/$first" ] || { echo "FAIL: plugin mode: no Copilot skill link"; fail=1; }
git -C "$TMP/work" config core.hooksPath /opt/custom/hooks
(cd "$TMP/work" && IAH_PLUGIN=1 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet 2>/dev/null)
[ "$(git -C "$TMP/work" config core.hooksPath)" = /opt/custom/hooks ] || { echo "FAIL: custom hooksPath overwritten"; fail=1; }
git -C "$TMP/work" config core.hooksPath "/home/x/.claude/plugins/cache/m/infra-agent-harness/0.1.0/bin/hooks"
(cd "$TMP/work" && IAH_PLUGIN=1 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet)
[ "$(git -C "$TMP/work" config core.hooksPath)" = "$IAH_STABLE_LINK/bin/hooks" ] || { echo "FAIL: plugin cache hooksPath not replaced"; fail=1; }

# 6. Plugin mode, fresh settings: deny/ask rules only, never hooks (the plugin registers the guards)
SL="$IAH_STABLE_LINK"; mkdir -p "$SL/skills"
prun() { (cd "$TMP/work" && IAH_PLUGIN=1 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" "$@" 2>&1); }
rm -f "$TMP/.claude/settings.json"
prun --quiet >/dev/null
check '.permissions.deny | index("Bash(kubectl * delete *)")' "plugin mode: deny rules installed"
check '.permissions.ask | index("Bash(git push --force*)")' "plugin mode: ask rules installed"
check '(.hooks // {}) | has("PreToolUse") | not' "plugin mode: hooks added to a fresh settings.json"

# 7. Plugin mode: stable-link guard entries removed (with backup), foreign ones kept with a message
ROG="$SL/hooks/ro-guard/ro-guard.sh"; BDP="$SL/hooks/block-destructive-platform/block-destructive-platform.sh"
FOREIGN="/home/x/other-harness/hooks/ro-guard/ro-guard.sh"
cat > "$S" <<EOF
{ "permissions": { "deny": ["Bash(kubectl delete *)"] },
  "hooks": { "PreToolUse": [
    { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$ROG" }, { "type": "command", "command": "$BDP" } ] },
    { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$FOREIGN" }, { "type": "command", "command": "/home/x/other-tool/hooks/block-git-write.sh" } ] } ],
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "/home/x/start.sh" } ] } ] },
  "model": "opus" }
EOF
cp "$S" "$TMP/settings.before"
b0="$(backups)"
out="$(prun --dry-run)"
cmp -s "$S" "$TMP/settings.before" || { echo "FAIL: plugin mode --dry-run changed settings.json"; fail=1; }
[ "$(backups)" = "$b0" ] || { echo "FAIL: plugin mode --dry-run made a backup"; fail=1; }
grep -qF "would: remove hook $ROG from settings.json (the plugin registers it)" <<<"$out" || { echo "FAIL: dry-run does not list the ro-guard removal"; fail=1; }
grep -qF "would: remove hook $BDP from settings.json (the plugin registers it)" <<<"$out" || { echo "FAIL: dry-run does not list the block-destructive removal"; fail=1; }
sleep 1
out="$(prun)"
grep -qF "kept hook $FOREIGN in settings.json (not this harness; the guard will run twice: the plugin also registers it)" <<<"$out" || { echo "FAIL: no message for the foreign guard entry"; fail=1; }
[ "$(backups)" = "$((b0 + 1))" ] || { echo "FAIL: removal made no backup"; fail=1; }
check "[.hooks.PreToolUse[].hooks[].command] | index(\"$ROG\") == null and index(\"$BDP\") == null" "stable-link guard entries not removed"
check "[.hooks.PreToolUse[].hooks[].command] | index(\"$FOREIGN\") != null" "foreign guard entry removed"
check '[.hooks.PreToolUse[].hooks[].command] | index("/home/x/other-tool/hooks/block-git-write.sh") != null' "other hook removed"
check '(.hooks.PreToolUse | length) == 1' "emptied PreToolUse group kept"
check '.hooks.SessionStart | length == 1' "SessionStart hook lost"
check '.model == "opus" and (.permissions.ask | index("Bash(git push --force*)"))' "other keys / ask rules lost"
before="$(cat "$S")"; sleep 1; prun --quiet >/dev/null
[ "$(cat "$S")" = "$before" ] || { echo "FAIL: plugin mode second run changed the file"; fail=1; }
# only our entries: the whole PreToolUse key disappears when it becomes empty
cat > "$S" <<EOF
{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$ROG" }, { "type": "command", "command": "$BDP" } ] } ] } }
EOF
prun --quiet >/dev/null
check '(.hooks // {}) | has("PreToolUse") | not' "empty PreToolUse key left behind"

# 8. Manual mode still adds the hooks
rm -f "$S"
(cd "$TMP/work" && IAH_PLUGIN=0 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet >/dev/null 2>&1)
check '[.hooks.PreToolUse[].hooks[].command] | length == 2' "manual mode: hooks not registered"

if [ "$fail" = 0 ]; then echo "link-harness settings: all tests passed"; else echo "link-harness settings: tests FAILED"; exit 1; fi
