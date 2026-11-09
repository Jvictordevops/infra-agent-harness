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
#   cred_match <path>          0 if <path> is a credential file, a glob that would match one (~/.aws/*) or a
#                              directory that holds one (~/.aws, ~); sets CRED_HIT to the pattern. Needs cred_load.
#   cred_check_line <command>  0 if the command line only uses credentials; 1 if it reads, copies or sends one
#                              (sets CRED_HIT and CRED_WHAT). Needs cred_load.
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
}

_cred_has_glob() { case "$1" in *[\*\?\[]*) return 0 ;; esac; return 1; }

cred_match() {
  local n="$1" p x base sample h='/~HOME~/'
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
        if _cred_has_glob "$n" && ! _cred_has_glob "${n:0:1}"; then
          sample="${x//\*/x}"
          # shellcheck disable=SC2053
          if [[ "$h$sample" == $n || "$sample" == $n || "/u/$sample" == $n ]]; then CRED_HIT="$p"; return 0; fi
        fi ;;
      '**/'*)
        x="${p#\*\*/}"
        # shellcheck disable=SC2053
        if [[ "$base" == $x ]]; then CRED_HIT="$p"; return 0; fi
        case "$base" in *[!\*\?]*) ;; *) continue ;; esac   # a bare '*' or '?*' names no file in particular
        if _cred_has_glob "$base"; then
          sample="${x//\*/x}"
          # shellcheck disable=SC2053
          if [[ "$sample" == $base ]]; then CRED_HIT="$p"; return 0; fi
        fi ;;
    esac
  done
  return 1
}

# Tokenizer: the command line on stdin -> one line per word ('W<TAB>index<TAB>word'), per path-like piece of
# a word ('C<TAB>index<TAB>flag<TAB>piece', flag r = read with '<', s = sent as @path or file://path, - = plain
# argument) and 'S' at the end of each simple command. Quotes are honoured; ; & | ( ) ` $( <( and newlines end a
# command; comments, heredoc bodies, here-strings and output redirection targets are not arguments.
# shellcheck disable=SC2016  # an awk program: its $ are awk's
_CRED_AWK='
function emit_seg() { if (nw > 0) print "S"; nw = 0; nextr = 0; nextout = 0 }
# Quick filter: only pieces that could be a credential path go to cred_match (a glob, a bare home directory, or
# an anchor of a pattern inside). An anchor "*" (a pattern with no fixed piece) lets everything through.
function maybe(p,   i) {
  sub(/\/+$/, "", p)
  if (p ~ /[*?[]/ || p == "~" || p == "$HOME" || p == "${HOME}" || p == home) return 1
  for (i = 1; i <= nanch; i++) if (anch[i] == "*" || index(p, anch[i]) > 0) return 1
  return 0
}
BEGIN { nanch = split(anchors, anch, "\n"); if (anch[nanch] == "") nanch-- }
function emit_word(   w, t, n, i, parts, p, flag) {
  w = word; word = ""; inword = 0
  if (hdpend) { hdm = w; sub(/^-/, "", hdm); hdpend = 0; return }
  if (nextout) { nextout = 0; return }
  gsub(/[\t\n]/, " ", w)
  print "W\t" nw "\t" w
  t = w; gsub(/file:\/\//, "@", t)
  n = split(t, parts, /[ \047"=:,()<>;|&`]/)
  for (i = 1; i <= n; i++) {
    p = parts[i]; flag = nextr ? "r" : "-"
    if (substr(p, 1, 1) == "@") { flag = "s"; sub(/^@+/, "", p) }
    if (p != "" && maybe(p)) print "C\t" nw "\t" flag "\t" p
  }
  nextr = 0; nw++
}
{ buf = buf (NR > 1 ? "\n" : "") $0 }
END {
  L = length(buf); q = ""; word = ""; inword = 0; nw = 0; nextr = 0; nextout = 0; hdpend = 0; hdm = ""
  for (i = 1; i <= L; i++) {
    c = substr(buf, i, 1)
    if (q == "\047") { if (c == "\047") q = ""; else word = word c; continue }
    if (q == "\"") {
      if (c == "\\" && i < L) { d = substr(buf, i + 1, 1); if (d ~ /["\\$`]/) { word = word d; i++; continue } }
      if (c == "\"") q = ""; else word = word c
      continue
    }
    if (c == "\\" && i < L) { i++; d = substr(buf, i, 1); if (d != "\n") { word = word d; inword = 1 }; continue }
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
      if (inword) emit_word()
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
      if (inword) emit_word()
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

# Evaluates one simple command (_CW words, _CI/_CF/_CP candidates); $1 depth. 1 = reads a credential.
_cred_segment() {
  local depth="$1" s=0 cmd k i reader=-1 host
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
    cred_match "${_CP[$i]}" || continue
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
  local depth="${2:-0}" kind a b c out
  local _CW=() _CI=() _CF=() _CP=()
  out="$(printf '%s\n' "$1" | awk -v anchors="$CRED_ANCHORS" -v home="$HOME" "$_CRED_AWK")"
  while IFS=$'\t' read -r kind a b c; do
    case "$kind" in
      W) _CW[a]="$b" ;;
      C) _CI+=("$a"); _CF+=("$b"); _CP+=("$c") ;;
      S) _cred_segment "$depth" || return 1; _CW=() _CI=() _CF=() _CP=() ;;
    esac
  done <<<"$out"
  return 0
}
