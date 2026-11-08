# shellcheck shell=bash
# Evidence module: install step. Sourced by bin/link-harness when "modules=evidence" is active; uses its
# say/link helpers, MODULE_DIR and MODULE_LINK_DIR (the path to write into links: stable link in plugin mode). Must not exit.
#   - cpush / cpull -> bin/clip in ~/.local/bin
#   - WSL only: cpush.cmd / cpull.cmd for Windows terminals (LINK_HARNESS_WINDOWS=0 skips this)

link "$MODULE_LINK_DIR/bin/clip" "$HOME/.local/bin/cpush"
link "$MODULE_LINK_DIR/bin/clip" "$HOME/.local/bin/cpull"
if [ "${DRY_RUN:-0}" = 1 ]; then :   # dry run: only the links above are simulated
elif [ "$(uname)" = "Darwin" ] && ! grep -qs 'HOME/.local/bin' "$HOME/.zshrc"; then
  # shellcheck disable=SC2016
  echo 'export PATH="$HOME/.local/bin:$PATH"  # infra-agent-harness (cpush/cpull)' >> "$HOME/.zshrc"; say "added ~/.local/bin to PATH in ~/.zshrc"
fi

if [ "${DRY_RUN:-0}" != 1 ] && [ "${LINK_HARNESS_WINDOWS:-1}" = 1 ] && { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; }; then
  ev_winprof="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r' || true)"
  if [ -z "$ev_winprof" ]; then
    say "evidence: cannot resolve %USERPROFILE%; cpush.cmd / cpull.cmd skipped"
  else
    # clip.exe already exists in Windows, hence the names cpush / cpull
    ev_wb="$(wslpath "$ev_winprof")/bin"; mkdir -p "$ev_wb"
    for ev_c in cpush cpull; do
      printf '@echo off\r\nwsl.exe --cd ~ --exec bash -ic "%s %s %%*"\r\n' "$MODULE_LINK_DIR/bin/clip" "${ev_c#c}" > "$ev_wb/$ev_c.cmd.new"
      if cmp -s "$ev_wb/$ev_c.cmd.new" "$ev_wb/$ev_c.cmd"; then rm -f "$ev_wb/$ev_c.cmd.new"
      else mv "$ev_wb/$ev_c.cmd.new" "$ev_wb/$ev_c.cmd"; say "wrote $ev_winprof\\bin\\$ev_c.cmd"; fi
    done
    # shellcheck disable=SC2016
    powershell.exe -NoProfile -Command '$b = Join-Path $env:USERPROFILE "bin"; $p = [Environment]::GetEnvironmentVariable("Path","User"); if (($p -split ";") -notcontains $b) { [Environment]::SetEnvironmentVariable("Path", ($p.TrimEnd(";") + ";" + $b), "User"); "added" }' 2>/dev/null \
      | grep -q added && say "added %USERPROFILE%\\bin to the user PATH (open a new terminal)"
  fi
fi
