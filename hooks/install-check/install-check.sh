#!/usr/bin/env bash
# install-check.sh — SessionStart (plugin, matcher "startup"). A plugin cannot ship permission rules, so the deny
# rules the harness needs (the Read(…) rules for credential files and the core and pack deny rules) get into
# ~/.claude/settings.json only when the user runs bin/link-harness. Without them the hooks are the only lock.
# This hook says so, once per session and in one line of context, when any of those deny rules is missing. It is
# silent when they are all there, when it does not run as a plugin, or when it cannot read the settings.
# Read only; never fails the session (always exit 0). The expected rules are the ones bin/doctor checks.
# Tests: tests/install-check.sh
set -uo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
{ [ -n "$ROOT" ] && [ -f "$ROOT/bin/lib/packs.sh" ]; } || exit 0
command -v jq >/dev/null 2>&1 || exit 0
SETTINGS="$HOME/.claude/settings.json"

# shellcheck source=bin/lib/packs.sh
. "$ROOT/bin/lib/packs.sh"
want="$(packs_permissions "$ROOT" 2>/dev/null | jq -c '.deny' 2>/dev/null)" || exit 0
[ -n "$want" ] || exit 0

have='[]'
if [ -f "$SETTINGS" ]; then
  # A settings.json that is not valid JSON is Claude Code's to report, not ours
  have="$(jq -c '.permissions.deny // []' "$SETTINGS" 2>/dev/null)" || exit 0
fi
missing="$(jq -n --argjson w "$want" --argjson h "$have" '($w - $h) | length' 2>/dev/null)" || exit 0

if [ "$missing" -gt 0 ] 2>/dev/null; then
  echo "infra-agent-harness: $missing deny rule(s) it needs (credential files, destructive commands) are missing from ~/.claude/settings.json, so only its hooks guard them. The user fixes it by running, once, in a terminal from their work repo: ~/.local/share/infra-agent-harness/current/bin/link-harness"
fi
exit 0
