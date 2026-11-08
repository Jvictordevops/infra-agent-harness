#!/usr/bin/env bash
# Tests for bin/denylist-scan, in a throwaway git repository.
# Sensitive-looking samples are split ("4182""7279…") so this file itself passes the scan.
set -uo pipefail

SCAN="$(cd "$(dirname "$0")/.." && pwd)/bin/denylist-scan"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/r" && cd "$TMP/r" || exit 1
printf 'contoso\n# comment\nintranet\\.corp\n' > "$TMP/denylist.txt"
export IAH_DENYLIST="$TMP/denylist.txt"
fail=0

case_() { # $1 expected exit, $2 file content, $3 label
  rm -f f.txt; printf '%b\n' "$2" > f.txt; git add f.txt
  "$SCAN" >/dev/null 2>&1; got=$?
  [ "$got" = "$1" ] || { echo "FAIL ($3): expected exit $1, got $got"; fail=1; }
}

case_ 0 "plain text about kubectl and terraform" "clean text"
case_ 1 "account 4182""72791745 in prod" "real-looking account id"
case_ 0 "account 123456789012 in the docs" "documentation account id"
case_ 1 "arn:aws:iam::4182""72791745:role/admin" "arn with account"
case_ 0 "arn:aws:iam::123456789012:role/ReadOnly" "documentation arn"
case_ 1 "key AKIA""ABCDEFGHIJKLMNOP" "access key"
case_ 1 "ssh 192.168"".77.10" "private ip"
case_ 0 "allow 10.0.0.0/8 in the example" "documentation cidr"
case_ 1 "ask jane.doe@""bigbank.io" "e-mail"
case_ 0 "write to ops@example.com" "documentation e-mail"
case_ 1 "the contoso cluster" "personal denylist word"
case_ 1 "see intranet.corp/wiki" "personal denylist regex"
case_ 0 "build 20261107123456 is a 14-digit number" "long number is not an account id"

# --staged scans what is staged, not the working tree
printf 'contoso\n' > g.txt; git add g.txt; printf 'clean\n' > g.txt
"$SCAN" --staged >/dev/null 2>&1; [ $? = 1 ] || { echo "FAIL (staged content)"; fail=1; }
git rm -q --cached -f g.txt; rm -f g.txt

# Without a denylist, a warning and only the generic patterns
out="$(IAH_DENYLIST="$TMP/none.txt" "$SCAN" 2>&1)"
case "$out" in *"no personal denylist"*) ;; *) echo "FAIL (missing denylist warning)"; fail=1 ;; esac

# --quiet reports file, line and rule, never the matching text
printf 'line one\nthe contoso cluster\n' > q.txt; git add q.txt
out="$("$SCAN" --quiet 2>/dev/null)"; got=$?
[ "$got" = 1 ] || { echo "FAIL (quiet exit): expected 1, got $got"; fail=1; }
case "$out" in *contoso*) echo "FAIL (quiet prints the text)"; fail=1 ;; esac
case "$out" in *"q.txt:2   [denylist:1]"*) ;; *) echo "FAIL (quiet location): $out"; fail=1 ;; esac
git rm -q --cached -f q.txt; rm -f q.txt

# --history finds what was committed and removed later, without printing it
if command -v gitleaks >/dev/null; then
  export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null
  export GIT_AUTHOR_NAME="Dana Doe" GIT_AUTHOR_EMAIL="dana@example.com" GIT_COMMITTER_NAME="Dana Doe" GIT_COMMITTER_EMAIL="dana@example.com"
  git rm -q --cached -f f.txt 2>/dev/null; rm -f f.txt
  printf 'clean start\n' > h.txt; git add h.txt; git commit -q -m one
  out="$("$SCAN" --history 2>&1)"; got=$?
  [ "$got" = 0 ] || { echo "FAIL (clean history): expected 0, got $got: $out"; fail=1; }
  printf 'ping the contoso cluster\n' > h.txt; git commit -q -am two
  printf 'clean again\n' > h.txt; git commit -q -am three
  "$SCAN" >/dev/null 2>&1 || { echo "FAIL (tree should be clean)"; fail=1; }
  out="$("$SCAN" --history 2>&1)"; got=$?
  [ "$got" = 1 ] || { echo "FAIL (history exit): expected 1, got $got"; fail=1; }
  case "$out" in *contoso*) echo "FAIL (history prints the text)"; fail=1 ;; esac
  case "$out" in *"h.txt:1   [denylist:1]"*) ;; *) echo "FAIL (history location): $out"; fail=1 ;; esac
  # .gitleaksignore accepts a known finding by its fingerprint
  c="$(git rev-parse HEAD~1)"; printf '%s:h.txt:denylist:1:1\n' "$c" > .gitleaksignore
  "$SCAN" --history >/dev/null 2>&1 || { echo "FAIL (.gitleaksignore not honoured)"; fail=1; }
  rm -f .gitleaksignore
  out="$(IAH_DENYLIST="$TMP/none.txt" "$SCAN" --history 2>&1)"; got=$?
  [ "$got" = 2 ] || { echo "FAIL (history without denylist): expected 2, got $got"; fail=1; }
else
  echo "denylist-scan: gitleaks not installed, --history tests skipped"
fi

if [ "$fail" = 0 ]; then echo "denylist-scan: all tests passed"; else echo "denylist-scan: tests FAILED"; exit 1; fi
