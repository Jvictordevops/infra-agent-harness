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

if [ "$fail" = 0 ]; then echo "denylist-scan: all tests passed"; else echo "denylist-scan: tests FAILED"; exit 1; fi
