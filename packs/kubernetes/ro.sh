# shellcheck shell=bash
# Pack kubernetes: bin/ro validator for 'kubectl'. Sourced by bin/ro, which provides deny, opt_val, in_list and lower.
# Only reads (get, describe, logs, top, events…), --context mandatory; Secrets are never read.
ro_tool kubectl

is_secret_res() { # $1 kubectl arg -> 0 if it names Secrets
  local t IFS=',/'
  for t in $1; do
    case "$(lower "$t")" in secret|secrets|secret.*|secrets.*) return 0 ;; esac
  done
  return 1
}

check_kubectl() {
  local ctx verb="${1-}" sub="${2-}" a
  opt_once --context "$@"
  ctx="$(opt_val --context "$@")" || deny "kubectl: --context is mandatory"
  in_list "$ctx" "${RO_CONTEXTS-}" || deny "kubectl: context $ctx not in RO_CONTEXTS ($RO_CONTEXTS)"
  case "$verb" in
    get|describe|api-resources|api-versions|version|explain|top|logs|events) ;;
    auth) case "$sub" in can-i|whoami) ;; *) deny "kubectl: auth $sub" ;; esac ;;
    cluster-info) [ "$sub" != dump ] || deny "kubectl: cluster-info dump" ;;
    *) deny "kubectl: verb '$verb' not allowed (the verb goes first)" ;;
  esac
  for a in "$@"; do
    case "$a" in
      --kubeconfig*|--as|--as=*|--as-group*|--as-uid*|--token*|--server*|-s|--username*|--password*|--client-key*|--client-certificate*|-w|--watch*|-f|--follow*|--filename*)
        deny "kubectl: $a not allowed" ;;
      --raw=*/secrets*|/api/*/secrets*) deny "kubectl: Secrets are never read" ;;
    esac
    if [ "$verb" = get ] || [ "$verb" = describe ]; then
      ! is_secret_res "$a" || deny "kubectl: Secrets are never read"
    fi
  done
}
