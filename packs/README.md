# Rule packs

A pack holds the safety rules for one technology, and their tests. The guards and `bin/ro` hold no platform rules of their own: they read them from `packs/<name>/`. Every pack under `packs/` is installed; the security profile chooses which ones you use, under the rule below.

| Pack | Tools | `bin/ro` reads | Destructive commands blocked |
|---|---|---|---|
| `aws` | `aws` | `describe-`/`list-`/`get-`/`batch-get-`/`lookup-`/`search-`, `s3 ls`, `--profile` mandatory | `delete-*`, `terminate-*`, `stop-*`, `s3 rb`, `s3 rm`, `s3 sync --delete` |
| `kubernetes` | `kubectl`, `eksctl`, `argocd`, `flux`, `k9s`, `kubectx`, `kubens` | `kubectl get`, `describe`, `logs`, `top`, `events`…, `--context` mandatory, never Secrets | `kubectl delete`, `drain`, `cordon`, `scale --replicas 0`, `rollout undo`, `replace --force`; `eksctl delete`; `argocd … delete\|rm`; `flux delete\|uninstall` |
| `helm` | `helm`, `helmfile` | `list`, `status` (as a table), `history`, `get metadata`, `--kube-context` mandatory | `helm uninstall`, `helm rollback`, `helmfile apply\|sync\|destroy\|delete` |
| `terraform` | `terraform`, `tofu`, `terragrunt` | none (`bin/ro` does not run them) | `destroy`, `import`, `apply -destroy`, `state rm\|push\|replace-provider`, `workspace delete` |

Deny rules (Claude Code refuses the command) cover the main destructive verbs of each pack. Ask rules (Claude Code asks you first) cover `apply` of the three Terraform tools, `kubectl apply` and `helm install|upgrade`; the `permissive` profile drops them (below).

## Choosing packs: only permissions go

You choose packs in the security profile: `bin/security-profile set standard --packs aws,kubernetes` (`all`, the default, or `none` also work; `docs/tools.md`). Choosing packs can only take away what is **allowed**, never what is **blocked**:

- Always loaded from every installed pack: `destructive.rules`, the `deny` and `ask` rules of `permissions.json`, `guard-tools`, `credential-files` and `credential-readers`. Someone who does not use Kubernetes still has `kubectl delete` blocked; it costs nothing.
- Only for the chosen packs: the `bin/ro` tools of `ro.sh` and, with the `strict` profile, the sandbox `domains`.

The `permissive` profile is the one exception to "always loaded": it drops the `ask` rules of every pack, so Claude Code runs `apply`, `install` and `upgrade` without asking. The `deny` rules, the guards and the core `ask` rules (git) stay (`docs/tools.md`).

`tests/floor.sh` holds the floor: destructive commands that only a person runs, and credential files no agent reads. Each destructive command must be blocked by `block-destructive-platform` and match a `deny` rule; each credential file must be blocked by `credential-guard` (in Bash and in the Read tool) and match a `Read(…)` deny rule. It runs with several profiles, the weakest with no pack chosen, and fails if any of them drops one. `tests/profile.sh` checks that `bin/ro` only runs the tools of the chosen packs.

## Credential files

The floor also says: agents never read credential files. Two locks, in every profile and mode, whatever packs you choose:

- `credential-guard` (PreToolUse on Bash, Read and Grep) blocks a credential path given to a command that **shows, copies or sends** its content: readers such as `cat`, `grep`, `jq` or `base64`, copies such as `cp`, `tar` or `scp`, senders such as `curl -T` or `nc`, code such as `python -c`, a `<` redirection, or `@file` / `file://file`. **Using** a credential passes: `ssh -i ~/.ssh/id_ed25519`, `kubectl --kubeconfig ~/.kube/config`, `KUBECONFIG=…`, `source .env`, `docker compose --env-file .env`, `ls`, `chmod`. It also looks inside `bash -c '…'`, `eval` and `ssh host '…'`. On the Read and Grep tools it blocks the path itself, also through a symlink. A directory that holds a credential (`~/.aws`, `~`) counts when it is given to a reader: `tar czf x.tgz ~/.ssh` is blocked, `ls ~/.ssh` is not.
- One `Read(…)` deny rule per credential file, added by `bin/link-harness` (`Read(~/.aws/credentials)`, `Read(//**/.env)`). Claude Code applies them to its file tools, to Grep and Glob, and to the file commands it recognises in Bash (`cat`, `head`, `tail`, `sed`).

The lists:

