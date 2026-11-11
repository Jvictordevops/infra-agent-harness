# shellcheck shell=bash
# Pack helm: bin/ro validator for 'helm'. Sourced by bin/ro, which provides deny, opt_val, in_list and lower.
# Only list, status (as a table), history, version and 'get metadata' (values and manifests may hold secrets).
ro_tool helm

check_helm() {
  local ctx a
  opt_once --kube-context "$@"
  ctx="$(opt_val --kube-context "$@")" || deny "helm: --kube-context is mandatory"
  in_list "$ctx" "${RO_CONTEXTS-}" || deny "helm: context $ctx not in RO_CONTEXTS ($RO_CONTEXTS)"
  case "${1-}" in
    list|ls|status|history|version) ;;
    get) [ "${2-}" = metadata ] || deny "helm: only 'get metadata' (values and manifests may hold secrets)" ;;
    *) deny "helm: '${1-}' not allowed" ;;
  esac
  if [ "${1-}" = status ]; then   # as json or yaml, status carries the values and the manifest of the release
    for a in "$@"; do
      case "$a" in -o|-o*|--output|--output=*) deny "helm: status only as a table ($a: json and yaml carry values and manifests, which may hold secrets)" ;; esac
    done
  fi
  for a in "$@"; do
    case "$a" in --kubeconfig*|--kube-token*|--kube-as-*|--kube-apiserver*|--post-renderer*) deny "helm: $a not allowed" ;; esac
  done
}
