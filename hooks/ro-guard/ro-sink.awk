# Sink of ro-guard for hooks/lib/cmdparse.awk: a command whose name is on the forbidden list (CMDP_FORB, a regex
# alternation) outside bin/ro blocks. Only the name counts, not the arguments; bin/ro's own arguments are not looked at.
function cmd_seen(d, k, cls, m, V,   b) {
  if (k == "deep") hit("A command nested too deeply to inspect.")
  if (V[1] == "bin/ro" || V[1] ~ /\/bin\/ro$/) return
  b = base(V[1])
  if (b ~ ("^(" ENVIRON["CMDP_FORB"] ")$")) hit("'" b "' outside bin/ro.")
}
