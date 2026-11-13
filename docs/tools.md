# Tool-specific notes

Generic notes for the agent tools the harness installs into (Claude Code, Claude desktop app, Copilot CLI). Loaded on demand, not in every session.

## Where instructions are loaded

- `GLOBAL.md` (root of the consumer repo, copied from `templates/GLOBAL.md`) = the always-loaded global instructions. `~/.claude/CLAUDE.md` and `~/.copilot/copilot-instructions.md` are symlinks to it.
- `AGENTS.md` and `CLAUDE.md` in the repo root = 3-line pointers to `GLOBAL.md`, both copied from `templates/root-pointer.md`. They are pointers, not copies, so the tool does not load the same text twice (global + repo) when the working directory is the repo.
- Skills in Claude Code, plugin install: the plugin provides `skills/<name>/` and puts its `bin/` on the PATH of the Bash tool (skills call `check-work`, `new-work`, `ro`... by bare name). A `SessionStart` hook keeps `~/.local/share/infra-agent-harness/current` pointing at the installed plugin, and another (`install-check`) says once per session if the `deny` rules are missing from `~/.claude/settings.json` (you have not run `link-harness`). The same plugin registers the guards through `hooks/hooks.json` (`ro-guard` and `block-destructive-platform` on Bash, `credential-guard` on Bash, Read and Grep), so they are active as soon as it is installed (security profile: see below). `link-harness` then only does the `permissions.deny` / `permissions.ask` rules (plugins cannot ship them), `GLOBAL.md`, git hooks and Copilot.
- Skills, manual install: source in `skills/<name>/` of the harness, symlinked from `~/.claude/skills/<name>`. `~/.copilot/skills` points to `~/.claude/skills` (or, if it is a real folder, gets one link per skill). Plugin mode is detected from `~/.claude/plugins/installed_plugins.json`; `IAH_PLUGIN=1|0` overrides.
- Path-specific instructions: `instructions/*.instructions.md` and `<repo>/.github/instructions/*.instructions.md`.
- `bin/link-harness` installs all of this. It is idempotent, backs up a real file before replacing it with a link, and never removes your own settings (see "Hook registration" for what it takes back). The `post-merge` and `post-rewrite` git hooks re-run it after every pull or rebase.

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
- `bin/doctor` checks a machine in a few seconds and prints no secrets. It is read-only: it runs `link-harness --dry-run` and reports what `bin/link-harness` would change. `bin/doctor --tests` also runs the tests of the guards and the packs on that machine (a few minutes on WSL). `bin/doctor --security [--no-network]` is a separate, faster run (no `git fetch`) that checks the posture of the machine: profile and packs, read-only mode, sandbox under `strict`, permission prompts turned off in the settings the agent loads, credential variables in the environment (names only) and the AWS role and Kubernetes permissions the agent uses (shown through `ro`, which does not change). It exits 1 only on `FAIL`; every `WARN` says how to fix it.

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
  - `bin/ro --check …` validates without running (prints `ok` or the reason). Tests: `bash tests/ro.sh` (core) and `packs/<name>/tests.sh`.
