#!/usr/bin/env bash
# Tests for the record vocabulary: bin/lib/vocab.sh, bin/render-template and the language
# handling of bin/hooks/prepare-commit-msg. Uses throwaway repos; touches nothing else.
# Checks are strings evaluated by check(), so single quotes and "unused" variables are intended.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset IAH_LANG
export GIT_AUTHOR_NAME="Dana Doe" GIT_AUTHOR_EMAIL="dana@example.com"
export GIT_COMMITTER_NAME="Dana Doe" GIT_COMMITTER_EMAIL="dana@example.com"
fail=0
ok() { :; }
ko() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok; else ko "$1"; fi; }

# shellcheck source-path=SCRIPTDIR source=../bin/lib/vocab.sh
. "$ROOT/bin/lib/vocab.sh"

# --- language selection -----------------------------------------------------
mkdir -p "$TMP/en" "$TMP/es" "$TMP/bad" "$TMP/unknown" "$TMP/inject"
printf 'language=es\n' > "$TMP/es/.harness.conf"
printf 'language=e s\n' > "$TMP/bad/.harness.conf"
printf '# comment\nlanguage = xx  # not shipped\n' > "$TMP/unknown/.harness.conf"
printf 'language=$(touch %s/pwned)\n' "$TMP" > "$TMP/inject/.harness.conf"

vocab_load "$TMP/en";              check "default is en" '[ "$VOC_LANG" = en ] && [ "$VOC_TASK" = Task ]'
vocab_load "$TMP/es";              check ".harness.conf language=es" '[ "$VOC_LANG" = es ] && [ "$VOC_TASK" = Tarea ]'
IAH_LANG=en vocab_load "$TMP/es";  check "IAH_LANG overrides .harness.conf" '[ "$VOC_LANG" = en ]'
vocab_load "$TMP/bad" 2>/dev/null; check "invalid language falls back to en" '[ "$VOC_LANG" = en ]'
vocab_load "$TMP/unknown" 2>/dev/null; check "missing locale falls back to en" '[ "$VOC_LANG" = en ]'
vocab_load "$TMP/inject" 2>/dev/null
check ".harness.conf is never executed" '[ ! -e "$TMP/pwned" ] && [ "$VOC_LANG" = en ]'

