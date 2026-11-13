#!/usr/bin/env bash
# Tests for the paths agents do not write (hooks/lib/protected.sh, hooks/ro-guard/write-sink.awk, in ro-guard in every
# mode), the redirections the parser reports, and the Edit deny rules link-harness installs. Fake HOME and fake stable
# link in a temp dir; nothing real is read or written. The commands are data: they are never run.
# shellcheck disable=SC2016
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ko() { echo "FAIL: $*"; fail=1; }

export HOME="$TMP/home" IAH_HOOK_LOG="$TMP/log.jsonl" RO_MODE_FILE="$TMP/ro-mode" IAH_PROFILE_FILE="$TMP/profile"
export IAH_STABLE_LINK="$TMP/link/current"
CACHE="$HOME/.claude/plugins/cache/mk/infra-agent-harness/0.1.0"
INST="$TMP/installed"; CLONE="$TMP/clone"
mkdir -p "$HOME/.claude" "$HOME/.config/infra-agent-harness" "$CACHE/hooks" "$INST/hooks" "$CLONE/hooks" "$TMP/link" "$TMP/work"
git init -q "$CLONE" 2>/dev/null || mkdir -p "$CLONE/.git"   # .git present = a git clone
unset RO_PROFILES RO_CONTEXTS

# hook <command> [cwd] -> exit code of ro-guard
hook() { jq -n --arg c "$1" --arg d "${2:-$TMP/work}" '{tool_input:{command:$c},cwd:$d}' | "$ROOT/hooks/ro-guard/ro-guard.sh" >/dev/null 2>"$TMP/err"; }
blocks() { local rc; hook "$1" "${2:-}"; rc=$?; [ "$rc" = 2 ] || ko "should block: $1"; }
passes() { local rc; hook "$1" "${2:-}"; rc=$?; [ "$rc" = 0 ] || ko "should pass: $1 ($(cat "$TMP/err"))"; }

ln -sfn "$INST" "$IAH_STABLE_LINK"   # installed copy = a plain directory, not a git clone
for mode in off on; do
  if [ "$mode" = on ]; then echo "2026-11-13" > "$RO_MODE_FILE"; else rm -f "$RO_MODE_FILE"; fi

  # --- writes that block
  blocks 'echo x > ~/.claude/settings.json'
  blocks 'echo x >> ~/.claude/settings.json'
  blocks 'echo x > "$HOME/.claude/settings.local.json"'
  blocks 'echo x > ${HOME}/.claude/settings.json'
  blocks "echo x > $HOME/.claude/settings.json"
  blocks 'cat f | tee ~/.claude/settings.json'
  blocks 'tee -a ~/.claude/settings.local.json'
  blocks 'sed -i s/a/b/ ~/.claude/settings.json'
  blocks 'sed -i.bak s/a/b/ ~/.claude/settings.json'
  blocks 'sed -Ei s/a/b/ ~/.claude/settings.json'
  blocks 'sed --in-place s/a/b/ ~/.claude/settings.json'
  blocks 'rm ~/.claude/settings.json'
  blocks 'rm -rf ~/.config/infra-agent-harness'
  blocks 'rm -rf ~/.config/infra-agent-harness/'
  blocks 'rm ~/.config/infra-agent-harness/denylist.txt'
  blocks 'cp /tmp/x ~/.claude/settings.json'
  blocks 'cp -t ~/.config/infra-agent-harness /tmp/x'
  blocks 'cp --target-directory=~/.config/infra-agent-harness /tmp/x'
  blocks 'mv ~/.claude/settings.json /tmp/b'
  blocks 'ln -sf /tmp/x ~/.claude/settings.json'
  blocks 'touch ~/.claude/settings.local.json'
  blocks 'truncate -s 0 ~/.claude/settings.json'
  blocks 'chmod 777 ~/.claude/settings.json'
  blocks 'dd if=/dev/zero of=~/.claude/settings.json'
  blocks 'echo x > ~/.claude/../.claude/settings.json'
  blocks 'echo x > ~/.claude//./settings.json'
  blocks "echo x > $CACHE/hooks/ro-guard.sh"
  blocks "cp /tmp/x $CACHE/hooks/ro-guard.sh"
  blocks "rm -rf $HOME/.claude/plugins/cache/mk/infra-agent-harness"
  blocks "echo x > $INST/hooks/ro-guard.sh"
  blocks "sed -i s/a/b/ $INST/hooks/ro-guard.sh"
  blocks 'bash -c "echo x > ~/.claude/settings.json"'
  blocks 'sudo tee ~/.claude/settings.json'
  blocks 'echo $(echo x > ~/.claude/settings.json)'
  blocks 'ssh host "echo x > ~/.claude/settings.json"'
  blocks 'echo x > settings.json' "$HOME/.claude"
  blocks 'cp /tmp/x settings.local.json' "$HOME/.claude"
  blocks 'echo x > ../.claude/settings.json' "$TMP/home/sub"
  blocks 'xargs -I{} cp {} ~/.claude/settings.json'

  # --- things that are not writes, or not there
  passes 'cat ~/.claude/settings.json'
  passes 'jq . ~/.claude/settings.json'
  passes 'cp ~/.claude/settings.json /tmp/backup'
  passes 'cp -r ~/.config/infra-agent-harness /tmp/backup'
  passes 'grep -r foo ~/.config/infra-agent-harness'
  passes 'ls -la ~/.claude ~/.config/infra-agent-harness'
  passes 'diff ~/.claude/settings.json /tmp/x'
  passes 'echo "write to ~/.claude/settings.json"'
  passes 'git commit -m "edit ~/.claude/settings.json and rm ~/.config/infra-agent-harness"'
  passes 'grep -rn "sed -i" ~/.claude/settings.json'
  passes 'echo x > /tmp/y'
  passes 'echo x > ~/.claude/other.json'
  passes 'echo x > ~/.claude/settings.json.bak'
  passes 'echo x > ~/.config/other-tool/settings.json'
  passes 'echo x > ~/.claude/plugins/cache/mk/other-plugin/hooks/x.sh'
  passes 'sed -i s/a/b/ notes.md'
  passes 'sed -n 1,5p ~/.claude/settings.json'
  passes 'cat x 2>&1 | tee /tmp/log'
  passes 'echo x > settings.json' "$TMP/work"
  passes 'echo x > /dev/null 2>&1'
  # the harness is developed in a git clone: not protected
  ln -sfn "$CLONE" "$IAH_STABLE_LINK"
  passes "echo x > $CLONE/hooks/ro-guard.sh"
  passes "sed -i s/a/b/ $CLONE/hooks/ro-guard.sh"
  ln -sfn "$INST" "$IAH_STABLE_LINK"
  blocks "echo x > $INST/hooks/ro-guard.sh"
  rm -f "$IAH_STABLE_LINK"
  passes "echo x > $INST/hooks/ro-guard.sh"   # no link: nothing known to protect there
  ln -sfn "$INST" "$IAH_STABLE_LINK"
