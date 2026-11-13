#!/usr/bin/env bash
# Sourced by ro-guard. The paths agents never WRITE (reading and naming them is fine; the profile and the read-only
# mode file have their own, stricter protection in ro-guard):
#   F ~/.claude/settings.json, ~/.claude/settings.local.json   the user's Claude Code settings (rules, hooks, mode)
#   D ~/.config/infra-agent-harness                            the harness configuration of the user
#   D the installed copy of the plugin: ~/.claude/plugins/cache/*/infra-agent-harness, and the target of the stable
#     link when it is a plain directory. NOT a git clone: where the harness is developed (it is the installed copy
#     on a machine that develops it) the changes go through PR, tests and review.
# protected_list prints 'F<TAB>path' / 'D<TAB>path' lines, absolute; IAH_STABLE_LINK overrides the link (tests).
# Bash 3.2 compatible.

protected_list() {
  local d t link restore=0
  printf 'F\t%s\n' "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json"
  printf 'D\t%s\n' "$HOME/.config/infra-agent-harness"
  case $- in *f*) restore=1; set +f ;; esac
  for d in "$HOME"/.claude/plugins/cache/*/infra-agent-harness; do
    [ -d "$d" ] && printf 'D\t%s\n' "$d"
  done
  [ "$restore" = 0 ] || set -f
  link="${IAH_STABLE_LINK:-$HOME/.local/share/infra-agent-harness/current}"
  if [ -L "$link" ]; then
    t="$(cd "$link" 2>/dev/null && pwd -P)" || t=""
    # a git clone (.git as a directory or a file) is a place where the harness is developed
    if [ -n "$t" ] && [ ! -e "$t/.git" ]; then printf 'D\t%s\n' "$t"; fi
  fi
  return 0
}

# 0 if the stable link points to a git clone (doctor says that this copy is not protected)
protected_link_is_clone() {
  local link t; link="${IAH_STABLE_LINK:-$HOME/.local/share/infra-agent-harness/current}"
  [ -L "$link" ] || return 1
  t="$(cd "$link" 2>/dev/null && pwd -P)" || return 1
  [ -e "$t/.git" ]
}
