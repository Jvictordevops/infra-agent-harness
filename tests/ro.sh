#!/usr/bin/env bash
# Tests for bin/ro (allow-list) and hooks/ro-guard. Run nothing real: bin/ro --check and the hook with a temp mode file.
# The literal ~ in quotes is the point of some cases (bin/ro and the hook must expand it themselves).
# shellcheck disable=SC2088,SC2015
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RO="$ROOT/bin/ro"
HOOK="$ROOT/hooks/ro-guard/ro-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/code/repo/.git" "$TMP/code/repo/charts"
touch "$TMP/code/repo/values.yaml" "$TMP/code/repo/.env" "$TMP/code/repo/.git/config" "$TMP/code/repo/terraform.tfstate"
export RO_ROOTS="$TMP/code" RO_MODE_FILE="$TMP/ro-mode"
R="$TMP/code/repo"
fail=0

ok() { if "$RO" --check "$@" >/dev/null 2>&1; then :; else echo "FAIL (should pass): $*"; fail=1; fi; }
no() { if "$RO" --check "$@" >/dev/null 2>&1; then echo "FAIL (should deny): $*"; fail=1; fi; }

ok aws eks describe-cluster --name X --region eu-west-1 --profile P
ok aws ec2 describe-instance-type-offerings --profile P --filters Name=instance-type,Values=t3.micro
ok aws sts get-caller-identity --profile P
ok aws s3 ls --profile P
ok aws ssm get-parameter --name /x --profile P
no aws eks describe-cluster --name X
no aws ec2 run-instances --profile P
no aws s3 cp s3://a/b . --profile P
no aws secretsmanager get-secret-value --secret-id x --profile P
no aws ssm get-parameter --name /x --with-decryption --profile P
no aws eks get-token --cluster-name X --profile P
no aws ecr get-login-password --profile P
no aws sts assume-role --profile P
no aws --profile P eks describe-cluster
RO_PROFILES=A,B no aws eks list-clusters --profile P
RO_PROFILES=A,P ok aws eks list-clusters --profile P

ok kubectl get pods -A --context c
ok kubectl get externalsecrets,clustersecretstores -A --context c
ok kubectl auth can-i list pods --context c
no kubectl get pods
no kubectl get secrets -A --context c
no kubectl get secret/x -n y --context c
no kubectl describe Secret x --context c
no kubectl get cm,secrets --context c
no kubectl delete pod x --context c
no kubectl apply -f x --context c
no kubectl exec x --context c
no kubectl get pods -w --context c
no kubectl get pods --as admin --context c
no kubectl --context c get pods
RO_CONTEXTS=a no kubectl get pods --context c

ok helm list -A --kube-context c
ok helm get metadata r -n n --kube-context c
no helm get values r --kube-context c
no helm upgrade r x --kube-context c
no helm list -A

ok git -C "$R" log -5 --oneline
ok git -C "$R" branch -a
ok git -C "$R" remote -v
no git -C "$R" push
no git -C "$R" pull
no git -C "$R" checkout main
no git -C "$R" branch new
no git -C "$R" -c core.pager=x log
no git -C "$R" diff --output=/tmp/x
no git -C /etc log
no git log

ok cat "$R/values.yaml"
ok grep -rn "image:" "$R"
ok grep -A 2 -e repo "$R/values.yaml"
ok find "$R" -name '*.yaml' -type f
ok ls -la "$R/charts"
ok head -n 20 "$R/values.yaml"
no cat /etc/passwd
no cat "$R/../../../etc/passwd"
no cat "$R/.env"
no cat "$R/.git/config"
no cat "$R/terraform.tfstate"
no find "$R" -name x -delete
no find "$R" -exec rm {} ';'
no tail -f "$R/values.yaml"
no rm -rf "$R"
no bash -c "ls"
no sed -i s/a/b/ "$R/values.yaml"

if [ "$(HOME="$TMP" "$RO" cat '~/code/repo/values.yaml' 2>&1; echo "rc=$?")" != "rc=0" ]; then echo "FAIL: '~/' not expanded on run"; fail=1; fi

# hook
hook() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | "$HOOK" >/dev/null 2>"$TMP/hook.err"; }
hok() { if hook "$1"; then :; else echo "FAIL hook (should pass): $1 :: $(cat "$TMP/hook.err")"; fail=1; fi; }
hno() { if hook "$1"; then echo "FAIL hook (should block): $1"; fail=1; fi; }

hok "ssh other uname"                              # mode off: does nothing
"$RO" mode on test >/dev/null
hok "bin/ro --host other kubectl get pods --context dev | jq ."
hok "~/infra-agent-harness/bin/ro aws eks list-clusters --profile P --query 'clusters[] | [0]'"
hok "git -C ~/infra-agent-harness status && grep -rn helm README.md"
hok "ro --host other kubectl get pods --context dev | jq ."          # bare name (plugin bin/ on PATH)
hok "ro aws eks list-clusters --profile P"
hok "\"\${CLAUDE_PLUGIN_ROOT}/bin/ro\" aws sts get-caller-identity --profile P"
hno "ro aws eks list-clusters --profile P; kubectl delete ns x"
hno "ro mode off"
hno "ssh other uname"
hno "ssh -o BatchMode=yes other 'kubectl delete pod x'"
hno "AWS_PROFILE=x aws s3 rm s3://a --recursive"
hno "bin/ro aws eks list-clusters --profile P; kubectl delete ns x"
hno "echo \$(ssh other id)"
hno "bash -c 'kubectl apply -f x'"
hno "timeout 10 helm upgrade x y"
hno "/usr/bin/scp a other:b"
hno "bin/ro mode off"
hno "rm -f ~/.config/infra-agent-harness/ro-mode"
RO_MODE_FILE="$TMP/ro-mode" "$RO" mode off >/dev/null

[ "$fail" = 0 ] && echo "ro: all tests passed" || { echo "ro: tests FAILED"; exit 1; }
