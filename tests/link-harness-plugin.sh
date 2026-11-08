#!/usr/bin/env bash
# Tests for bin/link-harness --dry-run, plugin-mode link handling (own vs foreign links, Copilot through the
# stable link, no skill copy to Windows) and for bin/doctor being read-only. Throwaway HOME; touches nothing real.
# shellcheck disable=SC2015,SC2088
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ko() { echo "FAIL: $1"; fail=1; }
export GIT_CONFIG_NOSYSTEM=1
unset IAH_REPO IAH_MODULES

# Fake world: the plugin cache dir (a link to this repo), the stable link, another harness and a manual clone
CACHE="$TMP/cache/infra-agent-harness/0.1.0"; mkdir -p "$(dirname "$CACHE")"; ln -s "$ROOT" "$CACHE"
export IAH_STABLE_LINK="$TMP/share/current"; mkdir -p "$TMP/share"; ln -s "$CACHE" "$IAH_STABLE_LINK"
OTHER="$TMP/other"; mkdir -p "$OTHER/bin" "$OTHER/skills/close-task"
printf '#!/bin/sh\n' > "$OTHER/bin/link-harness"; chmod +x "$OTHER/bin/link-harness"; echo x > "$OTHER/skills/close-task/SKILL.md"
CLONE="$TMP/clone"; mkdir -p "$CLONE/bin" "$CLONE/skills/new-project" "$CLONE/.claude-plugin"
printf '#!/bin/sh\n' > "$CLONE/bin/link-harness"; chmod +x "$CLONE/bin/link-harness"
echo '{ "name": "infra-agent-harness" }' > "$CLONE/.claude-plugin/plugin.json"

