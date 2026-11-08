#!/usr/bin/env bash
# Tests for modules/two-machine/bin/setup-ssh-access in a throwaway HOME, with uname/nc/sudo stubbed.
# Touches nothing real: only --check or rejected input is exercised, never the sshd change.
# Checks are strings evaluated by check(): single quotes and variables used only there are intended.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

MOD="$(cd "$(dirname "$0")/.." && pwd)"
S="$MOD/bin/setup-ssh-access"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
fail=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; fail=1; fi; }

# Stubs: macOS uname, Remote Login listening, sudo that must never be called
STUBS="$TMP/stubs"; mkdir -p "$STUBS" "$TMP/linux"
printf '#!/bin/sh\necho Darwin\n' > "$STUBS/uname"
printf '#!/bin/sh\nexit 0\n' > "$STUBS/nc"
printf '#!/bin/sh\necho SUDO CALLED >> "%s/sudo-called"\nexit 1\n' "$TMP" > "$STUBS/sudo"
printf '#!/bin/sh\necho Linux\n' > "$TMP/linux/uname"
chmod +x "$STUBS"/* "$TMP/linux/uname"
on_macos() { PATH="$STUBS:$PATH" "$S" "$@"; }

check "bash -n" 'bash -n "$S"'

# --- not macOS -------------------------------------------------------------------------
out="$(PATH="$TMP/linux:$PATH" "$S" --check 2>&1)"; rc=$?
check "non-macOS: exits non-zero"      '[ "$rc" != 0 ]'
check "non-macOS: clear message"       'grep -q "for macOS" <<<"$out"'

# --- arguments -------------------------------------------------------------------------
out="$(on_macos --bogus 2>&1)"; rc=$?
check "unknown argument rejected"      '[ "$rc" != 0 ] && grep -q "unknown argument" <<<"$out"'
out="$(on_macos --pubkey 2>&1)"; rc=$?
check "--pubkey without value rejected" '[ "$rc" != 0 ] && grep -q "needs a value" <<<"$out"'
out="$(on_macos --pubkey-file "$TMP/nope" 2>&1)"; rc=$?
check "missing key file rejected"      '[ "$rc" != 0 ] && grep -q "cannot read" <<<"$out"'
out="$(on_macos 2>&1)"; rc=$?
check "no key and not --check: error"  '[ "$rc" != 0 ] && grep -q "no public key given" <<<"$out"'
for bad in "hello world" "-----BEGIN OPENSSH PRIVATE KEY-----" "ssh-ed25519" 'command="x" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAA k'; do
  out="$(on_macos --check --pubkey "$bad" 2>&1)"; rc=$?
  check "invalid key rejected: $bad"   '[ "$rc" != 0 ] && grep -q "not a public key" <<<"$out"'
done
out="$(on_macos --check --pubkey "$(printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAA a\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAA b')" 2>&1)"; rc=$?
check "two key lines rejected"         '[ "$rc" != 0 ] && grep -q "exactly one" <<<"$out"'

# --- valid key in --check mode ---------------------------------------------------------
if command -v ssh-keygen >/dev/null; then
  ssh-keygen -q -t ed25519 -N "" -C test-key -f "$TMP/k" >/dev/null
  key="$(cat "$TMP/k.pub")"
  out="$(on_macos --check --pubkey "$key" 2>&1)"
  check "valid key accepted by --check"          'grep -q "setup-ssh-access --check" <<<"$out"'
  check "--check reports the key as not authorized" 'grep -q "WARN  key is NOT authorized" <<<"$out"'
  check "--check adds no key and creates no ~/.ssh" '[ ! -e "$HOME/.ssh" ]'
  out="$(on_macos --check --pubkey-file "$TMP/k.pub" 2>&1)"
  check "--pubkey-file accepted"                 'grep -q "setup-ssh-access --check" <<<"$out"'
  out="$(on_macos --check --pubkey-file - < "$TMP/k.pub" 2>&1)"
  check "stdin accepted"                         'grep -q "setup-ssh-access --check" <<<"$out"'
  mkdir -p "$HOME/.ssh"; cp "$TMP/k.pub" "$HOME/.ssh/authorized_keys"
  out="$(on_macos --check --pubkey "$key" 2>&1)"
  check "--check recognizes an authorized key"   'grep -q "OK    key is authorized" <<<"$out"'
  check "authorized_keys untouched by --check"   'cmp -s "$TMP/k.pub" "$HOME/.ssh/authorized_keys"'
else
  echo "SKIP: ssh-keygen not installed (valid-key checks)"
fi
out="$(on_macos --check 2>&1)"
check "--check without key reports sshd state" 'grep -q "sshd" <<<"$out"'
check "sudo never called in --check"           '[ ! -e "$TMP/sudo-called" ]'
check "summary mentions no hard-coded IP"      '! grep -Eq "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" <<<"$out"'

if [ "$fail" = 0 ]; then echo "two-machine: all tests passed"; else echo "two-machine: tests FAILED"; exit 1; fi
