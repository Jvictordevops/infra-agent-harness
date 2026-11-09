# shellcheck shell=bash
# shellcheck disable=SC2034,SC2088  # CRED_HIT/CRED_WHAT are read by the callers; '~/' patterns are data, never expanded
# Credential files: the floor "agents never read credential files" (packs/README.md, "Credential files").
# Sourced by hooks/credential-guard, bin/ro and bin/lib/packs.sh. Bash 3.2 compatible.
#
#   . hooks/lib/credentials.sh
#   cred_patterns <harness>    patterns of the core (hooks/credential-guard/credential-files) and of every
#                              pack (packs/*/credential-files), one per line: '~/<path>' or '**/<name>'
#   cred_read_rules <harness>  the same patterns as Claude Code deny rules, JSON array: Read(~/…), Read(//**/…)
#   cred_load <harness>        loads the patterns and the readers (core hooks/credential-guard/readers +
#                              packs/*/credential-readers) into CRED_PATTERNS and CRED_READERS
#   cred_match <path> [lit]    0 if <path> is a credential file, a glob that would match one (~/.aws/*) or a
#                              directory that holds one (~/.aws, ~); sets CRED_HIT to the pattern. Needs cred_load.
#                              With lit not empty, its * ? [ are plain text (they were quoted in the command, so
#                              the shell does not expand them): only the name itself counts, not what it would match.
#   cred_check_line <command>  0 if the command line only uses credentials; 1 if it reads, copies or sends one
#                              (sets CRED_HIT and CRED_WHAT). Needs cred_load.
#   sec_check_line <command>   0 if no command that prints a secret (hooks/credential-guard/secret-commands +
#                              packs/*/secret-commands of the harness given to cred_load) shows it; 1 if its
#                              output ends on the screen, in a file or in a reader (sets CRED_HIT to the line of
#                              the list and CRED_WHAT). Needs cred_load.
#
# What counts as reading (decision "Leer o copiar, no usar"): a credential path given to a reader (cat, grep,
# cp, curl -T…, python -c…; list in the readers files), read with '<', or sent as '@path' / 'file://path'.
# Using it (ssh -i, --kubeconfig, KUBECONFIG=, source .env), listing it or changing its mode is allowed.
# Guards against mistakes, not against an adversary: a reader missing from the list, a script that opens the
# file itself, or a path built in a variable is not seen (the strict profile's sandbox covers those).
# The globs of cred_patterns/cred_load turn 'set -f' callers' globbing on for the loop and restore it.

_cred_files() { # $1 harness, $2 core file name, $3 pack file name -> existing files, one per line
  local f restore=0
  case $- in *f*) restore=1; set +f ;; esac
  [ -f "$1/hooks/credential-guard/$2" ] && printf '%s\n' "$1/hooks/credential-guard/$2"
  for f in "$1"/packs/*/"$3"; do [ -f "$f" ] && printf '%s\n' "$f"; done
  [ "$restore" = 0 ] || set -f
  return 0
}

_cred_lines() { # files on stdin -> their lines without comments, blank lines and trailing spaces
  local f line
  while IFS= read -r f; do
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%[[:space:]]#*}"; line="${line%"${line##*[![:space:]]}"}"
      case "$line" in ''|'#'*) continue ;; esac
      printf '%s\n' "$line"
    done < "$f"
  done
}

cred_patterns() { _cred_files "$1" credential-files credential-files | _cred_lines; }

cred_read_rules() {
  cred_patterns "$1" | while IFS= read -r p; do
    case "$p" in
      '~/'*) printf 'Read(%s)\n' "$p" ;;
      '**/'*) printf 'Read(//%s)\n' "$p" ;;
    esac
  done | jq -R . | jq -s 'reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)'
}