new_home() { # $1 name -> HOME with a work repo; prints the path
  local h="$TMP/$1"; mkdir -p "$h/.claude/skills" "$h/work"
  git init -q "$h/work"; echo "# global" > "$h/work/GLOBAL.md"
  ln -s "$OTHER/skills/close-task" "$h/.claude/skills/close-task"      # foreign link, same name as a skill here
  ln -s "$CLONE/skills/new-project" "$h/.claude/skills/new-project"    # manual clone of this harness
  printf '%s' "$h"
}
lh() { local h="$1"; shift; (cd "$h/work" && HOME="$h" IAH_PLUGIN=1 LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" "$@" 2>&1); }
snap() { (cd "$1" && find . -printf '%p|%y|%l|%s|%T@\n' | sort && find . -type f -exec sha256sum {} + | sort); }

# 1. --dry-run writes nothing and lists what it would do
H="$(new_home dry)"; before="$(snap "$H")"
out="$(lh "$H" --dry-run --quiet)"
[ "$(snap "$H")" = "$before" ] || ko "dry-run changed the home or the work repo"
grep -q "^would: remove $H/.claude/skills/new-project" <<<"$out" || ko "dry-run: does not list the removal of the manual-clone link"
grep -q "^would: link $H/.copilot/skills/close-task -> $IAH_STABLE_LINK/skills/close-task" <<<"$out" || ko "dry-run: no Copilot link through the stable link"
grep -q "^would: merge hooks/settings.base.json" <<<"$out" || ko "dry-run: no settings merge listed"
grep -q "^would: set core.hooksPath" <<<"$out" || ko "dry-run: no hooksPath listed"
grep -q "^would: link $H/.claude/CLAUDE.md" <<<"$out" || ko "dry-run: no GLOBAL.md link listed"
! grep -qv '^would: ' <<<"$out" || ko "dry-run --quiet printed something that is not a would: line"
# a real run afterwards makes the dry-run empty (idempotent)
lh "$H" --quiet >/dev/null
[ -z "$(lh "$H" --dry-run --quiet)" ] || ko "dry-run after a real run still lists actions: $(lh "$H" --dry-run --quiet)"

# 2. plugin mode: foreign links kept, links of a manual clone of this harness removed
[ -L "$H/.claude/skills/close-task" ] && [ "$(readlink "$H/.claude/skills/close-task")" = "$OTHER/skills/close-task" ] || ko "plugin mode removed or changed a link of another harness"
[ ! -e "$H/.claude/skills/new-project" ] && [ ! -L "$H/.claude/skills/new-project" ] || ko "plugin mode kept the link of a manual clone of this harness"
H2="$(new_home keep)"; out="$(lh "$H2")"
grep -q "kept $H2/.claude/skills/close-task -> $OTHER/skills/close-task (not this harness; the plugin's skill is available as infra-agent-harness:close-task)" <<<"$out" || ko "no 'kept' message for the foreign link"

# 3. Copilot: links go through the stable link, never into plugins/cache; foreign Copilot links are not replaced
H3="$(new_home cop)"; mkdir -p "$H3/.copilot/skills"
ln -s "$OTHER/skills/close-task" "$H3/.copilot/skills/close-task"
ln -s "$HOME/.claude/plugins/cache/m/infra-agent-harness/0.0.9/skills/digest" "$H3/.copilot/skills/digest"
lh "$H3" --quiet >/dev/null
n=0
for l in "$H3"/.copilot/skills/*; do
  [ -L "$l" ] || continue; n=$((n + 1)); t="$(readlink "$l")"
  case "$(basename "$l")" in close-task) [ "$t" = "$OTHER/skills/close-task" ] || ko "foreign Copilot link replaced"; continue ;; esac
  case "$t" in "$IAH_STABLE_LINK"/skills/*) ;; *) ko "Copilot link $l -> $t does not use the stable link" ;; esac
  case "$t" in *plugins/cache*|"$CACHE"*) ko "Copilot link $l -> $t points into the plugin cache" ;; esac
done
[ "$n" -gt 3 ] || ko "Copilot links not created (found $n)"
# ~/.copilot/skills -> ~/.claude/skills with kept foreign links: left alone
H4="$(new_home cslink)"; mkdir -p "$H4/.copilot"; ln -s "$H4/.claude/skills" "$H4/.copilot/skills"
out="$(lh "$H4")"
[ -L "$H4/.copilot/skills" ] && [ "$(readlink "$H4/.copilot/skills")" = "$H4/.claude/skills" ] || ko "~/.copilot/skills link converted although foreign links are kept"
grep -q "Copilot keeps using ~/.claude/skills" <<<"$out" || ko "no message that Copilot keeps using ~/.claude/skills"
# ... but without foreign links it becomes a real folder with stable-link entries
H5="$(new_home csown)"; rm "$H5/.claude/skills/close-task"; mkdir -p "$H5/.copilot"; ln -s "$H5/.claude/skills" "$H5/.copilot/skills"
lh "$H5" --quiet >/dev/null
{ [ -d "$H5/.copilot/skills" ] && [ ! -L "$H5/.copilot/skills" ]; } || ko "manual-install Copilot link not replaced by a folder"
[ "$(readlink "$H5/.copilot/skills/digest")" = "$IAH_STABLE_LINK/skills/digest" ] || ko "Copilot link in the new folder is not the stable one"
# stable link not there yet: links are still created on the stable path, with a warning
H6="$(new_home nostable)"
out="$(IAH_STABLE_LINK="$TMP/none/current" lh "$H6")"
[ "$(readlink "$H6/.copilot/skills/digest")" = "$TMP/none/current/skills/digest" ] || ko "no Copilot link on the stable path when the stable link is missing"
grep -q "warning: stable link $TMP/none/current does not exist yet" <<<"$out" || ko "no warning about the missing stable link"

# 4. Fake WSL: plugin mode copies no skills to Windows (GLOBAL.md only); manual mode still copies them
BIN="$TMP/fakebin"; WIN="$TMP/win"; mkdir -p "$BIN" "$WIN"
printf '#!/bin/sh\nprintf "C:\\\\Users\\\\acme\\r\\n"\n' > "$BIN/cmd.exe"
printf '#!/bin/sh\necho "%s"\n' "$WIN" > "$BIN/wslpath"; chmod +x "$BIN/cmd.exe" "$BIN/wslpath"
echo "microsoft fake" > "$TMP/proc-version"
H7="$(new_home wsl)"
(cd "$H7/work" && PATH="$BIN:$PATH" IAH_PROC_VERSION="$TMP/proc-version" HOME="$H7" IAH_PLUGIN=1 "$ROOT/bin/link-harness" >"$TMP/wsl.out" 2>&1)
[ -f "$WIN/.claude/CLAUDE.md" ] || ko "fake WSL: Windows CLAUDE.md not written (is the fake working?)"
[ -z "$(ls -A "$WIN/.claude/skills" 2>/dev/null)" ] || ko "plugin mode copied skills to the Windows profile"
grep -q "skills are not copied to Windows" "$TMP/wsl.out" || ko "no message about installing the plugin on the Windows side"
(cd "$H7/work" && PATH="$BIN:$PATH" IAH_PROC_VERSION="$TMP/proc-version" HOME="$H7" IAH_PLUGIN=0 "$ROOT/bin/link-harness" --quiet >/dev/null 2>&1)
[ -f "$WIN/.claude/skills/digest/SKILL.md" ] || ko "manual mode no longer copies skills to Windows"

# 5. doctor is read-only: home and work repo config unchanged
H8="$(new_home doctor)"; mkdir -p "$H8/.claude/plugins"
before="$(snap "$H8")"
dout="$(cd "$H8/work" && HOME="$H8" IAH_REPO="$H8/work" IAH_PLUGIN=1 IAH_NO_FETCH=1 "$ROOT/bin/doctor" 2>&1 || true)"
[ "$(snap "$H8")" = "$before" ] || ko "doctor changed the home or the work repo"
grep -q "WARN  link-harness would change" <<<"$dout" || ko "doctor does not report what link-harness would change"
grep -q "core.hooksPath is not set" <<<"$dout" || ko "doctor does not warn about the missing hooksPath"
[ -z "$(git -C "$H8/work" config core.hooksPath)" ] || ko "doctor set core.hooksPath"

if [ "$fail" = 0 ]; then echo "link-harness plugin: all tests passed"; else echo "link-harness plugin: tests FAILED"; exit 1; fi
