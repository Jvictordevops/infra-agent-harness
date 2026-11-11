# Security policy

## What this project protects, and what it does not

The harness puts guards in front of an AI agent that works on real infrastructure. They stop **mistakes**: a destructive command, a credential file read by accident, a cloud call outside the read-only executor. They do not stop an **adversary**: an agent that is set on going around them can write a script, build a path in a variable or use a tool that is not on a list.

Read [docs/threat-model.md](docs/threat-model.md) before you rely on it. The short version:

- The real barrier is a **read-only credential** for the agent, and the sandbox of the `strict` profile.
- The guards, the `deny` rules and `bin/ro` are layers on top of it, not a replacement.

## Reporting a vulnerability

Report it in private, not in a public issue:

- Use **Report a vulnerability** in the Security tab of this repository (GitHub private vulnerability reporting).

Please include:

- the version or commit, your system (Linux, macOS, WSL) and the security profile (`bin/security-profile show`);
- the exact command or tool call, what you expected and what happened;
- whether it needs the agent to act on purpose, or happens by mistake in normal work.

This is a personal project with no paid support: answers are best effort. Fixes ship in the next release and are listed in [CHANGELOG.md](CHANGELOG.md).

## What counts as a vulnerability

- A guard that lets through something its documentation says it blocks (for example a command in `packs/<name>/destructive.rules`, or a file in a `credential-files` list given to a reader).
- `bin/ro` running a command that writes, reading a file outside `RO_ROOTS`, or showing a secret.
- A guard that fails open: it ends with an error and the command runs.
- `bin/link-harness` or `bin/doctor` changing or removing something they say they leave alone.
- A secret or a private value printed in a log, the decision log or the CI output.

## What does not count

These are known limits, written down in the threat model:

- Going around a guard on purpose: a script written on the fly, a path in a variable, a tool that is not on the lists.
- A destructive command or a secret-printing command that is not on a list. Tell us in a normal issue or a pull request: the lists grow that way.
- A false positive (a command blocked because its text mentions a blocked one). It is a bug, not a vulnerability: open an issue.

## Supported versions

Only the latest release gets fixes.
