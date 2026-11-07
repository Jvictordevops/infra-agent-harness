#!/usr/bin/env bash
# ro-guard.sh — PreToolUse(Bash). In read-only mode (bin/ro mode on) clouds, clusters and other
# machines are reached only through bin/ro: blocks aws/kubectl/helm/terraform/ssh… outside it, and
# switching the mode off (only the user does it, from a terminal). No mode file -> does nothing.
# Guards against mistakes, not against an adversary: a script written on the fly is not inspected.
# Exit 2 = block (the reason goes to the agent on stderr).
set -uo pipefail
# shellcheck source=hooks/lib/log-decision.sh
. "$(dirname "$0")/../lib/log-decision.sh"

MODE="${RO_MODE_FILE:-$HOME/.config/infra-agent-harness/ro-mode}"
INPUT="$(cat)"   # always read stdin: the caller may fail writing to a closed pipe
[ -f "$MODE" ] || exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
FORBIDDEN='ssh|scp|sftp|rsync|sshfs|mosh|aws|kubectl|helm|helmfile|terraform|tofu|terragrunt|eksctl|argocd|k9s|kubectx|kubens|flux|gh|az|gcloud'

block() {
  log_decision ro-guard "$CMD" "$1"
  echo "ro-guard: read-only mode is on ($(cat "$MODE")). $1 Use bin/ro <tool> … (docs/tools.md); only the user switches it off ('bin/ro mode off' in a terminal)." >&2
  exit 2
}

if printf '%s' "$CMD" | grep -Eq 'ro[[:space:]]+mode[[:space:]]+off|ro-mode|RO_MODE_FILE'; then
  block "Agents never switch read-only mode off."
fi

printf '%s\n' "$CMD" | awk '{ gsub(/&&|\|\||[;|&()`]|\$\(/, "\n"); print }' | {
  set -f
  while IFS= read -r seg; do
    set -- $seg
    while [ $# -gt 0 ]; do # drop env assignments and wrappers to reach the real command
      case "$1" in
        [A-Za-z_]*=*|sudo|env|command|exec|time|nohup|nice|xargs|-*) shift ;;
        timeout) shift; [ $# -gt 0 ] && shift ;;
        *) break ;;
      esac
    done
    [ $# -gt 0 ] || continue
    base="${1##*/}"
    case "$1" in bin/ro|*/bin/ro) continue ;; esac
    if printf '%s' "$base" | grep -Eqx "$FORBIDDEN"; then
      block "'$base' outside bin/ro."
    fi
    case "$base" in
      bash|sh|zsh|dash|eval|source|.)
        if printf '%s' "$seg" | grep -Eqw "$FORBIDDEN"; then block "'$base' running a forbidden command."; fi ;;
    esac
  done
}
