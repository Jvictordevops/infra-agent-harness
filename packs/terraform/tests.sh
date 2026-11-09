#!/usr/bin/env bash
# shellcheck disable=SC2088  # '~/…' is passed to the helpers as the agent types it
# Tests for the terraform pack (terraform, tofu, terragrunt): destructive commands, deny/ask rules and ro-guard.
# bin/ro does not run them. Runs nothing real.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tests/lib/pack-test.sh
. "$ROOT/tests/lib/pack-test.sh"

# bin/ro: no terraform tool
ro_no terraform plan
ro_no tofu plan

# block-destructive-platform
blk "terraform destroy"
blk "terraform -chdir=infra destroy"
blk "terraform -chdir=infra apply -auto-approve -destroy"
blk "tofu destroy -target=module.x"
blk "terragrunt destroy"
blk "terragrunt run-all destroy"
blk "terraform state rm aws_s3_bucket.x"
blk "tofu state push x.tfstate"
blk "terraform state replace-provider a b"
blk "terraform import aws_s3_bucket.x b"
blk "cd infra && terraform destroy"
alw "terraform plan -destroy"
alw "terraform -chdir=infra plan"
alw "terraform state list"
alw "terraform apply -auto-approve"
alw "tofu plan"
alw "echo terraform"

# permissions.deny / ask: the same rules for terraform, tofu and terragrunt
for t in terraform tofu terragrunt; do
  denied "$t destroy -auto-approve"
  denied "$t -chdir=x destroy"
  denied "$t -chdir=x destroy -auto-approve"
  denied "$t state rm x.y"
  denied "$t -chdir=x state rm x.y"
  asked "$t apply -auto-approve"
  asked "$t -chdir=x apply"
  asked "$t -chdir=x apply tfplan"
  unruled "$t plan -out x"
done
denied "terragrunt run-all destroy"
asked "terragrunt run-all apply"

# ro-guard: never in read-only mode (bin/ro does not run them)
guarded "terraform plan"
guarded "tofu plan"
guarded "terragrunt plan"

# Credential files (credential-files): reading, copying or sending is blocked; using is not
credblk "cat ~/.terraform.d/credentials.tfrc.json"
credblk "jq . ~/.terraform.d/credentials.tfrc.json"
credblk "cat ~/.terraformrc"
credread "~/.terraform.d/credentials.tfrc.json"
readdenied "~/.terraform.d/credentials.tfrc.json"
readdenied "~/.terraformrc"
credok "TF_CLI_CONFIG_FILE=~/.terraformrc terraform plan"

pack_done "terraform pack"
