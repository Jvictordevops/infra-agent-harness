#!/usr/bin/env bash
# ro-guard.sh — PreToolUse(Bash). In read-only mode (bin/ro mode on) clouds, clusters and other
# machines are reached only through bin/ro: blocks aws/kubectl/helm/terraform/ssh… (core + packs) outside it, and
# switching the mode off (only the user does it, from a terminal). No mode file -> only the next check runs.
# In every mode it blocks changing the security profile (bin/security-profile set, the profile file).
# Guards against mistakes, not against an adversary: a script written on the fly (bash file.sh, source) is not inspected.
# Exit 2 = block (the reason goes to the agent on stderr). Without jq, or with an input it cannot parse, it
# blocks too (hooks/lib/fail-closed.sh).
set -uo pipefail
# shellcheck source=hooks/lib/log-decision.sh
. "$(dirname "$0")/../lib/log-decision.sh"
# shellcheck source=hooks/lib/fail-closed.sh
. "$(dirname "$0")/../lib/fail-closed.sh"
# shellcheck source=hooks/lib/cmdparse.sh
. "$(dirname "$0")/../lib/cmdparse.sh"
# shellcheck source=hooks/lib/protected.sh
. "$(dirname "$0")/../lib/protected.sh"

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

# Always, whatever the mode: agents do not WRITE the user's Claude Code settings, the harness configuration or the
# installed copy of the plugin (hooks/lib/protected.sh). By action: reading or naming them is fine. A script written on
# the fly is not inspected.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)" || guard_bad_input ro-guard
out="$(printf '%s\n' "$CMD" | CMDP_PROT="$(protected_list)" CMDP_HOME="$HOME" CMDP_CWD="$CWD" cmdparse_run "$(dirname "$0")/write-sink.awk" 2>/dev/null)" || guard_broken_tool ro-guard awk
case "$out" in
  '') ;;
  B*)
    log_decision ro-guard "$CMD" "protected path: ${out#B?}"
    echo "ro-guard: agents do not write there (${out#B?}): the user's Claude Code settings, the harness configuration and the installed plugin are changed by the user, in a terminal. Reading them is fine. If a change is needed, give it to the user." >&2
    exit 2 ;;
  *) guard_broken_tool ro-guard awk ;;
esac

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
  echo "ro-guard: read-only mode is on ($(cat "$MODE")). $1 Use 'ro <tool> …' (bin/ro in a clone of the harness; docs/tools.md). Only the user switches the mode off ('ro mode off' in a terminal)." >&2
  exit 2
}

if printf '%s' "$CMD" | grep -Eq 'ro[[:space:]]+mode[[:space:]]+off|ro-mode|RO_MODE_FILE'; then
  block "Agents never switch read-only mode off."
fi

# Every simple command of the line (also inside $(…), bash -c, eval, ssh host '…', watch, find -exec, a heredoc
# to a shell…), found by the common parser; the sink (ro-sink.awk) blocks a forbidden name outside bin/ro.
out="$(printf '%s\n' "$CMD" | CMDP_FORB="$FORBIDDEN" cmdparse_run "$(dirname "$0")/ro-sink.awk" 2>/dev/null)" || guard_broken_tool ro-guard awk
case "$out" in
  '') ;;
  B*) block "${out#B?}" ;;
  *) guard_broken_tool ro-guard awk ;;
esac
