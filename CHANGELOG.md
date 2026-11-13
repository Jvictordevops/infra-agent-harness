# Changelog

All notable changes to this project are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow [Semantic Versioning](https://semver.org/). Until 1.0.0, a minor version may change behaviour; the entry says so under **Changed**.

A release is a tag `vX.Y.Z` on `main`. The tag, `version` in `.claude-plugin/plugin.json` and the entry below must agree (the CI checks it).

## [Unreleased]

### Added

- `bin/doctor --security [--no-network]`: the posture of the machine in one short run. Shows the profile, packs and environment; warns about read-only mode off, permission prompts turned off (`bypassPermissions`, `skipDangerousModePermissionPrompt`, `Bash(*)`) in the user, local and repo settings (FAIL under `strict`), and credential variables in the environment (names only, never values); shows the AWS role (`ro aws sts get-caller-identity`) and the Kubernetes permissions (`ro kubectl auth can-i --list`) of `RO_PROFILES` and `RO_CONTEXTS`. It does not check whether a role can write, and `ro` is unchanged.

### Changed

- `ro-guard` reads the command line with a common parser (`hooks/lib/cmdparse.awk`, one `awk` per command; the list of commands whose arguments are text is `hooks/lib/cmdparse-data.txt`). A forbidden tool named only as text no longer blocks (`git commit -m "use aws"`, `command -v aws`, `source ./aws-env.sh`, a heredoc to `cat`). Forms that got through now block: `sudo -u x`, `nice -n 5`, `timeout -s KILL 5` before a tool, `find -exec`, `echo '…' | bash`, `xargs -n 1`, and a command nested more than 4 levels deep. `bash file.sh` and `source file` are not inspected.
- `block-destructive-platform` reads the command line with the same parser: a destructive command named only as text no longer blocks (`git commit -m "avoid terraform destroy"`, `grep "kubectl delete"`, `echo`, `sed`, a heredoc to `cat` or `tee`, single quotes, comments, inline `python3 -c`). Forms that got through now block (`sudo -u x`, `nice -n 5`, `timeout 5`, `xargs -I{}`, `echo '…' | bash`, a heredoc or here-string to a shell, `find -exec`, `<(…)`, a command nested more than 4 levels deep). The rule files of the packs do not change. The arguments of a tool that is not on `hooks/lib/cmdparse-data.txt` (`gh pr create --body "…"`) are still searched.

### Added

- A `SessionStart` hook, `install-check`, tells the agent (once per session, in one line) when the `deny` and `Read(…)` rules that `link-harness` merges are missing from `~/.claude/settings.json`, with the command that fixes it. It is silent when the rules are there.

## [0.1.0] - 2026-11-11

First public version. Everything below is new.

### Added

- **Guards** (Claude Code PreToolUse hooks), active in every security profile:
  - `block-destructive-platform`: blocks destructive platform commands (`terraform destroy`, `kubectl delete`, `aws … delete-*`, `helm uninstall`…), from the rules of each pack.
  - `credential-guard`: blocks reading, copying or sending credential files and showing the output of commands that print a secret; using them passes.
  - `ro-guard`: in read-only mode, cloud, cluster and remote tools only run through `bin/ro`; in every mode, agents cannot change the security profile.
  - They fail closed: without `jq`, or with an input they cannot parse, they block.
- **Read-only executor** `bin/ro`: one allow-listed read command at a time (`aws`, `kubectl`, `helm`, `git`, `gh`, file readers), here or on another machine over SSH.
- **Rule packs** `packs/{aws,kubernetes,helm,terraform}`: the platform rules as data, each with its tests. Format in `packs/README.md`.
- **Security profiles** `permissive`, `standard` (default) and `strict` (`bin/security-profile`). `strict` turns on the sandbox of Claude Code with an allow-list of domains and every credential file denied inside it.
- **Permission rules**: `deny` and `ask` rules of the core and the packs, and one `Read(…)` deny rule per credential file, merged into `~/.claude/settings.json` by `bin/link-harness`.
- **Decision log**: every block is appended to `~/.local/state/infra-agent-harness/hook-decisions.jsonl`.
- **Work method**: `bin/new-work`, `bin/check-work`, templates and skills (`new-project`, `load-project`, `close-task`, `init-context`, `troubleshoot`, `digest`, `parallel-audit`, `parallel-review`, `role`), in a light and a full variant, with English and Spanish vocabulary.
- **Git hooks** for the work repository: `pre-commit` (gitleaks, `check-work`), `prepare-commit-msg` (task trailers), `commit-msg` (optional AI attribution check, `ai_attribution=block`), `post-merge` and `post-rewrite`.
- **Tools**: `bin/link-harness` (install, idempotent, `--dry-run`), `bin/doctor` (read-only check of a machine; `--tests` runs the guard tests), `bin/denylist-scan` (nothing that identifies a company or a person gets published).
- **Optional modules**: `evidence` (shared evidence store, encrypted archives, clipboard between machines) and `two-machine` (architect and executor on two machines).
- **Packaging**: Claude Code plugin and marketplace in this repository; manual install as the fallback.
- **Documentation**: `README.md`, `docs/guide.md`, `docs/threat-model.md`, `docs/architecture.md`, `docs/tools.md`, `docs/method.md`, `docs/method-full.md`, `packs/README.md`.

### Known limits

- The guards stop mistakes, not an adversary: see `docs/threat-model.md`.
- A command whose text only mentions a blocked command (in a commit message, a `grep` pattern or a heredoc) can be blocked too.
- Hooks are registered for Claude Code only. Copilot CLI gets the skills and the instructions, not the guards.
- Tested on Linux, WSL2 and macOS (bash 3.2 and its awk). The sandbox of the `strict` profile has been used on WSL2 only. Windows without WSL is not supported.
