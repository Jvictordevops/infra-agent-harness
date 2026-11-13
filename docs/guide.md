# Guide: install and first day

One path from nothing to an agent working read-only against your infrastructure. One step at a time: each step says what to run and what you should see. Reference detail is in [tools.md](tools.md) and [packs/README.md](../packs/README.md); the limits are in [threat-model.md](threat-model.md).

About 30 minutes. You need Linux, macOS or WSL2, with `bash`, `git` and `jq`. `gitleaks` is needed for the commit hook of your work repo.

## 1. Check the tools

```bash
for t in git jq gitleaks claude; do command -v "$t" >/dev/null && echo "ok   $t" || echo "MISS $t"; done
```

You should see four `ok` lines. What to do with a `MISS`:

- `jq`: `sudo apt-get install jq` or `brew install jq`. Without it the guards block every command (they fail closed), so install it first.
- `gitleaks`: `brew install gitleaks`, or the binary from its [releases page](https://github.com/gitleaks/gitleaks/releases) copied to a folder of your PATH. Without it `doctor` shows one `FAIL` in step 5 and commits in your work repo are blocked.
- `claude`: install Claude Code from its [documentation](https://docs.claude.com/en/docs/claude-code/overview).
 On Windows, `claude` lives on the Windows side and everything else inside WSL: run the `claude plugin` commands of step 2 in a Windows terminal and the rest in WSL.

## 2. Install the plugin

```bash
claude plugin marketplace add Jvictordevops/infra-agent-harness
```

```bash
claude plugin install infra-agent-harness@infra-agent-harness
```

Open a new Claude Code session and say hello: its first start creates a stable link to the installed plugin. Check it from a terminal:

```bash
ls ~/.local/share/infra-agent-harness/current/bin
```

You should see `check-work`, `doctor`, `link-harness`, `new-work`, `ro`, `security-profile` and a few more. From this moment the three guards are active in every session.

If you do not use the plugin (Copilot-only machine, or you prefer a clone), follow "Manual install" in the [README](../README.md#manual-install) and replace `~/.local/share/infra-agent-harness/current` with your clone in the steps below.

## 3. Create your work repo

Your work lives in a repository of its own, separate from the harness.

```bash
H=~/.local/share/infra-agent-harness/current
mkdir -p ~/my-work && cd ~/my-work && git init
cp $H/templates/GLOBAL.md GLOBAL.md
cp $H/templates/root-pointer.md AGENTS.md
cp $H/templates/root-pointer.md CLAUDE.md
mkdir -p contexts work/global
printf 'language=en\nmethod=light\n' > .harness.conf
```

Open `GLOBAL.md` and fill in the `TODO` lines: who you are, your stack, one line per company or platform you work on. It is loaded in every session, so keep it short.

## 4. Link the harness to your machine

Run it from the work repo. First look at what it would do; it writes nothing:

```bash
cd ~/my-work && ~/.local/share/infra-agent-harness/current/bin/link-harness --dry-run
```

You should see `would:` lines: link `GLOBAL.md` as `~/.claude/CLAUDE.md`, link `ro` and `security-profile` into `~/.local/bin`, set the git hooks of the repo, and merge the permission rules into `~/.claude/settings.json`. Then run it for real:

```bash
cd ~/my-work && ~/.local/share/infra-agent-harness/current/bin/link-harness
```

- What it does: adds the `deny` and `ask` rules and one `Read(…)` rule per credential file (a plugin cannot ship them), and the links above.
- How to undo it: `~/.claude/settings.json.bak-<date>` is the file as it was; the links are plain symlinks you can delete.
- It never removes your own settings. Run it again after you change the security profile or update the plugin.

## 5. Check the machine

```bash
cd ~/my-work && ~/.local/share/infra-agent-harness/current/bin/doctor
```

The last line should be `=== 0 fail(s), N warning(s)` (one `FAIL` if you skipped `gitleaks` in step 1). Each `WARN` and `FAIL` line says what to run. Common ones:

- `gitleaks missing`: install it, or your commits in the work repo are blocked.
- `~/.local/bin is not on the PATH`: add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile and open a new terminal. Until then, type the full path of `ro` and `security-profile`.
- `no contexts/<name>/ yet`: fine for now; works go under `work/global/`.

## 6. See a guard block

In a Claude Code session opened in `~/my-work`, ask the agent to run `kubectl delete pod demo`. Nothing is deleted: the command never runs. You should see `Blocked destructive platform command`. Then look at the log from a terminal:

```bash
jq -r '[.ts,.hook,.reason,.command]|@tsv' ~/.local/state/infra-agent-harness/hook-decisions.jsonl | tail -3
```

You should see one line with `block-destructive-platform` and the command. (The file does not exist until a guard has blocked something.)

## 7. Turn read-only mode on

Do this when the cloud role of the agent can write (for example an administrator role that is the only one you have). From a terminal, not from the agent. If the terminal answers `ro: command not found`, `~/.local/bin` is not on your PATH yet (step 5): open a new terminal after adding it, or type `~/.local/bin/ro`.

```bash
ro mode on "admin role in use"
```

```bash
ro mode status
```

You should see `ro: ON since <date> admin role in use`. Now the agent reaches clouds, clusters and other machines only through `ro`, one read command at a time. These two need the `aws` and `kubectl` tools installed and a profile and a context of yours in place of `dev`; to see only whether `ro` would allow a command, without running it, put `--check` after `ro` (it prints `ok` or the reason):

```bash
ro aws eks list-clusters --profile dev --region eu-west-1
```

```bash
ro kubectl get pods -A --context dev
```

- Anything else (`aws …`, `kubectl …`, `terraform …`, `ssh …` typed directly) is blocked while the mode is on.
- Only you switch it off, from a terminal: `ro mode off`. The agent is blocked from doing it.
- `ro` is an allow-list of read verbs, not an IAM policy: read "The read-only executor" in the [threat model](threat-model.md#5-the-read-only-executor-binro).

## 8. Choose a security profile

```bash
security-profile show
```

You should see `profile: standard` and the installed packs. The three profiles:

| Profile | What it adds | When |
|---|---|---|
| `permissive` | Nothing: the agent runs `terraform apply`, `kubectl apply` and `helm upgrade` without asking | A sandbox account you can lose |
| `standard` (default) | Claude Code asks you before those commands, and before `git push --force` and `git reset --hard` | Daily work |
| `strict` | `standard` plus the sandbox of Claude Code: writes only in the session folder, a list of allowed domains, credential files denied | Long or unattended runs |

Every profile keeps the floor: destructive commands blocked, credential files not read, every block logged. To change it (from a terminal; the agent is blocked from doing it), then link again:

```bash
security-profile set strict
```

```bash
cd ~/my-work && ~/.local/share/infra-agent-harness/current/bin/link-harness
```

`strict` needs `bubblewrap` and `socat` on Linux and WSL2 (`sudo apt-get install bubblewrap socat`), and it changes daily work: you run `git commit` and `git push` yourself. Read "Security profile" in [tools.md](tools.md) before you choose it. Go back with `security-profile set standard` and `link-harness` again.

To use only some packs (the tools `ro` runs and the domains of `strict`): `security-profile set standard --packs aws,kubernetes`. Every installed pack keeps blocking its destructive commands whatever you choose. The choice of packs stays when you change the profile later: go back to all of them with `--packs all`.

## 9. Start your first work

In a Claude Code session opened in `~/my-work`, ask for it in plain words:

> Start an investigation about why the staging ingress returns 502.

The `new-project` skill creates `work/global/<date>.<slug>/` with a `README.md`, a `ROADMAP/` and a `RECORD/` folder, and fills in the goal and the first tasks. During the work the agent writes one record per finding or decision. When you stop, say "save progress": the `close-task` skill updates the README and validates the folder. Next day, say "let's continue with the ingress work" and `load-project` reads it back.

The method in two pages: [method.md](method.md).

## 10. When a guard blocks something you wanted

1. Read the message: it names the guard and the reason.
2. If the command is right, run it yourself in a terminal. That is the design: destructive commands and secrets go through a person.
3. If the command only mentions a blocked one in the arguments of a tool the parser does not know as text (`gh pr create --body "…"`), ask the agent to write the text with its file tools instead of the shell. This is a known limit (a commit message, a `grep` pattern or `echo` are not blocked).
4. If a rule gets in the way every day, change the data, not the guard: the lists are in `packs/<name>/` and `hooks/credential-guard/` ([packs/README.md](../packs/README.md)). Tell us in an issue.

## Update and uninstall

- Update: `claude plugin update infra-agent-harness@infra-agent-harness`, open a new session, then run `link-harness` again from your work repo.
- Uninstall: `claude plugin uninstall infra-agent-harness@infra-agent-harness`. Then remove by hand what `link-harness` added: the rules in `~/.claude/settings.json` (or restore a `settings.json.bak-<date>` copy), the links in `~/.local/bin` and `~/.claude/CLAUDE.md`, the `core.hooksPath` of your work repo (`git config --unset core.hooksPath`) and `~/.config/infra-agent-harness/`.
