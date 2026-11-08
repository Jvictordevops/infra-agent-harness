#!/usr/bin/env bash
# Tests for bin/new-work, bin/check-work and hooks/confidence-nudge in a throwaway repository,
# in English (default) and Spanish (.harness.conf). Touches nothing else.
# Checks are strings evaluated by check(): single quotes and variables used only there are intended.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset IAH_LANG IAH_REPO IAH_METHOD
export GIT_AUTHOR_NAME="Dana Doe" GIT_AUTHOR_EMAIL="dana@example.com"
export GIT_COMMITTER_NAME="Dana Doe" GIT_COMMITTER_EMAIL="dana@example.com"
# Throwaway repos only: do not inherit the user's commit signing or hooks
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }

repo() { # $1 = name, $2 = language ("" = default) -> fresh repo with contexts/acme/
  local r="$TMP/$1"
  git init -q "$r"; mkdir -p "$r/contexts/acme" "$r/contexts/_template-x"
  [ -z "$2" ] || printf 'language=%s\n' "$2" > "$r/.harness.conf"
  echo "$r"
}
nw() { (cd "$1" && shift && "$ROOT/bin/new-work" "$@" >/dev/null 2>&1); }
cw() { (cd "$1" && shift && "$ROOT/bin/check-work" "$@" 2>&1) || true; }   # output only: exit 1 on errors is expected in some cases

# --- new-work -----------------------------------------------------------------------
EN="$(repo en "")"
check "new-work: known context"        'nw "$EN" acme prj demo-work --date 2030-01-02 --title "A & B | C/D"'
check "new-work: global always valid"  'nw "$EN" global inv other-work --date 2030-01-02'
check "new-work: unknown context"      '! nw "$EN" nobody prj x --date 2030-01-02'
check "new-work: _template not a context" '! nw "$EN" _template-x prj x --date 2030-01-02'
check "new-work: bad slug"             '! nw "$EN" acme prj Bad_Slug'
W="$EN/work/acme/2030-01-02.demo-work"
check "new-work: title kept literally" 'grep -qxF "# A & B | C/D" "$W/README.md"'
check "new-work: English objectives"   'grep -qF "| Id | Objective | Done when |" "$W/README.md"'
check "new-work: only prj block"       '! grep -q "## Symptom" "$W/README.md" && grep -q "## Scope" "$W/README.md"'
check "new-work: roadmap revision"     '[ -f "$W/ROADMAP/2030-01-02.md" ]'
check "check-work: fresh works pass"   'cw "$EN" | tail -1 | grep -q " 0 error(s)"'

ES="$(repo es es)"
nw "$ES" acme prj demo-es --date 2030-01-02
check "new-work (es): Spanish objectives" 'grep -qF "| Id | Objetivo | Hecho cuando |" "$ES/work/acme/2030-01-02.demo-es/README.md"'

# --- check-work -----------------------------------------------------------------------
mkdir -p "$EN/work/nobody/2030-01-02.stray"
check "check-work: parent without contexts/ is an error" 'cw "$EN" "$EN/work/nobody/2030-01-02.stray" | grep -q "parent must be global or have contexts/nobody/"'
rm -rf "$EN/work/nobody"

rec() { # $1 repo, $2 work dir (relative), $3 file name, $4 content
  printf '%b' "$4" > "$1/$2/RECORD/$3"; git -C "$1" add -A
}
git -C "$EN" add -A && git -C "$EN" commit -qm init
rec "$EN" work/acme/2030-01-02.demo-work 2030-01-02.decision-x.done.md '# d\n\n**Task:** 1.1 TODO\n\n## Open\n\nConfidence: high\n'
check "check-work (en): English decision record passes" '! cw "$EN" --staged | grep -q "^WARN.*decision-x"'
rec "$EN" work/acme/2030-01-02.demo-work 2030-01-02.decision-y.done.md '# d\n\n**Tarea:** 1.1 TODO\n\n## Abierto\n\nConfianza: alta\n'
check "check-work (en): Spanish fields warned" 'cw "$EN" --staged | grep -q "decision-y.*'"'"'\*\*Task:\*\*"'
git -C "$EN" commit -qm records

git -C "$ES" add -A && git -C "$ES" commit -qm init
rec "$ES" work/acme/2030-01-02.demo-es 2030-01-02.decision-z.done.md '# d\n\n**Tarea:** 1.1 TODO\n\n## Abierto\n\nConfianza: alta\n'
check "check-work (es): Spanish decision record passes" '! cw "$ES" --staged | grep -q "^WARN.*decision-z"'
git -C "$ES" commit -qm records

# append-only + banners in the repository language
R="$ES/work/acme/2030-01-02.demo-es/RECORD/2030-01-02.decision-z.done.md"
cp "$R" "$R.orig"; printf '# d\n\n> **Corregido por:** [n](2030-01-02.decision-z.done.md)\n' > "$R.new"; tail -n +2 "$R.orig" >> "$R.new"; mv "$R.new" "$R"; rm "$R.orig"
git -C "$ES" add -A
check "check-work (es): Spanish banner allowed" 'cw "$ES" --staged | tail -1 | grep -q " 0 error(s)"'
git -C "$ES" reset -q --hard
sed -i 's/alta/baja/' "$R"; git -C "$ES" add -A
check "check-work (es): edited record is an error" 'cw "$ES" --staged | grep -q "committed record modified"'
git -C "$ES" reset -q --hard

