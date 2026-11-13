# cmdparse.awk — common command parser of the guards (hooks/lib/cmdparse.sh runs it).
# stdin: the command line. Each guard adds a sink file with  function cmd_seen(depth, kind, cls, n, V)  and
# is run as  awk -f cmdparse.awk -f <sink>.awk . A sink reports with hit(reason): 'B<TAB>reason', then exit.
# No output = nothing found. Environment: CMDP_DATAFILE (the list of commands whose arguments are text);
# the rest belongs to each sink. Exit 2 = the parser itself failed (the guard then blocks).
#
# No awk recursion (portable to the awk of macOS): the lexer pushes the texts it finds inside a command
# ($(…), `…`, bash -c, eval, ssh host '…', heredoc to a shell…) on a queue, and the driver lexes them in turn.
# A sink may also see the target of each redirection with  function cmd_redir(depth, kind, target)  (kind in | out |
# fd = '>&1'); a sink that does not care defines it empty. Every simple command, after dropping VAR=, shell keywords and wrappers (sudo -u x, timeout 5, nice -n 5…),
# goes to cmd_seen(depth, kind, cls, n, V): V[1] is the command as typed, V[2..n] its arguments.
#   kind top | sub ($(…) `…` <(…)) | sh (bash -c) | eval | ssh | su | watch | exec (find -exec) | pipe |
#        heredoc | herestring | deep (nested past MAXD levels: the sink must block)
#   cls  data   = the arguments are text, not commands (git, grep, echo, printf, sed, cat, python -c…)
#        opaque = anything else: the arguments may hold a command
function base(s,   n, a) { sub(/\/+$/, "", s); n = split(s, a, "/"); return n ? a[n] : s }
function join(A, from, to, sep,   k, o) { o = ""; for (k = from; k <= to; k++) o = o (k > from ? sep : "") A[k]; return o }
function push(t, d, k) { qn++; QT[qn] = t; QD[qn] = d; QK[qn] = k; QW[qn] = 0 }
function pushw(t, d, k) { push(t, d, k); QW[qn] = 1 }
function hit(why) { print "B\t" why; exit 0 }
function wr(name, opts, pos) { WRAP[name] = 1; WOPT[name] = " " opts " "; WPOS[name] = pos }

