#!/usr/bin/env bash
# Tests for hooks/block-destructive-platform: how it reads packs/*/destructive.rules and matches a command,
# with a made-up pack 'demo' and no real pack. The real rules are tested in packs/<name>/tests.sh and the
# floor in tests/floor.sh. Runs nothing real: only feeds commands to the hook.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
IAH_HOOK_LOG="$TMP/hook-decisions.jsonl"; export IAH_HOOK_LOG   # keep test blocks out of the real decision log
cp -R "$ROOT/hooks" "$TMP/"
mkdir -p "$TMP/packs/demo"
HOOK="$TMP/hooks/block-destructive-platform/block-destructive-platform.sh"
fail=0

decide() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | "$HOOK"; }
blk() { out="$(decide "$1")"; case "$out" in *'"block"'*) ;; *) echo "FAIL (should block): $1"; fail=1 ;; esac; }
alw() { out="$(decide "$1")"; [ -z "$out" ] || { echo "FAIL (should pass): $1"; fail=1; }; }

# No pack: nothing is blocked and nothing fails
alw "demo nuke"

# Comments and empty lines are skipped; the last line may lack its newline
printf '# demo rules\n\ndemo-nuke|<P>demo<G><S>nuke<E>\n# two words\ndemo-state-wipe|<P>demo<G><S>state<G><S>wipe<E>' \
  > "$TMP/packs/demo/destructive.rules"

# The tool anywhere in the command, any tokens between tool and verb, never across ; | &
blk "demo nuke"
blk "demo -n prod nuke"
blk "demo --context pro nuke"
blk "demo -chdir=infra nuke"
blk "/usr/local/bin/demo nuke"
blk "sudo demo nuke"
blk "DEMO_X=1 demo nuke"
blk "cd infra && demo nuke"
blk "ls | demo nuke x"
blk "ssh mac 'demo nuke'"
blk "bash -c \"demo nuke\""
blk "echo \$(demo nuke)"
blk "(demo nuke)"
blk "demo nuke&&ls"
blk "demo nuke; ls"
blk "demo -x state -y wipe"
alw "demo list"
alw "demo list | grep nuke"
alw "demo list; echo nuke"
alw "demo logs job/nuke-old"
alw "demo nukes"
alw "xdemo nuke"
alw "demo-x nuke"
alw "demo state list"
alw "echo demo"
alw "git status"

# The rule name goes to the decision log
grep -q '"reason":"demo-state-wipe"' "$IAH_HOOK_LOG" || { echo "FAIL: rule name not in the decision log"; fail=1; }

if [ "$fail" = 0 ]; then echo "block-destructive: all tests passed"; else echo "block-destructive: tests FAILED"; exit 1; fi
