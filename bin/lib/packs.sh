# shellcheck shell=bash
# Rule packs (packs/<name>/, format in packs/README.md). Every pack under packs/ is active.
#
#   . bin/lib/packs.sh
#   packs_names "$harness"         # pack names, one per line, in name order
#   packs_permissions "$harness"   # {"deny": […], "ask": […]}: hooks/settings.base.json (core) + packs/*/permissions.json
#                                  # + Read(…) deny rules for the credential files (hooks/lib/credentials.sh)
#
# Needs jq for packs_permissions.

packs_names() {
  local d
  for d in "$1"/packs/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; printf '%s\n' "${d##*/}"
  done
}

# Core rules first, then each pack in name order, then one Read(…) deny rule per credential file of the core and
# the packs (hooks/lib/credentials.sh); duplicates are dropped (first one kept).
packs_permissions() {
  local h="$1" p pfiles=() reads
  for p in "$h"/packs/*/permissions.json; do
    [ -f "$p" ] && pfiles+=("$p")
  done
  # shellcheck source=hooks/lib/credentials.sh
  . "$h/hooks/lib/credentials.sh"
  reads="$(cred_read_rules "$h")" || return 1
  jq -s --argjson reads "$reads" '
    def uniq_keep: reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end);
    (.[0].permissions // {}) as $core | .[1:] as $packs
    | {deny: ([($core.deny // [])[], ($packs[] | (.deny // [])[]), $reads[]] | uniq_keep),
       ask:  ([($core.ask  // [])[], ($packs[] | (.ask  // [])[])] | uniq_keep)}
  ' "$h/hooks/settings.base.json" ${pfiles[@]+"${pfiles[@]}"}
}
