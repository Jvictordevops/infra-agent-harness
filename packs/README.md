# Rule packs

A pack holds the safety rules for one technology, and their tests. The guards and `bin/ro` hold no platform rules of their own: they read them from `packs/<name>/`. Every pack under `packs/` is active; choosing packs comes with the profiles, under the rule below.

| Pack | Tools | `bin/ro` reads | Destructive commands blocked |
|---|---|---|---|
| `aws` | `aws` | `describe-`/`list-`/`get-`/`batch-get-`/`lookup-`/`search-`, `s3 ls`, `--profile` mandatory | `delete-*`, `terminate-*`, `stop-*`, `s3 rb`, `s3 rm` |
| `kubernetes` | `kubectl`, `eksctl`, `argocd`, `flux`, `k9s`, `kubectx`, `kubens` | `kubectl get`, `describe`, `logs`, `top`, `events`…, `--context` mandatory, never Secrets | `delete`, `drain`, `cordon`, `scale --replicas 0`, `rollout undo` |
| `helm` | `helm`, `helmfile` | `list`, `status`, `history`, `get metadata`, `--kube-context` mandatory | `helm uninstall`, `helmfile apply\|destroy\|delete` |
| `terraform` | `terraform`, `tofu`, `terragrunt` | none (`bin/ro` does not run them) | `destroy`, `import`, `apply -destroy`, `state rm\|push\|replace-provider` |

Deny rules (Claude Code refuses the command) cover the main destructive verbs of each pack. Ask rules (Claude Code asks you first) cover `apply` of the three Terraform tools, `kubectl apply` and `helm install|upgrade`.

## Choosing packs: only permissions go

Choosing packs can only take away what is **allowed**, never what is **blocked**:

- Always loaded from every installed pack: `destructive.rules`, the `deny` and `ask` rules of `permissions.json`, and `guard-tools`. Someone who does not use Kubernetes still has `kubectl delete` blocked; it costs nothing.
- Only for the chosen packs: the `bin/ro` tools of `ro.sh` and, with the `strict` profile, the sandbox `domains`.

`tests/floor.sh` holds the floor: destructive commands that only a person runs. Each one must be blocked by `block-destructive-platform` and match a `deny` rule. It fails if a change of packs drops any of them.

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
| `permissions.json` | `bin/link-harness`, `bin/doctor` | `{"deny": ["Bash(…)"], "ask": ["Bash(…)"]}`, Claude Code permission rules. They are merged into `~/.claude/settings.json` after the core ones. |
| `tests.sh` | `tests/run`, `bin/doctor` | The pack's own tests, with the helpers of `tests/lib/pack-test.sh`: `ro_ok`/`ro_no`, `blk`/`alw`, `denied`/`asked`/`unruled`, `guarded`. |
| `domains` | — | Reserved for the sandbox allow-list of the `strict` profile. Not read yet. |
| `README.md` | people | Optional notes. |

Lines starting with `#` and empty lines are ignored in `guard-tools` and `destructive.rules`.

## Example

A rule in `packs/aws/destructive.rules`:

```
aws-s3-rb-rm|<P>aws<G><S>s3<G><S>(rb|rm)<E>
```

It blocks `aws s3 rm s3://b`, `aws --profile pro s3 rb s3://b` and `ssh host 'aws s3 rm …'`. It lets `aws s3 ls` through.

## Tests

- `packs/<name>/tests.sh`: the rules of each pack (reads of `bin/ro`, destructive commands, `deny`/`ask`, `ro-guard`).
- `tests/floor.sh`: the floor, whatever packs there are.
- `tests/packs.sh`: each pack is well formed, and a made-up pack in a copy of the harness reaches `bin/ro`, both guards and the `deny`/`ask` merge.
- `tests/ro.sh` and `tests/block-destructive.sh`: the core and how the guards read a command, with no pack rule involved.
