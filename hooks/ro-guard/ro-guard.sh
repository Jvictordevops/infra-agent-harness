#!/usr/bin/env bash
# ro-guard.sh — PreToolUse(Bash). In read-only mode (bin/ro mode on) clouds, clusters and other
# machines are reached only through bin/ro: blocks aws/kubectl/helm/terraform/ssh… (core + packs) outside it, and
# switching the mode off (only the user does it, from a terminal). No mode file -> only the next check runs.
# In every mode it blocks changing the security profile (bin/security-profile set, the profile file).
# Guards against mistakes, not against an adversary: a script written on the fly is not inspected.
# Exit 2 = block (the reason goes to the agent on stderr). Without jq, or with an input it cannot parse, it
# blocks too (hooks/lib/fail-closed.sh).
set -uo pipefail
# shellcheck source=hooks/lib/log-decision.sh
. "$(dirname "$0")/../lib/log-decision.sh"
# shellcheck source=hooks/lib/fail-closed.sh
. "$(dirname "$0")/../lib/fail-closed.sh"

MODE="${RO_MODE_FILE:-$HOME/.config/infra-agent-harness/ro-mode}"
INPUT="$(cat)"   # always read stdin: the caller may fail writing to a closed pipe
guard_need_jq ro-guard
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)" || guard_bad_input ro-guard

# Always, whatever the mode: the security profile belongs to the user (bin/security-profile, packs/README.md).
# Blocks 'security-profile set', any command that names the profile file and its override variable.
if printf '%s' "$CMD" | grep -Eq 'security-profile[[:space:]]+set|infra-agent-harness/profile([^a-z0-9_.-]|$)|IAH_PROFILE_FILE'; then
  log_decision ro-guard "$CMD" "security profile"
  echo "ro-guard: agents never change the security profile. Show it with 'security-profile show'; only the user sets it ('security-profile set …' in a terminal, then link-harness)." >&2
  exit 2
fi

[ -f "$MODE" ] || exit 0
# Core: other machines, GitHub, and the clouds without a pack (blocked by default). The packs add theirs
# (packs/*/guard-tools, one name per line). Every pack under packs/ is active.
FORBIDDEN='ssh|scp|sftp|rsync|sshfs|mosh|gh|az|gcloud'
for f in "$(dirname "$0")"/../../packs/*/guard-tools; do
  [ -f "$f" ] || continue
  while IFS= read -r t || [ -n "$t" ]; do
    case "$t" in ''|'#'*) continue ;; esac
    [[ "$t" =~ ^[a-z0-9_-]+$ ]] && FORBIDDEN="$FORBIDDEN|$t"
  done < "$f"
done

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
    # shellcheck disable=SC2086  # split the segment into words on purpose (globbing is off)
    set -- $seg
    while [ $# -gt 0 ]; do # drop env assignments, wrappers and shell keywords to reach the real command
      case "$1" in
        [A-Za-z_]*=*|sudo|env|command|exec|time|nohup|nice|xargs|-*) shift ;;
        '{'|'}'|'!'|if|then|else|elif|do|while|until) shift ;;   # for p in a b; do <tool> …; done · if <tool> …
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
      bash|sh|zsh|dash|ksh|eval|source|.|watch)
        if printf '%s' "$seg" | grep -Eqw "$FORBIDDEN"; then block "'$base' running a forbidden command."; fi ;;
    esac
  done
}
