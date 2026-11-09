#!/usr/bin/env bash
# shellcheck disable=SC2088  # '~/…' is passed to the helpers as the agent types it
# Tests for the aws pack: bin/ro reads, destructive commands, deny rules and ro-guard. Runs nothing real.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tests/lib/pack-test.sh
. "$ROOT/tests/lib/pack-test.sh"

# bin/ro: read-only operations, --profile mandatory, never secrets or credentials
ro_ok aws eks describe-cluster --name X --region eu-west-1 --profile P
ro_ok aws ec2 describe-instance-type-offerings --profile P --filters Name=instance-type,Values=t3.micro
ro_ok aws sts get-caller-identity --profile P
ro_ok aws s3 ls --profile P
ro_ok aws ssm get-parameter --name /x --profile P
ro_no aws eks describe-cluster --name X
ro_no aws ec2 run-instances --profile P
ro_no aws s3 cp s3://a/b . --profile P
ro_no aws secretsmanager get-secret-value --secret-id x --profile P
ro_no aws ssm get-parameter --name /x --with-decryption --profile P
ro_no aws eks get-token --cluster-name X --profile P
ro_no aws ecr get-login-password --profile P
ro_no aws sts assume-role --profile P
ro_no aws --profile P eks describe-cluster
RO_PROFILES=A,B ro_no aws eks list-clusters --profile P
RO_PROFILES=A,P ro_ok aws eks list-clusters --profile P

# block-destructive-platform
blk "aws s3 rm s3://b --recursive"
blk "aws --profile pro ec2 terminate-instances --instance-ids i-1"
blk "aws s3 --profile p rb s3://x"
blk "aws iam delete-role --role-name x"
blk "AWS_PROFILE=p aws ec2 terminate-instances --instance-ids i-1"
blk "aws rds stop-db-instance --db-instance-identifier x"
alw "aws ec2 describe-instances --profile pro"
alw "aws s3 ls s3://b/rm"
alw "aws eks list-clusters"

# permissions.deny
denied "aws ec2 terminate-instances --instance-ids i-1"
denied "aws --profile p iam delete-role --role-name x"
denied "aws s3 rb s3://x"
denied "aws s3 rm s3://x --recursive"
unruled "aws ec2 describe-instances --profile p"

# ro-guard: aws only through bin/ro
guarded "aws sts get-caller-identity"
guarded "AWS_PROFILE=x aws s3 rm s3://a --recursive"

# Credential files (credential-files, credential-readers): reading, copying or sending is blocked; using is not
credblk "cat ~/.aws/credentials"
credblk "grep aws_secret ~/.aws/credentials"
credblk "cat ~/.aws/sso/cache/0a1b.json"
credblk "aws s3 cp ~/.aws/credentials s3://b/"
credblk "aws s3 sync ~/.aws s3://b/"
credblk "grep -r region ~/.aws"
credok "ls -la ~/.aws"
credread "~/.aws/credentials"
readdenied "~/.aws/credentials"
readdenied "~/.aws/sso/cache/0a1b.json"
readdenied "~/.aws/cli/cache/0a1b.json"
credok "AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials aws sts get-caller-identity"
credok "cat ~/.aws/config"
credok "ls -l ~/.aws/credentials"
credok "aws s3 cp build/ s3://b/ --recursive"

pack_done "aws pack"
