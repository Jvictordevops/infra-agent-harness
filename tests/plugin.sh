#!/usr/bin/env bash
# Tests for the Claude Code plugin packaging: manifests, hooks.json and hooks/stable-link. Throwaway HOME.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: macOS temp dirs sit behind the /var -> /private/var link
trap 'rm -rf "$TMP"' EXIT
fail=0
ko() { echo "FAIL: $1"; fail=1; }
P="$ROOT/.claude-plugin/plugin.json"; M="$ROOT/.claude-plugin/marketplace.json"; H="$ROOT/hooks/hooks.json"

# 1. Manifests
for f in "$P" "$M" "$H"; do jq -e . "$f" >/dev/null 2>&1 || ko "$f is not valid JSON"; done
pn="$(jq -r .name "$P")"
[ "$pn" = infra-agent-harness ] || ko "plugin name is '$pn'"
jq -e '.name | test("^[a-z0-9]+(-[a-z0-9]+)*$") and (startswith("claude-") or startswith("anthropic-") | not)' "$P" >/dev/null || ko "plugin name not kebab-case / reserved prefix"
jq -e '.version | type == "string" and length > 0' "$P" >/dev/null || ko "plugin version missing"
jq -e '.homepage | startswith("https://")' "$P" >/dev/null || ko "homepage is not a URL"
[ "$(jq -r .name "$M")" = "$pn" ] || ko "marketplace name != plugin name"
jq -e '.owner.name | length > 0' "$M" >/dev/null || ko "marketplace owner missing"
[ "$(jq -r '.plugins | length' "$M")" = 1 ] || ko "marketplace must list one plugin"
[ "$(jq -r '.plugins[0].name' "$M")" = "$pn" ] || ko "marketplace entry name != plugin name"
[ "$(jq -r '.plugins[0].source' "$M")" = "./" ] || ko "marketplace source is not ./"

# 2. Every path in hooks.json exists and is executable
n=0
while IFS= read -r cmd; do
  n=$((n + 1))
  path="$(printf '%s' "$cmd" | tr -d '"')"; path="${path//\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT}"
  [ -x "$path" ] || ko "hooks.json: '$cmd' -> $path missing or not executable"
done < <(jq -r '.hooks[][].hooks[].command' "$H")
[ "$n" -gt 0 ] || ko "hooks.json has no commands"

# 2b. PreToolUse/Bash registers both guards through ${CLAUDE_PLUGIN_ROOT}, and they work run from the plugin root
for g in ro-guard block-destructive-platform; do
  jq -e --arg c "\"\${CLAUDE_PLUGIN_ROOT}/hooks/$g/$g.sh\"" \
    '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[].command] | index($c) != null' "$H" >/dev/null \
    || ko "hooks.json: PreToolUse/Bash lacks the $g guard"
  [ -x "$ROOT/hooks/$g/$g.sh" ] || ko "$g.sh missing or not executable"
done
jq -e '[.hooks.PreToolUse[]? | select(.matcher == "Bash|Read|Grep") | .hooks[].command] | index("\"${CLAUDE_PLUGIN_ROOT}/hooks/credential-guard/credential-guard.sh\"") != null' "$H" >/dev/null \
  || ko "hooks.json: PreToolUse/Bash|Read|Grep lacks the credential-guard"
[ -x "$ROOT/hooks/credential-guard/credential-guard.sh" ] || ko "credential-guard.sh missing or not executable"
jq -e '.hooks.SessionStart | length > 0' "$H" >/dev/null || ko "hooks.json: SessionStart hook lost"
feed() { jq -n --arg c "$2" '{tool_input:{command:$c}}' | env CLAUDE_PLUGIN_ROOT="$ROOT" IAH_HOOK_LOG="$TMP/hook.log" RO_MODE_FILE="$TMP/ro-mode" HOME="$TMP/hhome" "$ROOT/hooks/$1/$1.sh"; }
mkdir -p "$TMP/hhome"; echo "test" > "$TMP/ro-mode"
feed ro-guard "kubectl get pods" >/dev/null 2>&1; [ "$?" = 2 ] || ko "ro-guard (plugin root) did not block kubectl in read-only mode"
feed ro-guard "ls -l" >/dev/null 2>&1 || ko "ro-guard (plugin root) blocked a harmless command"
out="$(feed block-destructive-platform "kubectl delete pod x" 2>&1 || true)"
case "$out" in *'"block"'*) ;; *) ko "block-destructive-platform (plugin root) did not block a destructive command" ;; esac
out="$(feed block-destructive-platform "kubectl get pods" 2>&1 || true)"
[ -z "$out" ] || ko "block-destructive-platform (plugin root) blocked a harmless command"
feed credential-guard "cat ~/.netrc" >/dev/null 2>&1; [ "$?" = 2 ] || ko "credential-guard (plugin root) did not block reading ~/.netrc"
feed credential-guard "ssh -i ~/.ssh/id_ed25519 host uptime" >/dev/null 2>&1 || ko "credential-guard (plugin root) blocked using a key"
[ -s "$TMP/hook.log" ] || ko "guards (plugin root) wrote no decision log"

# 3. stable-link
SL="$ROOT/hooks/stable-link/stable-link.sh"
mkdir -p "$TMP/rootA/bin/hooks" "$TMP/rootB/bin/hooks" "$TMP/nohooks/bin"
export IAH_STABLE_LINK="$TMP/share/current"
out="$(CLAUDE_PLUGIN_ROOT="$TMP/rootA" "$SL" 2>&1)"; rc=$?
if [ "$rc" != 0 ] || [ -n "$out" ]; then ko "stable-link: first run rc=$rc out='$out'"; fi
[ "$(readlink "$IAH_STABLE_LINK")" = "$TMP/rootA" ] || ko "stable-link: not created"
CLAUDE_PLUGIN_ROOT="$TMP/rootB" "$SL" || ko "stable-link: second run failed"
[ "$(readlink "$IAH_STABLE_LINK")" = "$TMP/rootB" ] || ko "stable-link: not replaced"
compgen -G "$TMP/share/*tmp*" >/dev/null && ko "stable-link: temp link left behind"
(unset CLAUDE_PLUGIN_ROOT; "$SL") || ko "stable-link: fails without CLAUDE_PLUGIN_ROOT"
CLAUDE_PLUGIN_ROOT="$TMP/nope" "$SL" || ko "stable-link: fails with a missing dir"
CLAUDE_PLUGIN_ROOT="$TMP/nohooks" "$SL" || ko "stable-link: fails with a dir without bin/hooks"
[ "$(readlink "$IAH_STABLE_LINK")" = "$TMP/rootB" ] || ko "stable-link: changed by a bad run"
mkdir -p "$TMP/real"; IAH_STABLE_LINK="$TMP/real" CLAUDE_PLUGIN_ROOT="$TMP/rootA" "$SL" 2>/dev/null || ko "stable-link: fails over a real directory"
[ ! -L "$TMP/real" ] || ko "stable-link: replaced a real directory"
(unset IAH_STABLE_LINK; HOME="$TMP/h" CLAUDE_PLUGIN_ROOT="$TMP/rootA" "$SL")
[ "$(readlink "$TMP/h/.local/share/infra-agent-harness/current")" = "$TMP/rootA" ] || ko "stable-link: default path not used"

if [ "$fail" = 0 ]; then echo "plugin: all tests passed"; else echo "plugin: tests FAILED"; exit 1; fi
