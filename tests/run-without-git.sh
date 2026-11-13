#!/usr/bin/env bash
# tests/run must also work from a plugin copy (the stable link in plugin mode), which has no .git, and from any
# working directory. A throwaway copy of tests/run with one trivial test; nothing else is touched.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
fail=0
mkdir -p "$TMP/copy/tests" "$TMP/elsewhere"
cp "$ROOT/tests/run" "$TMP/copy/tests/run"
# shellcheck disable=SC2016  # the $(…) is for the copy of the test, not for this script
printf '#!/usr/bin/env bash\necho "pwd=$(pwd -P)"\n' > "$TMP/copy/tests/one.sh"
out="$(cd "$TMP/elsewhere" && GIT_CEILING_DIRECTORIES="$TMP" bash "$TMP/copy/tests/run" one 2>&1)"; rc=$?
[ "$rc" = 0 ] || { echo "FAIL: tests/run in a copy without .git exits $rc: $out"; fail=1; }
grep -q "1 test scripts passed" <<<"$out" || { echo "FAIL: tests/run in a copy without .git did not run the test: $out"; fail=1; }
[ "$fail" = 0 ] && echo "run-without-git: all tests passed" || exit 1