- `hooks/credential-guard/credential-files`: SSH private keys by name (the `.pub` files stay readable), `.netrc`, `.git-credentials`, `~/.docker/config.json`, `~/.npmrc`, `~/.pypirc`, the `gh` token file, the evidence key and the cached Bitwarden session of this harness, and, anywhere on disk, `.env`, `.env.local`, `.env.production` and `*.key`. Not `*.pem` (mostly public certificates) nor `.env.*` (`.env.example` must stay readable, and a `Read` rule cannot have exceptions).
- `hooks/credential-guard/readers`: the commands that read, copy or send. If one gets in the way of your daily work, remove its line; add one when you find a reader that is missing.
- Each pack adds its `credential-files` and, when it has readers of its own, `credential-readers` (`aws s3 cp`, `kubectl cp`).

Exceptions that keep daily work going: the identity key of `scp`, `sftp` and `rsync` (`-i`, `-o IdentityFile=…`, `-e "ssh -i …"`), the destination of a copy (`cp .env.example .env`) and `sed -i` (it edits without showing). A `*`, `?` or `[` inside quotes or after `\` is text, as in the shell: `grep -o 'x.*' notes.md` passes, while `cat ~/.ssh/id_*` is blocked. The remote path of `scp`, `sftp` and `rsync` is the exception (`scp 'host:~/.ssh/id_*' .`), because the remote shell expands it. A quoted name is still compared as is: `find . -name '*.key' -exec cat {} \;` is blocked.

What it does not stop, because it guards against mistakes, not an adversary: a reader missing from the list, a command that reads without naming the path (`cd ~/.aws && cat credentials`, `grep -r x .`), a script or heredoc that opens the file itself, and a path built in a variable. The sandbox of the `strict` profile covers them.

## Commands that show secrets

Some commands print a secret without opening any file. `credential-guard` treats them like the files: **showing** the secret is blocked, **using** it passes, in every profile and mode, whatever packs you choose. Two kinds are on the lists: the credentials of the agent (`gh auth token`, `aws configure export-credentials`, `aws ecr get-login-password`, `kubectl config view --raw`, `kubectl create token`, `bw get password`) and the values of the secrets of applications (`aws secretsmanager get-secret-value`, `aws ssm get-parameter --with-decryption`, `kubectl get secret … -o yaml`). Listing or describing secrets passes (`kubectl get secrets`, `aws secretsmanager list-secrets`). `helm get values` and `terraform output` are not on the lists: they are daily work, like reading a `*.tfstate`.

The guard follows where the output of the command goes:

- Blocked: the screen (`gh auth token`), a file (`… > token.txt`, `… | tee token.txt`), or a reader on the way to either (`… | base64`, `… | jq -r .SecretString`, `echo "$(gh auth token)"`, `cat <(…)`).
- Passes: piped into a tool that is not a reader (`aws ecr get-login-password | docker login --password-stdin …`, `kubectl get secret x -o yaml | kubectl apply -f -`), substituted into one (`curl -H "Authorization: Bearer $(gh auth token)" …`, `eval "$(aws configure export-credentials --format env)"`), kept in a variable (`TOKEN=$(…)`, `export TOKEN=$(…)`) or thrown away (`> /dev/null`).
- It looks inside `bash -c '…'`, `eval`, `watch` and `ssh host '…'`: `ssh host gh auth token` shows the token here.

The lists: `hooks/credential-guard/secret-commands` (`gh`, `bw`, `git credential`, the `docker-credential-*` helpers, the macOS keychain) and `packs/<name>/secret-commands` (aws, kubernetes). The readers are the same as for the files (`hooks/credential-guard/readers`), plus `echo`, `printf` and `tee`.

What it does not stop: a secret already in a variable or in the environment (`echo $TOKEN`, `env`, `printenv`), a command missing from the lists, and a tool that is not a reader but prints what it gets. `kubectl get secret … -o name` is blocked too, because any `-o` of a Secret is.

## What stays in the core

Some rules are not about one technology, so they stay outside the packs:

- `bin/ro`: `git`, `gh` and the file readers (`cat`, `head`, `tail`, `ls`, `find`, `grep`, `wc`, `stat`).
- `ro-guard`: `ssh`, `scp`, `sftp`, `rsync`, `sshfs`, `mosh` and `gh`. It also blocks `az` and `gcloud`, so Azure and Google Cloud stay blocked in read-only mode even without a pack.
- `hooks/settings.base.json`: the `ask` rules for `git push --force` and `git reset --hard`.

## Files of a pack

All files are optional. Any other file name is an error (`tests/packs.sh`).

| File | Read by | Format |
|---|---|---|
| `ro.sh` | `bin/ro` | Bash, sourced. It calls `ro_tool <tool>` for each tool and defines `check_<tool>`, which gets the arguments after the tool and calls `deny "<reason>"` to refuse. Helpers: `deny`, `opt_val <option> "$@"` (value of `--opt X` or `--opt=X`), `opt_once <option> "$@"` (denies an option given twice: the tool would use the last one, the check reads the first), `in_list <value> <comma list>`, `lower`. If the tool takes shortened options, as the aws CLI does (`--with-decrypt`), the check must refuse those too. A pack cannot register a core tool or a tool of another pack. |
| `guard-tools` | `ro-guard` | One command name per line (`[a-z0-9_-]`). In read-only mode, these commands are blocked outside `bin/ro`. |
| `destructive.rules` | `block-destructive-platform` | One `name\|regex` per line (extended regex, matched against the whole command). The name goes to the decision log. Placeholders: `<P>` start of a tool name (also after `/`, a quote or `$(`), `<S>` whitespace, `<G>` any tokens in the same command segment (never across `;`, `\|` or `&`), `<E>` end of a word. The hook gives each rule one command at a time (the parser splits `;`, `\|`, `&&`, `$(…)`, `bash -c '…'`, `ssh host '…'`…), the command and its arguments joined by a field separator that `<S>`, `<G>` and `<E>` take as a space; a command whose arguments are text (`git`, `grep`, `echo`, `sed`, `python -c`…: `hooks/lib/cmdparse-data.txt`) is not matched, so a rule only fires on something that runs. Write rules as before. |
| `credential-files` | `credential-guard`, `bin/ro`, `bin/link-harness` | One pattern per line: `~/<path>` (from the home directory) or `**/<name>` (that file name anywhere); `*` is any text. Each line also becomes a `Read(~/<path>)` or `Read(//**/<name>)` deny rule. |
| `credential-readers` | `credential-guard` | One `<command>` or `<command> <word>` per line (a reader only when `<word>` is one of its arguments), like `hooks/credential-guard/readers`. |
| `secret-commands` | `credential-guard` | One `<command> <word> …` per line: a command that prints a secret when all the words are among its arguments, in any order; `*` is any text (`aws ssm get-parameter* --w*`: the aws CLI takes `--with-decryption` shortened too). Like `hooks/credential-guard/secret-commands`. See "Commands that show secrets". |
| `permissions.json` | `bin/link-harness`, `bin/doctor` | `{"deny": ["Bash(…)"], "ask": ["Bash(…)"]}`, Claude Code permission rules. They are merged into `~/.claude/settings.json` after the core ones. |
| `tests.sh` | `tests/run`, `bin/doctor --tests` | The pack's own tests, with the helpers of `tests/lib/pack-test.sh`: `ro_ok`/`ro_no`, `blk`/`alw`, `denied`/`asked`/`unruled`, `guarded`. |
| `domains` | `bin/link-harness`, `bin/doctor` | Domains the sandbox of the `strict` profile allows when the pack is chosen, one per line: `host`, `*.domain` or `host:port` (`bin/lib/packs.sh` `packs_sandbox`). Only domains checked inside the sandbox; any other is refused (`strictAllowlist`). |
| `README.md` | people | Optional notes. |

Lines starting with `#` and empty lines are ignored in `guard-tools`, `destructive.rules`, `credential-files`, `credential-readers` and `secret-commands`.

## Example

A rule in `packs/aws/destructive.rules`:

```
aws-s3-rb-rm|<P>aws<G><S>s3<G><S>(rb|rm)<E>
```

It blocks `aws s3 rm s3://b`, `aws --profile pro s3 rb s3://b` and `ssh host 'aws s3 rm …'`. It lets `aws s3 ls` through.

## Tests

- `packs/<name>/tests.sh`: the rules of each pack (reads of `bin/ro`, destructive commands, `deny`/`ask`, `ro-guard`).
- `tests/floor.sh`: the floor, whatever packs there are: destructive commands and credential files.
- `tests/credential-guard.sh`: how `credential-guard` tells reading from using, with no pack rule involved.
- `tests/packs.sh`: each pack is well formed, and a made-up pack in a copy of the harness reaches `bin/ro`, both guards and the `deny`/`ask` merge.
- `tests/ro.sh` and `tests/block-destructive.sh`: the core and how the guards read a command, with no pack rule involved.
