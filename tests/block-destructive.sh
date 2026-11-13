#!/usr/bin/env bash
# shellcheck disable=SC2016  # the test commands are text, never expanded here
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
alw "x-demo nuke"
alw "demo-x nuke"
alw "demo state list"
alw "echo demo"
alw "git status"

# Common parser (hooks/lib/cmdparse.awk): text that names a command is not the command...
alw 'git commit -m "fix: avoid demo nuke in CI"'
alw 'grep "demo nuke" docs/'
alw "grep -rn 'demo nuke' ."
alw "sed -i 's/old/demo nuke/' notes.md"
alw $'cat > rec.md <<\'EOF\'\nrun demo nuke later\nEOF'
alw 'echo "demo nuke"'
alw "printf '%s\\n' \"demo nuke\" >> notes.md"
alw 'git log --grep="demo nuke"'
alw 'ls # then demo nuke'
alw "echo '\$(demo nuke)'"
alw $'tee notes.md <<EOF\ndemo state wipe\nEOF'
alw "python3 -c \"import os; os.system('demo nuke')\""   # the code of a language is not looked into (docs/threat-model.md)
alw 'demo logs job/nuke-old'
# ... a tool that is not on the list of data commands keeps its friction: its arguments may run a command
blk 'gh pr create --body "uses demo nuke"'
# ... and a command behind a wrapper, a pipe, an exec or a nesting is
blk 'sudo -u root demo nuke'
blk 'sudo -u ops env A=1 timeout 10 demo nuke'
blk 'nice -n 5 demo nuke'
blk 'timeout 5 demo nuke'
blk 'ls | xargs -I{} demo nuke {}'
blk 'find . -name x -exec demo nuke {} \;'
blk "echo 'demo nuke' | bash"
blk $'bash <<EOF\ndemo nuke\nEOF'
blk 'bash <<< "demo nuke"'
blk $'cat <<EOF | sh\ndemo nuke\nEOF'
blk 'eval "demo nuke"'
blk 'watch demo nuke'
blk 'echo "$(demo nuke)"'
blk 'echo `demo nuke`'
blk 'X=$(demo nuke)'
blk 'cat <(demo nuke)'
blk 'docker run --rm img demo nuke'
blk "bash -c \"bash -c 'demo nuke'\""
blk 'kubectl get pods; demo nuke'
blk 'if true; then demo nuke; fi'
deep="demo nuke"; for _ in 1 2 3 4 5 6; do deep="bash -c $(printf '%q' "$deep")"; done
blk "$deep"                                                                         # nested past 4 levels: blocks

# No awk, no list of data commands, or an awk that prints garbage: the guard blocks (exit 2), it does not let it through
printf '#!/bin/sh\ncat >/dev/null\necho "awk: syntax error" >&2\nexit 2\n' > "$TMP/awk-bad"
mkdir -p "$TMP/badawk"; cp "$TMP/awk-bad" "$TMP/badawk/awk"; chmod +x "$TMP/badawk/awk"
jq -n '{tool_input:{command:"ls"}}' | PATH="$TMP/badawk:$PATH" "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a failing awk should block with exit 2, got $rc"; fail=1; }
printf '#!/bin/sh\ncat >/dev/null\necho "garbage"\n' > "$TMP/badawk/awk"
jq -n '{tool_input:{command:"ls"}}' | PATH="$TMP/badawk:$PATH" "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] || { echo "FAIL: an awk that prints garbage should block with exit 2, got $rc"; fail=1; }
jq -n '{tool_input:{command:"ls"}}' | CMDP_DATAFILE="$TMP/no-such-list" "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a missing list of data commands should block with exit 2, got $rc"; fail=1; }

# The rule name goes to the decision log
grep -q '"reason":"demo-state-wipe"' "$IAH_HOOK_LOG" || { echo "FAIL: rule name not in the decision log"; fail=1; }

if [ "$fail" = 0 ]; then echo "block-destructive: all tests passed"; else echo "block-destructive: tests FAILED"; exit 1; fi
