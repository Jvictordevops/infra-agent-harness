# shellcheck shell=bash
# Security profile of this machine: ~/.config/infra-agent-harness/profile (IAH_PROFILE_FILE overrides), lines "key=value":
#   profile=permissive|standard|strict      default standard ('isolated' comes with the container, v0.2)
#   packs=all|none|<comma list>             packs whose permissions are used; default all installed packs
# Parsed as data, never sourced. Only the user changes it (bin/security-profile set, from a terminal); ro-guard
# blocks agents from touching it. Choosing packs only takes permissions away, never blocks (packs/README.md).
#
#   . bin/lib/packs.sh; . bin/lib/profile.sh
#   profile_file                       # path of the profile file
#   profile_raw <key>                  # value of <key> as written (spaces removed), or empty
#   profile_name                       # permissive | standard | strict; missing or invalid -> standard
#   profile_packs <harness>            # chosen packs that are installed, one per line, in name order
#   profile_unknown_packs <harness>    # names in packs= that are not installed, one per line
# Bash 3.2 compatible. profile_packs and profile_unknown_packs glob: callers with 'set -f' turn it off around them.

profile_file() { printf '%s' "${IAH_PROFILE_FILE:-$HOME/.config/infra-agent-harness/profile}"; }

profile_raw() {
  local f; f="$(profile_file)"
  [ -f "$f" ] || return 0
  sed -n -E "s/^[[:space:]]*$1[[:space:]]*=([^#]*).*\$/\\1/p" "$f" | tail -1 | tr -d ' \t\r'
}

profile_name() {
  local p; p="$(profile_raw profile)"
  case "$p" in permissive|standard|strict) printf '%s\n' "$p" ;; *) echo standard ;; esac
}

profile_packs() {
  local want n; want="$(profile_raw packs)"
  case "$want" in none) return 0 ;; ''|all) packs_names "$1"; return 0 ;; esac
  packs_names "$1" | while IFS= read -r n; do
    case ",$want," in *",$n,"*) printf '%s\n' "$n" ;; esac
  done
}

profile_unknown_packs() {
  local want n installed; want="$(profile_raw packs)"
  case "$want" in ''|all|none) return 0 ;; esac
  installed=" $(packs_names "$1" | tr '\n' ' ')"
  printf '%s\n' "$want" | tr ',' '\n' | while IFS= read -r n; do
    [ -z "$n" ] && continue
    case "$installed" in *" $n "*) ;; *) printf '%s\n' "$n" ;; esac
  done
}
