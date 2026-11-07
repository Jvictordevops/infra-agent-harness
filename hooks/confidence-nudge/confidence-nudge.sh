#!/usr/bin/env bash
# confidence-nudge.sh — Claude Code UserPromptSubmit hook.
# When the prompt looks like troubleshooting, adds a reminder to the context: every conclusion
# ends with a confidence level. Words and message follow the repository language
# (.harness.conf, bin/lib/vocab.sh); English trigger words always count. Never blocks.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../../bin/lib/vocab.sh
. "$HERE/../../bin/lib/vocab.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)"
REPO="$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
vocab_load "$REPO" 2>/dev/null

BASE='error|fail|crash|broke|problem|issue|debug|troubleshoot|diagnos|investigat|oomkill|timeout|latency|stuck|hang|[^0-9](403|404|500|502|503)([^0-9]|$)'
PATTERN="$BASE${VOC_NUDGE_WORDS:+|$VOC_NUDGE_WORDS}"

if printf ' %s ' "$PROMPT" | grep -qE "$PATTERN"; then
  jq -n --arg c "[confidence-gate] $VOC_NUDGE_MESSAGE" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
fi
exit 0
