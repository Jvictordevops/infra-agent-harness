# shellcheck shell=bash
# Helpers for the tests of a rule pack (packs/<name>/tests.sh) and for tests/floor.sh. They test the harness in
# ROOT (set it before sourcing) with every pack loaded, and run nothing real: bin/ro --check and hooks fed with
# commands.
#
#   ro_ok / ro_no <tool> <args…>   bin/ro --check passes / denies        (env prefixes work: RO_PROFILES=a ro_no …)
#   blk / alw "<command>"          block-destructive-platform blocks it / lets it through
#   denied / asked "<command>"     a permissions.deny / permissions.ask rule of the core or a pack matches it
#   unruled "<command>"            no deny or ask rule matches it
#   guarded "<command>"            ro-guard blocks it in read-only mode
#   pack_done <name>               prints the result; exits 1 if any case failed
#
# denied/asked/unruled approximate Claude Code's 'Bash(…)' rules with a shell glob ('*' = any text). Give
# commands with arguments: whether 'Bash(x *)' also matches a bare 'x' is left to Claude Code.

# shellcheck source=bin/lib/packs.sh
. "$ROOT/bin/lib/packs.sh"
_PT_TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$_PT_TMP"' EXIT
IAH_HOOK_LOG="$_PT_TMP/hook-decisions.jsonl"; export IAH_HOOK_LOG   # keep test blocks out of the real decision log
RO_MODE_FILE="$_PT_TMP/ro-mode"; RO_ROOTS="$_PT_TMP"; export RO_MODE_FILE RO_ROOTS
unset RO_PROFILES RO_CONTEXTS
_PT_PERMS="$(packs_permissions "$ROOT")" || { echo "FAIL: cannot read the deny/ask rules"; exit 1; }
fail=0

_pt_ko() { echo "FAIL: $*"; fail=1; }
ro_ok() { "$ROOT/bin/ro" --check "$@" >/dev/null 2>&1 || _pt_ko "ro should pass: $*"; }
ro_no() { if "$ROOT/bin/ro" --check "$@" >/dev/null 2>&1; then _pt_ko "ro should deny: $*"; fi; }

_pt_bdp() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | "$ROOT/hooks/block-destructive-platform/block-destructive-platform.sh"; }
blk() { case "$(_pt_bdp "$1")" in *'"block"'*) ;; *) _pt_ko "block-destructive should block: $1" ;; esac; }
alw() { [ -z "$(_pt_bdp "$1")" ] || _pt_ko "block-destructive should pass: $1"; }

_pt_match() { # $1 deny|ask, $2 command -> 0 if a rule matches
  local pat
  while IFS= read -r pat; do
    # shellcheck disable=SC2053  # the rule is a glob on purpose
    [ -n "$pat" ] && [[ "$2" == $pat ]] && return 0
  done <<<"$(jq -r --arg k "$1" '.[$k][] | select(startswith("Bash(") and endswith(")")) | .[5:-1]' <<<"$_PT_PERMS")"
  return 1
}
denied() { _pt_match deny "$1" || _pt_ko "no deny rule matches: $1"; }
asked() { _pt_match ask "$1" || _pt_ko "no ask rule matches: $1"; }
unruled() { if _pt_match deny "$1" || _pt_match ask "$1"; then _pt_ko "a deny/ask rule matches: $1"; fi; }

guarded() {
  local rc
  : > "$RO_MODE_FILE"
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | "$ROOT/hooks/ro-guard/ro-guard.sh" >/dev/null 2>&1; rc=$?
  rm -f "$RO_MODE_FILE"
  [ "$rc" = 2 ] || _pt_ko "ro-guard should block in read-only mode: $1"
}

pack_done() { if [ "$fail" = 0 ]; then echo "$1: all tests passed"; else echo "$1: tests FAILED"; exit 1; fi; }
