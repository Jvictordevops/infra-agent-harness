---
name: load-project
description: "Use when the user resumes or names a work: \"load project X\", \"let's continue with X\", \"back to X\", \"how was X going?\". Loads the work README, LESSONS.md and the current ROADMAP revision. Usage: /load-project [name]"
argument-hint: "[work name]"
---

Works live in `work/<context>/<YYYY-MM-DD.slug>/` of the repository that holds them (`$IAH_REPO`, else the current git repository). The name comes from `$ARGUMENTS` or, if empty, from the user's message (a keyword of the work).

Find the work: glob `work/*/*<name>*/README.md`.
If several match, list them and ask which one. If none and no name was given, list `work/*/*/` (names + `status:`) and ask. If none matches the name, offer to create it with `new-project`.

Read in order (skip what does not exist):
1. `README.md` — main context (required).
2. `LESSONS.md` — read it entirely before touching anything.
3. `ROADMAP/<latest>.md` — the revision with the greatest date is the current one.

Do NOT read `RECORD/`, `evidence/`, `scripts/` or old ROADMAP revisions unless the README links them and the task needs them. Instead, list by name only the WIP records: glob `RECORD/*.WIP.md` (names, no content).

Then confirm with:
- Goal and current status.
- Objectives: id + name from `## Objectives` (`1 · …`, sub-objectives `1.1 · …` if any), and which success criteria are still open.
- Context: the `company:` field of the frontmatter. Suggest `/init-context <name>` (do not run it yourself; skip it for `global`).
- Key resources (repos, accounts, services).
- In progress: items marked `[~]` in the current ROADMAP revision (id + short name), first, and propose to continue them. Warn about any mismatch between README `## In progress` and the `[~]` items.
- Next tasks and blockers: `In progress` plus `Next steps`, each as id + short name (`1.3.4 key script`), checked against the current revision (open items of `Carried`/`New`; those under `Blocked` flagged as blocked). Never `#id`. Then the WIP records (names only).
- If the frontmatter has `numbering: legacy`, say so and show the ids as written.
- Tickets: if `tickets:` is not empty and the context card (`contexts/<name>/AGENTS.md`) has a `- **Tracker:** …` line (how to read it) you can use, show each ticket's name, state and open tasks, read-only. If you cannot reach it, say so and continue.
