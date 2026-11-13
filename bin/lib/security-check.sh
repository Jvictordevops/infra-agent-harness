# shellcheck shell=bash
# Checks of 'bin/doctor --security': is this machine set up as docs/threat-model.md recommends ("What to set up, in
# order")? Read-only, and it never prints the value of a variable or a credential: only names. Sourced by bin/doctor,
# which provides ok/warn/fail (they only append to an array), HARNESS, REPO and the profile/packs libraries.
#
#   security_checks [--no-network]
#
# Overrides for the tests: RO_MODE_FILE (mode file), IAH_RO_BIN (the 'ro' to call), IAH_SECURITY_SETTINGS (settings.json
# of the user). The role of the cloud is only SHOWN (ro sts get-caller-identity, already allowed): whether it can write
# is not checked, because that would need a new operation in 'ro'. Kubernetes: ro kubectl auth can-i --list.
# Bash 3.2 compatible.

# Names of environment variables that give an agent a cloud or tool credential (exact names; *_TOKEN/*_SECRET/*_PASSWORD below)
_SEC_ENV_NAMES=" AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AZURE_CLIENT_SECRET GOOGLE_APPLICATION_CREDENTIALS KUBECONFIG VAULT_TOKEN "

# Settings files that can leave the permission prompts off: $1 = path. Prints what it finds, one phrase per line.
_sec_bypass_in() {
  [ -f "$1" ] || return 0
  jq -r '
    (if .permissions.defaultMode == "bypassPermissions" then "permissions.defaultMode=bypassPermissions" else empty end),
    (if .skipDangerousModePermissionPrompt == true then "skipDangerousModePermissionPrompt=true" else empty end),
    (if ((.permissions.allow // []) | map(select(. == "Bash" or . == "Bash(*)")) | length) > 0 then "permissions.allow has Bash(*)" else empty end)
  ' "$1" 2>/dev/null
}

security_checks() {
  local nonet=0 a
  for a in "$@"; do [ "$a" = --no-network ] && nonet=1; done
  local ro_bin="${IAH_RO_BIN:-$HARNESS/bin/ro}"
  local mode="${RO_MODE_FILE:-$HOME/.config/infra-agent-harness/ro-mode}"
  local settings="${IAH_SECURITY_SETTINGS:-$HOME/.claude/settings.json}"
  local prof packs

  # 0. Profile and environment: always shown
  prof="$(profile_name)"; packs="$(profile_packs "$HARNESS" | paste -sd, -)"
  ok "profile: $prof · packs: ${packs:-none} · environment: not defined (7.4)"

  # 1. Read-only mode
  if [ -f "$mode" ]; then ok "read-only mode is on (ro mode status)"
  else warn "read-only mode is off: ro mode on (before you open the session). With it off the agent can reach clouds and clusters directly"; fi

  # 2. Sandbox: only the strict profile asks for it
  if [ "$prof" = strict ]; then
    if jq -e '.sandbox.enabled == true' "$settings" >/dev/null 2>&1; then ok "sandbox: on (profile strict)"
    else warn "sandbox: profile strict asks for it but settings.json has it off: bin/link-harness (docs/tools.md)"; fi
  else
    ok "sandbox: not asked by profile $prof (strict turns it on; docs/tools.md)"
  fi

  # 3. Permission prompts left off, in the settings the agent loads
  local f out found="" repo_files=""
  [ -n "${REPO:-}" ] && repo_files="$REPO/.claude/settings.json $REPO/.claude/settings.local.json"
  for f in "$settings" "$(dirname "$settings")/settings.local.json" $repo_files; do
    out="$(_sec_bypass_in "$f")"
    [ -z "$out" ] || found="$found
        $f: $(printf '%s' "$out" | paste -sd, -)"
  done
  if [ -z "$found" ]; then
    ok "no settings file turns the permission prompts off (limit: the flag of a session already open is not visible from here)"
  elif [ "$prof" = strict ]; then
    fail "permission prompts turned off, and profile strict does not allow it:$found
        Remove those entries."
  else
    warn "permission prompts turned off:$found
        Remove those entries unless you want it. Limit: the flag of a session already open is not visible from here."
  fi

  # 4. Credentials in the environment of the agent (names only; compgen -e never prints values)
  local names="" n
  for n in $(compgen -e); do
    case "$n" in CLAUDE_CODE_*) continue ;; esac   # variables of Claude Code itself, not the user's credentials
    case "$_SEC_ENV_NAMES" in *" $n "*) names="$names $n"; continue ;; esac
    case "$n" in *_TOKEN|*_SECRET|*_PASSWORD) names="$names $n" ;; esac
  done
  if [ -z "$names" ]; then ok "no credential variables in the environment"
  else warn "credential variables in the environment:$names. The agent inherits them: take them out of your shell start and use a profile (--profile) or 'ro'"; fi

  # 5. Role the agent uses (shown, not judged)
  if [ "$nonet" = 1 ]; then
    ok "cloud role and cluster permissions: not looked at (--no-network)"
    return 0
  fi
  local p arn role
  if [ -n "${RO_PROFILES-}" ]; then
    for p in $(printf '%s' "$RO_PROFILES" | tr ',' ' '); do
      arn="$("$ro_bin" aws sts get-caller-identity --profile "$p" 2>/dev/null | jq -r '.Arn // empty' 2>/dev/null)"
      if [ -n "$arn" ]; then
        role="${arn##*:}"; role="${role#assumed-role/}"; role="${role%%/*}"; role="${role#role/}"
        ok "AWS profile '$p' uses '${role:-unknown}'. Whether it can write is not checked: use a read-only role for the agent (docs/threat-model.md)"
      else
        warn "AWS profile '$p': the role could not be shown (no network, expired login or ro refused). Use a read-only role for the agent"
      fi
    done
  else
    warn "RO_PROFILES is empty: the AWS role the agent uses could not be shown"
  fi
  if [ -n "${RO_CONTEXTS-}" ]; then
    for p in $(printf '%s' "$RO_CONTEXTS" | tr ',' ' '); do
      out="$("$ro_bin" kubectl auth can-i --list --context "$p" 2>/dev/null)" || out=""
      if [ -z "$out" ]; then
        warn "Kubernetes context '$p': permissions could not be checked (no access or ro refused)"
      elif printf '%s\n' "$out" | awk 'NR>1 && ($0 ~ /\*/ || $0 ~ /(create|delete|patch|update)/) {f=1} END {exit !f}'; then
        warn "Kubernetes context '$p': the role can change things (* or create/delete/patch/update in 'auth can-i --list'). Use a read-only role for the agent"
      else
        ok "Kubernetes context '$p': 'auth can-i --list' shows no create/delete/patch/update/*"
      fi
    done
  else
    warn "RO_CONTEXTS is empty: the Kubernetes permissions the agent has could not be checked"
  fi
  return 0
}
