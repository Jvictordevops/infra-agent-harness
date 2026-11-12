#!/usr/bin/env bash
# Tests for hooks/lib/fail-closed.sh: a guard that cannot read its input blocks (exit 2) instead of letting the
# call through. Two cases per guard: jq is not installed, and the hook input is not JSON. Runs nothing real:
# the guards only get a harmless command, with a PATH that holds the few tools they need before the check.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
IAH_HOOK_LOG="$TMP/hook-decisions.jsonl"; export IAH_HOOK_LOG   # keep test blocks out of the real decision log
RO_MODE_FILE="$TMP/ro-mode"; IAH_PROFILE_FILE="$TMP/profile"; export RO_MODE_FILE IAH_PROFILE_FILE
fail=0

# A PATH without jq: links to the real tools, one by one (the system directories may hold jq)
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
for t in bash cat dirname grep awk sed tr date mkdir; do
  p="$(command -v "$t")" || { echo "FAIL: this test needs '$t'"; exit 1; }
  ln -s "$p" "$NOJQ/$t"
done

GUARDS="ro-guard block-destructive-platform credential-guard"
INPUT='{"tool_name":"Bash","tool_input":{"command":"ls"}}'

for g in $GUARDS; do
  hook="$ROOT/hooks/$g/$g.sh"

  # With jq and a harmless command, the guard lets it through
  out="$(printf '%s' "$INPUT" | "$hook" 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && [ -z "$out" ]; } || { echo "FAIL: $g should pass 'ls' (rc=$rc): $out"; fail=1; }

  # Without jq: exit 2, and the reason names jq
  out="$(printf '%s' "$INPUT" | PATH="$NOJQ" "$hook" 2>&1)"; rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: $g without jq should block with exit 2, got $rc: $out"; fail=1; }
  case "$out" in *"$g: jq is not installed"*) ;; *) echo "FAIL: $g without jq does not say why: $out"; fail=1 ;; esac

  # An input that is not JSON: exit 2
  out="$(printf '%s' 'not json {' | "$hook" 2>&1)"; rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: $g with a broken input should block with exit 2, got $rc: $out"; fail=1; }
  case "$out" in *"$g: cannot read the hook input"*) ;; *) echo "FAIL: $g with a broken input does not say why: $out"; fail=1 ;; esac
done

# An awk that fails (the awk of another system that rejects the program): the two guards that parse with awk
# block instead of seeing an empty command line
BADAWK="$TMP/badawk"; mkdir -p "$BADAWK"
printf '#!/bin/sh\ncat >/dev/null\necho "awk: syntax error" >&2\nexit 2\n' > "$BADAWK/awk"; chmod +x "$BADAWK/awk"
: > "$RO_MODE_FILE"   # ro-guard parses the command only in read-only mode
for g in ro-guard credential-guard; do
  out="$(printf '%s' "$INPUT" | PATH="$BADAWK:$PATH" "$ROOT/hooks/$g/$g.sh" 2>&1)"; rc=$?
  [ "$rc" = 2 ] || { echo "FAIL: $g with a failing awk should block with exit 2, got $rc: $out"; fail=1; }
done

# The common parser needs its list of data commands (hooks/lib/cmdparse-data.txt): without it ro-guard blocks
out="$(printf '%s' "$INPUT" | CMDP_DATAFILE="$TMP/no-such-list.txt" "$ROOT/hooks/ro-guard/ro-guard.sh" 2>&1)"; rc=$?
[ "$rc" = 2 ] || { echo "FAIL: ro-guard without its list of data commands should block with exit 2, got $rc: $out"; fail=1; }
# ... and an awk that prints something that is not a verdict is a broken tool, not a pass
printf '#!/bin/sh\ncat >/dev/null\necho "garbage"\n' > "$BADAWK/awk"
out="$(printf '%s' "$INPUT" | PATH="$BADAWK:$PATH" "$ROOT/hooks/ro-guard/ro-guard.sh" 2>&1)"; rc=$?
[ "$rc" = 2 ] || { echo "FAIL: ro-guard with an awk that prints garbage should block with exit 2, got $rc: $out"; fail=1; }
rm -f "$RO_MODE_FILE"

# The Read tool goes through credential-guard too: blocked without jq
out="$(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/tmp/notes.md"}}' | PATH="$NOJQ" "$ROOT/hooks/credential-guard/credential-guard.sh" 2>&1)"; rc=$?
[ "$rc" = 2 ] || { echo "FAIL: credential-guard without jq should block the Read tool, got $rc: $out"; fail=1; }

if [ "$fail" = 0 ]; then echo "fail-closed: all tests passed"; else echo "fail-closed: tests FAILED"; exit 1; fi
