#!/usr/bin/env bash
# The floor, whatever packs are chosen (packs/README.md, "Choosing packs"): destructive platform commands that
# only a person runs, each blocked by block-destructive-platform AND matching a permissions.deny rule; and
# credential files no agent reads, each blocked by credential-guard AND matching a Read(…) deny rule. Two layers
# stop each one. It fails if a change of packs drops any of them. Runs nothing real.
# shellcheck disable=SC2088  # '~/…' is passed to the helpers as the agent types it
# It runs once with the default profile and again with each profile file below: the weakest profile with no
# pack chosen still has the whole floor (security-profile, packs/README.md).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${PT_PROFILE_FILE-}" ]; then
  _fl_tmp="$(mktemp -d)"
  for _fl_p in 'profile=permissive|packs=none' 'profile=permissive' 'profile=strict|packs=aws' 'profile=standard|packs=kubernetes,helm'; do
    printf '%s\n' "$_fl_p" | tr '|' '\n' > "$_fl_tmp/profile"
    echo "with $_fl_p:"
    PT_PROFILE_FILE="$_fl_tmp/profile" bash "$0" || { rm -rf "$_fl_tmp"; exit 1; }
  done
  rm -rf "$_fl_tmp"
  echo "with the default profile:"
fi
# shellcheck source=tests/lib/pack-test.sh
. "$ROOT/tests/lib/pack-test.sh"

FLOOR=(
  "terraform destroy -auto-approve"
  "terraform state rm aws_s3_bucket.x"
  "tofu destroy -auto-approve"
  "tofu state rm aws_s3_bucket.x"
  "terragrunt destroy -auto-approve"
  "terragrunt state rm aws_s3_bucket.x"
  "kubectl delete ns prod"
  "kubectl drain node-1"
  "helm uninstall api"
  "aws ec2 terminate-instances --instance-ids i-1"
  "aws rds delete-db-instance --db-instance-identifier x"
  "aws s3 rb s3://bucket --force"
  "aws s3 rm s3://bucket --recursive"
)
for c in "${FLOOR[@]}"; do
  blk "$c"
  denied "$c"
done

# git force push and hard reset ask in every profile; permissive only drops the asks of the packs.
for c in "git push --force origin main" "git push origin main --force" "git push -f origin main" "git reset --hard HEAD~1"; do
  asked "$c"
done
if [ "$(profile_name)" = permissive ]; then
  for c in "terraform apply -auto-approve" "tofu apply" "terragrunt apply" "kubectl apply -f x.yaml" "helm upgrade api ./chart" "helm install api ./chart"; do
    unruled "$c"
  done
else
  for c in "terraform apply -auto-approve" "kubectl apply -f x.yaml" "helm upgrade api ./chart"; do
    asked "$c"
  done
fi

# Credential files: never read by an agent, whatever the profile and packs. Two locks: credential-guard (a
# reader in Bash, and the Read tool) and a Read(…) deny rule. Core files first, then one per pack.
FLOOR_CREDENTIALS=(
  "~/.ssh/id_ed25519"
  "~/.ssh/id_rsa"
  "~/.netrc"
  "~/.git-credentials"
  "~/.docker/config.json"
  "~/.config/gh/hosts.yml"
  "~/.config/infra-agent-harness/evidence.key"
  "~/.config/infra-agent-harness/bw-session"
  "app/.env"
  "certs/server.key"
  "~/.aws/credentials"
  "~/.kube/config"
  "~/.terraform.d/credentials.tfrc.json"
  "~/.config/helm/registry/config.json"
)
for f in "${FLOOR_CREDENTIALS[@]}"; do
  credblk "cat $f"
  credread "$f"
  readdenied "$f"
done

# Commands that print a secret: never shown to an agent, whatever the profile and packs (credential-guard).
# Core first, then the packs.
FLOOR_SECRET_COMMANDS=(
  "gh auth token"
  "bw get password x"
  "git credential fill"
  "aws configure export-credentials"
  "aws secretsmanager get-secret-value --secret-id x"
  "kubectl config view --raw"
  "kubectl get secret x -o yaml"
)
for c in "${FLOOR_SECRET_COMMANDS[@]}"; do
  credblk "$c"
  credblk "$c | base64"
  credok "X=\$($c)"
done

pack_done floor
