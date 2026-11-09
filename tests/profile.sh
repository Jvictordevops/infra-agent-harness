#!/usr/bin/env bash
# Tests for the security profile: bin/lib/profile.sh, bin/security-profile, the packs bin/ro accepts and ro-guard
# protecting the profile in every mode. Runs nothing real: temp profile files, bin/ro --check, the hook fed JSON.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export IAH_HOOK_LOG="$TMP/hook-decisions.jsonl" RO_MODE_FILE="$TMP/ro-mode" RO_ROOTS="$TMP" IAH_PROFILE_FILE="$TMP/profile"
unset RO_PROFILES RO_CONTEXTS
export IAH_SANDBOX_TOOLS=sh   # 'set strict' checks the sandbox tools on Linux; the runners need not have bwrap
# shellcheck source=bin/lib/packs.sh
. "$ROOT/bin/lib/packs.sh"
# shellcheck source=bin/lib/profile.sh
. "$ROOT/bin/lib/profile.sh"
SP="$ROOT/bin/security-profile"
ALL="$(packs_names "$ROOT" | paste -sd' ' -)"
fail=0
ko() { echo "FAIL: $*"; fail=1; }
eq() { [ "$2" = "$3" ] || ko "$1: expected '$3', got '$2'"; }
prof() { printf '%s\n' "$@" > "$IAH_PROFILE_FILE"; }
chosen() { profile_packs "$ROOT" | paste -sd' ' -; }

# --- library
rm -f "$IAH_PROFILE_FILE"
eq "no file: profile" "$(profile_name)" standard
eq "no file: packs" "$(chosen)" "$ALL"
prof "profile=strict" "packs=aws,helm"
eq "strict: profile" "$(profile_name)" strict
eq "strict: packs" "$(chosen)" "aws helm"
prof "  profile = permissive  # comment" "packs = kubernetes, aws"
eq "spaces and comment: profile" "$(profile_name)" permissive
eq "spaces: packs in name order" "$(chosen)" "aws kubernetes"
prof "profile=bogus"
eq "invalid profile" "$(profile_name)" standard
prof "profile=isolated"
eq "isolated is not available yet" "$(profile_name)" standard
prof "packs=none"
eq "packs=none" "$(chosen)" ""
prof "packs=all"
eq "packs=all" "$(chosen)" "$ALL"
prof "packs=aws,gcp,kubernetes"
eq "unknown pack ignored" "$(chosen)" "aws kubernetes"
eq "unknown pack listed" "$(profile_unknown_packs "$ROOT" | paste -sd' ' -)" "gcp"
prof "profile=strict" "profile=permissive"
eq "last line wins" "$(profile_name)" permissive

# --- bin/security-profile
rm -f "$IAH_PROFILE_FILE"
out="$("$SP" show 2>&1)" || ko "show without file fails"
case "$out" in *"profile: standard"*"missing: defaults"*) ;; *) ko "show without file: $out" ;; esac
"$SP" set strict >/dev/null 2>&1 || ko "set strict fails"
eq "set strict" "$(profile_name)" strict
"$SP" set strict --packs aws,kubernetes >/dev/null 2>&1 || ko "set --packs fails"
eq "set --packs" "$(chosen)" "aws kubernetes"
if [ "$(uname -s)" = Linux ]; then
  out="$(IAH_SANDBOX_TOOLS="sh no-such-tool-iah" "$SP" set strict --packs aws 2>&1)" && ko "set strict without a sandbox tool works"
  case "$out" in *"strict needs 'no-such-tool-iah'"*"apt-get install bubblewrap socat"*) ;; *) ko "set strict without a sandbox tool: $out" ;; esac
  eq "set strict refused: packs unchanged" "$(chosen)" "aws kubernetes"
