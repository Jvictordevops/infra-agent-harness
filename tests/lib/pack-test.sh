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
#   credblk / credok "<command>"   credential-guard blocks it / lets it through (reading vs using a credential)
#   credread "<path>"              credential-guard blocks the Read tool on it ('~/…' is expanded)
#   readdenied "<path>"            a Read(…) deny rule matches it ('~/<path>', or a path ending in a file name)
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
IAH_PROFILE_FILE="${PT_PROFILE_FILE:-$_PT_TMP/profile}"; export IAH_PROFILE_FILE   # not the machine's profile; default: all packs
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

# Credential files (hooks/credential-guard, decision "Leer o copiar, no usar")
_pt_crg() { # $1 tool, $2 command or path -> exit code of credential-guard
  if [ "$1" = Bash ]; then jq -n --arg c "$2" '{tool_name:"Bash", tool_input:{command:$c}}'
  else jq -n --arg t "$1" --arg p "$2" '{tool_name:$t, tool_input:{file_path:$p}}'; fi \
    | "$ROOT/hooks/credential-guard/credential-guard.sh" >/dev/null 2>&1
}
credblk() { _pt_crg Bash "$1"; [ $? = 2 ] || _pt_ko "credential-guard should block: $1"; }
credok() { _pt_crg Bash "$1" || _pt_ko "credential-guard should pass: $1"; }
# shellcheck disable=SC2088  # '~/…' is matched as the agent types it, not expanded
credread() { # $1 '~/<path>' or a path: the Read tool is blocked on it
  local p="$1"
  case "$p" in '~/'*) p="$HOME/${p#\~/}" ;; esac
  _pt_crg Read "$p"; [ $? = 2 ] || _pt_ko "credential-guard should block Read of: $1"
}
# shellcheck disable=SC2088
readdenied() { # $1 '~/<path>' or a path ending in a file name: a Read(…) deny rule matches it
  local pat path="$1"
  while IFS= read -r pat; do
    case "$pat" in
      '//**/'*)
        # shellcheck disable=SC2053  # the rule is a glob on purpose
        [[ "${path##*/}" == ${pat#//\*\*/} ]] && return 0 ;;
      '~/'*)
        # shellcheck disable=SC2053
        case "$path" in '~/'*) [[ "${path#\~/}" == ${pat#\~/} ]] && return 0 ;; esac ;;
    esac
  done <<<"$(jq -r '.deny[] | select(startswith("Read(") and endswith(")")) | .[5:-1]' <<<"$_PT_PERMS")"
  _pt_ko "no Read deny rule matches: $1"
}

pack_done() { if [ "$fail" = 0 ]; then echo "$1: all tests passed"; else echo "$1: tests FAILED"; exit 1; fi; }
