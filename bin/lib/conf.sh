# shellcheck shell=bash
# Read keys from <repo root>/.harness.conf (lines "key=value"). The file is parsed as data:
# nothing in it is executed.
#
#   . bin/lib/conf.sh
#   conf_get "$repo_root" language     # last value of the key, or empty
#   conf_method "$repo_root"           # light | full  (IAH_METHOD > .harness.conf > light)
#   conf_modules "$repo_root"          # active optional modules, one per line (IAH_MODULES > .harness.conf)

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

# conf_modules [repo root] -> names of the active optional modules (modules/<name>/), one per line.
# .harness.conf: "modules=evidence,other" (comma list, no spaces). IAH_MODULES overrides it, even when empty.
conf_modules() {
  local m
  if [ -n "${IAH_MODULES+x}" ]; then m="$IAH_MODULES"
  elif [ -n "${1:-}" ] && [ -f "$1/.harness.conf" ]; then   # whole value: "a, b" is allowed
    m="$(sed -n -E 's/^[[:space:]]*modules[[:space:]]*=([^#]*).*$/\1/p' "$1/.harness.conf" | tail -1)"
  else m=""; fi
  printf '%s\n' "$m" | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$' || true
}
