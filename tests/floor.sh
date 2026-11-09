#!/usr/bin/env bash
# The floor: destructive platform commands that only a person runs, whatever packs are chosen (packs/README.md,
# "Choosing packs"). Each one must be blocked by block-destructive-platform AND match a permissions.deny rule,
# so two layers stop it. It fails if a change of packs drops any of them. Runs nothing real.
# It runs once with the default profile and again with each profile file below: the weakest profile with no
# pack chosen still has the whole floor (security-profile, packs/README.md).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${PT_PROFILE_FILE-}" ]; then
  _fl_tmp="$(mktemp -d)"
  for _fl_p in 'profile=permissive|packs=none' 'profile=strict|packs=aws' 'profile=standard|packs=kubernetes,helm'; do
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

pack_done floor
