# shellcheck shell=bash
# Rule packs (packs/<name>/, format in packs/README.md). Every pack under packs/ is active.
#
#   . bin/lib/packs.sh
#   packs_names "$harness"         # pack names, one per line, in name order
#   packs_permissions "$harness"   # {"deny": […], "ask": […]}: hooks/settings.base.json (core) + packs/*/permissions.json
#                                  # + Read(…) deny rules for the credential files (hooks/lib/credentials.sh)
#   packs_profile_permissions "$harness" "$profile"   # the same for one security profile, plus "drop": the ask
#                                  # rules settings.json must not have (permissive: the asks of the packs)
#   packs_sandbox "$harness" "$profile"   # the sandbox block of the strict profile (needs bin/lib/profile.sh)
#
# Needs jq for packs_permissions and packs_sandbox.

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

# The rules a security profile puts in settings.json: {"deny": […], "ask": […], "drop": […]}. 'drop' is the ask
# rules link-harness removes from settings.json. permissive: no pack asks (apply, install, upgrade); the core
# asks (git force push, hard reset) and every deny rule stay: permissive means no platform questions, nothing else.
# Other profiles: everything, drop empty.
packs_profile_permissions() { # $1 harness, $2 profile name (profile_name)
  local all
  all="$(packs_permissions "$1")" || return 1
  jq -c --arg p "$2" --slurpfile b "$1/hooks/settings.base.json" '
    (($b[0].permissions.ask // [])) as $core
    | if $p == "permissive" then (.ask - $core) as $pack | {deny, ask: (.ask - $pack), drop: $pack}
      else {deny, ask, drop: []} end
  ' <<<"$all"
}

_packs_lines() { # files -> their lines without comments, blank lines and trailing spaces (missing files skipped)
  local f line
  for f in "$@"; do
    [ -f "$f" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%[[:space:]]#*}"; line="${line%"${line##*[![:space:]]}"}"
      case "$line" in ''|'#'*) continue ;; esac
      printf '%s\n' "$line"
    done < "$f"
  done
}

# The sandbox of the strict profile (ro runs outside it, the credential files are denied inside it as a third
# lock, and a domain not listed is refused without asking), as
# {"strict": bool, "excluded": […], "domains": […], "all_domains": […], "creds": [{path, mode}…]}:
#   excluded     commands that run outside the sandbox: core .sandbox.excludedCommands (ro, the read-only gate,
#                reads the cloud credentials itself)
#   domains      allowed domains: core .sandbox.network.allowedDomains + packs/<chosen>/domains
#   all_domains  the same with every installed pack: what link-harness takes back for the packs not chosen
#   creds        one deny entry per credential pattern of the core and every pack, chosen or not (the floor).
#                '~/<path>' as is; '**/<name>' relative, so Claude Code anchors it at the session's working
#                directory (an absolute '/**/<name>' starts with a glob, which the Linux sandbox skips).
# A domain not listed is refused in every permission mode (link-harness sets network.strictAllowlist): asking
# was not enough, because auto mode let an unlisted domain through without asking.
packs_sandbox() { # $1 harness, $2 profile name (profile_name)
  local h="$1" n chosen all creds
  chosen="$(profile_packs "$h" | while IFS= read -r n; do _packs_lines "$h/packs/$n/domains"; done | jq -R . | jq -sc .)" || return 1
  all="$(packs_names "$h" | while IFS= read -r n; do _packs_lines "$h/packs/$n/domains"; done | jq -R . | jq -sc .)" || return 1
  # shellcheck source=hooks/lib/credentials.sh
  . "$h/hooks/lib/credentials.sh"
  creds="$(cred_patterns "$h" | jq -R '{path: ., mode: "deny"}' | jq -sc .)" || return 1
  jq -c --arg p "$2" --argjson chosen "$chosen" --argjson all "$all" --argjson creds "$creds" '
    def uniq_keep: reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end);
    (.sandbox // {}) as $c
    | {strict: ($p == "strict"),
       excluded: (($c.excludedCommands // []) | uniq_keep),
       domains: ([($c.network.allowedDomains // [])[], $chosen[]] | uniq_keep),
       all_domains: ([($c.network.allowedDomains // [])[], $all[]] | uniq_keep),
       creds: ($creds | uniq_keep)}
  ' "$h/hooks/settings.base.json"
}
