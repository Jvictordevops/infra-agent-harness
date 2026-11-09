# Rule packs

A pack holds the safety rules for one technology, and their tests. The guards and `bin/ro` hold no platform rules of their own: they read them from `packs/<name>/`. Every pack under `packs/` is installed; the security profile chooses which ones you use, under the rule below.

| Pack | Tools | `bin/ro` reads | Destructive commands blocked |
|---|---|---|---|
| `aws` | `aws` | `describe-`/`list-`/`get-`/`batch-get-`/`lookup-`/`search-`, `s3 ls`, `--profile` mandatory | `delete-*`, `terminate-*`, `stop-*`, `s3 rb`, `s3 rm` |
| `kubernetes` | `kubectl`, `eksctl`, `argocd`, `flux`, `k9s`, `kubectx`, `kubens` | `kubectl get`, `describe`, `logs`, `top`, `events`…, `--context` mandatory, never Secrets | `delete`, `drain`, `cordon`, `scale --replicas 0`, `rollout undo` |
| `helm` | `helm`, `helmfile` | `list`, `status`, `history`, `get metadata`, `--kube-context` mandatory | `helm uninstall`, `helmfile apply\|destroy\|delete` |
| `terraform` | `terraform`, `tofu`, `terragrunt` | none (`bin/ro` does not run them) | `destroy`, `import`, `apply -destroy`, `state rm\|push\|replace-provider` |

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

What it does not stop, because it guards against mistakes, not an adversary: a reader missing from the list, a command that reads without naming the path (`cd ~/.aws && cat credentials`, `grep -r x .`), a script or heredoc that opens the file itself, a path built in a variable, and commands that print a secret without opening a file (`gh auth token`; planned). The sandbox of the `strict` profile covers the first ones.

## What stays in the core

Some rules are not about one technology, so they stay outside the packs:

- `bin/ro`: `git`, `gh` and the file readers (`cat`, `head`, `tail`, `ls`, `find`, `grep`, `wc`, `stat`).
- `ro-guard`: `ssh`, `scp`, `sftp`, `rsync`, `sshfs`, `mosh` and `gh`. It also blocks `az` and `gcloud`, so Azure and Google Cloud stay blocked in read-only mode even without a pack.
- `hooks/settings.base.json`: the `ask` rules for `git push --force` and `git reset --hard`.

## Files of a pack

All files are optional. Any other file name is an error (`tests/packs.sh`).

| File | Read by | Format |
|---|---|---|
| `ro.sh` | `bin/ro` | Bash, sourced. It calls `ro_tool <tool>` for each tool and defines `check_<tool>`, which gets the arguments after the tool and calls `deny "<reason>"` to refuse. Helpers: `deny`, `opt_val <option> "$@"` (value of `--opt X` or `--opt=X`), `in_list <value> <comma list>`, `lower`. A pack cannot register a core tool or a tool of another pack. |
| `guard-tools` | `ro-guard` | One command name per line (`[a-z0-9_-]`). In read-only mode, these commands are blocked outside `bin/ro`. |
| `destructive.rules` | `block-destructive-platform` | One `name\|regex` per line (extended regex, matched against the whole command). The name goes to the decision log. Placeholders: `<P>` start of a tool name (also after `/`, a quote or `$(`), `<S>` whitespace, `<G>` any tokens in the same command segment (never across `;`, `\|` or `&`), `<E>` end of a word. |
| `credential-files` | `credential-guard`, `bin/ro`, `bin/link-harness` | One pattern per line: `~/<path>` (from the home directory) or `**/<name>` (that file name anywhere); `*` is any text. Each line also becomes a `Read(~/<path>)` or `Read(//**/<name>)` deny rule. |
| `credential-readers` | `credential-guard` | One `<command>` or `<command> <word>` per line (a reader only when `<word>` is one of its arguments), like `hooks/credential-guard/readers`. |
| `permissions.json` | `bin/link-harness`, `bin/doctor` | `{"deny": ["Bash(…)"], "ask": ["Bash(…)"]}`, Claude Code permission rules. They are merged into `~/.claude/settings.json` after the core ones. |
| `tests.sh` | `tests/run`, `bin/doctor` | The pack's own tests, with the helpers of `tests/lib/pack-test.sh`: `ro_ok`/`ro_no`, `blk`/`alw`, `denied`/`asked`/`unruled`, `guarded`. |
| `domains` | — | Reserved for the sandbox allow-list of the `strict` profile. Not read yet. |
| `README.md` | people | Optional notes. |

Lines starting with `#` and empty lines are ignored in `guard-tools`, `destructive.rules`, `credential-files` and `credential-readers`.

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
