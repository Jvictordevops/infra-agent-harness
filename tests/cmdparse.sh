#!/usr/bin/env bash
# Tests for the common command parser (hooks/lib/cmdparse.awk): which simple commands it finds in a command line,
# at which depth and of which class. Uses a sink that lists them (tests/lib/cmdparse-list.awk), so the table is
# the whole contract: 'depth kind class command words'. The guards' own tests (ro, block-destructive) check what
# they do with the list.
# The command texts are data: they are never run here.
# shellcheck disable=SC2016,SC2015
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/hooks/lib"
SINK="$ROOT/tests/lib/cmdparse-list.awk"
fail=0

parse() { printf '%s\n' "$1" | CMDP_DATAFILE="${DATAFILE:-$LIB/cmdparse-data.txt}" "${AWKBIN:-awk}" -f "$LIB/cmdparse.awk" -f "$SINK"; }
# t <command> <expected list, one 'depth kind class words' per line>
t() {
  local got
  got="$(parse "$1")"
  if [ "$got" != "$2" ]; then
    echo "FAIL: $(printf '%s' "$1" | tr '\n' '~')"
    printf '  want:\n%s\n  got:\n%s\n' "$(printf '%s' "$2" | sed 's/^/    /')" "$(printf '%s' "$got" | sed 's/^/    /')"
    fail=1
  fi
}

# Text is data
t 'git commit -m "fix: avoid terraform destroy in CI"' '0 top data git commit -m fix: avoid terraform destroy in CI'
t 'grep "kubectl delete" docs/ | wc -l' $'0 top data grep kubectl delete docs/\n0 top data wc -l'
t 'echo "x" > out.txt # kubectl delete pod y' '0 top data echo x'
t "sed -i 's/old/helm rollback web/' notes.md" '0 top data sed -i s/old/helm rollback web/ notes.md'
t 'ls; true && false || echo no' $'0 top data ls\n0 top data true\n0 top data false\n0 top data echo no'
t 'echo $((1 + 2))' '0 top data echo $()'   # arithmetic runs nothing: no command inside
# Wrappers, assignments, keywords: the command underneath
t 'sudo -u ops env A=1 timeout 10 helm uninstall r' '0 top opaque helm uninstall r'
t 'nice -n 5 aws s3 ls' '0 top opaque aws s3 ls'
t 'timeout -s KILL 5 ssh x' '0 top opaque ssh x'
t 'A=1 B=2 aws s3 ls' '0 top opaque aws s3 ls'
t 'command -v aws' ''
t 'for n in a b; do kubectl cordon $n; done' $'0 top data for n in a b\n0 top opaque kubectl cordon $n\n0 top data done'
t '! aws s3 ls' '0 top opaque aws s3 ls'
t '{ aws s3 ls; }' '0 top opaque aws s3 ls'
t 'if kubectl get x; then echo ok; fi' $'0 top opaque kubectl get x\n0 top data echo ok\n0 top data fi'
t '/usr/bin/ssh host' '0 top opaque /usr/bin/ssh host'
# Things that run a command inside an argument
t 'X="$(aws s3 ls)"; echo $X' $'0 top data echo $X\n1 sub opaque aws s3 ls'
t 'echo `aws s3 ls`' $'0 top data echo $()\n1 sub opaque aws s3 ls'
t 'echo "$(aws s3 ls)"' $'0 top data echo $()\n1 sub opaque aws s3 ls'
t "echo '\$(aws s3 ls)'" '0 top data echo $(aws s3 ls)'
t "bash -c 'aws s3 ls'" $'0 top opaque bash -c aws s3 ls\n1 sh opaque aws s3 ls'
t "sh -lc 'aws s3 ls; ls'" $'0 top opaque sh -lc aws s3 ls; ls\n1 sh opaque aws s3 ls\n1 sh data ls'
t 'eval "ssh x"' $'0 top opaque eval ssh x\n1 eval opaque ssh x'
t "ssh mac 'kubectl get pods; kubectl delete pod x'" $'0 top opaque ssh mac kubectl get pods; kubectl delete pod x\n1 ssh opaque kubectl get pods\n1 ssh opaque kubectl delete pod x'
t "ssh -o BatchMode=yes -p 22 mac ls" $'0 top opaque ssh -o BatchMode=yes -p 22 mac ls\n1 ssh data ls'
t 'su -c "aws s3 ls" root' $'0 top opaque su -c aws s3 ls root\n1 su opaque aws s3 ls'
t 'watch -n 5 aws s3 ls' '1 watch opaque aws s3 ls'
t 'find . -name x -exec kubectl delete -f {} \;' $'0 top opaque find . -name x -exec kubectl delete -f {} ;\n1 exec opaque kubectl delete -f {}'
t 'echo x | xargs -n 1 aws s3 ls' $'0 top data echo x\n0 top opaque aws s3 ls'
# Heredocs and pipes to a shell are code; to anything else they are text
t $'cat > rec.md <<\'EOF\'\nssh host\nEOF' '0 top data cat'
t $'bash <<EOF\naws s3 ls\nEOF' $'0 top opaque bash\n1 heredoc opaque aws s3 ls'
t 'bash <<< "aws s3 ls"' $'0 top opaque bash\n1 herestring opaque aws s3 ls'
t "echo 'aws s3 ls' | bash" $'0 top data echo aws s3 ls\n0 top opaque bash\n1 pipe opaque aws s3 ls'
t $'cat <<EOF | sh\naws s3 ls\nEOF' $'0 top opaque sh\n0 top data cat\n1 pipe opaque aws s3 ls'
t 'echo hi | cat' $'0 top data echo hi\n0 top data cat'
# Scripts and the code of languages are not looked into
t 'bash script.sh; source ./aws-env.sh' $'0 top opaque bash script.sh\n0 top data source ./aws-env.sh'
t 'python3.12 -c "import os; os.system(1)"; ls' $'0 top data python3.12 -c import os; os.system(1)\n0 top data ls'
# Nested too deep: the sink gets a 'deep' command
nest() { # <levels>: ssh x inside that many bash -c
  local s="ssh x" i
  for ((i = 0; i < $1; i++)); do s="bash -c $(printf '%q' "$s")"; done
  printf '%s' "$s"
}
if parse "$(nest 4)" | grep -q ' deep '; then echo "FAIL: 4 levels of bash -c are 'deep' (the limit is past 4)"; fail=1; fi
if ! parse "$(nest 4)" | grep -q '^4 sh opaque ssh x$'; then echo "FAIL: the innermost command at level 4 is not found"; fail=1; fi
if ! parse "$(nest 5)" | grep -q '^5 deep opaque '; then echo "FAIL: 5 levels of bash -c do not reach the sink as 'deep'"; fail=1; fi
# Empty line and a multi-line command
t '' ''
t $'ls\naws s3 ls' $'0 top data ls\n0 top opaque aws s3 ls'

# The list of data commands is needed: without it the parser fails (exit 2), and so the guard blocks
DATAFILE="$ROOT/does-not-exist" parse 'ls' >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a missing list of data commands should make the parser exit 2, got $rc"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '# only a comment\n' > "$T/empty.txt"
DATAFILE="$T/empty.txt" parse 'ls' >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] || { echo "FAIL: an empty list of data commands should make the parser exit 2, got $rc"; fail=1; }

[ "$fail" = 0 ] && echo "cmdparse: all tests passed" || { echo "cmdparse: tests FAILED"; exit 1; }
