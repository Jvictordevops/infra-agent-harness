#!/usr/bin/env bash
# Tests for the rule packs (packs/README.md): every pack is well formed, a pack is loaded just by being under
# packs/ (a made-up pack 'demo' in a copy of the harness reaches bin/ro, both guards and the deny/ask rules), and
# the helpers of tests/lib/pack-test.sh fail when they must.
# Runs nothing real: bin/ro --check and the hooks fed with commands.
# shellcheck disable=SC2015,SC2016  # "check && check || ko": ko only reports; helper_fails gets code in single quotes
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tests/lib/portable.sh
. "$ROOT/tests/lib/portable.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
IAH_HOOK_LOG="$TMP/hook-decisions.jsonl"; export IAH_HOOK_LOG   # keep test blocks out of the real decision log
fail=0
ko() { echo "FAIL: $*"; fail=1; }

# 1. Every pack is well formed
n=0
for d in "$ROOT"/packs/*/; do
  d="${d%/}"; p="${d##*/}"; n=$((n + 1))
  [[ "$p" =~ ^[a-z0-9-]+$ ]] || ko "$p: pack name must be [a-z0-9-]"
  for f in "$d"/*; do
    case "${f##*/}" in ro.sh|guard-tools|destructive.rules|permissions.json|tests.sh|domains|README.md) ;;
      *) ko "$p: unknown file ${f##*/} (packs/README.md)" ;; esac
  done
  if [ -f "$d/permissions.json" ]; then
    jq -e 'type == "object" and (keys - ["deny", "ask"] | length == 0)
           and ([.deny // [], .ask // []] | all(type == "array" and all(type == "string" and startswith("Bash("))))' \
      "$d/permissions.json" >/dev/null || ko "$p: permissions.json must be {\"deny\": [\"Bash(…)\"], \"ask\": […]}"
  fi
  if [ -f "$d/guard-tools" ]; then
    while IFS= read -r t || [ -n "$t" ]; do
      case "$t" in ''|'#'*) continue ;; esac
      [[ "$t" =~ ^[a-z0-9_-]+$ ]] || ko "$p: guard-tools: bad name '$t'"
    done < "$d/guard-tools"
  fi
  if [ -f "$d/destructive.rules" ]; then
    while IFS= read -r r || [ -n "$r" ]; do
      case "$r" in ''|'#'*) continue ;; esac
      [[ "${r%%|*}" =~ ^[a-z0-9-]+$ ]] && [ "${r#*|}" != "$r" ] || ko "$p: destructive.rules: not 'name|regex': $r"
      grep -E -- "${r#*|}" </dev/null >/dev/null 2>&1; [ $? -le 1 ] || ko "$p: destructive.rules: bad regex: $r"
    done < "$d/destructive.rules"
  fi
done
[ "$n" -ge 4 ] || ko "expected the aws, helm, kubernetes and terraform packs, found $n"

# 2. A new pack is loaded just by being there: copy of the harness + made-up pack 'demo'
H="$TMP/harness"
mkdir -p "$H"
cp -R "$ROOT/bin" "$ROOT/hooks" "$ROOT/packs" "$H/"
mkdir "$H/packs/demo"
cat > "$H/packs/demo/ro.sh" <<'EOF'
# shellcheck shell=bash
ro_tool demo
check_demo() { [ "${1-}" = list ] || deny "demo: only list"; }
EOF
printf '# demo\ndemo\n' > "$H/packs/demo/guard-tools"
printf '# demo\ndemo-nuke|<P>demo<G><S>nuke<E>\n' > "$H/packs/demo/destructive.rules"
printf '{"deny": ["Bash(demo nuke *)"], "ask": ["Bash(demo apply *)"]}\n' > "$H/packs/demo/permissions.json"

