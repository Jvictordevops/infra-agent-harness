#!/usr/bin/env bash
# Sourced by the guards. Reads a shell command line and gives every simple command in it to a per-guard sink,
# so a guard looks at commands and not at words that merely appear in text (a commit message, a grep pattern).
#   cmdparse_run <sink.awk>   command on stdin. Prints 'B<TAB>reason' if the sink blocked, nothing otherwise.
#                             Returns non-zero when awk (or the parser) failed: the guard must block then.
# The parser is hooks/lib/cmdparse.awk; the sink defines cmd_seen() (contract in the header of that file).
# One awk process per command line. The guard's own settings go in the environment (CMDP_*), never in -v.
# Tests: tests/cmdparse.sh

CMDP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cmdparse_run() { # $1 sink file
  CMDP_DATAFILE="${CMDP_DATAFILE:-$CMDP_DIR/cmdparse-data.txt}" awk -f "$CMDP_DIR/cmdparse.awk" -f "$1"
}
