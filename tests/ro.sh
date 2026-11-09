#!/usr/bin/env bash
# Tests for bin/ro (allow-list) and hooks/ro-guard, core only: git, gh, file readers, remote shells and how the
# hook reads a command. The aws, kubectl and helm cases live in packs/<name>/tests.sh.
# Run nothing real: bin/ro --check and the hook with a temp mode file.
# The literal ~ in quotes is the point of some cases (bin/ro and the hook must expand it themselves).
# shellcheck disable=SC2088,SC2015
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RO="$ROOT/bin/ro"
HOOK="$ROOT/hooks/ro-guard/ro-guard.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: macOS temp dirs sit behind the /var -> /private/var link
trap 'rm -rf "$TMP"' EXIT
IAH_HOOK_LOG="$TMP/hook-decisions.jsonl"; export IAH_HOOK_LOG   # keep test blocks out of the real decision log
mkdir -p "$TMP/code/repo/.git" "$TMP/code/repo/charts"
touch "$TMP/code/repo/values.yaml" "$TMP/code/repo/.env" "$TMP/code/repo/.git/config" "$TMP/code/repo/terraform.tfstate"
export RO_ROOTS="$TMP/code" RO_MODE_FILE="$TMP/ro-mode"
R="$TMP/code/repo"
fail=0

ok() { if "$RO" --check "$@" >/dev/null 2>&1; then :; else echo "FAIL (should pass): $*"; fail=1; fi; }
no() { if "$RO" --check "$@" >/dev/null 2>&1; then echo "FAIL (should deny): $*"; fail=1; fi; }

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

ok gh repo list owner --limit 50
ok gh repo view owner/repo
ok gh pr list -R owner/repo --state open
ok gh pr view 12 -R owner/repo --comments
ok gh pr diff 12 -R owner/repo
ok gh pr checks 12 -R owner/repo
ok gh issue list -R owner/repo
ok gh run list -R owner/repo
ok gh run view 123 --log-failed -R owner/repo
ok gh workflow list -R owner/repo
ok gh search code "foo" --owner owner
ok gh auth status
ok gh api repos/owner/repo --jq .default_branch
ok gh api repos/owner/repo/pulls --paginate
ok gh api -X GET search/issues -f q=repo:owner/repo
ok gh api --method=GET search/issues -f q=x
no gh repo clone owner/repo
no gh repo delete owner/repo
no gh repo create x
no gh pr create
no gh pr merge 12
no gh pr checkout 12
no gh pr comment 12 -b x
no gh pr view 12 --web
no gh issue create -t x
no gh issue close 3
no gh run rerun 123
no gh run download 123
no gh run cancel 123
no gh workflow run deploy.yml
no gh release create v1
no gh secret list
no gh variable list
no gh auth token
no gh auth status --show-token
no gh auth login
no gh extension install x/y
no gh api repos/owner/repo/issues -f title=x
no gh api -X POST repos/owner/repo/issues
no gh api --method DELETE repos/owner/repo
no gh api -XPATCH repos/owner/repo
no gh api repos/owner/repo/issues --input body.json
no gh api graphql -f query=x
no gh api repos/owner/repo/actions/secrets
no gh api repos/owner/repo/actions/variables
no gh api user/keys
no gh api -H "X-HTTP-Method-Override: DELETE" repos/owner/repo
ok gh api -H "Accept: application/vnd.github.diff" repos/owner/repo/pulls/1
ok gh api --jq .name -X GET repos/owner/repo
no gh api
no gh

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
hok "ro gh pr list -R owner/repo | head"
hno "gh pr list -R owner/repo"
hok "\"\${CLAUDE_PLUGIN_ROOT}/bin/ro\" aws sts get-caller-identity --profile P"
hno "ro gh pr list -R owner/repo; ssh other id"
hno "ro mode off"
hno "ssh other uname"
hno "ssh -o BatchMode=yes other 'kubectl delete pod x'"
hno "GH_TOKEN=x gh pr list -R owner/repo"
hno "bin/ro git -C ~/code status; scp a other:b"
hno "echo \$(ssh other id)"
hno "bash -c 'ssh other id'"
hno "timeout 10 ssh other id"
hno "az vm list"
hno "gcloud compute instances list"
hno "/usr/bin/scp a other:b"
hno "bin/ro mode off"
hno "rm -f ~/.config/infra-agent-harness/ro-mode"
RO_MODE_FILE="$TMP/ro-mode" "$RO" mode off >/dev/null

[ "$fail" = 0 ] && echo "ro: all tests passed" || { echo "ro: tests FAILED"; exit 1; }