cred_load() {
  local l a
  CRED_PATTERNS=() CRED_READERS=() CRED_ANCHORS=""
  while IFS= read -r l; do
    CRED_PATTERNS+=("$l")
    # Anchor: a fixed piece every path that matches the pattern contains, for the tokenizer's quick filter.
    # ~/<x>: its first component (.aws, .ssh, .netrc); **/<name>: the name up to its first glob (.env, .key)
    case "$l" in
      '~/'*) a="${l#\~/}"; a="${a%%/*}" ;;
      *) a="${l#\*\*/}"; a="${a#\*}"; a="${a%%[\*\?\[]*}" ;;
    esac
    case "$a" in *[\*\?\[]*) a="" ;; esac
    if [ -n "$a" ]; then CRED_ANCHORS="$CRED_ANCHORS$a"$'\n'; else CRED_ANCHORS="$CRED_ANCHORS*"$'\n'; fi
  done < <(cred_patterns "$1")
  while IFS= read -r l; do CRED_READERS+=("$l"); done < <(_cred_files "$1" readers credential-readers | _cred_lines)
  CRED_HARNESS="$1"   # its secret-commands lists: picked by cred_check_line, used by sec_check_line
}

_cred_has_glob() { case "$1" in *[\*\?\[]*) return 0 ;; esac; return 1; }

cred_match() {
  local n="$1" lit="${2-}" p x base sample h='/~HOME~/'
  # shellcheck disable=SC2088,SC2016  # literal "~/", "$HOME" and "${HOME}" as typed in a command
  case "$n" in
    '~'|'$HOME'|'${HOME}'|"$HOME") n="${h%/}" ;;
    '~/'*) n="$h${n#\~/}" ;;
    '$HOME/'*) n="$h${n#\$HOME/}" ;;
    '${HOME}/'*) n="$h${n#\$\{HOME\}/}" ;;
    "$HOME/"*) n="$h${n#"$HOME"/}" ;;
  esac
  while [ "${n%/}" != "$n" ] && [ "$n" != / ]; do n="${n%/}"; done
  base="${n##*/}"
  for p in ${CRED_PATTERNS[@]+"${CRED_PATTERNS[@]}"}; do
    case "$p" in
      '~/'*)
        x="${p#\~/}"
        # shellcheck disable=SC2053  # the pattern is a glob on purpose
        if [[ "$n" == $h$x || "$n" == */$x || "$n" == $x ]]; then CRED_HIT="$p"; return 0; fi
        # a directory that holds it (~/.aws, ~/, .ssh from the home directory): reading it reads the file
        case "$h$x" in "$n"/*) CRED_HIT="$p"; return 0 ;; esac
        case "$x" in "$n"/*) CRED_HIT="$p"; return 0 ;; esac
        # a glob in the command that would reach the file: ~/.aws/*, /home/u/.ssh/id_*; not one that starts with
        # a glob (*/*), which would match anything
        if [ -z "$lit" ] && _cred_has_glob "$n" && ! _cred_has_glob "${n:0:1}"; then
          sample="${x//\*/x}"
          # shellcheck disable=SC2053
          if [[ "$h$sample" == $n || "$sample" == $n || "/u/$sample" == $n ]]; then CRED_HIT="$p"; return 0; fi
        fi ;;
      '**/'*)
        x="${p#\*\*/}"
        # shellcheck disable=SC2053
        if [[ "$base" == $x ]]; then CRED_HIT="$p"; return 0; fi
        case "$base" in *[!\*\?]*) ;; *) continue ;; esac   # a bare '*' or '?*' names no file in particular
        if [ -z "$lit" ] && _cred_has_glob "$base"; then
          sample="${x//\*/x}"
          # shellcheck disable=SC2053
          if [[ "$sample" == $base ]]; then CRED_HIT="$p"; return 0; fi
        fi ;;
    esac
  done
  return 1
}

