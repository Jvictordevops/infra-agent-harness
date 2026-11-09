#!/usr/bin/env bash
# Tests for denylist= in .harness.conf (link-harness links ~/.config/infra-agent-harness/denylist.txt) and for the
# work-repo checks of bin/doctor (behind upstream, CLAUDE.md, denylist link). Throwaway HOME and repos.
# shellcheck disable=SC2015
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: macOS temp dirs sit behind the /var -> /private/var link
trap 'rm -rf "$TMP"' EXIT
fail=0
ko() { echo "FAIL: $1"; fail=1; }
export GIT_CONFIG_NOSYSTEM=1 IAH_NO_FETCH=1 IAH_PLUGIN=0 LINK_HARNESS_WINDOWS=0
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
unset IAH_REPO IAH_MODULES IAH_DENYLIST

# shellcheck source-path=SCRIPTDIR source=lib/portable.sh
. "$ROOT/tests/lib/portable.sh"   # snap
new_home() { # $1 name -> HOME with a work repo holding GLOBAL.md and a private denylist
  local h="$TMP/$1"; mkdir -p "$h/work/private" "$h/.claude"
  git init -q "$h/work"; echo "# global" > "$h/work/GLOBAL.md"
  echo "secretword" > "$h/work/private/deny.txt"
  printf 'denylist=private/deny.txt\n' > "$h/work/.harness.conf"
  printf '%s' "$h"
}
lh() { local h="$1"; shift; (cd "$h/work" && HOME="$h" "$ROOT/bin/link-harness" "$@" 2>&1); }
LINK=".config/infra-agent-harness/denylist.txt"

# 1. link created, idempotent
H="$(new_home a)"
lh "$H" --quiet >/dev/null
[ -L "$H/$LINK" ] && [ "$(readlink "$H/$LINK")" = "$H/work/private/deny.txt" ] || ko "denylist link not created with the absolute path"
before="$(snap "$H")"; lh "$H" --quiet >/dev/null
[ "$(snap "$H")" = "$before" ] || ko "second run changed something"
[ -z "$(lh "$H" --dry-run --quiet)" ] || ko "dry-run after a real run still lists actions"

# 2. regular file and foreign link are backed up with a warning
H="$(new_home b)"; mkdir -p "$H/.config/infra-agent-harness"; echo mine > "$H/$LINK"
out="$(lh "$H" --quiet)"
[ -L "$H/$LINK" ] || ko "regular file not replaced by the link"
grep -q mine "$H/$LINK".bak-* 2>/dev/null || ko "regular file not backed up"
grep -q "warning:.*denylist.txt" <<<"$out" || ko "no warning when replacing a regular file"
H="$(new_home c)"; mkdir -p "$H/.config/infra-agent-harness"; echo other > "$TMP/other-deny"; ln -s "$TMP/other-deny" "$H/$LINK"
out="$(lh "$H" --quiet)"
[ "$(readlink "$H/$LINK")" = "$H/work/private/deny.txt" ] || ko "foreign link not replaced"
[ "$(readlink "$H/$LINK".bak-*)" = "$TMP/other-deny" ] || ko "foreign link not backed up"
grep -q "warning:" <<<"$out" || ko "no warning when replacing a foreign link"

# 3. dry-run writes nothing and prints would:
H="$(new_home d)"; before="$(snap "$H")"
out="$(lh "$H" --dry-run --quiet)"
[ "$(snap "$H")" = "$before" ] || ko "dry-run changed the home or the repo"
grep -q "^would: link $H/$LINK -> $H/work/private/deny.txt" <<<"$out" || ko "dry-run does not list the denylist link"

# 4. key unset: nothing; file missing: warning and nothing
H="$(new_home e)"; : > "$H/work/.harness.conf"
lh "$H" --quiet >/dev/null
[ ! -e "$H/$LINK" ] && [ ! -L "$H/$LINK" ] || ko "link created without denylist="
H="$(new_home f)"; rm "$H/work/private/deny.txt"
out="$(lh "$H" --quiet)"
[ ! -L "$H/$LINK" ] || ko "link created for a missing file"
grep -q "warning:.*does not exist" <<<"$out" || ko "no warning for the missing denylist file"

