# Sink of block-destructive-platform for hooks/lib/cmdparse.awk. CMDP_RULES: one 'name|regex' per line, placeholders
# already expanded; the regex sees the command and its arguments joined by the parser's field separator (US, which
# <S>, <G> and <E> accept as a space). A command whose arguments are text (git, grep, echo, python -c…) is skipped:
# naming a destructive command there is not running it. The first rule that matches blocks, by name.
BEGIN {
  n = split(ENVIRON["CMDP_RULES"], RR, "\n")
  for (i = 1; i <= n; i++) {
    if (RR[i] == "") continue
    p = index(RR[i], "|"); NRULE++; RN[NRULE] = substr(RR[i], 1, p - 1); RX[NRULE] = substr(RR[i], p + 1)
  }
}
function cmd_seen(d, k, cls, m, V,   s, j) {
  if (k == "deep") hit("nested too deeply to inspect")
  if (cls == "data") return
  s = join(V, 1, m, US)
  for (j = 1; j <= NRULE; j++) if (s ~ RX[j]) hit(RN[j])
}
function cmd_redir(d, kind, target) { }   # redirections are not looked at
