# infra-agent-harness

A safe-by-default harness for AI coding agents that work on real infrastructure, with traceable work.

> Status: v0.1, in progress, not released. See [Status and roadmap](#status-and-roadmap).

## Why

- Platform engineers often run agents (Claude Code, Copilot CLI) with cloud roles that are administrators. One wrong command is enough.
- The harness puts guards in front of the agent: hooks that block destructive commands, deny and ask rules for writes, and a read-only mode where cloud and cluster access goes through an allow-listed wrapper.
- Every finding and decision is written down as an append-only record, so another session (or another person) can resume the work cold.
- The harness is a separate repo from your work: you clone it once and point your work repo at it.

## How it fits together

```mermaid
flowchart TB
  tools["Agent tools: Claude Code, Copilot CLI"]
  guards["Guards: agent hooks and git hooks"]
  method["Method: skills, check-work, templates, vocabulary"]
  mods["Optional modules: evidence, two-machine"]
  work["Your work repo: work, contexts, .harness.conf, GLOBAL.md"]
  tools --> guards
  guards --> method
  method --> mods
  method --> work
  mods --> work
```

- The harness (everything above the last box) lives in its own checkout. Your work repo only holds your data and a small config.
- Agent hooks guard what the agent runs. Git hooks guard what you commit.
- The method turns work into folders, records and a roadmap that a script can validate.
- Modules are off until you list them in `.harness.conf`.

Full detail and more diagrams: [docs/architecture.md](docs/architecture.md).

## What you get

- **Agent guards** (`hooks/`, registered in `~/.claude/settings.json` by `bin/link-harness`):
  - `ro-guard`: in read-only mode, blocks `aws`, `kubectl`, `helm`, `terraform`, `ssh`... outside `bin/ro`.
  - `block-destructive-platform`: blocks `terraform destroy`, `kubectl delete`, `aws ... delete-*`, `helm uninstall`...
  - `permissions.deny` / `permissions.ask` rules from `hooks/settings.base.json`.
  - Every block is appended to `~/.local/state/infra-agent-harness/hook-decisions.jsonl`.
- **Read-only executor** (`bin/ro`): one allow-listed command at a time, here or over SSH (`--host`).
- **Git hooks** (`bin/hooks/`): `commit-msg` (no AI attribution), `prepare-commit-msg` (adds the task trailer), `pre-commit` (gitleaks, then `bin/check-work --staged`), `post-merge` and `post-rewrite` (re-run `link-harness`).
- **Method** (`docs/method.md`, `docs/method-full.md`): `bin/new-work`, `bin/check-work`, `templates/`, English and Spanish vocabulary in `locale/`.
- **Skills** (`skills/`): `new-project`, `load-project`, `close-task`, `init-context`, `troubleshoot`, `digest`, `parallel-audit`, `parallel-review`, `role`.
- **Modules** (`modules/`): `evidence` (shared evidence store, encrypted archives), `two-machine` (architect and executor on two machines).
- **Tools**: `bin/doctor` (checks a machine, fixes what is safe), `bin/denylist-scan` (used by this repo's own contributor hook).

## Quick start

### As a Claude Code plugin (new, main path)

This repo is also its own plugin marketplace. The plugin packaging is new and lightly tested; the manual install below still works and is the fallback.

```bash
claude plugin marketplace add Jvictordevops/infra-agent-harness
claude plugin install infra-agent-harness@infra-agent-harness
```

- The plugin provides the skills and puts `bin/` (`check-work`, `new-work`, `ro`, `link-harness`...) on the PATH of the agent's Bash tool. A `SessionStart` hook keeps `~/.local/share/infra-agent-harness/current` pointing at the installed version.
- Then, once, from your work repo (see the manual steps 2 and 3 below to create it), run `link-harness` from a terminal: it merges the permissions and guard hooks, links `GLOBAL.md`, sets the repo's git hooks and handles Copilot. Plugin commands are only on the agent's PATH, so from a terminal use the plugin directory, for example `~/.local/share/infra-agent-harness/current/bin/link-harness` (the link exists after the first Claude Code session with the plugin).
- For development, add your clone instead: `claude plugin marketplace add <path to your clone>` (the plugin loads in place).

### Manual install

Needs `git`, `jq` and `gitleaks`. The commit hook blocks commits when `gitleaks` is missing.

```bash
# 1. Clone the harness (anywhere; the examples use ~/infra-agent-harness)
git clone <this-repo-url> ~/infra-agent-harness

# 2. Prepare your work repo (a separate git repo)
mkdir -p ~/my-work && cd ~/my-work && git init
cp ~/infra-agent-harness/templates/GLOBAL.md GLOBAL.md        # edit the TODO profile
cp ~/infra-agent-harness/templates/root-pointer.md AGENTS.md
cp ~/infra-agent-harness/templates/root-pointer.md CLAUDE.md
mkdir -p contexts work/global

# 3. Configure the harness for this repo
printf 'language=en\nmethod=light\n# modules=evidence,two-machine\n' > .harness.conf

# 4. Point git hooks at the harness
git config core.hooksPath ~/infra-agent-harness/bin/hooks

# 5. From the work repo: install skills, this GLOBAL.md and the hooks into ~/.claude and ~/.copilot
~/infra-agent-harness/bin/link-harness

# 6. Check the machine (from the work repo, so it sees its settings)
~/infra-agent-harness/bin/doctor
```

- Then start your first work from the agent: ask for a new project and the `new-project` skill runs `bin/new-work`.
- `link-harness` is idempotent and never removes your own settings. It reads the work repo of the current directory (or `$IAH_REPO`). The `post-merge` and `post-rewrite` hooks re-run it after each pull of the work repo; after pulling the harness, run it yourself.
- A plugin-based install is planned, not available yet.

## Configuration

| Setting | Where | Values | Default |
|---|---|---|---|
| `language` | `.harness.conf` | `en`, `es` (a `locale/<lang>.sh` file) | `en` |
| `method` | `.harness.conf` | `light`, `full` | `light` |
| `modules` | `.harness.conf` | comma list: `evidence`, `two-machine` | none |
| `IAH_LANG`, `IAH_METHOD`, `IAH_MODULES` | environment | same as above; they win over `.harness.conf` | unset |
| `IAH_REPO` | environment | path of the work repo | the git repo of the current directory |
| `evidence.conf` | `~/.config/infra-agent-harness/` | per-machine keys of the evidence module | see its README |

## Documentation

- [docs/architecture.md](docs/architecture.md): how the pieces fit, with diagrams and limits.
- [docs/method.md](docs/method.md): the light work method (default).
- [docs/method-full.md](docs/method-full.md): the full method (strict numbering).
- [docs/tools.md](docs/tools.md): tool notes, read-only executors, hook registration, decision log.
- [modules/evidence/README.md](modules/evidence/README.md): evidence store, archives, secrets backends.
- [modules/two-machine/README.md](modules/two-machine/README.md): architect and executor protocol, SSH.

## Status and roadmap

Version 0.1 is in progress and has not been released. What is described above exists in this repo, with tests under `tests/` and `modules/*/tests/`. Some parts are only lightly tested; the module READMEs say which.

Planned, not implemented (do not rely on any of these):

- Claude Code plugin and marketplace install.
- CI.
- Security profiles: permissive, standard, strict, isolated.
- Environments: corporate and personal.
- Provider packs.
- IT managed policy.
- `doctor --security`.
- Copilot hooks (today the hooks are registered for Claude Code only).
- Container isolation.

## License

Apache-2.0 is intended. There is no `LICENSE` file in the repo yet; it is coming.