"$H/bin/ro" --check demo list >/dev/null 2>&1 || ko "ro: the demo pack's tool is not allowed"
"$H/bin/ro" --check demo nuke >/dev/null 2>&1 && ko "ro: the demo pack's check does not run"
"$ROOT/bin/ro" --check demo list >/dev/null 2>&1 && ko "ro: 'demo' allowed without its pack"
out="$("$H/bin/ro" --check nope x 2>&1)"
grep_q -F "(aws, demo, helm, kubectl, git, gh," <<<"$out" || ko "ro: unknown-tool message does not list the pack tools: $out"

decide() { jq -n --arg c "$2" '{tool_input:{command:$c}}' | "$1"; }
case "$(decide "$H/hooks/block-destructive-platform/block-destructive-platform.sh" "demo -x 1 nuke")" in
  *'"block"'*) ;; *) ko "block-destructive: the demo rule does not block" ;; esac
[ -z "$(decide "$H/hooks/block-destructive-platform/block-destructive-platform.sh" "demo list")" ] || ko "block-destructive: 'demo list' blocked"
grep_q -F '"reason":"demo-nuke"' < "$IAH_HOOK_LOG" || ko "block-destructive: rule name demo-nuke not logged"

touch "$TMP/ro-mode"
RO_MODE_FILE="$TMP/ro-mode" decide "$H/hooks/ro-guard/ro-guard.sh" "demo list" 2>/dev/null; [ $? = 2 ] || ko "ro-guard: 'demo' not blocked outside bin/ro"
RO_MODE_FILE="$TMP/ro-mode" decide "$H/hooks/ro-guard/ro-guard.sh" "az vm list" 2>/dev/null; [ $? = 2 ] || ko "ro-guard: core tool 'az' not blocked"
RO_MODE_FILE="$TMP/ro-mode" decide "$H/hooks/ro-guard/ro-guard.sh" "ls -la" 2>/dev/null || ko "ro-guard: 'ls' blocked"

# shellcheck source=bin/lib/packs.sh
. "$ROOT/bin/lib/packs.sh"
perms="$(packs_permissions "$H")"
jq -e '(.deny | index("Bash(demo nuke *)")) and (.ask | index("Bash(demo apply *)")) and (.ask[0] | startswith("Bash(git "))' <<<"$perms" >/dev/null \
  || ko "packs_permissions: demo rules missing or core not first: $perms"
[ "$(packs_names "$H" | paste -sd, -)" = "aws,demo,helm,kubernetes,terraform" ] || ko "packs_names: $(packs_names "$H" | paste -sd, -)"

# 3. A pack cannot take over a core tool, and a tool needs its check
printf 'ro_tool git\n' > "$H/packs/demo/ro.sh"
out="$("$H/bin/ro" --check git -C "$TMP" status 2>&1)"; rc=$?
[ "$rc" = 2 ] && grep_q -F "registered twice" <<<"$out" || ko "ro: a pack registering 'git' was not refused (rc $rc): $out"
printf 'ro_tool demo\n' > "$H/packs/demo/ro.sh"
out="$("$H/bin/ro" --check demo list 2>&1)"; rc=$?
[ "$rc" = 2 ] && grep_q -F "defines no check_demo" <<<"$out" || ko "ro: a tool without check_ was not refused (rc $rc): $out"

# 4. The helpers of tests/lib/pack-test.sh fail when they must (or every pack test could pass by mistake)
helper_fails() { # $@ = one helper call, with a wrong expectation
  printf 'ROOT=%q\n. "$ROOT/tests/lib/pack-test.sh"\n%s\npack_done x\n' "$ROOT" "$*" > "$TMP/helper.sh"
  if bash "$TMP/helper.sh" >/dev/null 2>&1; then ko "pack-test helper does not fail: $*"; fi
}
helper_fails 'ro_ok nope x'
helper_fails 'ro_no git -C "$_PT_TMP" status'
helper_fails 'blk "ls -la"'
helper_fails 'alw "kubectl delete pod x"'
helper_fails 'denied "ls -la"'
helper_fails 'asked "ls -la"'
helper_fails 'unruled "kubectl delete pod x"'
helper_fails 'guarded "ls -la"'

[ "$fail" = 0 ] && echo "packs: all tests passed"
exit "$fail"
