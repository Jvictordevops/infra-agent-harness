# shellcheck shell=bash
# Read keys from <repo root>/.harness.conf (lines "key=value"). The file is parsed as data:
# nothing in it is executed.
#
#   . bin/lib/conf.sh
#   conf_get "$repo_root" language     # last value of the key, or empty
#   conf_method "$repo_root"           # light | full  (IAH_METHOD > .harness.conf > light)
#   conf_modules "$repo_root"          # active optional modules, one per line (IAH_MODULES > .harness.conf)
#   conf_denylist "$repo_root"         # path of the private denylist, or empty (IAH_DENYLIST > denylist= in .harness.conf)

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

# conf_denylist [repo root] -> path of the private denylist, or empty when none is configured.
# IAH_DENYLIST (a path, used as is) wins; else "denylist=<path relative to the repo root>" in .harness.conf
# (an absolute path is accepted as is). The file need not exist: callers check.
conf_denylist() {
  local d="${IAH_DENYLIST:-}"
  [ -n "$d" ] || d="$(conf_get "${1:-}" denylist)"
  [ -n "$d" ] || return 0
  case "$d" in /*) printf '%s' "$d" ;; *) printf '%s/%s' "${1:-.}" "$d" ;; esac
}

# plugin_mode -> exit 0 when the harness is installed as a Claude Code plugin on this machine
# (~/.claude/plugins/installed_plugins.json mentions "infra-agent-harness@"). IAH_PLUGIN=1|0 overrides.
plugin_mode() {
  local f="$HOME/.claude/plugins/installed_plugins.json"
  case "${IAH_PLUGIN:-}" in 1) return 0 ;; 0) return 1 ;; esac
  [ -f "$f" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e 'tostring | contains("infra-agent-harness@")' "$f" >/dev/null 2>&1
  else
    grep -q 'infra-agent-harness@' "$f"
  fi
}

# stable_link -> path of the symlink that always points at the installed plugin (see hooks/stable-link)
stable_link() { printf '%s' "${IAH_STABLE_LINK:-$HOME/.local/share/infra-agent-harness/current}"; }