# --- locale files ---------------------------------------------------------------
keys() { grep -oE '^VOC_[A-Z0-9_]+' "$1" | sort; }
for f in "$ROOT"/locale/*.sh; do
  [ "$f" = "$ROOT/locale/en.sh" ] && continue
  extra="$(comm -13 <(keys "$ROOT/locale/en.sh") <(keys "$f"))"
  missing="$(comm -23 <(keys "$ROOT/locale/en.sh") <(keys "$f"))"
  check "$(basename "$f") has no key unknown to en.sh: $extra" '[ -z "$extra" ]'
  check "$(basename "$f") defines every key of en.sh: $missing" '[ -z "$missing" ]'
done
used="$(grep -ohE '\{\{VOC_[A-Z0-9_]+\}\}' "$ROOT"/templates/*.md | tr -d '{}' | sort -u)"
undef="$(comm -23 <(printf '%s\n' "$used") <(keys "$ROOT/locale/en.sh"))"
check "templates only use keys defined in en.sh: $undef" '[ -z "$undef" ]'

# --- rendering ------------------------------------------------------------------
for t in record decision README roadmap training-unit; do
  out="$("$ROOT/bin/render-template" --repo "$TMP/en" "$t" TITLE="A & B | C/D" DATE=2030-01-02)"
  check "$t (en): no {{VOC_ left" '! grep -q "{{VOC_" <<<"$out"'
  check "$t (en): literal values kept" '! grep -q "{{TITLE}}" <<<"$out" || [ "$t" = README ] || [ "$t" = roadmap ]'
done
rec_en="$("$ROOT/bin/render-template" --repo "$TMP/en" record TITLE="A & B | C/D")"
rec_es="$("$ROOT/bin/render-template" --repo "$TMP/es" record TITLE=x)"
check "record (en): title with & | / kept literally" 'grep -qxF "# A & B | C/D" <<<"$rec_en"'
check "record (en): English fields" 'grep -q "^\*\*Task:\*\*" <<<"$rec_en" && grep -qx "## Open" <<<"$rec_en" && grep -q "^Confidence: high|medium|low" <<<"$rec_en"'
check "record (es): Spanish fields" 'grep -q "^\*\*Tarea:\*\*" <<<"$rec_es" && grep -qx "## Abierto" <<<"$rec_es" && grep -q "^Confianza: alta|media|baja" <<<"$rec_es"'
tu_es="$("$ROOT/bin/render-template" --repo "$TMP/es" training-unit)"
tu_en="$("$ROOT/bin/render-template" --repo "$TMP/en" training-unit)"
check "training-unit (es): all headings in Spanish" '[ "$(grep -c "^## [0-9]\. " <<<"$tu_es")" = 8 ] && grep -qx "## 1. El caso que seguimos" <<<"$tu_es" && grep -qx "## Abierto" <<<"$tu_es"'
check "training-unit (en): all headings in English" 'grep -qx "## 1. The case we follow" <<<"$tu_en" && grep -qx "## 8. What you can ratify when done" <<<"$tu_en" && ! grep -q "{{VOC_" <<<"$tu_en"'
check "training-unit (en): check-work prefixes match the template" 'for k in "$VOC_TU_CASE" ; do :; done; IAH_LANG=en bash -c ". \"$ROOT/bin/lib/vocab.sh\"; vocab_load; for p in \"\$VOC_TU_CASE\" \"\$VOC_TU_WALKTHROUGH\" \"\$VOC_TU_CONCEPTS\" \"\$VOC_TU_QUESTIONS\"; do grep -qF \"## \$p\" <<<\"$tu_en\" || exit 1; done"'
check "training-unit (es): check-work prefixes match the template" 'IAH_LANG=es bash -c ". \"$ROOT/bin/lib/vocab.sh\"; vocab_load; for p in \"\$VOC_TU_CASE\" \"\$VOC_TU_WALKTHROUGH\" \"\$VOC_TU_CONCEPTS\" \"\$VOC_TU_QUESTIONS\"; do grep -qF \"## \$p\" <<<\"$tu_es\" || exit 1; done"'
check "README keeps unfilled placeholders" '"$ROOT/bin/render-template" --repo "$TMP/en" README | grep -q "{{DATE}}"'
check "unknown template is refused" '! "$ROOT/bin/render-template" --repo "$TMP/en" ../x 2>/dev/null'

# --- banner regex ---------------------------------------------------------------
vocab_load "$TMP/es"
check "banner (es) matches" 'grep -Eq "$(vocab_banner_re)" <<<"> **Corregido por:** [x](2030-01-01.y.done.md)"'
check "banner (es) rejects English" '! grep -Eq "$(vocab_banner_re)" <<<"> **Corrected by:** [x](2030-01-01.y.done.md)"'

# --- prepare-commit-msg -----------------------------------------------------------
trailer() { # $1 = language ("" = no .harness.conf), $2 = field written in the record
  local repo="$TMP/repo-${1:-none}-$2"
  git init -q "$repo"
  [ -z "$1" ] || printf 'language=%s\n' "$1" > "$repo/.harness.conf"
  mkdir -p "$repo/work/acme/2030-01-01.demo/RECORD"
  printf '# t\n\n**%s:** 2.8 Vocabulary per language\n' "$2" > "$repo/work/acme/2030-01-01.demo/RECORD/2030-01-01.x.done.md"
  git -C "$repo" add -A
  printf 'msg\n' > "$repo/.git/MSG"
  (cd "$repo" && "$ROOT/bin/hooks/prepare-commit-msg" .git/MSG message)
  tail -1 "$repo/.git/MSG"
}
check "trailer (en)" '[ "$(trailer "" Task)" = "Task: demo 2.8 Vocabulary per language" ]'
check "trailer (es)" '[ "$(trailer es Tarea)" = "Tarea: demo 2.8 Vocabulary per language" ]'
check "trailer (es) ignores the English field" '[ "$(trailer es Task)" = "msg" ]'

if [ "$fail" = 0 ]; then echo "vocab: all tests passed"; else echo "vocab: tests FAILED"; exit 1; fi