BEGIN {
  US = "\037"; MAXD = 4
  n = split("{ } ! if then else elif do while until", a, " "); for (i = 1; i <= n; i++) KW[a[i]] = 1
  f = ENVIRON["CMDP_DATAFILE"]; nd = 0
  while ((r = (getline line < f)) > 0) { sub(/#.*/, "", line); n = split(line, a, " "); for (i = 1; i <= n; i++) { DATA[a[i]] = 1; nd++ } }
  close(f)
  if (r < 0 || nd == 0) { print "cmdparse: cannot read the list of data commands (" f ")" > "/dev/stderr"; broken = 1; exit 2 }
  wr("sudo", "-u -g -h -p -C -D -R -T -U -r -t", 0); wr("doas", "-u -C", 0); wr("env", "-u -C -S", 0)
  wr("command", "", 0); wr("builtin", "", 0); wr("exec", "-a", 0); wr("time", "-f -o", 0); wr("nohup", "", 0)
  wr("nice", "-n", 0); wr("ionice", "-c -n -p -P -u", 0); wr("setsid", "", 0); wr("stdbuf", "-i -o -e", 0)
  wr("timeout", "-s -k", 1); wr("flock", "-w -E", 1); wr("watch", "-n --interval", 0)
  wr("xargs", "-a -d -E -I -L -n -P -s -J", 0); wr("parallel", "-j -S -a -n -N", 0)
}

# --- the parser -----------------------------------------------------------------------------------
# index of the ')' that closes a $( or <( whose body starts at j (length+1 if it never closes)
function close_paren(t, j,   L, lvl, c, qq) {
  L = length(t); lvl = 1; qq = ""
  for (; j <= L; j++) {
    c = substr(t, j, 1)
    if (qq == "'") { if (c == "'") qq = ""; continue }
    if (qq == "\"") { if (c == "\\") j++; else if (c == "\"") qq = ""; continue }
    if (c == "\\") { j++; continue }
    if (c == "'" || c == "\"") { qq = c; continue }
    if (c == "(") lvl++
    else if (c == ")") { lvl--; if (lvl == 0) return j }
  }
  return L + 1
}
function close_tick(t, j,   L, c) { L = length(t); for (; j <= L; j++) { c = substr(t, j, 1); if (c == "\\") j++; else if (c == "`") return j }; return L + 1 }
# $( … ): queue its body; $(( … )) is arithmetic and runs nothing. Returns the index of the closing ')'
function subshell(t, j,   e) {
  if (substr(t, j, 1) == "(") return close_paren(t, j)
  e = close_paren(t, j); push(substr(t, j, e - j), CD + 1, "sub"); return e
}
function tick(t, i,   j) { j = close_tick(t, i + 1); push(substr(t, i + 1, j - i - 1), CD + 1, "sub"); return j }

function addword() {
  inword = 0
  if (hdp) { hdp = 0; hdmk = hdmk (hdmk == "" ? "" : US) word; word = ""; return }
  if (hsp) { hsp = 0; hsb = hsb (hsb == "" ? "" : "\n") word; word = ""; return }
  if (skipw) { skipw = 0; cmd_redir(CD, (rk == "fd" && word !~ /^[0-9]+-?$/) ? "out" : rk, word); word = ""; return }
  ws = ws (nw > 0 ? US : "") word; nw++; word = ""
}
function endsimple() {
  if (inword) addword()
  if (nw > 0) {
    if (hdmk != "") { HQn++; HQws[HQn] = ws; HQmk[HQn] = hdmk; HQhs[HQn] = hsb }
    else command(ws, hsb, "", CD, CK)
  }
  ws = ""; nw = 0; hdmk = ""; hsb = ""; skipw = 0; hsp = 0; hdp = 0
}
# the bodies of the heredocs queued on this line, from the character after the newline at i; returns the new i
function heredocs(t, i, L,   k, m, mk, nm, body, line, j) {
  for (k = 1; k <= HQn; k++) {
    nm = split(HQmk[k], mk, US); body = ""
    for (m = 1; m <= nm; m++) {
      while (i < L) {
        j = index(substr(t, i + 1), "\n"); line = (j ? substr(t, i + 1, j - 1) : substr(t, i + 1))
        i = j ? i + j : L
        sub(/^\t+/, "", line)
        if (line == mk[m]) break
        body = body line "\n"
      }
    }
    command(HQws[k], HQhs[k], body, CD, CK)
  }
  HQn = 0
  return i
}
function flush_pipe(   k) { if (pipesh) for (k = 1; k <= PTn; k++) push(PT[k], CD + 1, "pipe"); PTn = 0; pipesh = 0 }

function lex(t, d, k,   L, i, c, e, q) {
  CD = d; CK = k; L = length(t); q = ""; word = ""; inword = 0; ws = ""; nw = 0
  skipw = 0; hsp = 0; hdp = 0; hdmk = ""; hsb = ""; HQn = 0; PTn = 0; pipesh = 0
  for (i = 1; i <= L; i++) {
    c = substr(t, i, 1); e = substr(t, i + 1, 1)
    if (q == "'") { if (c == "'") q = ""; else word = word c; continue }
    if (q == "\"") {
      if (c == "\\") { if (e ~ /["\\$`]/) { word = word e; i++ } else word = word c; continue }
      if (c == "\"") { q = ""; continue }
      if (c == "$" && e == "(") { i = subshell(t, i + 2); word = word "$()"; continue }
      if (c == "`") { i = tick(t, i); word = word "$()"; continue }
      word = word c; continue
    }
    if (c == "\\") { if (i < L) { i++; if (e != "\n") { word = word e; inword = 1 } } ; continue }
    if (c == "'" || c == "\"") { q = c; inword = 1; continue }
    if (c == "#" && !inword) { while (i < L && substr(t, i + 1, 1) != "\n") i++; continue }
    if (c == "$" && e == "(") { i = subshell(t, i + 2); word = word "$()"; inword = 1; continue }
    if (c == "`") { i = tick(t, i); word = word "$()"; inword = 1; continue }
    if (c == " " || c == "\t") { if (inword) addword(); continue }
    if (c == "\n") { endsimple(); i = heredocs(t, i, L); flush_pipe(); continue }
    if (c == "&" && e == ">") {   # &> file
      if (inword) addword()
      i++; if (substr(t, i + 1, 1) == ">") i++
      skipw = 1; rk = "out"; continue
    }
    if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")") {
      endsimple()
      if (c == "|" && e != "|") { if (e == "&") i++; continue }   # a pipe: the pipeline goes on
      if ((c == "|" || c == "&") && e == c) i++
      else if (c == ";" && e == ";") i++
      if (HQn == 0) flush_pipe()
      continue
    }
    if (c == "<" || c == ">") {
      if (inword) { if (word ~ /^[0-9]+$/) { word = ""; inword = 0 } else addword() }
      if (c == "<" && e == "<") {
        if (substr(t, i + 2, 1) == "<") { i += 2; hsp = 1; continue }     # <<< here-string
        i++; if (substr(t, i + 1, 1) == "-") i++; hdp = 1; continue        # << heredoc
      }
      if (e == "(") { i = subshell(t, i + 2); word = word "$()"; inword = 1; continue }   # <(…) >(…)
      if (c == ">" && (e == ">" || e == "|")) i++
      else if (e == "&") { i++; fdup = 1 }
      skipw = 1; rk = (c == "<") ? "in" : (fdup ? "fd" : "out"); fdup = 0; continue
    }
    word = word c; inword = 1
  }
  endsimple()
  i = heredocs(t, L, L)
  flush_pipe()
}

# index of the command after a wrapper at W[s] (options with a value skipped); 0 = a lookup (command -v)
function wrap_skip(W, n, s, b,   j, o) {
  j = s + 1
  if ((b == "command" || b == "builtin") && W[j] ~ /^-[a-zA-Z]*[vV]/) return 0
  while (j <= n && W[j] ~ /^-/) {
    if (W[j] == "--") { j++; break }
    o = W[j]
    if (index(WOPT[b], " " o " ") > 0) j += 2; else j++
  }
  j += WPOS[b]
  while (j <= n && W[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) j++
  return j
}

function command(cws, hs, hb, d, k,   n, W, s, w, b, lb, m, V, j, cls, e, found) {
  n = split(cws, W, US)
  s = 1
  while (s <= n) {
    w = W[s]
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || (w in KW)) { s++; continue }
    b = base(w)
    if (!(b in WRAP)) break
    j = wrap_skip(W, n, s, b)
    if (j == 0) return
    if (b == "watch") { if (j <= n) push(join(W, j, n, " "), d + 1, "watch"); return }   # watch runs it through sh -c
    s = j
  }
  if (s > n) return
  b = base(W[s]); m = n - s + 1
  for (j = 1; j <= m; j++) V[j] = W[s + j - 1]
  lb = (b ~ /^python[0-9.]+$/) ? "python" : b   # python3, python3.12…
  cls = (lb in DATA) ? "data" : "opaque"
  cmd_seen(d, k, cls, m, V)
  if (b ~ /^(bash|sh|zsh|dash|ksh|ash)$/) {
    found = 0
    for (j = 2; j <= m; j++) {
      if (V[j] ~ /^-[A-Za-z]*c[A-Za-z]*$/) { if (j < m) push(V[j + 1], d + 1, "sh"); found = 1; break }
      if (V[j] !~ /^-/) { found = 2; break }   # a script file: not inspected
    }
    if (found == 0) { pipesh = 1; if (hb != "") push(hb, d + 1, "heredoc"); if (hs != "") push(hs, d + 1, "herestring") }
    return
  }
  if (b == "eval") push(join(V, 2, m, " "), d + 1, "eval")
  else if (b == "ssh") {
    for (j = 2; j <= m; j++) {
      if (V[j] == "--") { j++; break }
      if (V[j] ~ /^-[BbcDEeFIiJLlmOoPpQRSWw]$/) { j++; continue }
      if (V[j] ~ /^-/) continue
      break
    }
    if (j < m) push(join(V, j + 1, m, " "), d + 1, "ssh")
  } else if (b == "su") {
    for (j = 2; j < m; j++) if (V[j] ~ /^-[A-Za-z]*c$/ || V[j] == "--command") { push(V[j + 1], d + 1, "su"); break }
  } else if (b == "find") {
    for (j = 2; j <= m; j++) if (V[j] ~ /^-(exec|execdir|ok|okdir)$/) {
      e = j + 1; while (e <= m && V[e] != ";" && V[e] != "+") e++
      if (e > j + 1) pushw(join(V, j + 1, e - 1, US), d + 1, "exec")
      j = e
    }
  }
  if (b == "echo" || b == "printf") PT[++PTn] = join(V, 2, m, " ")
  if (hb != "") PT[++PTn] = hb
  if (hs != "") PT[++PTn] = hs
}

{ buf = buf (NR > 1 ? "\n" : "") $0 }
END {
  if (broken) exit 2
  gsub(/\037/, " ", buf)
  push(buf, 0, "top")
  while (qi < qn) {
    qi++
    if (QD[qi] > MAXD) { V1[1] = QT[qi]; cmd_seen(QD[qi], "deep", "opaque", 1, V1); continue }
    if (QW[qi]) command(QT[qi], "", "", QD[qi], QK[qi]); else lex(QT[qi], QD[qi], QK[qi])
  }
}
