# Rule packs

A pack holds the safety rules for one technology. The guards and `bin/ro` hold no platform rules of their own: they read them from `packs/<name>/`. Every pack under `packs/` is active. Choosing packs per profile comes later.

| Pack | Tools | `bin/ro` reads | Destructive commands blocked |
|---|---|---|---|
| `aws` | `aws` | `describe-`/`list-`/`get-`/`batch-get-`/`lookup-`/`search-`, `s3 ls`, `--profile` mandatory | `delete-*`, `terminate-*`, `stop-*`, `s3 rb`, `s3 rm` |
| `kubernetes` | `kubectl`, `eksctl`, `argocd`, `flux`, `k9s`, `kubectx`, `kubens` | `kubectl get`, `describe`, `logs`, `top`, `events`…, `--context` mandatory, never Secrets | `delete`, `drain`, `cordon`, `scale --replicas 0`, `rollout undo` |
| `helm` | `helm`, `helmfile` | `list`, `status`, `history`, `get metadata`, `--kube-context` mandatory | `helm uninstall`, `helmfile apply\|destroy\|delete` |
| `terraform` | `terraform`, `tofu`, `terragrunt` | none (`bin/ro` does not run them) | `destroy`, `import`, `apply -destroy`, `state rm\|push\|replace-provider` |

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

- `tests/packs.sh` checks that each pack is well formed. It also adds a made-up pack to a copy of the harness and checks that `bin/ro`, both guards and the `deny`/`ask` merge pick it up.
- `tests/ro.sh` and `tests/block-destructive.sh` test the rules themselves.
