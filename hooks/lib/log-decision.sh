#!/usr/bin/env bash
# Sourced by the hooks: log_decision <hook> <command> <reason> appends one JSON line to a local log,
# outside the repo. Never fails the hook: any error is swallowed. The command is cut to 300 chars.
# Log: $IAH_HOOK_LOG or ~/.local/state/infra-agent-harness/hook-decisions.jsonl (mode 600).

log_decision() {
  local log="${IAH_HOOK_LOG:-$HOME/.local/state/infra-agent-harness/hook-decisions.jsonl}"
  {
    if [ ! -e "$log" ]; then mkdir -p "$(dirname "$log")" && (umask 077 && : > "$log"); fi &&
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg hook "$1" --arg cmd "${2:0:300}" \
      --arg reason "$3" --arg cwd "$PWD" \
      '{ts: $ts, hook: $hook, decision: "block", command: $cmd, reason: $reason, cwd: $cwd}' >> "$log"
  } 2>/dev/null || true
}
