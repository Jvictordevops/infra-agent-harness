#!/usr/bin/env bash
# stable-link.sh — SessionStart (plugin). Keeps ~/.local/share/infra-agent-harness/current pointing at the
# installed plugin directory ($CLAUDE_PLUGIN_ROOT, which changes on every update), so that git's
# core.hooksPath can use a path that survives updates. IAH_STABLE_LINK overrides the link path (tests).
# Silent on success; never fails the session (always exit 0, problems go to stderr).
set -uo pipefail

LINK="${IAH_STABLE_LINK:-$HOME/.local/share/infra-agent-harness/current}"
ROOT="${CLAUDE_PLUGIN_ROOT:-}"

{ [ -n "$ROOT" ] && [ -d "$ROOT/bin/hooks" ]; } || exit 0
[ "$(readlink "$LINK" 2>/dev/null)" = "$ROOT" ] && exit 0
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  echo "stable-link: $LINK exists and is not a symlink; left as is" >&2; exit 0
fi

tmp="$LINK.tmp.$$"
# Atomic replace of the link: mv -T (GNU) or mv -h (BSD/macOS); both refuse to move into the old target dir.
if mkdir -p "$(dirname "$LINK")" && ln -s "$ROOT" "$tmp" \
  && { mv -T "$tmp" "$LINK" 2>/dev/null || mv -fh "$tmp" "$LINK"; }; then :
else
  rm -f "$tmp" 2>/dev/null
  echo "stable-link: could not update $LINK" >&2
fi
exit 0
