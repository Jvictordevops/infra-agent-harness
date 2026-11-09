# Tool-specific notes

Generic notes for the agent tools the harness installs into (Claude Code, Claude desktop app, Copilot CLI). Loaded on demand, not in every session.

## Where instructions are loaded

- `GLOBAL.md` (root of the consumer repo, copied from `templates/GLOBAL.md`) = the always-loaded global instructions. `~/.claude/CLAUDE.md` and `~/.copilot/copilot-instructions.md` are symlinks to it.
- `AGENTS.md` and `CLAUDE.md` in the repo root = 3-line pointers to `GLOBAL.md`, both copied from `templates/root-pointer.md`. They are pointers, not copies, so the tool does not load the same text twice (global + repo) when the working directory is the repo.
- Skills in Claude Code, plugin install: the plugin provides `skills/<name>/` and puts its `bin/` on the PATH of the Bash tool (skills call `check-work`, `new-work`, `ro`... by bare name). A `SessionStart` hook keeps `~/.local/share/infra-agent-harness/current` pointing at the installed plugin. The same plugin registers the `ro-guard` and `block-destructive-platform` guards (PreToolUse on Bash) through `hooks/hooks.json`, so they are active as soon as it is installed (profile fixed to `standard` until profiles land). `link-harness` then only does the `permissions.deny` / `permissions.ask` rules (plugins cannot ship them), `GLOBAL.md`, git hooks and Copilot.
- Skills, manual install: source in `skills/<name>/` of the harness, symlinked from `~/.claude/skills/<name>`. `~/.copilot/skills` points to `~/.claude/skills` (or, if it is a real folder, gets one link per skill). Plugin mode is detected from `~/.claude/plugins/installed_plugins.json`; `IAH_PLUGIN=1|0` overrides.
- Path-specific instructions: `instructions/*.instructions.md` and `<repo>/.github/instructions/*.instructions.md`.
- `bin/link-harness` installs all of this. It is idempotent, backs up a real file before replacing it with a link, and never removes your own settings. The `post-merge` and `post-rewrite` git hooks re-run it after every pull or rebase.

## Windows + WSL

- Keep the repo inside WSL. The Claude desktop app on Windows reads `%USERPROFILE%\.claude` and cannot follow WSL symlinks, so `link-harness` **copies** `GLOBAL.md` (as `CLAUDE.md`, with a "generated" first line) and, outside plugin mode, the skills there (in plugin mode install the plugin from the Windows side). Re-run it after a pull (the git hooks do). `LINK_HARNESS_WINDOWS=0` skips this part.
- Run repo commands from the Windows side with:

  ```
  wsl.exe -d <distro> --cd <repo> --exec bash -ic '<cmd>'
  ```

  - `--exec`: without it, `wsl.exe` passes the command through another shell and expands variables too early.
  - `-ic`: loads `~/.bashrc` (version manager, SSH agent bridge). Without it, git over SSH and commit signing fail.
  - From Git Bash, prefix `MSYS_NO_PATHCONV=1` so it does not rewrite `/home/...` paths.
- If the SSH agent lives in a password manager, keep it unlocked for push, pull and signed commits (`agent refused operation` usually means a locked vault).
- Claude hooks (`hooks/*`) are registered in the profile inside WSL (`~/.claude/settings.json`); the Windows app profile only receives `CLAUDE.md` and the skills.
- `bin/doctor` checks a machine in a few seconds and prints no secrets. It is read-only: it runs `link-harness --dry-run` and reports what `bin/link-harness` would change.

## Read-only executors (`bin/ro`)