# 5. IAH_DENYLIST wins over .harness.conf
H="$(new_home g)"; echo x > "$TMP/env-deny"
(cd "$H/work" && HOME="$H" IAH_DENYLIST="$TMP/env-deny" "$ROOT/bin/link-harness" --quiet >/dev/null 2>&1)
[ "$(readlink "$H/$LINK")" = "$TMP/env-deny" ] || ko "IAH_DENYLIST does not override the conf"

# 6. doctor: read-only; warns on mismatch, ok after link-harness
doc() { (cd "$TMP" && HOME="$1" IAH_REPO="$1/work" "$ROOT/bin/doctor" 2>&1 || true); }
H="$(new_home h)"; before="$(snap "$H")"
out="$(doc "$H")"
[ "$(snap "$H")" = "$before" ] || ko "doctor changed the home or the work repo"
grep -q "^WARN  ~/.claude/CLAUDE.md does not resolve to $H/work/GLOBAL.md" <<<"$out" || ko "no CLAUDE.md warning"
grep -q "^WARN  denylist: .*does not resolve to" <<<"$out" || ko "no denylist warning"
lh "$H" --quiet >/dev/null
out="$(doc "$H")"
grep -q "^OK    ~/.claude/CLAUDE.md -> " <<<"$out" || ko "no OK for CLAUDE.md after link-harness"
grep -q "^OK    denylist: " <<<"$out" || ko "no OK for the denylist after link-harness"
echo y > "$H/work/GLOBAL.md.new"; rm -f "$H/.claude/CLAUDE.md"; echo copy > "$H/.claude/CLAUDE.md"
grep -q "^WARN  ~/.claude/CLAUDE.md does not resolve" <<<"$(doc "$H")" || ko "a regular CLAUDE.md copy is not reported"
rm -f "$H/work/GLOBAL.md.new"
# no GLOBAL.md: the check is skipped
H="$(new_home i)"; rm "$H/work/GLOBAL.md"
! grep -q "CLAUDE.md" <<<"$(doc "$H" | grep -v 'link-harness would')" || ko "CLAUDE.md check not skipped without GLOBAL.md"

# 7. doctor: work repo behind its upstream (local refs only)
H="$(new_home j)"; U="$TMP/upstream.git"; git init -q --bare --initial-branch=main "$U"   # not the user's init.defaultBranch
git -C "$H/work" add -A; git -C "$H/work" -c user.name=t -c user.email=t@example.com commit -q -m one
git -C "$H/work" remote add origin "$U"; git -C "$H/work" push -q origin HEAD:main 2>/dev/null
git -C "$H/work" branch -q -u origin/main 2>/dev/null || git -C "$H/work" fetch -q origin && git -C "$H/work" branch -q -u origin/main
git clone -q "$U" "$TMP/second"; git -C "$TMP/second" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m two
git -C "$TMP/second" push -q origin HEAD:main
git -C "$H/work" fetch -q origin   # the user's own fetch; doctor must not do it
before="$(snap "$H")"
out="$(doc "$H")"
grep -q "^WARN  .*work repo is 1 commit(s) behind origin/main: git -C $H/work pull --rebase" <<<"$out" || ko "no behind-upstream warning: $(grep -i behind <<<"$out")"
[ "$(snap "$H")" = "$before" ] || ko "doctor changed the home or the work repo (behind case)"
H="$(new_home k)"
# only the work-repo warning: doctor also warns when the harness clone itself is behind, which depends on the machine
! grep -q "work repo is .* behind" <<<"$(doc "$H")" || ko "behind warning for a repo without upstream"

if [ "$fail" = 0 ]; then echo "denylist link and doctor work-repo checks: all tests passed"; else echo "denylist link and doctor work-repo checks: tests FAILED"; exit 1; fi
