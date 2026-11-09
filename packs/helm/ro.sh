# shellcheck shell=bash
# Pack helm: bin/ro validator for 'helm'. Sourced by bin/ro, which provides deny, opt_val, in_list and lower.
# Only list, status, history, version and 'get metadata' (values and manifests may hold secrets).
ro_tool helm

check_helm() {
  local ctx a
  ctx="$(opt_val --kube-context "$@")" || deny "helm: --kube-context is mandatory"
  in_list "$ctx" "${RO_CONTEXTS-}" || deny "helm: context $ctx not in RO_CONTEXTS ($RO_CONTEXTS)"
  case "${1-}" in
    list|ls|status|history|version) ;;
    get) [ "${2-}" = metadata ] || deny "helm: only 'get metadata' (values and manifests may hold secrets)" ;;
    *) deny "helm: '${1-}' not allowed" ;;
  esac
  for a in "$@"; do
    case "$a" in --kubeconfig*|--kube-token*|--kube-as-*|--kube-apiserver*|--post-renderer*) deny "helm: $a not allowed" ;; esac
  done
}
