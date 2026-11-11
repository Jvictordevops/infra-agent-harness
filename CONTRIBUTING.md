# Contributing

Thanks for looking. This is a small project with one maintainer: short pull requests with a test get merged fastest.

## Before you start

- A bug, a false positive of a guard, or a destructive command that is missing from a pack: open an issue or go straight to a pull request.
- A way around a guard that happens by mistake in normal work: see [SECURITY.md](SECURITY.md) and report it in private.
- A bigger change (a new pack, a new guard, a change to the method): open an issue first, so we agree on the shape.

## Set up

You need `bash`, `git`, `jq`, `shellcheck` and `gitleaks`, plus `zstd`, `openssl` and `python3` for the tests of the evidence module. On Ubuntu: `sudo apt-get install git jq shellcheck zstd openssl python3`; `gitleaks` comes from its [releases page](https://github.com/gitleaks/gitleaks/releases).

```bash
git clone https://github.com/Jvictordevops/infra-agent-harness && cd infra-agent-harness
git config core.hooksPath .githooks     # contributor hook: denylist scan and gitleaks on every commit
tests/lint                              # shellcheck on every script
tests/run                               # every test, about two minutes (tests/run ro runs only the scripts with "ro" in their path)
```

To try your changes in Claude Code, load the plugin from your clone instead of GitHub. The session reads the clone in place, so an edit is live in the next session (the guards, in the next command):

```bash
claude plugin marketplace add /path/to/your/clone
claude plugin install infra-agent-harness@infra-agent-harness
```

Careful: with the plugin loaded from your clone, a guard you break is broken in your own session. The guards fail closed, so a broken guard may block every command until you fix the file with an editor.

## Rules for a change

- **A test for every change of behaviour.** A new rule gets a case that it blocks and a case that it lets through. Check that the new case fails without your change: a test that passes first time proves nothing.
- **Bash 3.2.** Everything runs on the stock bash of macOS: no `mapfile`, no associative arrays, no `${var,,}`, and an empty array is expanded as `${a[@]+"${a[@]}"}`. Use `tests/lib/portable.sh` in tests. The CI runs the macOS job on release tags.
- **English** in code, comments, messages and documentation. Short sentences.
- **No data that identifies a company or a person**: use `acme`, `example.com`, `123456789012`. `bin/denylist-scan` runs on every commit and in the CI; put your own names in `~/.config/infra-agent-harness/denylist.txt` (never committed).
- **Guards block on exit 2 and fail closed** (`hooks/lib/fail-closed.sh`). A guard never prints the secret or the file it protects.
- **Rules are data.** A platform rule goes in `packs/<name>/`, not in a guard or in `bin/ro`. Format and tests: [packs/README.md](packs/README.md).
- **Say what a guard does not stop.** If your change has a known limit, add it to [docs/threat-model.md](docs/threat-model.md).

## Adding a pack

Copy the files you need from an existing pack, follow [packs/README.md](packs/README.md), and add `packs/<name>/tests.sh`. Only packs that someone has used against the real platform are merged; say in the pull request how you tested it.

## Commits and pull requests

- One change per commit, with a message that says what changed and why: `ro: refuse --files0-from in wc and find`.
- Update `CHANGELOG.md` under `[Unreleased]` when users will notice the change.
- The CI must be green: lint, tests, gitleaks and the denylist scan. Pull requests from forks get no secrets, so they run the generic patterns only.

## Releases (maintainer)

1. Move `[Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` in `CHANGELOG.md` and set `version` in `.claude-plugin/plugin.json`.
2. Tag `vX.Y.Z` on `main` and push the tag: the CI checks that the three agree and runs the macOS tests.
3. Users get a new version only when `version` changes.

## License

By contributing you agree that your contribution is licensed under the [Apache License 2.0](LICENSE).