- **What for:** let an executor and its sub-agents only read clouds, clusters and repos even when the cloud role is an administrator (for example an SSO admin role that is the only one available in an account). The barrier is ours, in two layers.
- **`bin/ro`** runs a single allow-listed command with a fixed shape. The `aws`, `kubectl` and `helm` checks come from the packs (`packs/<name>/ro.sh`, [packs/README.md](../packs/README.md)); `git`, `gh` and the file readers are core:
  - `aws <service> <operation> … --profile P`: `describe-`, `list-`, `get-`, `batch-get-`, `lookup-`, `search-` operations and `s3 ls`.
  - `kubectl <verb> … --context C`: `get`, `describe`, `logs`, `top`, `events`, `api-resources`, `auth can-i`…
  - `helm list|status|history|get metadata … --kube-context C`.
  - `git -C <dir> log|show|diff|grep|status|branch…`.
  - `gh` reads: `repo|release|workflow list|view`, `pr list|view|diff|checks|status`, `issue list|view|status`, `run list|view`, `label list`, `search …`, `auth status`, and `gh api <endpoint>` with GET only (`-f`/`-F` need `-X GET`; no GraphQL, secrets, variables, keys or tokens). `git clone`/`fetch` are not `ro`: `ro-guard` does not block `git`, it is a local tool.
  - `cat|head|tail|ls|find|grep|wc|stat` on paths under `RO_ROOTS` (default `$HOME/code`).
  - Never: secrets (`Secrets`, `get-secret-value`, `--with-decryption`), tokens, credentials or sensitive files. There is no shell inside: no pipes, redirections or chaining; filter the output (`jq`, `grep`) outside, locally.
  - Per-task limits: `RO_PROFILES=<profile> RO_CONTEXTS=<context> bin/ro …` (comma lists).
  - `bin/ro --check …` validates without running (prints `ok` or the reason). Tests: `bash tests/ro.sh`.
- **Read-only mode:** `bin/ro mode on [reason]` creates `~/.config/infra-agent-harness/ro-mode` (`RO_MODE_FILE` overrides the path); `bin/ro mode status` shows it. While the mode is on, the `ro-guard` hook (PreToolUse on Bash) blocks cloud, cluster and remote-access tools (`aws`, `kubectl`, `helm`, `terraform`, `gh`, remote shells…) outside `bin/ro`, and also blocks switching the mode off: **only the user** runs `bin/ro mode off`, from a terminal. It protects from mistakes, not from an adversary (a script written on the fly is not inspected). With no mode file the hook does nothing.
- **Sub-agents:** the brief and the prompt say "only `bin/ro`". The hook applies to them too, because they share the session.

### Hook registration

- `bin/link-harness` merges `hooks/settings.base.json` and the `permissions.json` of every pack into `~/.claude/settings.json` (macOS, Linux, WSL). Manual install: registers `ro-guard` and `block-destructive-platform` as PreToolUse hooks on Bash. Plugin mode: the plugin registers them, so it adds no hooks and removes the entries of this harness under the stable link that an earlier run added (they would run twice; the file is backed up first, and an entry that points to another harness is kept with a warning). In both modes it adds the `permissions.deny` / `permissions.ask` rules (destructive commands denied; force push, hard reset, `apply` and `helm install/upgrade` ask first).
- It only adds: it never removes anything, skips a hook whose script is already registered, and leaves a `settings.json.bak-<date>` copy when the file changes. It needs `jq`.
- `hooks/confidence-nudge` (UserPromptSubmit) is not in the base file; register it yourself if you want it. It adds a reminder to end troubleshooting conclusions with a confidence level.
- `bin/doctor` checks the registration (in plugin mode: registered by the plugin's `hooks/hooks.json`; WARN if the same guard is also in `~/.claude/settings.json`) and runs the guards' tests (`tests/block-destructive.sh`, `tests/packs.sh`, `tests/ro.sh`).

### Decision log

- Every block by `ro-guard` or `block-destructive-platform` appends one JSON line to `~/.local/state/infra-agent-harness/hook-decisions.jsonl`: outside the repo, mode 600, command cut to 300 characters. `IAH_HOOK_LOG` changes the path. Logging never makes a hook fail.
- See what is being blocked:

  ```
  jq -r '[.ts,.hook,.reason,.command]|@tsv' ~/.local/state/infra-agent-harness/hook-decisions.jsonl | tail
  ```

## Compaction

- At ~80% of the context: run `close-task` (micro) first to save progress, then compact, then check that the summary keeps the key decisions.
