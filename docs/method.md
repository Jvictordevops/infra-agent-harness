# Work method (light)

> The default method: enough structure for an agent to resume any work cold and for you to trace every decision.
> The full method ([method-full.md](method-full.md)) adds strict numbering, revision rules and README limits; switch with `method=full` in `.harness.conf` (or `IAH_METHOD=full`).
> Tooling: `bin/new-work` creates a work, `bin/check-work` validates it (the pre-commit hook runs it on staged works).

## 1. Works

Every piece of work (project, incident, investigation, proof of concept) is a folder:

```
work/<context>/<YYYY-MM-DD.slug>/
├── README.md     # the only rewritable doc; the entry point
├── LESSONS.md    # optional: traps to read before touching anything
├── RECORD/       # append-only: one file per finding or decision
├── ROADMAP/      # the plan, one file per revision
├── evidence/     # raw data backing the records; never versioned
├── scripts/      # optional
├── training/     # optional: study units derived from the work
└── .tmp/         # disposable; never referenced, never versioned
```

- `<context>` is `global` or a folder that has `contexts/<context>/` (a company, client, team or platform: its stack, accounts and conventions).
- Folder name: opening date + kebab-case slug of up to 5 words (`2026-09-09.queue-autoscaling`). No versions, no `-final`, no spaces or accents.
- Nothing else in the work root: the plan is the ROADMAP, not a `PLAN.md`.
- Prompts for another agent go in the chat, never in files.
- Type (`prj`, `inc`, `inv`, `poc`) lives in the README frontmatter and may change.

## 2. README

Frontmatter: `id` (= folder name), `type`, `type_history`, `company` (= context folder), `status` (`active|paused|closed|dropped`), `tickets`, `repos`, `updated`. Then these sections, in order:

| Section | Content |
|---|---|
| `## Goal` | 2-3 lines: what "done" means |
| `## Objectives` | Table `Id · Objective · Done when`, objectives numbered `1, 2, 3…` |
| `## Status` | One sentence, rewritten every session |
| `## In progress` | Tasks left half-done (read first) |
| `## Next steps` | 3-5 tasks from the ROADMAP, id + short name |
| `## Constraints` | Restrictions, do-not-touch |
| `## Map` | Table: file or record → what it is |

Keep it short: it is what an agent reads first, every session.

## 3. Records

- `RECORD/YYYY-MM-DD.<slug>.<WIP|done>.md`, one per relevant finding, decision or session outcome, from `templates/record.md` or `templates/decision.md`.
- **Append-only.** A committed record is never edited or deleted; the only rename is `.WIP.md → .done.md`. To correct one, write a new record and add a banner under the old title (`> **Corrected by:** [new](<new>.done.md)`).
- The title asserts something ("Queue metric is diluted", not "Queue analysis"). `## Facts` carries the key data inline (figures, the log line, the command and its result); `evidence/` is the backup, not a substitute.
- Every record ends with `## Open` and `Confidence: high|medium|low`.
- Decisions name their options in bold (`**Own load balancer**`), never "option A" or "option 1".
- A record that belongs to a task carries `**Task:** <id> <short name>` under its title.

Section words follow the repository language (`language=` in `.harness.conf`; see `locale/`).

## 4. ROADMAP and ids

- The plan is `ROADMAP/YYYY-MM-DD.md`; the current revision is the newest file. Edit it in place; copy it to a new date only when the plan changes.
- Sections: `What landed since` · `Carried` · `New` · `Blocked` · `Dropped` · `Risks` (optional).
- Tasks hang from objectives: `1.1`, `1.2`… (and `1.2.1` under a sub-objective, three levels at most). Ids are stable: never reused, never renumbered. Every id has a short name and goes with it in prose: `1.3 (key script)`, never `#3`.
- One item = one task: `- **1.3** <short name>. <1-2 lines> → [record]`.
- **States:** open; in progress `- **1.3** [~] …` (mark it, and list it in README `In progress`, *before* starting); done `- ~~**1.3** …~~ → [record]` (struck, never deleted).

## 5. Lifecycle

1. **Open:** skill `new-project` (runs `bin/new-work <context> <type> <slug>`); fill Goal, Objectives, Constraints.
2. **Load:** skill `load-project` reads README → `LESSONS.md` → current ROADMAP. Records only when the README links them and the task needs them.
3. **During:** mark the task `[~]`; each finding or decision is a new record; strike the task when done.
4. **Save:** skill `close-task` rewrites Status, In progress, Next steps and `updated:`, and runs `bin/check-work`.
5. **Close:** `status: closed` and a final record; promote what applies elsewhere to `contexts/<context>/decisions.md` or `lessons.md` (append-only, linking the record).

## 6. What `check-work` enforces in light

- **Errors:** layout and names, frontmatter, record and revision names, append-only records (only `WIP → done` renames and banners pointing to existing records), new files under `prompts/`, ROADMAP open items without an id, duplicate ids.
- **Warnings** (errors in full): the rest of the numbering rules (declared objectives, depth per objective, reused ids, `Next steps` present in the current revision, standard sections only) and README length over 150 lines; plus new records without a `**Task:**` line and `[~]` items missing from README `In progress`.

Switch to `full` when several people or agents share works and you want the numbering to block commits instead of warning.
