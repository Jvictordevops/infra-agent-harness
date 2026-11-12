#!/usr/bin/env bash
# Tests for hooks/install-check: the SessionStart hook that says, once and in one line, when the deny rules the
# harness needs are not in ~/.claude/settings.json (a plugin cannot ship them; bin/link-harness merges them).
# Throwaway HOME and settings.json; runs nothing real and never touches the machine's settings.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: macOS temp dirs sit behind the /var -> /private/var link
trap 'rm -rf "$TMP"' EXIT
HOOK="$ROOT/hooks/install-check/install-check.sh"
fail=0
ko() { echo "FAIL: $1"; fail=1; }

# shellcheck source=bin/lib/packs.sh
. "$ROOT/bin/lib/packs.sh"
ALL="$(packs_permissions "$ROOT")" || { echo "FAIL: cannot compute the expected rules"; exit 1; }
DENY="$(jq -c '.deny' <<<"$ALL")"
N="$(jq 'length' <<<"$DENY")"
NREAD="$(jq '[.[] | select(startswith("Read("))] | length' <<<"$DENY")"
if [ "$N" -le 0 ] || [ "$NREAD" -le 0 ] || [ "$NREAD" -ge "$N" ]; then ko "the expected rules look wrong (deny $N, Read $NREAD)"; fi
ASK="$(jq -c '.ask' <<<"$ALL")"
[ "$(jq 'length' <<<"$ASK")" -gt 0 ] || ko "the core and packs have no ask rules to test with"

H="$TMP/home"
settings() { # $1 JSON text, or nothing: a fresh HOME with that ~/.claude/settings.json
  rm -rf "$H"; mkdir -p "$H/.claude"
  [ $# -eq 0 ] || printf '%s' "$1" > "$H/.claude/settings.json"
}
run() { # prints the hook's stdout; $RC is its exit code. CLAUDE_PLUGIN_ROOT defaults to the repo
  OUT="$(HOME="$H" CLAUDE_PLUGIN_ROOT="${PLUG-$ROOT}" "$HOOK" 2>"$TMP/err")"; RC=$?
}
with_deny() { jq -nc --argjson d "$1" '{permissions: {deny: $d}}'; }
lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }
silent() { # $1 label: no output, exit 0
  [ "$RC" = 0 ] || ko "$1: exit $RC"
  [ -z "$OUT" ] || ko "$1: should be silent, said: $OUT"
}
says() { # $1 label, $2 how many rules: one line, exit 0, the count, the fix
  [ "$RC" = 0 ] || ko "$1: exit $RC"
  [ "$(lines "$OUT")" = 1 ] || ko "$1: should be one line, got: $OUT"
  case "$OUT" in *"$2 deny rule(s)"*) ;; *) ko "$1: should name $2 rule(s): $OUT" ;; esac
  case "$OUT" in *"~/.local/share/infra-agent-harness/current/bin/link-harness"*) ;; *) ko "$1: does not give the command: $OUT" ;; esac
}

# 1. No settings.json at all: every rule is missing
settings; run; says "no settings.json" "$N"
# 2. The two cases of the brief: all the rules there -> silent
settings "$(with_deny "$DENY")"; run; silent "all rules present"
# 3. Other keys, other rules, and no ask rules: still silent (the floor is deny; doctor reports asks)
settings "$(jq -nc --argjson d "$DENY" '{model: "x", permissions: {deny: (["Bash(rm -rf /)"] + $d), allow: ["Bash(ls)"]}, hooks: {}}')"; run; silent "all rules plus others, no asks"
# 4. One rule missing, any one
settings "$(with_deny "$(jq -c '.[1:]' <<<"$DENY")")"; run; says "first rule missing" 1
settings "$(with_deny "$(jq -c '.[:-1]' <<<"$DENY")")"; run; says "last rule missing" 1
# 5. Only a Read(…) rule missing, and then all of them
R1="$(jq -r '[.[] | select(startswith("Read("))][0]' <<<"$DENY")"
settings "$(with_deny "$(jq -c --arg r "$R1" '. - [$r]' <<<"$DENY")")"; run; says "one Read rule missing" 1
settings "$(with_deny "$(jq -c '[.[] | select(startswith("Read(") | not)]' <<<"$DENY")")"; run; says "all Read rules missing" "$NREAD"
# 6. Nothing in permissions.deny, however it is written
settings '{}'; run; says "empty settings" "$N"
settings '{"permissions": {}}'; run; says "no deny key" "$N"
settings "$(jq -nc --argjson a "$ASK" '{permissions: {ask: $a}}')"; run; says "asks but no deny" "$N"
# 7. Things it must not complain about: invalid JSON (Claude Code reports it), no plugin, a root without the harness
settings 'not json {'; run; silent "invalid settings.json"
settings; PLUG="" run; silent "not running as a plugin"
settings; PLUG="$TMP/nowhere" run; silent "plugin root without the harness"
# 8. Read only: the hook writes nothing in HOME
settings; before="$(cd "$H" && find . | sort)"; run; after="$(cd "$H" && find . | sort)"
[ "$before" = "$after" ] || ko "the hook changed HOME: $after"
# 9. Without jq it stays silent and exits 0 (the guards are the ones that block without jq)
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"; ln -s "$(command -v bash)" "$NOJQ/bash"
settings; OUT="$(HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" PATH="$NOJQ" "$HOOK" 2>&1)"; RC=$?; silent "no jq"

# 10. Registered in hooks.json: SessionStart, only on startup (once per session), next to stable-link
HJ="$ROOT/hooks/hooks.json"
CMD="\"\${CLAUDE_PLUGIN_ROOT}/hooks/install-check/install-check.sh\""
jq -e --arg c "$CMD" '[.hooks.SessionStart[] | select(.matcher == "startup") | .hooks[].command] | index($c) != null' "$HJ" >/dev/null \
  || ko "hooks.json: SessionStart with matcher startup does not run install-check"
jq -e --arg c "$CMD" '[.hooks.SessionStart[] | select(.matcher != "startup") | .hooks[].command] | index($c) == null' "$HJ" >/dev/null \
  || ko "hooks.json: install-check also runs on other SessionStart sources (it would repeat after /clear and compaction)"
jq -e '[.hooks.SessionStart[].hooks[].command | select(endswith("stable-link.sh\""))] | length == 1' "$HJ" >/dev/null \
  || ko "hooks.json: stable-link is no longer registered once"
[ -x "$HOOK" ] || ko "install-check.sh is not executable"

if [ "$fail" = 0 ]; then echo "install-check: all tests passed"; else echo "install-check: tests FAILED"; exit 1; fi
