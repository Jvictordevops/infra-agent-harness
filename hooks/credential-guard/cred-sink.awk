# Sink of credential-guard for hooks/lib/cmdparse.awk: which words of each simple command could be a credential
# path. It does not decide: hooks/lib/credentials.sh does (cred_match, readers, copies). Output, one line each:
#   W<TAB>index<TAB>word            a word of the simple command (0 = the command), then, per path-like piece of
#   C<TAB>index<TAB>flag<TAB>piece<TAB>lit
#                                   it that could be a credential: flag s = sent as @path or file://path, - =
#                                   plain; lit l = its * ? [ were all quoted or escaped (plain text, not a glob)
#   S                               the end of the simple command
#   R<TAB>flag<TAB>piece<TAB>lit    a piece of the target of '<' (read), same fields: blocks on its own
#   K<TAB>line                      a line of the secret-commands files (SEC_FILES) whose anchor is in the
#                                   command line (sec_check_line looks only at those)
# The first argument of jq and the script of sed are a program, not a path: they are not reported (jq '.key'
# is not a *.key file, sed "s|$HOME|~|" does not read ~). The files they read still are (jq . f, sed p f,
# jq -f f, jq --rawfile n f, sed -f f). yq is not exempt: its filter can read files (load("…")).
# Environment: CRED_ANCHORS (one per line), CRED_HOME, SEC_FILES (one path per line).

# Quick filter: only pieces that could be a credential path go to the shell side (an unquoted glob in raw, a bare
# home directory, or an anchor of a pattern inside). An anchor "*" (a pattern with no fixed piece) lets
# everything through.
function maybe(p, raw,   i) {
  sub(/\/+$/, "", p)
  if (raw ~ /[*?[]/ || p == "~" || p == "$HOME" || p == "${HOME}" || p == home) return 1
  for (i = 1; i <= nanch; i++) if (anch[i] == "*" || index(p, anch[i]) > 0) return 1
  return 0
}
# The anchors come in the environment: the awk of macOS refuses a newline in a -v value
BEGIN { home = ENVIRON["CRED_HOME"]; nanch = split(ENVIRON["CRED_ANCHORS"], anch, "\n"); if (anch[nanch] == "") nanch-- }

# EX[j] = 1 for the words of V[2..n] that are the program of jq or sed. Options that take a value are skipped
# (jq: --arg, --argjson, --slurpfile, --rawfile take a name and a value; --indent, -L one; -f/--from-file one,
# and then there is no program among the positionals. sed: -e/--expression is the program, -f/--file is not).
function program_words(b, n, V,   j, w, given) {
  split("", EX); given = 0
  if (b != "jq" && b != "sed") return
  for (j = 2; j <= n; j++) {
    w = V[j]
    if (w == "--") { if (!given && j < n) EX[j + 1] = 1; return }
    if (w !~ /^-./) { if (!given) EX[j] = 1; return }
    if (b == "jq") {
      if (w ~ /^--(arg|argjson|slurpfile|rawfile)$/) { j += 2; continue }
      if (w == "--from-file" || w ~ /^-[A-Za-z]*f$/) { given = 1; j++; continue }
      if (w == "--indent" || w == "--library-path" || w ~ /^-[A-Za-z]*L$/) { j++; continue }
    } else {
      if (w == "--expression" || w ~ /^-[A-Za-z]*e$/) { given = 1; if (j < n) EX[j + 1] = 1; j++; continue }
      if (w ~ /^--expression=/ || w ~ /^-e./) { given = 1; EX[j] = 1; continue }
      if (w == "--file" || w ~ /^-[A-Za-z]*f$/) { given = 1; j++; continue }
      if (w == "-l" || w == "--line-length") { j++; continue }
    }
  }
}

# The path-like pieces of a word as typed (raw, with its quoted * ? [ as \001-\003): split at the characters that
# separate paths inside a word (a=b:~/.aws/credentials, --opt=@path, "a;b"). Calls report(flag, piece, lit).
function pieces(raw, idx, redir,   t, n, parts, i, p, pr, flag, l) {
  t = raw; gsub(/file:\/\//, "@", t)
  n = split(t, parts, /[ \047"=:,()<>;|&`]/)
  for (i = 1; i <= n; i++) {
    p = parts[i]; flag = redir ? "r" : "-"
    if (substr(p, 1, 1) == "@") { flag = "s"; sub(/^@+/, "", p) }
    pr = unlit(p); l = (p != pr && p !~ /[*?[]/) ? "l" : "-"
    if (pr == "" || !maybe(pr, p)) continue
    if (redir) print "R\t" flag "\t" pr "\t" l
    else print "C\t" idx "\t" flag "\t" pr "\t" l
  }
}

function cmd_seen(d, k, cls, n, V,   j, w) {
  if (k == "deep") hit("A command nested too deeply to inspect.")
  program_words(base(V[1]), n, V)
  for (j = 1; j <= n; j++) {
    w = V[j]; gsub(/[\t\n]/, " ", w)
    print "W\t" (j - 1) "\t" w
    if (!(j in EX)) pieces(VL[j], j - 1, 0)
  }
  print "S"
}
# Only '<' reads. Output targets (> >> &>) and descriptor copies are not arguments.
function cmd_redir(d, kind, target, lit) { if (kind == "in") pieces(lit, -1, 1) }

END {
  # First the lines of the secret-commands files (SEC_FILES, one path per line) whose anchor, their longest
  # piece without * ? [, is in the command line: K<TAB>line
  nsf = split(ENVIRON["SEC_FILES"], sf, "\n")
  for (fi = 1; fi <= nsf; fi++) {
    if (sf[fi] == "") continue
    while ((getline sl < sf[fi]) > 0) {
      sub(/[ \t]+#.*$/, "", sl); sub(/[ \t]+$/, "", sl)
      if (sl == "" || sl ~ /^#/) continue
      sn = split(sl, sw, /[ \t]+/); sbest = ""
      for (sk = 1; sk <= sn; sk++) { sm = split(sw[sk], spc, /[*?[]/); for (sj = 1; sj <= sm; sj++) if (length(spc[sj]) > length(sbest)) sbest = spc[sj] }
      if (index(buf, sbest) > 0) print "K\t" sl
    }
    close(sf[fi])
  }
}
