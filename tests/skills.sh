#!/usr/bin/env bash
# Static checks for skills/*/SKILL.md: frontmatter, no private paths, English only.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ko() { echo "FAIL: $1"; fail=1; }

n=0
for f in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  n=$((n + 1))
  dir="$(basename "$(dirname "$f")")"
  [ "$(head -1 "$f")" = "---" ] || ko "$dir: no frontmatter"
  name="$(awk 'NR>1 && /^---$/ {exit} /^name:/ {sub(/^name:[ \t]*/, ""); print}' "$f")"
  [ "$name" = "$dir" ] || ko "$dir: name '$name' != folder"
  awk 'NR>1 && /^---$/ {exit} /^description: *"?.{20,}/ {found=1} END {exit !found}' "$f" || ko "$dir: description missing or too short"
  grep -nE '~/code/|/Users/' "$f" && ko "$dir: private path (the private names are in your denylist)"
  # the frontmatter description may carry Spanish trigger phrases (repositories in language=es use them)
  grep -v '^description:' "$f" | grep -nE '[áéíóúñ¿¡]| (el|la|los|las|del|para|que|con|una?) ' | head -3 | grep . && ko "$dir: Spanish text left"
done
[ "$n" -gt 0 ] || ko "no skills found"

if [ "$fail" = 0 ]; then echo "skills: all tests passed ($n skills)"; else echo "skills: tests FAILED"; exit 1; fi
