#!/usr/bin/env bash
# Tests for 'bin/doctor --security' (bin/lib/security-check.sh). Fake HOME, fake settings, a fake 'ro' with fixed
# answers, marker values in the environment: nothing real is read, and no value may ever reach the output.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ko() { echo "FAIL: $*"; fail=1; }
has() { grep -qF -- "$2" <<<"$OUT" || ko "$1: output lacks '$2'"; }
hasnt() { grep -qF -- "$2" <<<"$OUT" && ko "$1: output has '$2'"; true; }

mkdir -p "$TMP/home/.claude" "$TMP/bin" "$TMP/repo/.claude"
export HOME="$TMP/home" IAH_PROFILE_FILE="$TMP/profile" RO_MODE_FILE="$TMP/ro-mode" IAH_RO_BIN="$TMP/bin/ro" IAH_NO_FETCH=1
unset RO_PROFILES RO_CONTEXTS IAH_REPO
# a clean base: no credential variable of the machine reaches the tests
for v in $(compgen -e); do case "$v" in *_TOKEN|*_SECRET|*_PASSWORD|AWS_*|AZURE_*|GOOGLE_APPLICATION_CREDENTIALS|KUBECONFIG) unset "$v" ;; esac; done

# fake ro: aws -> a role ARN, kubectl -> $TMP/k8s-answer; records its calls
cat > "$TMP/bin/ro" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_RO_LOG"
case "$1" in
  aws) case "$5" in broken) exit 1 ;; esac
       printf '{"UserId":"X","Account":"123456789012","Arn":"arn:aws:sts::123456789012:assumed-role/%s/session"}\n' "${FAKE_ROLE:-reader}" ;;
  kubectl) cat "$FAKE_K8S" 2>/dev/null || exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/ro"
export FAKE_RO_LOG="$TMP/ro.log" FAKE_K8S="$TMP/k8s"

run() { OUT="$(cd "$TMP/repo" && IAH_REPO="$TMP/repo" bash "$ROOT/bin/doctor" --security "$@" 2>&1)"; RC=$?; }
reset() { rm -f "$IAH_PROFILE_FILE" "$RO_MODE_FILE" "$FAKE_RO_LOG" "$FAKE_K8S" "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" "$TMP/repo/.claude/"*; unset RO_PROFILES RO_CONTEXTS; }

# --- 0. profile and environment are always shown
reset; run --no-network
has "base" "profile: standard"; has "base" "environment: not defined"; has "base" "packs:"
[ "$RC" = 0 ] || ko "base: exit $RC"
echo "profile=strict" > "$IAH_PROFILE_FILE"; run --no-network; has "strict shown" "profile: strict"

# --- 1. read-only mode
reset; run --no-network; has "mode off" "read-only mode is off"
echo "2026-11-13" > "$RO_MODE_FILE"; run --no-network; has "mode on" "read-only mode is on"; hasnt "mode on" "read-only mode is off"

# --- 2. sandbox: only strict asks
reset; run --no-network; has "standard sandbox" "not asked by profile standard"
echo "profile=strict" > "$IAH_PROFILE_FILE"; run --no-network; has "strict, no sandbox" "profile strict asks for it"
echo '{"sandbox":{"enabled":true}}' > "$HOME/.claude/settings.json"; run --no-network; has "strict, sandbox" "sandbox: on (profile strict)"

# --- 3. permission prompts off: user, local and repo settings
reset; echo '{"permissions":{"defaultMode":"bypassPermissions"}}' > "$HOME/.claude/settings.json"; run --no-network
has "bypass standard" "WARN  permission prompts turned off"; has "bypass standard" "defaultMode=bypassPermissions"; [ "$RC" = 0 ] || ko "bypass standard: exit $RC"
reset; echo '{"skipDangerousModePermissionPrompt":true}' > "$HOME/.claude/settings.local.json"; run --no-network; has "skip prompt, local" "skipDangerousModePermissionPrompt=true"
reset; echo '{"permissions":{"allow":["Bash(*)"]}}' > "$TMP/repo/.claude/settings.json"; run --no-network; has "Bash(*) in repo" "permissions.allow has Bash(*)"
reset; echo '{"permissions":{"allow":["Bash(git status)"]}}' > "$HOME/.claude/settings.json"; run --no-network; has "narrow allow" "no settings file turns the permission prompts off"
echo "profile=strict" > "$IAH_PROFILE_FILE"; echo '{"permissions":{"defaultMode":"bypassPermissions"},"sandbox":{"enabled":true}}' > "$HOME/.claude/settings.json"
run --no-network; has "bypass strict" "FAIL  permission prompts turned off"; [ "$RC" = 1 ] || ko "bypass strict: exit $RC, expected 1"
reset; run --no-network; has "no settings file" "no settings file turns the permission prompts off"