- **Read-only mode:** `bin/ro mode on [reason]` creates `~/.config/infra-agent-harness/ro-mode` (`RO_MODE_FILE` overrides the path); `bin/ro mode status` shows it. While the mode is on, the `ro-guard` hook (PreToolUse on Bash) blocks cloud, cluster and remote-access tools (`aws`, `kubectl`, `helm`, `terraform`, `gh`, remote shells…) outside `bin/ro`, and also blocks switching the mode off: **only the user** runs `bin/ro mode off`, from a terminal. It protects from mistakes, not from an adversary (a script written on the fly is not inspected). With no mode file the hook only runs the profile check below.
- **What agents do not write:** `~/.claude/settings.json` and `settings.local.json`, the folder `~/.config/infra-agent-harness/` and the installed copy of the plugin (`~/.claude/plugins/cache/*/infra-agent-harness`, and the stable-link target when it is a plain directory). `ro-guard` blocks writes there in every mode (a redirection, `tee`, `cp` to it, `rm`, `sed -i`…), and `settings.base.json` / `bin/link-harness` add `Edit` deny rules for the Edit tool. Reading and naming them is fine. The user changes them in a terminal; the agent gives the change to the user, so it cannot edit the Claude Code settings. **Not protected:** a harness installed as a git clone (the stable link points to a clone): that is where the harness is developed, so changes there go through PR, tests and review; `bin/doctor` says which case this machine is in. A script written on the fly is not inspected.
- **Security profile:** `bin/security-profile` shows it; `bin/security-profile set <permissive|standard|strict> [--packs all|none|aws,kubernetes]` changes it, then run `bin/link-harness`. It lives in `~/.config/infra-agent-harness/profile` (`IAH_PROFILE_FILE` overrides the path); without the file the profile is `standard` with every installed pack. `packs=` only takes permissions away: `bin/ro` runs the tools of the chosen packs only, while every installed pack keeps blocking (`packs/README.md`). **Only the user** changes the profile: `ro-guard` blocks `security-profile set` and any command that names the file, in every mode, and a core `deny` rule stops the Edit tool on it and on the mode file. `bin/doctor` always shows the profile. What each profile does:
  - every profile keeps the floor: the `deny` rules and the guards of every pack, the credential locks, the decision log and the secret scan;
  - `standard` (default) adds the `ask` rules: Claude Code asks you before `terraform`/`tofu`/`terragrunt apply`, `kubectl apply`, `helm install|upgrade`, `git push --force` and `git reset --hard`;
  - `permissive` drops the `ask` rules of the packs, so the platform ones run without asking; the git ones stay. `bin/link-harness` removes them from `~/.claude/settings.json` and lists each one: any identical rule goes, even one you wrote yourself. Going back to `standard` (`set standard`, then `link-harness`) adds them again. `bin/doctor` warns if `settings.json` still has them;
  - `strict` is `standard` plus the native sandbox of Claude Code around Bash commands. `bin/link-harness` turns it on in `~/.claude/settings.json` with `failIfUnavailable` (Claude Code does not start without it) and no retry outside it, and adds:
    - the domains of the core (GitHub) and of the chosen packs (`packs/<name>/domains`). Any other domain is refused, in every permission mode (`strictAllowlist`): asking was not enough, because auto mode let an unlisted domain through without asking. To allow one of yours, add it to `sandbox.network.allowedDomains` in `~/.claude/settings.json`; `link-harness` keeps it;
    - `ro` outside the sandbox: it is the read-only gate and reads the cloud credentials itself. The cloud CLIs called directly run inside, without credentials, so under `strict` the agent reaches the cloud only through `ro` (you run `terraform plan`; `init`, `validate` and `fmt` work inside);
    - every credential file denied inside it, the third lock: it also stops a script that opens `.env` by itself.
  - Going back to another profile takes all that back (exact matches, named one by one) and keeps your own sandbox entries. On Linux and WSL2 it needs `bubblewrap` and `socat`: `security-profile set strict` refuses without them and `bin/doctor` fails. Claude Code applies the change to running sessions too;
  - what changes in daily work (checked in WSL2):
    - **you run git commit, push, pull and fetch**: the SSH agent is not reachable inside the sandbox, so signed commits and git over SSH fail there. The agent prepares the message (`git commit -F <file>`) and gives you the commands;
    - `ro` runs outside the sandbox only when the command starts with it: `cd x && ro …` stays inside and fails without credentials;
    - commands write only under the folder the session started in (and `$TMPDIR`): open the session in your work repo, not in your home directory, or the whole home is writable;
    - a credential file is denied only if it exists when the command starts, and `**/.env` only under the session's starting folder; inside the sandbox a denied file cannot be deleted either (delete it from a terminal);
    - a download from a domain not listed (`npm install`, `pip install`, `curl`) fails until you add the domain;
  - `isolated` comes with the container (v0.2).
