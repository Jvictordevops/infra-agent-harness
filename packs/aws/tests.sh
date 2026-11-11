#!/usr/bin/env bash
# shellcheck disable=SC2088,SC2016  # '~/…' and '$(…)' are passed to the helpers as the agent types them
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
# The CLI takes any unique prefix of an option
ro_no aws ssm get-parameter --name /x --with-decrypt --profile P
ro_no aws ssm get-parameters-by-path --path /x --with-d --profile P
ro_no aws ssm get-parameter --name /x --w --profile P
ro_no aws ec2 describe-instances --endpoint http://127.0.0.1:9 --profile P
ro_no aws ec2 describe-instances --endpoint=http://127.0.0.1:9 --profile P
ro_no aws ec2 describe-instances --deb --profile P
ro_no aws ec2 describe-instances --prof P
ro_no aws ec2 describe-instances --profile P --prof Q
ro_no aws ec2 describe-instances --profile P --profile Q
RO_PROFILES=P ro_no aws ec2 describe-instances --profile P --profile=Q
ro_ok aws logs filter-log-events --log-group-name g --end-time 1 --profile P
ro_ok aws ec2 describe-instances --dry-run --profile P
ro_ok aws rds describe-db-instances --db-instance-identifier d --profile P
# A parameter read from a local file
ro_no aws ec2 describe-tags --filters file:///etc/hostname --profile P
ro_no aws ssm get-parameter --name fileb:///etc/hostname --profile P
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
blk "aws s3 sync . s3://b --delete"
blk "aws --profile p s3 sync s3://a s3://b --delete --dryrun"
alw "aws s3 sync . s3://b"
alw "aws s3 sync . s3://b --exclude '*.delete'"
alw "aws eks list-clusters"

# permissions.deny
denied "aws ec2 terminate-instances --instance-ids i-1"
denied "aws --profile p iam delete-role --role-name x"
denied "aws s3 rb s3://x"
denied "aws s3 rm s3://x --recursive"
denied "aws s3 sync . s3://b --delete"
unruled "aws s3 sync . s3://b"
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

# Commands that print a secret (secret-commands): shown is blocked, used is not
credblk "aws configure export-credentials --profile p"
credblk "aws configure export-credentials --format env --profile p"
credblk "aws configure get aws_secret_access_key --profile p"
credblk "aws configure get profile.p.aws_session_token"
credblk "aws --profile p ecr get-login-password"
credblk "aws ecr get-login-password --region eu-west-1 | base64 -d"
credblk "aws ecr-public get-login-password"
credblk "aws codeartifact get-authorization-token --domain d"
credblk "aws sts get-session-token"
credblk "aws ssm get-parameter --name /x --with-decrypt --profile p"
credblk "aws ssm get-parameters --names /x --with-d"
credok "aws ssm get-parameter --name /x --profile p"
credblk "aws sts assume-role --role-arn arn:aws:iam::1:role/r --role-session-name s"
credblk "aws sts assume-role-with-web-identity --role-arn r --web-identity-token t"
credblk "aws sso get-role-credentials --role-name r --account-id 1 --access-token t"
credblk "aws eks get-token --cluster-name c"
credblk "aws rds generate-db-auth-token --hostname h --port 5432 --username u"
credblk "aws iam create-access-key --user-name u"
credblk "aws secretsmanager get-secret-value --secret-id db --profile p"
credblk "aws secretsmanager get-secret-value --secret-id db | jq -r .SecretString"
credblk "aws secretsmanager batch-get-secret-value --secret-id-list a b"
credblk "aws ssm get-parameter --name /x --with-decryption"
credblk "aws ssm get-parameters --names /x /y --with-decryption > p.json"
credblk "aws ssm get-parameters-by-path --path /x --recursive --with-decryption"
credblk "aws kms decrypt --ciphertext-blob fileb://x"
credblk 'echo "$(aws secretsmanager get-secret-value --secret-id db)"'
credok "aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin 1.dkr.ecr.eu-west-1.amazonaws.com"
credok 'docker login -u AWS -p "$(aws ecr get-login-password)" 1.dkr.ecr.eu-west-1.amazonaws.com'
credok 'docker login -u AWS --password-stdin x <<< "$(aws ecr get-login-password)"'
credok 'eval "$(aws configure export-credentials --format env)"'
credok 'export DB_PASS=$(aws secretsmanager get-secret-value --secret-id db --query SecretString --output text)'
credok "aws secretsmanager list-secrets"
credok "aws secretsmanager describe-secret --secret-id db"
credok "aws ssm get-parameter --name /x"
credok "aws ssm get-parameter --name /x --no-with-decryption"
credok "aws configure get region"
credok "aws configure list"
credok "aws sts get-caller-identity"

pack_done "aws pack"