# --- 4. credential variables: names, never values
reset; run --no-network; has "no creds" "no credential variables"
AWS_SESSION_TOKEN="SECRET-VALUE-aaa" MY_API_SECRET="SECRET-VALUE-bbb" KUBECONFIG="SECRET-VALUE-ccc" DB_PASSWORD="SECRET-VALUE-ddd" run --no-network
has "creds" "AWS_SESSION_TOKEN"; has "creds" "MY_API_SECRET"; has "creds" "KUBECONFIG"; has "creds" "DB_PASSWORD"; hasnt "creds" "SECRET-VALUE"
AWS_REGION="eu-west-1" run --no-network; has "harmless var" "no credential variables"

# --- 5. role: shown, never judged
reset; export RO_PROFILES="dev" RO_CONTEXTS="c1"; run --no-network; hasnt "no network" "AWS profile"; has "no network" "not looked at"; [ ! -f "$FAKE_RO_LOG" ] || ko "--no-network called ro"
reset; run; has "no RO_PROFILES" "RO_PROFILES is empty"; has "no RO_CONTEXTS" "RO_CONTEXTS is empty"
reset; export RO_PROFILES="dev,prod"; run
has "role shown" "AWS profile 'dev' uses 'reader'"; has "role shown 2" "AWS profile 'prod' uses 'reader'"; has "not checked" "Whether it can write is not checked"
hasnt "account id" "123456789012"; grep -q "sts get-caller-identity --profile dev" "$FAKE_RO_LOG" || ko "ro not called for dev"
[ "$(wc -l < "$FAKE_RO_LOG")" = 2 ] || ko "ro calls: $(wc -l < "$FAKE_RO_LOG"), expected 2 (AWS only; no RO_CONTEXTS)"
reset; export RO_PROFILES="broken"; run; has "ro fails" "AWS profile 'broken': the role could not be shown"; [ "$RC" = 0 ] || ko "ro fails: exit $RC"
reset; export RO_PROFILES="dev"; FAKE_ROLE="admin" run; has "admin role is only shown" "uses 'admin'"; hasnt "admin role is only shown" "FAIL"
# nothing in the check calls anything but sts get-caller-identity and kubectl auth can-i
reset; export RO_PROFILES="dev" RO_CONTEXTS="c1"; printf 'Resources  Verbs\npods  [get list]\n' > "$FAKE_K8S"; run
grep -vE '^(aws sts get-caller-identity --profile dev|kubectl auth can-i --list --context c1)$' "$FAKE_RO_LOG" && ko "ro called with something else"
has "k8s read only" "Kubernetes context 'c1': 'auth can-i --list' shows no create"
printf 'Resources  Verbs\npods  [get list delete]\n' > "$FAKE_K8S"; run; has "k8s delete" "Kubernetes context 'c1': the role can change things"
printf 'Resources  Verbs\n*.*  [*]\n' > "$FAKE_K8S"; run; has "k8s wildcard" "the role can change things"
rm -f "$FAKE_K8S"; run; has "k8s no answer" "Kubernetes context 'c1': permissions could not be checked"

# --- doctor itself: flags, and nothing written
reset; OUT="$(bash "$ROOT/bin/doctor" --no-network 2>&1)"; [ $? = 2 ] || ko "--no-network alone must be refused"
OUT="$(bash "$ROOT/bin/doctor" --security --tests 2>&1)"; [ $? = 2 ] || ko "--security --tests must be refused"
reset; before="$(find "$TMP/home" "$TMP/repo" -type f -exec cksum {} + | sort | cksum)"; run; after="$(find "$TMP/home" "$TMP/repo" -type f -exec cksum {} + | sort | cksum)"
[ "$before" = "$after" ] || ko "--security wrote into HOME or the repo"

[ "$fail" = 0 ] && echo "doctor-security: ok" || exit 1
