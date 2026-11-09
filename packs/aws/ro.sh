# shellcheck shell=bash
# Pack aws: bin/ro validator for 'aws'. Sourced by bin/ro, which provides deny, opt_val, in_list and lower.
# Only reads: describe-/list-/get-/batch-get-/lookup-/search-, s3 ls; never secrets or credentials.
ro_tool aws

check_aws() {
  local svc="${1-}" op="${2-}" p a
  [[ "$svc" =~ ^[a-z0-9-]+$ && "$op" =~ ^[a-z0-9-]+$ ]] || deny "aws: use 'aws <service> <operation> …'"
  p="$(opt_val --profile "$@")" || deny "aws: --profile is mandatory"
  in_list "$p" "${RO_PROFILES-}" || deny "aws: profile $p not in RO_PROFILES ($RO_PROFILES)"
  case "$op" in
    *token*|*password*|*secret-value*|*credential*|*login*|*decrypt*) deny "aws: $op returns secrets or credentials" ;;
  esac
  case "$svc $op" in
    "sts get-caller-identity"|"s3 ls") ;;
    sts\ *|sso\ *|sso-oidc\ *|"s3api get-object"*|"secretsmanager get-"*) deny "aws: $svc $op not allowed" ;;
    s3\ *) deny "aws: only 's3 ls' in s3" ;;
    *) [[ "$op" =~ ^(describe|list|get|batch-get|lookup|search)- ]] || [ "$op" = filter-log-events ] \
         || deny "aws: $op is not read-only (describe-/list-/get-/batch-get-/lookup-/search-)" ;;
  esac
  for a in "$@"; do
    case "$a" in --with-decryption|--endpoint-url|--endpoint-url=*|--debug) deny "aws: $a not allowed" ;; esac
  done
}
