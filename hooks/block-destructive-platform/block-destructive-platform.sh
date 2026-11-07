#!/usr/bin/env bash
# block-destructive-platform.sh — PreToolUse(Bash): blocks destructive platform commands.
# Same API as block-git-write: JSON on stdin, JSON decision on stdout, exit 0.
# Matches the tool anywhere in the command (also inside ssh '…' or bash -c "…") and allows any
# tokens between the tool and the verb (-n prod, --profile pro, -chdir=x), but never across ; | &.
# Guards against mistakes, not against an adversary. Tests: tests/block-destructive.sh
set -euo pipefail
# shellcheck source=hooks/lib/log-decision.sh
. "$(dirname "$0")/../lib/log-decision.sh"

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

P='(^|[^[:alnum:]_-])'           # start of the tool name (allows /usr/bin/, quotes, $( )
S='[[:space:]]+'
G="(${S}[^[:space:];|&]+)*"      # any tokens in the same segment
E='([[:space:]]|$|["'"'"'`;|&)])' # end of the verb

TF="${P}(terraform|tofu|terragrunt)"
RULES=(   # name|pattern
  "terraform-destroy-import|${TF}${G}${S}(destroy|import)${E}"
  "terraform-apply-destroy|${TF}${G}${S}apply${G}${S}-destroy${E}"
  "terraform-state-write|${TF}${G}${S}state${G}${S}(rm|push|replace-provider)${E}"
  "kubectl-delete-drain-cordon|${P}kubectl${G}${S}(delete|drain|cordon)${E}"
  "kubectl-scale-to-zero|${P}kubectl${G}${S}scale${G}${S}--replicas(=|${S})0${E}"
  "kubectl-rollout-undo|${P}kubectl${G}${S}rollout${G}${S}undo${E}"
  "helm-uninstall|${P}helm${G}${S}(uninstall|delete|del|un)${E}"
  "helmfile-apply-destroy|${P}helmfile${G}${S}(destroy|apply|delete)${E}"
  "aws-delete-terminate-stop|${P}aws${G}${S}(delete-|terminate-|stop-)[a-z0-9-]+${E}"
  "aws-s3-rb-rm|${P}aws${G}${S}s3${G}${S}(rb|rm)${E}"
)

for rule in "${RULES[@]}"; do
  name="${rule%%|*}" pattern="${rule#*|}"
  if printf '%s\n' "$CMD" | grep -qE -- "$pattern"; then
    log_decision block-destructive-platform "$CMD" "$name"
    echo '{"decision": "block", "reason": "Blocked destructive platform command. Propose the command and let the user execute it manually (or via ! in chat)."}'
    exit 0
  fi
done
