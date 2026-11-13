# Sink of ro-guard (every mode) for hooks/lib/cmdparse.awk: a command that WRITES into a protected path blocks.
# Writing = a redirection to it (> >> >|), or a command that changes files given the path: rm mv tee touch chmod chown
# chgrp truncate patch shred unlink rmdir (any argument), cp install ln rsync scp (the destination: last argument,
# or -t DIR), sed -i / --in-place (any argument), dd of=. Reading it, listing it or naming it in text is not writing.
# CMDP_PROT: one 'F<TAB>path' (that file) or 'D<TAB>path' (that directory and everything under it) per line, absolute.
# CMDP_HOME and CMDP_CWD (may be empty) expand ~, $HOME and relative paths. A script written on the fly is not looked at.
BEGIN {
  home = ENVIRON["CMDP_HOME"]; cwd = ENVIRON["CMDP_CWD"]
  n = split(ENVIRON["CMDP_PROT"], PL, "\n")
  for (i = 1; i <= n; i++) {
    if (PL[i] == "") continue
    p = index(PL[i], "\t"); NP++; PK[NP] = substr(PL[i], 1, p - 1); PP[NP] = substr(PL[i], p + 1)
  }
  n = split("rm mv tee touch chmod chown chgrp truncate patch shred unlink rmdir", a, " "); for (i = 1; i <= n; i++) ANY[a[i]] = 1
  n = split("cp install ln rsync scp", a, " "); for (i = 1; i <= n; i++) DEST[a[i]] = 1
}
# ~, $HOME, ${HOME} and relative paths made absolute; . .. and // collapsed. No symlink resolution (awk cannot).
function norm(p,   k, m, parts, out, no) {
  if (p == "~" || p == "$HOME" || p == "${HOME}") p = home
  else if (p ~ /^~\//) p = home substr(p, 2)
  else if (p ~ /^\$HOME\//) p = home substr(p, 6)
  else if (p ~ /^\$\{HOME\}\//) p = home substr(p, 8)
  if (substr(p, 1, 1) != "/" && cwd != "") p = cwd "/" p
  m = split(p, parts, "/"); no = 0
  for (k = 1; k <= m; k++) {
    if (parts[k] == "" || parts[k] == ".") continue
    if (parts[k] == "..") { if (no > 0) no--; continue }
    out[++no] = parts[k]
  }
  p = ""
  for (k = 1; k <= no; k++) p = p "/" out[k]
  return p
}
function protected(raw,   p, i) {
  if (raw == "") return ""
  p = norm(raw)
  for (i = 1; i <= NP; i++) {
    if (PK[i] == "F" && p == PP[i]) return PP[i]
    if (PK[i] == "D" && (p == PP[i] || index(p, PP[i] "/") == 1)) return PP[i]
  }
  return ""
}
function chk(raw, how,   w) { w = protected(raw); if (w != "") hit(how " " w) }
function cmd_redir(d, kind, target) { if (kind == "out") chk(target, "redirection to") }
function cmd_seen(d, k, cls, m, V,   b, j, inplace) {
  if (k == "deep") return
  b = base(V[1])
  if (b in ANY) { for (j = 2; j <= m; j++) if (V[j] !~ /^-/) chk(V[j], b); return }
  if (b in DEST) {
    for (j = 2; j <= m; j++) {
      if (V[j] == "-t" && j < m) chk(V[j + 1], b)
      if (V[j] ~ /^--target-directory=/) chk(substr(V[j], 20), b)
    }
    if (V[m] !~ /^-/) chk(V[m], b)
    return
  }
  if (b == "sed") {
    inplace = 0
    for (j = 2; j <= m; j++) if (V[j] ~ /^-[A-Za-z]*i/ || V[j] ~ /^--in-place/) inplace = 1
    if (inplace) for (j = 2; j <= m; j++) if (V[j] !~ /^-/) chk(V[j], b " -i")
    return
  }
  if (b == "dd") for (j = 2; j <= m; j++) if (V[j] ~ /^of=/) chk(substr(V[j], 4), b)
}
