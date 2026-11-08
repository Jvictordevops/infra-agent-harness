# shellcheck shell=bash
# Read keys from <repo root>/.harness.conf (lines "key=value"). The file is parsed as data:
# nothing in it is executed.
#
#   . bin/lib/conf.sh
#   conf_get "$repo_root" language     # last value of the key, or empty
#   conf_method "$repo_root"           # light | full  (IAH_METHOD > .harness.conf > light)

# conf_get <repo root> <key> -> value (empty when the file or the key is missing)
conf_get() {
  [ -n "${1:-}" ] && [ -f "$1/.harness.conf" ] || return 0
  sed -n -E "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*([^[:space:]#]*).*\$/\\1/p" "$1/.harness.conf" | tail -1
}

# conf_method [repo root] -> "light" or "full". An invalid value warns on stderr and gives "full".
conf_method() {
  local m="${IAH_METHOD:-}"
  [ -n "$m" ] || m="$(conf_get "${1:-}" method)"
  case "${m:-light}" in
    light|full) printf '%s' "${m:-light}" ;;
    *) echo "conf: invalid method '$m' (use light|full), using full" >&2; printf 'full' ;;
  esac
}
