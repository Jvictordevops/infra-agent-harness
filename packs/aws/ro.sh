# shellcheck shell=bash
# Pack aws: bin/ro validator for 'aws'. Sourced by bin/ro, which provides deny, opt_val, in_list and lower.
# Only reads: describe-/list-/get-/batch-get-/lookup-/search-, s3 ls; never secrets or credentials.
# Sourced by bin/ro, which also provides opt_once.
ro_tool aws

# The aws CLI takes any unique prefix of an option (--with-decrypt, --endpoint, --prof): 0 if it would read
# $1 as the option $2
aws_abbrev() {
  local n="${1%%=*}"
  [ "${#n}" -ge 3 ] || return 1
  case "$2" in "$n"*) return 0 ;; esac
  return 1
}

check_aws() {
  local svc="${1-}" op="${2-}" p a
  [[ "$svc" =~ ^[a-z0-9-]+$ && "$op" =~ ^[a-z0-9-]+$ ]] || deny "aws: use 'aws <service> <operation> …'"
  for a in "$@"; do
    case "${a%%=*}" in --profile) ;; *) ! aws_abbrev "$a" --profile || deny "aws: write --profile in full, not $a" ;; esac
  done
  opt_once --profile "$@"
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
    if aws_abbrev "$a" --with-decryption || aws_abbrev "$a" --endpoint-url || aws_abbrev "$a" --debug; then
      deny "aws: $a not allowed (--with-decryption, --endpoint-url and --debug, also shortened)"
    fi
    # file:// and fileb:// load a local file into a parameter: any file of the machine would travel in the call
    case "$a" in *file://*|*fileb://*) deny "aws: $a not allowed (a parameter read from a local file)" ;; esac
  done
}
