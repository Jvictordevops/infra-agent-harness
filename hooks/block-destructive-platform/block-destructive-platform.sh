#!/usr/bin/env bash
# block-destructive-platform.sh — PreToolUse(Bash): blocks destructive platform commands.
# Same API as block-git-write: JSON on stdin, JSON decision on stdout, exit 0.
# Matches the tool anywhere in the command (also inside ssh '…' or bash -c "…") and allows any
# tokens between the tool and the verb (-n prod, --profile pro, -chdir=x), but never across ; | &.
# Guards against mistakes, not against an adversary. Tests: tests/block-destructive.sh, tests/packs.sh
set -euo pipefail
# shellcheck source=hooks/lib/log-decision.sh
. "$(dirname "$0")/../lib/log-decision.sh"

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

P='(^|[^[:alnum:]_-])'           # start of the tool name (allows /usr/bin/, quotes, $( )
S='[[:space:]]+'
G="(${S}[^[:space:];|&]+)*"      # any tokens in the same segment
E='([[:space:]]|$|["'"'"'`;|&)])' # end of the verb

# Rules come from packs/*/destructive.rules ('name|regex' per line, # comments); the regex may use the
# placeholders <P> <S> <G> <E> for the four pieces above (packs/README.md). Every pack under packs/ is active.
PACKS="$(dirname "$0")/../../packs"
shopt -u patsub_replacement 2>/dev/null || true   # bash >= 5.2 would turn a '&' of the replacement into the match
RULES=()
for f in "$PACKS"/*/destructive.rules; do
  [ -f "$f" ] || continue
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    line="${line//<P>/$P}"; line="${line//<S>/$S}"; line="${line//<G>/$G}"; line="${line//<E>/$E}"
    RULES+=("$line")
  done < "$f"
done

for rule in ${RULES[@]+"${RULES[@]}"}; do
  name="${rule%%|*}" pattern="${rule#*|}"
  if printf '%s\n' "$CMD" | grep -qE -- "$pattern"; then
    log_decision block-destructive-platform "$CMD" "$name"
    echo '{"decision": "block", "reason": "Blocked destructive platform command. Propose the command and let the user execute it manually (or via ! in chat)."}'
    exit 0
  fi
done
