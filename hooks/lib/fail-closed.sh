#!/usr/bin/env bash
# Sourced by the guards (PreToolUse hooks): a guard that cannot read its input blocks, it never lets the call
# through. Claude Code treats any exit code other than 2 as "go on", so a guard that fails halfway would be
# a guard that is not there.
#   guard_need_jq <guard>     exits 2 when jq is not installed (the guards read the hook input with it)
#   guard_bad_input <guard>   exits 2: the hook input could not be parsed
#   guard_broken_tool <guard> <tool>   exits 2: a tool the guard needs to read the command (awk) failed
# Tests: tests/fail-closed.sh

guard_need_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "$1: jq is not installed, so this guard cannot read the command and blocks it (it fails closed). Ask the user to install jq (apt-get install jq, brew install jq); nothing gets through until then." >&2
  exit 2
}

guard_broken_tool() { # $1 guard, $2 tool
  echo "$1: $2 failed on this machine, so this guard cannot read the command and blocks it (it fails closed). Tell the user: this is a bug of the harness on this system." >&2
  exit 2
}

guard_bad_input() {
  echo "$1: cannot read the hook input (not JSON), so this guard blocks the call (it fails closed)." >&2
  exit 2
}