- **Credential files:** in every profile and mode, `credential-guard` (PreToolUse on Bash, Read and Grep) blocks reading, copying or sending a credential file (`cat ~/.aws/credentials`, `cp ~/.kube/config /tmp`, `curl -T ~/.netrc …`, the Read tool on `.env`); using it passes (`ssh -i`, `--kubeconfig`, `source .env`). `bin/link-harness` also adds one `Read(…)` deny rule per file. Lists, exceptions and limits: `packs/README.md`, "Credential files".
- **Commands that show secrets:** the same guard blocks a command that prints a secret (`gh auth token`, `aws configure export-credentials`, `kubectl get secret x -o yaml`) when its output ends on the screen, in a file or in a reader; piped into another tool (`| docker login --password-stdin`) or kept in a variable (`TOKEN=$(…)`) it passes. `packs/README.md`, "Commands that show secrets".
- **Sub-agents:** the brief and the prompt say "only `bin/ro`". The hook applies to them too, because they share the session.

### Hook registration

- `bin/link-harness` merges `hooks/settings.base.json` and the `permissions.json` of every pack into `~/.claude/settings.json` (macOS, Linux, WSL). Manual install: registers `ro-guard` and `block-destructive-platform` as PreToolUse hooks on Bash, and `credential-guard` on Bash, Read and Grep. Plugin mode: the plugin registers them, so it adds no hooks and removes the entries of this harness under the stable link that an earlier run added (they would run twice; the file is backed up first, and an entry that points to another harness is kept with a warning). In both modes it adds the `permissions.deny` / `permissions.ask` rules (destructive commands denied; force push, hard reset, `terraform`/`tofu`/`terragrunt apply`, `kubectl apply` and `helm install/upgrade` ask first) and one `Read(…)` deny rule per credential file.
- It never removes your own settings. What it takes back is what the harness itself put there and the profile no longer wants, named one by one: the `ask` rules of the packs with `permissive`, the sandbox entries of `strict` in any other profile, and in plugin mode the guard entries an earlier run registered. It skips a hook whose script is already registered and leaves a `settings.json.bak-<date>` copy when the file changes. It needs `jq`.
- The guards fail closed: without `jq`, or with a hook input they cannot parse, they block the call (exit 2) and say why (`hooks/lib/fail-closed.sh`, `tests/fail-closed.sh`); the same when the command parser (`hooks/lib/cmdparse.sh`) fails. A guard that stopped halfway would let the command run.
- `hooks/confidence-nudge` (UserPromptSubmit) is not in the base file; register it yourself if you want it. It adds a reminder to end troubleshooting conclusions with a confidence level.
- `bin/doctor` checks the registration (in plugin mode: registered by the plugin's `hooks/hooks.json`; WARN if the same guard is also in `~/.claude/settings.json`) and, with `--tests`, runs the guards' tests (`tests/block-destructive.sh`, `tests/credential-guard.sh`, `tests/fail-closed.sh`, `tests/floor.sh`, `tests/packs.sh`, `tests/ro.sh` and each `packs/<name>/tests.sh`).

### Decision log

- Every block by `ro-guard`, `block-destructive-platform` or `credential-guard` appends one JSON line to `~/.local/state/infra-agent-harness/hook-decisions.jsonl`: outside the repo, mode 600, command cut to 300 characters. `IAH_HOOK_LOG` changes the path. Logging never makes a hook fail.
- See what is being blocked:

  ```
  jq -r '[.ts,.hook,.reason,.command]|@tsv' ~/.local/state/infra-agent-harness/hook-decisions.jsonl | tail
  ```

## Compaction

- At ~80% of the context: run `close-task` (micro) first to save progress, then compact, then check that the summary keeps the key decisions.