fi
"$SP" set standard >/dev/null 2>&1 || ko "set standard fails"
eq "set keeps packs" "$(chosen)" "aws kubernetes"
eq "set keeps packs: profile" "$(profile_name)" standard
"$SP" set permissive --packs=none >/dev/null 2>&1 || ko "set --packs=none fails"
eq "set --packs=none" "$(chosen)" ""
before="$(cat "$IAH_PROFILE_FILE")"
for bad in "set isolated" "set bogus" "set strict --packs gcp" "set strict --packs ../aws" "set" "set strict --packs" "nonsense"; do
  # shellcheck disable=SC2086  # split the case into words on purpose
  if "$SP" $bad >/dev/null 2>&1; then ko "security-profile $bad should fail"; fi
done
eq "failed sets leave the file alone" "$(cat "$IAH_PROFILE_FILE")" "$before"
out="$("$SP" set isolated 2>&1)"; case "$out" in *v0.2*) ;; *) ko "isolated says v0.2: $out" ;; esac
for f in "$TMP"/profile.*; do [ -e "$f" ] && ko "temp file left next to the profile: $f"; done

# --- bin/ro accepts only the tools of the chosen packs; the core is always there
ro_ok() { "$ROOT/bin/ro" --check "$@" >/dev/null 2>&1 || ko "ro should pass: $*"; }
ro_no() { if "$ROOT/bin/ro" --check "$@" >/dev/null 2>&1; then ko "ro should deny: $*"; fi; }
mkdir -p "$TMP/repo/.git"
prof "packs=kubernetes"
ro_ok kubectl get pods -A --context c
ro_no aws sts get-caller-identity --profile P
ro_no helm list -A --kube-context c
ro_ok git -C "$TMP/repo" log -5
out="$("$ROOT/bin/ro" --check aws sts get-caller-identity --profile P 2>&1)"
case "$out" in *"pack 'aws', not chosen"*) ;; *) ko "ro names the pack not chosen: $out" ;; esac
prof "packs=none"
ro_no kubectl get pods -A --context c
ro_ok git -C "$TMP/repo" log -5
out="$("$ROOT/bin/ro" --check terraform plan 2>&1)"
case "$out" in *"not allowed (git, gh"*) ;; *) ko "ro lists only the core with packs=none: $out" ;; esac
rm -f "$IAH_PROFILE_FILE"
ro_ok aws sts get-caller-identity --profile P
ro_ok helm list -A --kube-context c

# --- ro-guard protects the profile, with read-only mode off and on
hook() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | "$ROOT/hooks/ro-guard/ro-guard.sh" >/dev/null 2>&1; }
for mode in off on; do
  if [ "$mode" = on ]; then : > "$RO_MODE_FILE"; else rm -f "$RO_MODE_FILE"; fi
  for c in "security-profile set permissive" "bin/security-profile  set strict --packs none" \
           "/x/plugins/cache/h/bin/security-profile set standard" "cd /tmp && security-profile set permissive" \
           "echo profile=permissive > ~/.config/infra-agent-harness/profile" \
           "rm ~/.config/infra-agent-harness/profile" "cat \$HOME/.config/infra-agent-harness/profile" \
           "IAH_PROFILE_FILE=/tmp/p bin/ro aws s3 ls" "export IAH_PROFILE_FILE=/tmp/p"; do
    hook "$c"; [ $? = 2 ] || ko "ro-guard (mode $mode) should block: $c"
  done
  for c in "security-profile show" "security-profile" "ls ~/.config/infra-agent-harness/profiles-notes" \
           "cat tests/profile.sh" "git log --oneline -3"; do
    hook "$c" || ko "ro-guard (mode $mode) should allow: $c"
  done
done
rm -f "$RO_MODE_FILE"
grep -q '"reason":"security profile"' "$IAH_HOOK_LOG" || ko "the block is in the decision log"

# --- the Edit tool cannot change the profile or the mode file (core deny rules)
perms="$(packs_permissions "$ROOT")"
for r in "Edit(~/.config/infra-agent-harness/profile)" "Edit(~/.config/infra-agent-harness/ro-mode)"; do
  jq -e --arg r "$r" '.deny | index($r)' <<<"$perms" >/dev/null || ko "core deny rule missing: $r"
done

if [ "$fail" = 0 ]; then echo "profile: all tests passed"; else echo "profile: tests FAILED"; exit 1; fi
