#!/usr/bin/env bash
# block-destructive-platform.sh — PreToolUse(Bash): blocks destructive platform commands.
# Same API as block-git-write: JSON on stdin, JSON decision on stdout, exit 0.
# Reads the command line with the common parser (hooks/lib/cmdparse.awk) and matches the rules of the packs
# against each command it runs (also inside ssh '…', bash -c "…", $(…), a heredoc to a shell), allowing any
# tokens between the tool and the verb (-n prod, --profile pro, -chdir=x). Text that only names a command (a
# commit message, a grep pattern, echo) is not a command.
# Guards against mistakes, not against an adversary. Without jq, or with an input it cannot parse, it blocks
# (exit 2, hooks/lib/fail-closed.sh). Tests: tests/block-destructive.sh, tests/packs.sh, tests/fail-closed.sh
set -euo pipefail
# shellcheck source=hooks/lib/log-decision.sh
. "$(dirname "$0")/../lib/log-decision.sh"
# shellcheck source=hooks/lib/fail-closed.sh
. "$(dirname "$0")/../lib/fail-closed.sh"
# shellcheck source=hooks/lib/cmdparse.sh
. "$(dirname "$0")/../lib/cmdparse.sh"

INPUT=$(cat)   # always read stdin: the caller may fail writing to a closed pipe
guard_need_jq block-destructive-platform
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || guard_bad_input block-destructive-platform

US=$'\037'                          # field separator of the parser: it joins a command and its arguments
P='(^|[^[:alnum:]_-])'           # start of the tool name (allows /usr/bin/, quotes, $( )
S="[[:space:]${US}]+"
G="(${S}[^[:space:]${US};|&]+)*"      # any tokens in the same command
E="([[:space:]${US}]|\$|[\"'\`;|&)])" # end of the verb

# Rules come from packs/*/destructive.rules ('name|regex' per line, # comments); the regex may use the
# placeholders <P> <S> <G> <E> for the four pieces above (packs/README.md). Every pack under packs/ is active.
PACKS="$(dirname "$0")/../../packs"
shopt -u patsub_replacement 2>/dev/null || true   # bash >= 5.2 would turn a '&' of the replacement into the match
RULES=""
for f in "$PACKS"/*/destructive.rules; do
  [ -f "$f" ] || continue
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    line="${line//<P>/$P}"; line="${line//<S>/$S}"; line="${line//<G>/$G}"; line="${line//<E>/$E}"
    RULES="$RULES$line"$'\n'
  done < "$f"
done
[ -n "$RULES" ] || exit 0

out="$(printf '%s\n' "$CMD" | CMDP_RULES="$RULES" cmdparse_run "$(dirname "$0")/destructive-sink.awk" 2>/dev/null)" || guard_broken_tool block-destructive-platform awk
case "$out" in
  '') ;;
  B*)
    log_decision block-destructive-platform "$CMD" "${out#B?}"
    echo '{"decision": "block", "reason": "Blocked destructive platform command. Propose the command and let the user execute it manually (or via ! in chat)."}'
    exit 0 ;;
  *) guard_broken_tool block-destructive-platform awk ;;
esac