# --- check-work: method light | full --------------------------------------------------
# Throwaway work with: undeclared objective 9 (numbering), an open item without id, README > 150 lines
mw() { # $1 = repo name, $2 = method line ("" = no conf) -> repo with a work that breaks numbering
  local r; r="$(repo "$1" "")"
  [ -z "$2" ] || printf '%s\n' "$2" > "$r/.harness.conf"
  nw "$r" acme prj m --date 2030-01-02
  printf '\n## Carried\n\n- **9.1** orphan task\n' >> "$r/work/acme/2030-01-02.m/ROADMAP/2030-01-02.md"
  echo "$r"
}
M0="$(mw m0 "")"; MW="$M0/work/acme/2030-01-02.m"
check "method: default is light"            'cw "$M0" | tail -1 | grep -q "(method: light)"'
check "method light: numbering is WARN"     'cw "$M0" | grep -q "^WARN.*objective '"'"'9'"'"' not declared"'
check "method light: exit 0"                '(cd "$M0" && "$ROOT/bin/check-work" >/dev/null 2>&1)'
check "method light: 0 errors"              'cw "$M0" | tail -1 | grep -q " 0 error(s)"'
printf -- '- plain item\n' >> "$MW/ROADMAP/2030-01-02.md"
check "method light: item without id is ERROR" 'cw "$M0" | grep -q "^ERROR.*without id"'
sed -i '$d' "$MW/ROADMAP/2030-01-02.md"
printf -- '- **9.1** orphan twin\n' >> "$MW/ROADMAP/2030-01-02.md"
check "method light: duplicate task id is ERROR" 'cw "$M0" | grep -q "^ERROR.*duplicate task id '"'"'9.1'"'"'"'
sed -i '$d' "$MW/ROADMAP/2030-01-02.md"
sed -i 's/^## Objectives$/## Objectives\n\n| **1** | dup | x |\n| **1** | dup | x |/' "$MW/README.md"
check "method light: duplicate objective id is ERROR" 'cw "$M0" | grep -q "^ERROR.*Objectives: duplicate id '"'"'1'"'"'"'
git -C "$M0" checkout -q -- . 2>/dev/null; nw "$M0" acme prj big --date 2030-01-03
for i in $(seq 1 160); do echo "line $i" >> "$M0/work/acme/2030-01-03.big/README.md"; done
check "method light: README > 150 lines is WARN" 'cw "$M0" "$M0/work/acme/2030-01-03.big" | grep -q "^WARN.*lines > 150"'
check "method light: README > 150 lines no ERROR" '! cw "$M0" "$M0/work/acme/2030-01-03.big" | grep -q "^ERROR.*lines > 150"'

MF="$(mw mf "method=full")"
check "method full: summary line"           'cw "$MF" | tail -1 | grep -q "(method: full)"'
check "method full: numbering is ERROR"     'cw "$MF" | grep -q "^ERROR.*objective '"'"'9'"'"' not declared"'
nw "$MF" acme prj big --date 2030-01-03
for i in $(seq 1 160); do echo "line $i" >> "$MF/work/acme/2030-01-03.big/README.md"; done
check "method full: README > 150 lines is ERROR" 'cw "$MF" "$MF/work/acme/2030-01-03.big" | grep -q "^ERROR.*lines > 150"'
ML="$(mw ml "method=light")"
check "method: IAH_METHOD=full overrides conf light" 'IAH_METHOD=full cw "$ML" | grep -q "^ERROR.*objective .9. not declared"'
MB="$(mw mb "method=sloppy")"
check "method: invalid value falls back to full" 'cw "$MB" | grep -q "^ERROR.*objective .9. not declared"'
check "method: invalid value says so on stderr" 'cw "$MB" | grep -q "invalid method .sloppy."'

# --- confidence-nudge -----------------------------------------------------------------
nudge() { jq -n --arg p "$1" --arg c "$2" '{prompt: $p, cwd: $c}' | "$ROOT/hooks/confidence-nudge/confidence-nudge.sh"; }
check "nudge (en): troubleshooting prompt" 'nudge "the pod keeps crashing" "$EN" | jq -e ".hookSpecificOutput.additionalContext | test(\"Confidence: high\")" >/dev/null'
check "nudge (en): normal prompt is silent" '[ -z "$(nudge "write a readme" "$EN")" ]'
check "nudge (es): Spanish trigger and message" 'nudge "el servicio no responde" "$ES" | jq -e ".hookSpecificOutput.additionalContext | test(\"Confianza: alta\")" >/dev/null'
check "nudge: port numbers are not status codes" '[ -z "$(nudge "listen on 15003" "$EN")" ]'

if [ "$fail" = 0 ]; then echo "work: all tests passed"; else echo "work: tests FAILED"; exit 1; fi
