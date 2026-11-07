---
name: new-project
description: "Use when the user starts a new work: \"start a project / troubleshooting / investigation / poc on X\", \"open a new work\", \"new incident\". Creates work/<context>/<date>.<slug>/ with bin/new-work and fills Goal, Objectives, Constraints and the first tasks. Usage: /new-project [context] [type] [slug]"
argument-hint: "[context] [prj|inc|inv|poc] [slug]"
---

Creates a work folder in the repository that holds your works (`$IAH_REPO`, else the current git repository). Never create the folder or README by hand: the script produces the format. The harness is at `$IAH_HOME` (default `~/infra-agent-harness`).

## 1. Gather inputs (ask only what is missing, one question at a time)

| Input | Values | Infer from |
|---|---|---|
| `context` | `global` or a folder with `contexts/<name>/` | user words; the current directory if a context card (`contexts/<name>/AGENTS.md`) lists that repository |
| `type` | `prj` project/migration · `inc` troubleshooting/incident · `inv` investigation/comparison · `poc` proof of concept | user words |
| `slug` | kebab-case, ≤5 words, English, no date/version/ticket | propose one from the topic and confirm |
| Goal | 2-3 lines: what "done" means | ask if not stated |
| Objectives | 1-3 objectives, each with its success criteria; sub-objectives only if there are many tasks | ask if not stated: "What are the objectives and how will we know each is done?" |
| First tasks | 1-5 tasks with a short name, each under its objective | user words; else propose from the objectives and confirm |
| Constraints | restrictions / do-not-touch (optional) | user words; else leave TODO |
| Title, tickets, repos | optional | user words |

Before creating, check duplicates: glob `work/*/*<keyword>*/README.md`. If a matching active work exists, propose loading it (`load-project`) instead.

## 2. Create

```bash
"${IAH_HOME:-$HOME/infra-agent-harness}/bin/new-work" <context> <type> <slug> [--title "<human title>"] [--date YYYY-MM-DD]
```

If it fails, show the error and fix the input (do not bypass the script).

## 3. Fill the README and the ROADMAP (only these parts)

The files come in the repository language (`.harness.conf`); keep their headings and field names as generated.

In `work/<context>/<id>/README.md`:
- `## Goal` ← the Goal.
- `## Constraints` ← the constraints (or keep TODO).
- Frontmatter `repos:` if known (YAML list); `tickets:` only with ids the user gives.
- The type-specific section if the user already gave it (`Symptom` for `inc`, `Question` for `inv`, …).
- `## Objectives` ← replace the `| **1** | TODO | … |` row with one row per objective: `| **N** | <objective> | <criteria> |`. Each criterion is numbered with the id of its verification task (`**1.2** <short name>`); there is no separate criteria numbering. Add sub-objective rows `| **N.M** | … |` only for an objective with many tasks; then ALL its tasks are `N.M.K` (depth is fixed per objective), otherwise they are `N.M`.
- `## Next steps` ← the first tasks as `- **1.n** <short name>` (3-5, no explanation).

In `ROADMAP/<date>.md`: replace `- **1.1** TODO` with the first tasks as `- **1.n** <short name>. <1-2 lines>`, one `### N · <objective>` heading per objective (and `#### N.M · <sub-objective>` if any). Ids continue the sequence of their parent: `1.1`, `1.2`, `2.1`…

Ids are stable (never reused or renumbered) and every id keeps its short name. Never `#1`, never letters (`A`, `T3`) or other identifier families; groupings that are not sub-objectives are plain words or `###` headings.

Do not touch anything else and do not create other files in the work root.

## 4. Validate and report

```bash
"${IAH_HOME:-$HOME/infra-agent-harness}/bin/check-work" work/<context>/<id>
```

It must exit 0. Fix any `ERROR` in the README/ROADMAP and repeat.

Report in ≤5 lines: path, type, Goal, objectives (id + name), next task (id + short name). Suggest `/init-context <context>` if its context is needed (not for `global`).
