#!/usr/bin/env bash
# credential-guard.sh — PreToolUse(Bash|Read|Grep), in every profile and mode: agents use credentials but never
# read, copy or send them (the floor; packs/README.md, "Credential files").
#   Bash: blocks a credential path given to a reader (cat, grep, cp, curl -T, python -c…), read with '<' or sent
#         as @path / file://path. Using it (ssh -i, --kubeconfig, KUBECONFIG=, source .env) is allowed.
#         Also blocks a command that prints a secret (gh auth token, aws secretsmanager get-secret-value…) when
#         its output is shown: on the screen, in a file or through a reader. Piped into another tool or kept in a
#         variable it is a use and passes. Lists: hooks/credential-guard/secret-commands + packs/*/secret-commands.
#   Read, Grep: blocks a credential path (also through a symlink).
# Credential paths: hooks/credential-guard/credential-files + packs/*/credential-files. Readers:
# hooks/credential-guard/readers + packs/*/credential-readers. The same paths are Read(…) deny rules
# (bin/link-harness), the second lock. Guards against mistakes, not against an adversary (hooks/lib/credentials.sh).
# Exit 2 = block (the reason goes to the agent on stderr). Without jq, or with an input it cannot parse, it
# blocks too (hooks/lib/fail-closed.sh). Tests: tests/credential-guard.sh, tests/floor.sh, tests/fail-closed.sh
set -uo pipefail
HERE="$(dirname "$0")"
# shellcheck source=hooks/lib/log-decision.sh
. "$HERE/../lib/log-decision.sh"
# shellcheck source=hooks/lib/credentials.sh
. "$HERE/../lib/credentials.sh"
# shellcheck source=hooks/lib/fail-closed.sh
. "$HERE/../lib/fail-closed.sh"
shopt -u patsub_replacement 2>/dev/null || true

INPUT="$(cat)"   # always read stdin: the caller may fail writing to a closed pipe
guard_need_jq credential-guard
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // "Bash"' 2>/dev/null)" || guard_bad_input credential-guard
cred_load "$HERE/../.."

block() { # $1 what the agent tried, $2 why
  log_decision credential-guard "$1" "credential $CRED_HIT: $2"
  echo "credential-guard: $CRED_HIT is a credential file ($2). Agents use credentials (ssh -i, --kubeconfig, source .env) but never read, copy or send them. If you need something from it, ask the user to look." >&2
  exit 2
}

case "$TOOL" in
  Read|Grep)
    P="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)"
    [ -n "$P" ] || exit 0
    cred_match "$P" && block "$TOOL $P" "$TOOL tool"
    R="$(realpath "$P" 2>/dev/null || true)"
    [ -n "$R" ] && [ "$R" != "$P" ] && cred_match "$R" && block "$TOOL $P" "$TOOL tool, through a link"
    exit 0 ;;
esac

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)"
[ -n "$CMD" ] || exit 0
cred_check_line "$CMD" || block "$CMD" "$CRED_WHAT"
if ! sec_check_line "$CMD"; then
  log_decision credential-guard "$CMD" "secret command '$CRED_HIT': $CRED_WHAT"
  echo "credential-guard: '$CRED_HIT' prints a secret, and here it would be $CRED_WHAT. Agents use secrets (piped into the tool that needs them, '… | docker login --password-stdin', or kept in a variable, 'TOKEN=\$(…)') but never show them. If you need its value, ask the user to look." >&2
  exit 2
fi
exit 0
