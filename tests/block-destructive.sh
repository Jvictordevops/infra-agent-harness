#!/usr/bin/env bash
# Tests for hooks/block-destructive-platform. Runs nothing real: only feeds commands to the hook.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/block-destructive-platform/block-destructive-platform.sh"
IAH_HOOK_LOG="$(mktemp)"; export IAH_HOOK_LOG   # keep test blocks out of the real decision log
trap 'rm -f "$IAH_HOOK_LOG"' EXIT
fail=0

decide() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | "$HOOK"; }
blk() { out="$(decide "$1")"; case "$out" in *'"block"'*) ;; *) echo "FAIL (should block): $1"; fail=1 ;; esac; }
alw() { out="$(decide "$1")"; [ -z "$out" ] || { echo "FAIL (should pass): $1"; fail=1; }; }

# The 8 variants of the 2026-11-07 finding (5 used to pass)
blk "terraform destroy"
blk "terraform -chdir=infra destroy"
blk "kubectl delete ns x"
blk "kubectl -n prod delete deploy api"
blk "kubectl --context pro delete pod x"
blk "helm -n x uninstall y"
blk "aws s3 rm s3://b --recursive"
blk "aws --profile pro ec2 terminate-instances --instance-ids i-1"

# More forms that must block
blk "terraform -chdir=infra apply -auto-approve -destroy"
blk "tofu destroy -target=module.x"
blk "terragrunt destroy"
blk "terraform state rm aws_s3_bucket.x"
blk "terraform import aws_s3_bucket.x b"
blk "cd infra && terraform destroy"
blk "/usr/local/bin/kubectl delete pod x"
blk "sudo kubectl drain node-1"
blk "kubectl scale deploy x --replicas=0"
blk "kubectl -n x scale deploy y --replicas 0"
blk "kubectl rollout undo deploy/x"
blk "ssh mac 'kubectl delete pod x'"
blk "bash -c \"helm uninstall x\""
blk "echo \$(kubectl delete pod x)"
blk "helm delete x"
blk "helmfile -e pro apply"
blk "aws s3 --profile p rb s3://x"
blk "aws iam delete-role --role-name x"
blk "AWS_PROFILE=p aws ec2 terminate-instances --instance-ids i-1"
blk "aws rds stop-db-instance --db-instance-identifier x"

# Must pass
alw "kubectl get pods -n prod"
alw "kubectl -n prod describe deploy api"
alw "kubectl get pods | grep delete"
alw "kubectl logs job/delete-old-data"
alw "kubectl scale deploy x --replicas=3"
alw "kubectl rollout status deploy/x"
alw "terraform plan -destroy"
alw "terraform -chdir=infra plan"
alw "terraform state list"
alw "terraform apply -auto-approve"
alw "helm -n x list"
alw "helm history x"
alw "helmfile -e pro diff"
alw "aws ec2 describe-instances --profile pro"
alw "aws s3 ls s3://b/rm"
alw "aws eks list-clusters"
alw "git status"
alw "echo terraform"

if [ "$fail" = 0 ]; then echo "block-destructive: all tests passed"; else echo "block-destructive: tests FAILED"; exit 1; fi