# Tokenizer: the command line on stdin -> one line per word ('W<TAB>index<TAB>word'), per path-like piece of
# a word ('C<TAB>index<TAB>flag<TAB>piece<TAB>lit', flag r = read with '<', s = sent as @path or file://path,
# - = plain argument; lit l = its * ? [ are all quoted or escaped, so plain text, else -) and 'S' at the end of
# each simple command. Quotes are honoured; ; & | ( ) ` $( <( and newlines end a command; comments, heredoc
# bodies, here-strings and output redirection targets are not arguments.
# shellcheck disable=SC2016  # an awk program: its $ are awk's
_CRED_AWK='
# A word of digits right before > or < is the number of a redirection (2>/dev/null), not an argument
function fd_or_word() { if (word ~ /^[0-9]+$/) { word = ""; inword = 0 } else emit_word() }
function emit_seg() { if (nw > 0) print "S"; nw = 0; nextr = 0; nextout = 0 }
# A quoted or escaped * ? [ is text, not a glob (grep -o "x.*"): kept as \001 \002 \003 inside the word until
# the word is emitted, so the pieces know which of their globs the shell would expand
function lit(c) { return c == "*" ? "\001" : c == "?" ? "\002" : c == "[" ? "\003" : c }
function unlit(s) { gsub("\001", "*", s); gsub("\002", "?", s); gsub("\003", "[", s); return s }
# Quick filter: only pieces that could be a credential path go to cred_match (an unquoted glob in raw, a bare
# home directory, or an anchor of a pattern inside). An anchor "*" (a pattern with no fixed piece) lets
# everything through.
function maybe(p, raw,   i) {
  sub(/\/+$/, "", p)
  if (raw ~ /[*?[]/ || p == "~" || p == "$HOME" || p == "${HOME}" || p == home) return 1
  for (i = 1; i <= nanch; i++) if (anch[i] == "*" || index(p, anch[i]) > 0) return 1
  return 0
}
BEGIN { nanch = split(anchors, anch, "\n"); if (anch[nanch] == "") nanch-- }
function emit_word(   w, t, n, i, parts, p, pr, flag, l) {
  w = word; word = ""; inword = 0
  if (hdpend) { hdm = unlit(w); sub(/^-/, "", hdm); hdpend = 0; return }
  if (nextout) { nextout = 0; return }
  gsub(/[\t\n]/, " ", w)
  print "W\t" nw "\t" unlit(w)
  t = w; gsub(/file:\/\//, "@", t)
  n = split(t, parts, /[ \047"=:,()<>;|&`]/)
  for (i = 1; i <= n; i++) {
    p = parts[i]; flag = nextr ? "r" : "-"
    if (substr(p, 1, 1) == "@") { flag = "s"; sub(/^@+/, "", p) }
    pr = unlit(p); l = (p != pr && p !~ /[*?[]/) ? "l" : "-"
    if (pr != "" && maybe(pr, p)) print "C\t" nw "\t" flag "\t" pr "\t" l
  }
  nextr = 0; nw++
}
{ buf = buf (NR > 1 ? "\n" : "") $0 }
END {
  # First the lines of the secret-commands files (ENVIRON SEC_FILES, one path per line) whose anchor, their
  # longest piece without * ? [, is in the command line: K<TAB>line (sec_check_line parses only for those)
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
  L = length(buf); q = ""; word = ""; inword = 0; nw = 0; nextr = 0; nextout = 0; hdpend = 0; hdm = ""
  for (i = 1; i <= L; i++) {
    c = substr(buf, i, 1)
    if (q == "\047") { if (c == "\047") q = ""; else word = word lit(c); continue }
    if (q == "\"") {
      if (c == "\\" && i < L) { d = substr(buf, i + 1, 1); if (d ~ /["\\$`]/) { word = word d; i++; continue } }
      if (c == "\"") q = ""; else word = word lit(c)
      continue
    }
    if (c == "\\" && i < L) { i++; d = substr(buf, i, 1); if (d != "\n") { word = word lit(d); inword = 1 }; continue }
    if (c == "\047" || c == "\"") { q = c; inword = 1; continue }
    if (c == "#" && !inword) { while (i < L && substr(buf, i + 1, 1) != "\n") i++; continue }
    if (c == " " || c == "\t") { if (inword) emit_word(); continue }
    if (c == "\n") {
      if (inword) emit_word()
      emit_seg()
      if (hdm != "") {   # skip the heredoc body, up to the line that is the marker (tabs allowed before it)
        while (i < L) {
          j = index(substr(buf, i + 1), "\n"); line = (j ? substr(buf, i + 1, j - 1) : substr(buf, i + 1))
          i = j ? i + j : L
          sub(/^\t+/, "", line)
          if (line == hdm) break
        }
        hdm = ""
      }
      continue
    }
    if (c ~ /[;&|()`]/) { if (inword) emit_word(); emit_seg(); continue }
    if (c == "$" && substr(buf, i + 1, 1) == "(") { if (inword) emit_word(); emit_seg(); i++; continue }
    if (c == "<") {
      if (inword) fd_or_word()
      d = substr(buf, i + 1, 1)
      if (d == "<") {
        if (substr(buf, i + 2, 1) == "<") { i += 2; nextout = 1; continue }   # <<< here-string: data
        i++; hdpend = 1; continue                                              # << heredoc: marker
      }
      if (d == "(") { emit_seg(); i++; continue }
      if (d == "&") { i++; nextout = 1; continue }
      nextr = 1; continue
    }
    if (c == ">") {
      if (inword) fd_or_word()
      if (substr(buf, i + 1, 1) == ">") i++
      if (substr(buf, i + 1, 1) == "&") i++
      if (substr(buf, i + 1, 1) == "(") { emit_seg(); i++; continue }
      nextout = 1; continue
    }
    word = word c; inword = 1
  }
  if (inword) emit_word()
  emit_seg()
}'

# Is the simple command in _CW (from index $1) a reader? Reader lines: '<command>' or '<command> <word>'
# (a reader only when <word> is one of its arguments). python3.12 also matches 'python'.
_cred_is_reader() {
  local s="$1" cmd="${_CW[$1]##*/}" cmd2 r rc rw k j
  cmd2="${cmd%%[0-9.]*}"
  for ((k = 0; k < ${#CRED_READERS[@]}; k++)); do
    r="${CRED_READERS[$k]}"; rc="${r%% *}"; rw="${r#* }"; [ "$rw" = "$r" ] && rw=""
    [ "$rc" = "$cmd" ] || [ "$rc" = "$cmd2" ] || continue
    [ -z "$rw" ] && return 0
    for ((j = s + 1; j < ${#_CW[@]}; j++)); do [ "${_CW[$j]}" = "$rw" ] && return 0; done
  done
  return 1
}

_cred_has_word() { # 0 if a word of _CW is one of $@ or starts with one of them followed by '.' or '=' (-i.bak)
  local k w o
  for ((k = 0; k < ${#_CW[@]}; k++)); do
    w="${_CW[$k]}"
    for o in "$@"; do case "$w" in "$o"|"$o".*|"$o"=*) return 0 ;; esac; done
  done
  return 1
}

_cred_join() { # $1 first index: words of _CW from there, joined by spaces
  local out="" k
  for ((k = $1; k < ${#_CW[@]}; k++)); do out="$out ${_CW[$k]}"; done
  printf '%s' "${out# }"
}

# Evaluates one simple command (_CW words, _CI/_CF/_CP/_CL candidates); $1 depth. 1 = reads a credential.
_cred_segment() {
  local depth="$1" s=0 cmd k i reader=-1 host lit
  while [ "$s" -lt "${#_CW[@]}" ]; do
    case "${_CW[$s]}" in
      [A-Za-z_]*=*|sudo|env|command|exec|time|nohup|nice|xargs|'{'|'}'|'!'|if|then|else|elif|do|while|until|-*) s=$((s + 1)) ;;
      timeout) s=$((s + 2)) ;;
      *) break ;;
    esac
  done
  cmd="${_CW[$s]-}"; cmd="${cmd##*/}"
  # Commands that run other commands: look inside them
  if [ "$depth" -lt 4 ]; then
    case "$cmd" in
      bash|sh|zsh|dash|ksh)
        for ((k = s + 1; k < ${#_CW[@]}; k++)); do
          case "${_CW[$k]}" in -*c) [ -n "${_CW[$((k + 1))]-}" ] && { cred_check_line "${_CW[$((k + 1))]}" $((depth + 1)) || return 1; }; break ;; -*) ;; *) break ;; esac
        done ;;
      eval|watch) cred_check_line "$(_cred_join $((s + 1)))" $((depth + 1)) || return 1 ;;
      ssh)
        host=""
        for ((k = s + 1; k < ${#_CW[@]}; k++)); do
          case "${_CW[$k]}" in
            -[BbcDEeFIiJLlmOoPpQRSWw]) k=$((k + 1)) ;;
            -*) ;;
            *) host="$k"; break ;;
          esac
        done
        [ -n "$host" ] && { cred_check_line "$(_cred_join $((host + 1)))" $((depth + 1)) || return 1; } ;;
    esac
  fi
  for ((i = 0; i < ${#_CP[@]}; i++)); do
    # A quoted glob is text (grep -o 'x.*'), except in the remote path of a copy (scp 'host:~/.ssh/id_*' .):
    # the remote shell expands it
    lit=""; [ "${_CL[$i]-}" = l ] && lit=1
    case "$cmd" in scp|sftp|rsync) case "${_CW[${_CI[$i]}]-}" in *:*) lit="" ;; esac ;; esac
    cred_match "${_CP[$i]}" "$lit" || continue
    case "${_CF[$i]}" in
      r) CRED_WHAT="read with '<'"; return 1 ;;
      s) CRED_WHAT="sent as @file or file://"; return 1 ;;
    esac
    k="${_CI[$i]}"
    [ "$k" -gt "$s" ] || continue
    # scp/sftp/rsync: the identity key (-i, -o IdentityFile=…, -e "ssh -i …") is a use, not a copy
    case "$cmd" in scp|sftp|rsync)
      case "${_CW[$((k - 1))]-}" in -i|-e|-o|-F|-J) continue ;; esac
      case "${_CW[$k]}" in --rsh=*|-i*|-o*) continue ;; esac ;;
    esac
    # The destination of a copy is written, not read (cp .env.example .env); sed -i edits without showing
    case "$cmd" in
      cp|scp|rsync) [ "$k" = $((${#_CW[@]} - 1)) ] && continue ;;
      dd) case "${_CW[$k]}" in of=*) continue ;; esac ;;
      sed) _cred_has_word -i --in-place && continue ;;
    esac
    if [ "$reader" = -1 ]; then if _cred_is_reader "$s"; then reader=1; else reader=0; fi; fi
    [ "$reader" = 1 ] && { CRED_WHAT="given to '$cmd'"; return 1; }
  done
  return 0
}

cred_check_line() {
  local depth="${2:-0}" kind a b c d out files=""
  local _CW=() _CI=() _CF=() _CP=() _CL=()
  if [ "$depth" = 0 ]; then _sec_files; files="$_SEC_FILES"; SEC_LINES=(); SEC_PICKED="$1"; fi
  out="$(printf '%s\n' "$1" | SEC_FILES="$files" awk -v anchors="$CRED_ANCHORS" -v home="$HOME" "$_CRED_AWK")"
  while IFS=$'\t' read -r kind a b c d; do
    case "$kind" in
      K) SEC_LINES+=("$a") ;;
      W) _CW[a]="$b" ;;
      C) _CI+=("$a"); _CF+=("$b"); _CP+=("$c"); _CL+=("$d") ;;
      S) _cred_segment "$depth" || return 1; _CW=() _CI=() _CF=() _CP=() _CL=() ;;
    esac
  done <<<"$out"
  return 0
}

# --- Commands that print a secret (decision "Mostrar, no usar"): where does their output go?
# Parser: the command line on stdin -> 'W<TAB>node<TAB>index<TAB>word' per word and, when a simple command
# (node) ends, 'N<TAB>node<TAB>parent<TAB>word<TAB>out'. parent/word: the node and the index of its word that
# holds this node as $(…), `…` or <(…) (-1 at the top). out: where its standard output goes: |<node> piped to
# that node, > a file, 0 /dev/null, - the screen (top) or the word of the parent. Quotes are honoured ($(…)
# also inside double quotes); comments, heredoc bodies, here-strings and input redirections are not words.
# A subshell ( … ) or >(…) is only a separator; a ')' of a case pattern inside $(…) closes it too early.
# shellcheck disable=SC2016  # an awk program: its $ are awk's
_SEC_AWK='
function newnode(par, pw) { nid++; P[nid] = par; PW[nid] = pw; NW[nid] = 0; OUT[nid] = "-"; return nid }
function endnode(pipe,   nx) {
  if (inword) emit_word()
  nx = newnode(P[cur], PW[cur])
  if (pipe && OUT[cur] == "-") OUT[cur] = "|" nx
  print "N\t" cur "\t" P[cur] "\t" PW[cur] "\t" OUT[cur]
  cur = nx; pend = ""; skipw = 0
}
function emit_word(   w) {
  w = word; word = ""; inword = 0
  if (hdpend) { hdm = w; sub(/^-/, "", hdm); hdpend = 0; return }
  if (pend != "") { if (pend == "1" || pend == "&") OUT[cur] = (w == "/dev/null") ? "0" : ">"; pend = ""; return }
  if (skipw) { skipw = 0; return }
  gsub(/[\t\n]/, " ", w)
  print "W\t" cur "\t" NW[cur] "\t" w
  NW[cur]++
}
# $(…), `…` or <(…): a new node whose output goes into the word being built in the current one
function open_sub(t) {
  sp++; ST[sp] = t; SC[sp] = cur; SQ[sp] = q; SWD[sp] = word; SPD[sp] = pend; SSK[sp] = skipw; SHD[sp] = hdpend
  cur = newnode(cur, NW[cur]); word = ""; inword = 0; q = ""; pend = ""; skipw = 0; hdpend = 0
}
function close_sub() {
  if (inword) emit_word()
  print "N\t" cur "\t" P[cur] "\t" PW[cur] "\t" OUT[cur]
  cur = SC[sp]; q = SQ[sp]; word = SWD[sp]; pend = SPD[sp]; skipw = SSK[sp]; hdpend = SHD[sp]; sp--
  inword = 1
}
function backtick() { if (sp > 0 && ST[sp] == "b") close_sub(); else open_sub("b") }
{ buf = buf (NR > 1 ? "\n" : "") $0 }
END {
  L = length(buf); q = ""; word = ""; inword = 0; pend = ""; skipw = 0; hdpend = 0; hdm = ""; sp = 0; nid = 0
  cur = newnode(-1, -1)
  for (i = 1; i <= L; i++) {
    c = substr(buf, i, 1); d = substr(buf, i + 1, 1)
    if (q == "\047") { if (c == "\047") q = ""; else word = word c; continue }
    if (q == "\"") {
      if (c == "\\" && i < L && d ~ /["\\$`]/) { word = word d; i++; continue }
      if (c == "\"") { q = ""; continue }
      if (c == "$" && d == "(") { i++; open_sub("s"); continue }
      if (c == "`") { backtick(); continue }
      word = word c; continue
    }
    if (c == "\\" && i < L) { i++; if (d != "\n") { word = word d; inword = 1 }; continue }
    if (c == "\047" || c == "\"") { q = c; inword = 1; continue }
    if (c == "#" && !inword) { while (i < L && substr(buf, i + 1, 1) != "\n") i++; continue }
    if (c == " " || c == "\t") { if (inword) emit_word(); continue }
    if (c == "\n") {
      endnode(0)
      if (hdm != "") {   # skip the heredoc body, up to the line that is the marker (tabs allowed before it)
        while (i < L) {
          j = index(substr(buf, i + 1), "\n"); line = (j ? substr(buf, i + 1, j - 1) : substr(buf, i + 1))
          i = j ? i + j : L
          sub(/^\t+/, "", line)
          if (line == hdm) break
        }
        hdm = ""
      }
      continue
    }
    if (c == "`") { backtick(); continue }
    if (c == "$" && d == "(") { i++; open_sub("s"); continue }
    if (c == "(") { if (inword) emit_word(); sp++; ST[sp] = "g"; endnode(0); continue }
    if (c == ")") {
      if (sp > 0 && ST[sp] == "s") { close_sub(); continue }
      if (sp > 0 && ST[sp] == "g") sp--
      endnode(0); continue
    }
    if (c == "|") { if (d == "|") { i++; endnode(0); continue }; if (d == "&") i++; endnode(1); continue }
    if (c == "&") {
      if (d == "&") { i++; endnode(0); continue }
      if (d == ">") { if (inword) emit_word(); i++; if (substr(buf, i + 1, 1) == ">") i++; pend = "&"; continue }
      endnode(0); continue
    }
    if (c == ";") { endnode(0); continue }
    if (c == "<") {
      if (inword && word ~ /^[0-9]+$/) { word = ""; inword = 0 } else if (inword) emit_word()
      if (d == "<") {
        if (substr(buf, i + 2, 1) == "<") { i += 2; skipw = 1; continue }   # <<< here-string: data
        i++; hdpend = 1; continue                                           # << heredoc: marker
      }
      if (d == "(") { i++; open_sub("s"); continue }
      if (d == "&") i++
      skipw = 1; continue
    }
    if (c == ">") {
      fd = "1"
      if (inword && word ~ /^[0-9]+$/) { fd = word; word = ""; inword = 0 } else if (inword) emit_word()
      if (d == ">" || d == "|") { i++; d = substr(buf, i + 1, 1) }
      if (d == "&") { i++; skipw = 1; continue }                     # >&2, 2>&1: a copy of a descriptor
      if (d == "(") { i++; sp++; ST[sp] = "g"; endnode(0); continue }  # >(…): a separate command
      pend = fd; continue
    }
    word = word c; inword = 1
  }
  if (inword) emit_word()
  while (sp > 0) { if (ST[sp] != "g") close_sub(); else sp-- }
  print "N\t" cur "\t" P[cur] "\t" PW[cur] "\t" OUT[cur]
}'

_sec_words() { # $1 node -> _CW (its words) and _SEC_S (index of the command, after prefixes such as sudo, VAR=)
  local n="$1" k m="${_SNW[$1]:-0}"
  _CW=()
  for ((k = 0; k < m; k++)); do _CW[k]="${_SW[$((n * 100000 + k))]-}"; done
  _SEC_S=0
  while [ "$_SEC_S" -lt "${#_CW[@]}" ]; do
    case "${_CW[$_SEC_S]}" in
      [A-Za-z_]*=*|sudo|env|command|exec|time|nohup|nice|xargs|'{'|'}'|'!'|if|then|else|elif|do|while|until|-*) _SEC_S=$((_SEC_S + 1)) ;;
      timeout) _SEC_S=$((_SEC_S + 2)) ;;
      *) break ;;
    esac
  done
}

_sec_files() { # -> _SEC_FILES: the secret-commands files of the core and the packs of CRED_HARNESS, one per line
  local h="${CRED_HARNESS:-.}" f restore=0
  _SEC_FILES=""
  case $- in *f*) restore=1; set +f ;; esac
  [ -f "$h/hooks/credential-guard/secret-commands" ] && _SEC_FILES="$h/hooks/credential-guard/secret-commands"$'\n'
  for f in "$h"/packs/*/secret-commands; do [ -f "$f" ] && _SEC_FILES="$_SEC_FILES$f"$'\n'; done
  [ "$restore" = 0 ] || set -f
  return 0
}

_sec_is_secret() { # _CW/_SEC_S of a node -> 0 if it is one of SEC_LINES (CRED_HIT = the line)
  local cmd="${_CW[$_SEC_S]-}" k m j found f
  cmd="${cmd##*/}"; [ -n "$cmd" ] || return 1
  for ((k = 0; k < ${#SEC_LINES[@]}; k++)); do
    # shellcheck disable=SC2053  # the list holds globs on purpose
    [[ "$cmd" == ${SEC_LINES[$k]%% *} ]] || continue
    read -r -a f <<<"${SEC_LINES[$k]}"
    found=1
    for ((m = 1; m < ${#f[@]}; m++)); do
      found=0
      for ((j = _SEC_S + 1; j < ${#_CW[@]}; j++)); do
        # shellcheck disable=SC2053
        if [[ "${_CW[$j]}" == ${f[$m]} ]]; then found=1; break; fi
      done
      [ "$found" = 1 ] || break
    done
    if [ "$found" = 1 ]; then CRED_HIT="${SEC_LINES[$k]}"; return 0; fi
  done
  return 1
}

_sec_carrier() { # $1 node -> 0 if it passes the secret on to its output: a reader (cat, jq, base64, sed…),
  # echo, printf or tee. _SEC_CMD = its name; _SEC_TEE = 1 if it is tee writing a file
  local k
  _sec_words "$1"; _SEC_TEE=0; _SEC_CMD="${_CW[$_SEC_S]-}"; _SEC_CMD="${_SEC_CMD##*/}"
  case "$_SEC_CMD" in
    '') return 1 ;;
    echo|printf) return 0 ;;
    tee)
      for ((k = _SEC_S + 1; k < ${#_CW[@]}; k++)); do
        case "${_CW[$k]}" in -*|/dev/null|/dev/stdout|/dev/stderr) ;; *) _SEC_TEE=1 ;; esac
      done
      return 0 ;;
  esac
  _cred_is_reader "$_SEC_S"
}

_sec_inner() { # _CW/_SEC_S of a node -> 0 and _SEC_INNER if it runs a command line given as text (bash -c,
  # eval, watch, ssh <host> …): its output is the output of that line
  local k cmd="${_CW[$_SEC_S]-}"
  cmd="${cmd##*/}"; _SEC_INNER=""
  case "$cmd" in
    bash|sh|zsh|dash|ksh)
      for ((k = _SEC_S + 1; k < ${#_CW[@]}; k++)); do
        case "${_CW[$k]}" in -*c) _SEC_INNER="${_CW[$((k + 1))]-}"; break ;; -*) ;; *) break ;; esac
      done ;;
    eval) _SEC_INNER="$(_cred_join $((_SEC_S + 1)))" ;;
    watch)
      for ((k = _SEC_S + 1; k < ${#_CW[@]}; k++)); do
        case "${_CW[$k]}" in -n|--interval) k=$((k + 1)) ;; -*) ;; *) break ;; esac
      done
      _SEC_INNER="$(_cred_join "$k")" ;;
    ssh)
      for ((k = _SEC_S + 1; k < ${#_CW[@]}; k++)); do
        case "${_CW[$k]}" in
          -[BbcDEeFIiJLlmOoPpQRSWw]) k=$((k + 1)) ;;
          -*) ;;
          *) _SEC_INNER="$(_cred_join $((k + 1)))"; break ;;
        esac
      done ;;
  esac
  [ -n "$_SEC_INNER" ]
}

_sec_flow() { # $1 node whose output carries a secret -> 0 used (a tool that is not a reader, a variable,
  # /dev/null); 1 written to a file; 2 reaches the output of the whole line (the screen, at the top).
  # Sets CRED_WHAT.
  local n="$1" o p w via=""
  while :; do
    o="${_SO[$n]--}"
    case "$o" in
      0) return 0 ;;
      '>')
        if [ -n "$via" ]; then CRED_WHAT="written to a file through '$via'"; else CRED_WHAT="written to a file"; fi
        return 1 ;;
      '|'*)
        n="${o#|}"
        _sec_carrier "$n" || return 0
        if [ "$_SEC_TEE" = 1 ]; then CRED_WHAT="written to a file by 'tee'"; return 1; fi
        via="$_SEC_CMD"; continue ;;
    esac
    p="${_SP[$n]--1}"
    if [ "$p" -lt 0 ]; then
      if [ -n "$via" ]; then CRED_WHAT="shown through '$via'"; else CRED_WHAT="shown on the screen"; fi
      return 2
    fi
    w="${_SPW[$n]}"
    _sec_words "$p"
    # VAR=$(…) before the command is kept in a variable (TOKEN=$(…) echo done shows nothing). After it, the
    # command decides: export/local VAR=$(…) are not carriers, echo VAR=$(…) is
    case "${_CW[$w]-}" in [A-Za-z_]*=*) [ "$w" -lt "$_SEC_S" ] && return 0 ;; esac
    _sec_carrier "$p" || return 0
    if [ "$_SEC_TEE" = 1 ]; then CRED_WHAT="written to a file by 'tee'"; return 1; fi
    via="$_SEC_CMD"; n="$p"
  done
}

sec_check_line() {
  local depth="${2:-0}" kind a b c d out n rc l
  # The candidate lines (SEC_LINES) come from cred_check_line of this same line, which reads the lists in the awk
  # it runs anyway: no process of its own for a command line without one. The lines run by bash -c, eval or
  # ssh are part of it.
  if [ "$depth" = 0 ] && [ "${SEC_PICKED-}" != "$1" ]; then cred_check_line "$1" || true; fi
  [ "${#SEC_LINES[@]}" -gt 0 ] || return 0
  local _SW=() _SNW=() _SP=() _SPW=() _SO=() _SN=() _CW=() _SEC_S=0 _SEC_CMD="" _SEC_TEE=0 _SEC_INNER=""
  out="$(printf '%s\n' "$1" | awk "$_SEC_AWK")"
  while IFS=$'\t' read -r kind a b c d; do
    case "$kind" in
      W) _SW[a * 100000 + b]="$c"; _SNW[a]=$((b + 1)) ;;
      N) _SN+=("$a"); _SP[a]="$b"; _SPW[a]="$c"; _SO[a]="$d" ;;
    esac
  done <<<"$out"
  for n in ${_SN[@]+"${_SN[@]}"}; do
    _sec_words "$n"
    if _sec_is_secret; then
      :
    elif [ "$depth" -lt 4 ] && _sec_inner; then
      sec_check_line "$_SEC_INNER" $((depth + 1)); rc=$?
      [ "$rc" = 1 ] && return 1
      [ "$rc" = 2 ] || continue
    else
      continue
    fi
    _sec_flow "$n"; rc=$?
    case "$rc" in
      1) return 1 ;;
      2) [ "$depth" = 0 ] && return 1; return 2 ;;
    esac
  done
  return 0
}
