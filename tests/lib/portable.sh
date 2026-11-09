# shellcheck shell=bash
# Helpers so the tests run the same on Linux (GNU tools) and macOS (BSD tools, bash 3.2).
#   . "$ROOT/tests/lib/portable.sh"

# sed_i <sed args...> <file>: in-place edit (GNU and BSD sed disagree on -i)
sed_i() {
  local f; f="${!#}"   # last argument
  sed "$@" > "$f.sed_i.tmp" && cat "$f.sed_i.tmp" > "$f" && rm -f "$f.sed_i.tmp"
}

# b64 <file>: base64 on a single line
b64() { base64 < "$1" | tr -d '\n'; }

# _mtime <path>: modification time of the path itself (not the link target), as precise as the system gives
_mtime() { stat -c %.9Y "$1" 2>/dev/null || stat -f %Fm "$1"; }

# snap <dir>: every path with type, link target, size and mtime, then the content digest of each file.
# Two equal snaps mean nothing under <dir> was created, removed, relinked or written.
snap() {
  (
    cd "$1" || exit 1
    find . | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then t=l; elif [ -d "$p" ]; then t=d; elif [ -f "$p" ]; then t=f; else t=o; fi
      printf '%s|%s|%s|%s|%s\n' "$p" "$t" "$(readlink "$p" 2>/dev/null)" \
        "$( [ "$t" = f ] && wc -c < "$p" | tr -d ' ')" "$(_mtime "$p")"
    done
    find . -type f -exec sh -c 'for f; do if command -v sha256sum >/dev/null; then sha256sum "$f"; else shasum -a 256 "$f"; fi; done' sh {} + | LC_ALL=C sort
  )
}
