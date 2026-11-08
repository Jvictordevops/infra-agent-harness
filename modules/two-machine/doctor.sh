# shellcheck shell=bash
# two-machine module: checks. Sourced by bin/doctor when "modules=two-machine" is active; uses its
# ok/warn/fail, MACHINE and MODULE_DIR. No network calls. Must not exit.
# 'cond && ok … || warn …' is safe: ok/warn/fail only append to an array and never fail.
# shellcheck disable=SC2015

tm_name="${IAH_MACHINE:-$(hostname -s 2>/dev/null || echo unknown)}"
ok "two-machine: this machine is '$tm_name' ($MACHINE; set IAH_MACHINE to name it yourself)"

command -v ssh >/dev/null && ok "two-machine: ssh present" || warn "two-machine: ssh missing (needed only for bin/ro --host)"

[ -n "${RO_REMOTE_BIN:-}" ] && ok "two-machine: RO_REMOTE_BIN set ($RO_REMOTE_BIN)" \
  || ok "two-machine: RO_REMOTE_BIN not set (bin/ro --host uses ~/infra-agent-harness/bin/ro on the remote machine)"

if plugin_mode; then ok "two-machine: role skill comes from the plugin"
else [ -e "$HOME/.claude/skills/role" ] && ok "two-machine: role skill linked" \
  || warn "two-machine: role skill not linked (bin/link-harness)"; fi