done

# --- the list itself
. "$ROOT/hooks/lib/protected.sh"
list="$(protected_list)"
for want in "F	$HOME/.claude/settings.json" "F	$HOME/.claude/settings.local.json" "D	$HOME/.config/infra-agent-harness" "D	$CACHE/../.." "D	$INST"; do
  case "$want" in "D	$CACHE/../.."*) want="D	$HOME/.claude/plugins/cache/mk/infra-agent-harness" ;; esac
  grep -qxF -- "$want" <<<"$list" || ko "protected_list lacks: $want"
done
protected_link_is_clone && ko "installed copy is not a clone"
ln -sfn "$CLONE" "$IAH_STABLE_LINK"
protected_link_is_clone || ko "clone not detected"
grep -qF "$CLONE" <<<"$(protected_list)" && ko "a git clone must not be in the list"

# --- parser: redirections (hooks/lib/cmdparse.awk)
red() { printf '%s\n' "$1" | CMDP_LIST_REDIR=1 CMDP_DATAFILE="$ROOT/hooks/lib/cmdparse-data.txt" awk -f "$ROOT/hooks/lib/cmdparse.awk" -f "$ROOT/tests/lib/cmdparse-list.awk" | grep ' redir ' | sed 's/^0 redir //' | paste -sd, -; }
eq() { [ "$2" = "$3" ] || ko "$1: got '$2', want '$3'"; }
eq "redir out" "$(red 'echo hi > a.txt')" "out a.txt"
eq "redir append" "$(red 'echo hi >> a.txt')" "out a.txt"
eq "redir clobber" "$(red 'echo hi >| a.txt')" "out a.txt"
eq "redir &>" "$(red 'echo hi &> a.txt')" "out a.txt"
eq "redir in" "$(red 'cat < in.txt')" "in in.txt"
eq "redir fd dup" "$(red 'x 2>&1')" "fd 1"
eq "redir >&file is a file" "$(red 'x >&file')" "out file"
eq "redir 2>file" "$(red 'x 2>err.txt')" "out err.txt"
eq "no redir in text" "$(red 'echo "a > b"')" ""
eq "no redir in process substitution" "$(red 'diff <(ls) <(ls)')" ""

# --- link-harness: a plain-directory install is denied to the Edit tool, a clone is not
H="$TMP/lh"; mkdir -p "$H"
run_link() { HOME="$H" IAH_STABLE_LINK="$IAH_STABLE_LINK" LINK_HARNESS_WINDOWS=0 IAH_REPO="" "$ROOT/bin/link-harness" --quiet >/dev/null 2>&1; }
S="$H/.claude/settings.json"
ln -sfn "$CLONE" "$IAH_STABLE_LINK"; run_link
jq -e '.permissions.deny | index("Edit(~/.claude/settings.json)") and index("Edit(~/.claude/settings.local.json)") and index("Edit(~/.config/infra-agent-harness/**)") and index("Edit(~/.claude/plugins/cache/*/infra-agent-harness/**)")' "$S" >/dev/null || ko "link-harness: static Edit deny rules missing"
jq -e '[.permissions.deny[] | select(startswith("Edit(") and contains("/clone/"))] | length == 0' "$S" >/dev/null || ko "link-harness: a git clone must not get an Edit deny rule"
mkdir -p "$H/inst"; ln -sfn "$H/inst" "$IAH_STABLE_LINK"; run_link
jq -e '.permissions.deny | index("Edit(~/inst/**)")' "$S" >/dev/null || ko "link-harness: plain-directory install under HOME: Edit(~/inst/**) missing"
ln -sfn "$INST" "$IAH_STABLE_LINK"; run_link
jq -e --arg r "Edit(/$INST/**)" '.permissions.deny | index($r)' "$S" >/dev/null || ko "link-harness: plain-directory install outside HOME: absolute Edit rule missing"
run_link; jq -e --arg r "Edit(/$INST/**)" '[.permissions.deny[] | select(. == $r)] | length == 1' "$S" >/dev/null || ko "link-harness: Edit rule duplicated on the second run"

[ "$fail" = 0 ] && echo "protected-paths: all tests passed" || exit 1
