#!/usr/bin/env bash
# The floor: destructive platform commands that only a person runs, whatever packs are chosen (packs/README.md,
# "Choosing packs"). Each one must be blocked by block-destructive-platform AND match a permissions.deny rule,
# so two layers stop it. It fails if a change of packs drops any of them. Runs nothing real.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

pack_done floor
