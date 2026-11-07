#!/usr/bin/env bash
# Tests for bin/hooks/commit-msg. Runs inside a throwaway git repo; touches nothing else.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/bin/hooks/commit-msg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/repo"
cd "$TMP/repo" || exit 1
export GIT_AUTHOR_NAME="Dana Doe" GIT_AUTHOR_EMAIL="dana@example.com"
export GIT_COMMITTER_NAME="Dana Doe" GIT_COMMITTER_EMAIL="dana@example.com"
fail=0

run() { printf '%b' "$1" > "$TMP/msg"; "$HOOK" "$TMP/msg" 2>/dev/null; }
blk() { if run "$1"; then echo "FAIL (should block): $1"; fail=1; fi; }
alw() { if run "$1"; then :; else echo "FAIL (should pass): $1"; fail=1; fi; }

alw "6.22 Add commit-msg hook\n\nTask: harness-standard 6.22 commit-msg hook"
alw "link-harness: link each skill into ~/.copilot/skills when it is a folder"
alw "3.1 Claude Code plugin and marketplace in .claude-plugin/"
alw "5.2 Hook adapter for Copilot CLI"
alw "Align with the team copilot-skills repo"
alw "Message\n\nCo-authored-by: Ana Ruiz <ana@example.com>"
alw "Fix\n\n# Co-Authored-By: Claude <noreply@anthropic.com>"
blk "Fix\n\nCo-Authored-By: Claude Opus <noreply@anthropic.com>"
blk "Fix\n\nCo-authored-by: Copilot <copilot@""github.com>"
blk "Fix\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)"
blk "Fix\n\nGenerated with Copilot"
blk "Fix\n\nClaude-Session: https://claude.ai/code/session_x"
blk "Refactor suggested by Sonnet"
blk "Plan reviewed with GPT-5"

GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com blk "Normal message"
GIT_COMMITTER_NAME="copilot-swe-agent[bot]" blk "Normal message"

if [ "$fail" = 0 ]; then echo "commit-msg: all tests passed"; else echo "commit-msg: tests FAILED"; exit 1; fi
