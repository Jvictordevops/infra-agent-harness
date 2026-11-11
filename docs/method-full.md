# Work method: full

This is the **full** method. Enable it with `method=full` in the consumer repo's `.harness.conf` (or `IAH_METHOD=full`).
The light method is the default and lives in [method.md](method.md).
In `light`, `check-work` reports the numbering rules (§7, except missing and duplicate ids) and the README length limit as warnings; in `full`, as errors.

> Normative rules only. Tooling: `bin/new-work` creates, `bin/check-work` validates (the git `pre-commit` hook runs it on staged works).
> File and folder names, and the section titles of records, follow the repo language (`language=` in `.harness.conf`, default `en`; words in `locale/<lang>.sh`). The language of the content is your choice.

## 1. Layout

Two separate things: the **harness** (this repo: `bin/`, `hooks/`, `skills/`, `templates/`, `locale/`) and the **consumer repo** that holds your works.

```
<consumer-repo>/
├── .harness.conf        # language=<code>, method=light|full, modules=…, denylist=<path>
├── GLOBAL.md            # always-loaded instructions (from templates/GLOBAL.md; keep it short, ~1,000 tokens; linked from ~/.claude/CLAUDE.md and ~/.copilot/copilot-instructions.md by bin/link-harness)
├── AGENTS.md, CLAUDE.md # 3-line pointers to GLOBAL.md (avoid double loading; from templates/root-pointer.md)
├── contexts/<name>/     # stack, accounts, decisions.md, lessons.md, patterns.md (append-only logs)
├── instructions/        # optional: per-technology conventions (applyTo)
├── docs/                # tool-specific notes (loaded on demand)
└── work/<context>/<id>/ # works
```

- `<context>` is `global` or any folder `<name>` that has `contexts/<name>/` in the consumer repo (folders starting with `_` are templates, not contexts).
- The harness provides `bin/` (`new-work`, `check-work`, `link-harness`, `ro`, `doctor`, `denylist-scan`, `render-template`, git hooks in `bin/hooks/`), `hooks/` (agent hooks), `skills/` and `templates/` (`README.md`, `record.md`, `decision.md`, `roadmap.md`, `training-unit.md`). The consumer repo points its git hooks at the harness: `git config core.hooksPath <harness>/bin/hooks`.

## 2. Work types

| `type` | Meaning | Done when |
|---|---|---|
| `prj` | Project, migration | Delivered |
| `inc` | Troubleshooting / incident | Root cause + fix (or accepted) |
| `inv` | Investigation, analysis, comparison | Recommendation given |
| `poc` | Proof of concept / experiment | Go/no-go verdict |

- The type lives **only** in the frontmatter and may change. A change is documented with a record `…type-change.done.md` and appended to `type_history`.
- A technical decision is **not** a work type: it is a record (`…decision-<x>.done.md`), promoted to `contexts/<name>/decisions.md` if it applies to other works.

## 3. Naming

| Thing | Pattern | Example |
|---|---|---|
| Work folder (= `id`) | `YYYY-MM-DD.<slug>` (opening date) | `2026-09-09.queue-autoscaling` |
| Record | `RECORD/YYYY-MM-DD.<slug>.<WIP\|done>.md` | `2026-09-24.scaling-metric-diluted.done.md` |
| Roadmap revision | `ROADMAP/YYYY-MM-DD.md` | `ROADMAP/2026-10-08.md` |
| Evidence | `evidence/YYYY-MM-DD.<slug>/` | `evidence/2026-10-07.cluster-prod/` |
| Training unit | `training/<slug>.md` | `training/gateway-api-inference.md` |

- `slug`: kebab-case `[a-z0-9-]`, up to 5 words, no date, no version, no dots.
- Ticket ids never go in names → frontmatter `tickets:`.
- **Forbidden** (outside `evidence/` and `.tmp/`): `-v2`/`-vN`, `-final`, `-definitivo`, `ESTADO-*`, `RESUMEN-*`, `backup-*` (rejected by `check-work`), non-ISO dates, spaces, accents.

## 4. Anatomy of a work (same for all types)

```
<id>/
├── README.md     # the ONLY rewritable doc (besides training units); entry point
├── LESSONS.md    # optional: traps to read before touching anything
├── RECORD/       # append-only
├── ROADMAP/      # revisions
├── evidence/     # raw data backing records (immutable; never versioned: kept locally, see §11)
├── scripts/      # optional
├── training/     # optional: training units, one rewritable file per unit (versioned)
├── .claude/      # optional: per-work local tool settings, never versioned
└── .tmp/         # disposable, never referenced, never versioned
```

**Hard rule:** the work root contains only `README.md`, `LESSONS.md` and the folders above. The plan is the ROADMAP (there is no `PLAN.md`).

**`training/` (optional):** study material derived from the work's tasks.
- One file per unit, `training/<slug>.md` (slug rules of §3; no ids or dates in the name), with `**Task:** <id> <short name>` right under the title.
- **Start from `templates/training-unit.md`**: it fixes the structure (a case followed unit after unit, the step-by-step path, concepts explained in four parts, readings, exercise, questions, what can be ratified).
- Units are **rewritable**: they improve with the reader's questions.
- A unit never holds decisions or findings. What comes out of doing it (what gets ratified, what failed) goes to a new record.
- The ROADMAP task links its unit, and the README `Map` lists it.
- A `training/README.md` is optional: the index of the training (table of units, order, status and links to the records that agreed it). It is rewritable and is **not a unit**: the unit rules (name, `**Task:**` line, template sections) do not apply to it.

**No `prompts/`:** prompts for another agent are pasted in the chat as a code block, never saved to files. Existing `prompts/` folders are legacy and kept as is (warning only); adding files to them is an error.

## 5. `README.md` (up to 150 lines)

Frontmatter (all keys mandatory except `numbering`; extra keys such as `accounts:` allowed):

```yaml
---
id: 2026-09-09.queue-autoscaling    # == folder name
type: prj                           # prj|inc|inv|poc
type_history: [inc@2026-09-09, prj@2026-09-15]
company: my-context                 # == parent folder (the <context>; the key keeps this name)
status: active                      # active|paused|closed|dropped
tickets: [PROJ-123]                 # list of ticket ids, may be []
repos: [backend]                    # list, may be []
updated: 2026-10-08
numbering: legacy                   # optional: only in open works not yet migrated to §7 (see 7.4)
---
```

Then a 3-line rules header (from the template) and these sections, in order:

| Section | Content |
|---|---|
| `## Goal` | 2-3 lines: what "done" means for the whole work |
| `## Objectives` | Table `Id · Objective · Done when` (words from the locale): objectives `**N**` and, if any, sub-objectives `**N.M**` (§7.1). "Done when" lists the success criteria, each one numbered with the id of its verification task |
| `## Status` | One sentence, rewritten every session |
| `## In progress` | What was left half-done last session (read first): the tasks marked `[~]` in the current ROADMAP revision (§7.2) |
| `## Next steps` | 3-5 task ids from the current ROADMAP revision, each with its short name |
| `## Constraints` | Restrictions / do-not-touch |
| `## Map` | Table: file/record → what it is (only relevant ones) |

Extra sections by type (at the end):

| Type | Sections |
|---|---|
| `inc` | `Symptom` · `Hypotheses` (hypothesis · open/discarded/confirmed · record) · `Root cause` + `Confidence:` |
| `inv` | `Question` · `Evaluation criteria` · `Recommendation` + `Confidence:` |
| `poc` | `Hypothesis to validate` · `Go/no-go criteria` · `Verdict` |
| `prj` | `Scope` (in/out) |

## 6. Records (`RECORD/`)

- **Append-only.** A committed record is never edited or deleted. The only allowed rename is `<name>.WIP.md → <name>.done.md`. Appending at the end is tolerated (warning); anything else → write a new record that links the old one.
- **Banner lines.** A committed record may receive only banner lines under its title, so a reader landing on it knows it is outdated:
  - `> **Corrected by:** [<new>](<new>.done.md)` (or `Superseded by`) when a new record corrects or supersedes it;
  - `> **Ids renumbered in:** [<renumbering>](<renumbering>.done.md)` when the work's ids changed (§7.3).

  `check-work` accepts only those lines (each must point to an existing record); any other edit is an error. The banner words follow the configured language.
- **Task line.** A new record that belongs to a task carries, right under its title (and banners), `**Task:** <id> <short name>` (e.g. `**Task:** 1.3.5 Validate autoscaling on the inference service`). Ids never go in file names.
- One record per relevant finding, decision or session outcome. The title **asserts** something ("Scaling metric is diluted", not "Scaling analysis"). Ids in the text go with their short name at their first mention.
- Fixed skeleton (`templates/record.md`; headings shown in English, they follow the configured language):

```markdown
# <Assertive title>
**Task:** <id> <short name>     ← if it belongs to a task
**Context:** 1-3 lines + link to previous record.
## Question / Problem
## Facts                ← verified only, key data written inline, linked to evidence/
## Proposal / Result
## Discarded            ← and why
## Cost / Risk
## Open                 ← mandatory; feeds Next steps / ROADMAP
Confidence: high|medium|low
```

- **Decision records** `…decision-<x>.done.md` use `templates/decision.md`: `**Task:**` · `Context` · `Options` · `Decision` · `Consequences` · `Open` · `Confidence`. Options are named in bold (`**Own load balancer** → chosen/rejected: reason`), never lettered or numbered.
- **State of play** `…state-of-play.done.md`: periodic recount, every 1-2 weeks in long works.
- **Self-contained facts.** `## Facts` carries the key data itself (figures, the relevant log line, exact config, command + result); the link to `evidence/` is backup, not a substitute. Evidence may be archived or removed when the work closes (§11), so a record must still stand without it.

## 7. `ROADMAP/` and numbering

### 7.1 One numbering: objectives, sub-objectives, tasks

- Every work numbers its **objectives** `1, 2, 3…` in README `## Objectives`. Every ROADMAP **task** belongs to one objective.
- **Up to three levels:** objective `N` → optional sub-objective `N.M` → task. Four or more levels are forbidden.
- **Depth is fixed per objective.** If an objective has sub-objectives, all its tasks hang from one of them (`N.M.K`); if it has none, its tasks are `N.M`. Within one objective an id never means two different things. Sub-objectives are declared in README `## Objectives`, like objectives.
- **Stable ids.** Never reused, never renumbered. A task that moves to another objective or sub-objective is closed (`moved to 1.3.4`) and gets a new id there; a task that has to be split is closed (`split into 1.3.7, 1.3.8`). New tasks continue the sequence of their parent.
- **Every id has a stable short name.** ROADMAP item = `**1.3.4** <short name>. <1-2 lines> → [record]`. In prose (README, records, commits, conversation) the id goes with its short name at its first mention: `1.3.4 (keys script)`. Never `#1.3.4`.
- **Success criteria** belong to the objective (README `## Objectives`, "Done when") and are numbered with the id of their **verification task** (criterion `1.5.3` = task `1.5.3`). There is no separate criteria numbering.
- **Decisions are tasks** ("Decide …"); the decision record carries the task line. Options are named, never lettered or numbered.
- **No other identifier family**: no `#n`, no letters (`A`, `T3`, `G2`), no "decision n of m", no numbered criteria, no batch/phase/slice codes. Groupings that are not sub-objectives are plain words or `###` headings, never ids. Numbered lists in a conversation are only for one-off procedural steps and are never used to refer to tasks or decisions.

### 7.2 Revisions

- Current revision = file with the greatest date. Old revisions are never edited except to strike items that landed late.
- **When to cut a new revision:** only when the plan changes (new objective or sub-objective, re-prioritisation, renumbering) and, in long works, at least every 1-2 weeks. Otherwise the current revision is edited in place (strike what lands, add tasks). Day-to-day history lives in git. A new revision is created by **copying** the current one and reading the `Open` sections of the records written since.
- Sections, exactly: `What landed since <prev>` · `Carried` · `New` (with origin) · `Blocked` · `Dropped` (with reason) · `Risks` (optional). No variants (`Carried (new in …)`, `New in …`).
- Inside `Carried`/`New`/`Blocked`, tasks are grouped under `### N · <objective>` and, when the objective has sub-objectives, `#### N.M · <sub-objective>`.
- Every open item (`Carried`, `New`, `Blocked`) **must start with a bold task id** (`- **1.3.4** …`). **One item = one thing**: never group several tasks in one bullet. Never copy reasoning: 1-2 lines + link to the record that argues it.
- Done: `- ~~**1.3.4** <short name>…~~ → [record]`. Dropped: `- ~~**1.3.4** <short name>…~~ — <reason> → [record]`.
- **Three task states:** open, in progress, done.
  - In progress: `- **1.3.4** [~] <short name>. <1-2 lines> → [record]`. The marker goes right after the bold id, in `Carried`/`New` of the current revision. Several items may be `[~]` at once.
  - Done: struck, and the `[~]` is removed. Blocked items stay in `## Blocked`, without `[~]`.
  - **Rule:** when an agent **starts** a task it marks it `[~]` in the current revision and adds it (id + short name) to README `## In progress` immediately, before doing the work (not only at close). When finished: strike it (no `[~]`) and remove it from `In progress`. The in-progress state is thus committed with the work even if a session ends abruptly without `close-task`.
- README `Next steps` = next 3-5 task ids of the current revision, with their short name (no duplication).
- **Delegated task** (module `two-machine`): the architect marks it `[~]` and appends the executor marker, `- **N.M** [~] <short name>. <1-2 lines> ⇢ <executor word> → [brief]`. The word is `VOC_EXECUTOR` of the repo language (`executor` / `ejecutor`). After reviewing the executor's result record the architect strikes the item and removes the marker. See `modules/two-machine/README.md`.

### 7.3 Changing the numbering of an existing work

- It is a decision (`decision-renumbering`) with a **complete mapping table**: every old id and every other identifier family that appears in the work's records → new id.
- Old records stay as they are (they are the memory) and get the banner `> **Ids renumbered in:**` (§6). The README `Map` links the mapping record. The ROADMAP revision that renumbers uses only new ids.

### 7.4 Scope

- Numbering checks apply to works with `status: active` or `paused`. Works `closed` or `dropped` are history and are skipped.
- An open work not yet migrated carries `numbering: legacy` in its frontmatter: `check-work` only warns and lists it, without blocking the commit. The flag is removed by the work's `decision-renumbering`.

## 8. Global vs specific

| Information | Where | Lifecycle |
|---|---|---|
| How to work with AI, destructive-command guard, output style | `GLOBAL.md` | Rare |
| Tool-specific (routing, compaction…) | `docs/tools.md` | Rare |
| Stack, accounts, regions, tags, tracker | `contexts/<name>/AGENTS.md` | Platform changes |
| Per-technology conventions | `instructions/*.instructions.md` | Rare |
| Decisions affecting >1 work | `contexts/<name>/decisions.md` | Append-only, link to record |
| Reusable traps | `contexts/<name>/lessons.md` | Append-only, link to record |
| State and plan of a work | `work/…/README.md` + `ROADMAP/` | Every session |
| Reasoning, findings, local decisions | `work/…/RECORD/` | Append-only |
| Raw data | `work/…/evidence/` | Immutable; never versioned (see §11) |

**Tracker line.** If the context uses a ticket tracker, its card has one line in this exact shape, which the skills `load-project`, `close-task` and `new-project` look for:

```
- **Tracker:** <name> — <how to read it: MCP server/tool names or CLI> (<optional pointer to a file with details>)
```

Example: `- **Tracker:** Jira — MCP server "atlassian", tools getJiraIssue and searchJiraIssuesUsingJql (details: tracker.md)`. Without the line, skills do not touch tickets. They read tickets only; a comment is posted only after you confirm its exact text.

**Promotion:** when closing a work or a decision record, if it would apply to *another* work → one line in `contexts/<name>/decisions.md|lessons.md` linking the record.

## 9. Lifecycle

1. **Open** — skill `new-project` → `bin/new-work <context> <type> <slug>`; fill Goal/Objectives/Constraints. Works are versioned automatically (keep `evidence/` and `.claude/` out of git with a `.gitignore`).
2. **Load** — skill `load-project`: README → `LESSONS.md` → current ROADMAP revision → `contexts/<name>/AGENTS.md` (suggested via skill `init-context`). Records only via README links.
3. **During** — starting a task → mark it `[~]` in the current ROADMAP revision and add it to README `## In progress` before working on it (§7.2). Relevant finding/decision → new record `.WIP` → `.done`. Finished task → strike it (no `[~]`) and remove it from `In progress`.
4. **Save / close session** — skill `close-task`: rewrite Status / In progress / Next steps / `updated:` (task ids with short name; half-done tasks keep `[~]`); new records if needed; run `bin/check-work <work>`.
5. **Close work** — `status: closed`, final record, promotion to `contexts/<name>/`. If the work kept evidence: check that the records are self-contained (§6) before discarding it (§11).

## 10. Enforcement

All of it lives in the harness; the consumer repo enables it with `git config core.hooksPath <harness>/bin/hooks`.

- `bin/check-work [--staged | --changed] [work-dir…]` — `--staged` validates the index against HEAD (pre-commit); `--changed` validates the working tree against HEAD without `git add` (used by `close-task` before committing); `work-dir…` limits the works checked. Repository: `$IAH_REPO`, else the git repo of the current directory.
  - Checks: layout, names, frontmatter, README length, record/roadmap names, append-only on staged records (only the banner lines of §6, pointing to existing records), no new files under `prompts/`.
  - Numbering (§7, works `active`/`paused` without `numbering: legacy`): README `## Objectives` with `**N**`/`**N.M**` ids; every open item of the current revision with a valid task id whose parent is declared and whose depth matches its objective; no duplicate ids; no id that was struck or dropped in an earlier revision reappearing open; README `Next steps` ids present in the current revision; only the standard `##` sections.
  - Warnings: works with `numbering: legacy`; new records without the `**Task:**` line; new decision records without `## Open` or `Confidence:`; in the current ROADMAP revision, a `[~]` item (§7.2) whose id is not listed in README `## In progress`, and a struck item or a `Blocked` item that carries `[~]`.
  - Exit code is non-zero on any error. With `method=light` the numbering rules (except missing and duplicate ids) and the README length limit are warnings instead.
- `bin/hooks/prepare-commit-msg` runs on every commit and appends git trailers `Task: <work-slug> <id> <short name>` (`work-slug` = work folder id without the `YYYY-MM-DD.` prefix; the trailer word follows the configured language) for each task that the staged changes strike or mark `[~]` in a ROADMAP, plus the `**Task:**` line of records added (or renamed WIP→done) in `RECORD/` and of new training units. It is idempotent and never blocks the commit. Manual commit messages also mention task id + short name when the commit belongs to a task.
- `bin/hooks/commit-msg` is off unless `.harness.conf` has `ai_attribution=block` (`IAH_AI_ATTRIBUTION` overrides); then it blocks AI attribution (tool `Co-authored-by` trailers, "Generated with", session trailers, model names, an agent as author or committer); naming a product or a path is allowed. Test: `tests/commit-msg.sh`.
- `bin/hooks/pre-commit` runs `gitleaks` on staged content (blocks if it is not installed), then `check-work --staged`.
- `bin/hooks/post-merge` and `post-rewrite` re-run `bin/link-harness` after a pull or rebase.
- `bin/doctor` checks the setup of a machine (harness, hooks path, tools) and prints one summary; `bin/denylist-scan` fails if tracked files contain identifying data (use it before publishing a repo).
- `git commit --no-verify` only for one-off migrations, justified in the commit message.

## 11. Optional modules

Two optional modules, enabled per work repo with `modules=` in `.harness.conf` (`link-harness` and `doctor` read it):

- `two-machine`: architect/executor roles between two machines or sessions, briefs and result records, delegated tasks, read-only executors over SSH. See `modules/two-machine/README.md` (skill `role`).
- `evidence`: evidence store and clipboard shared between your machines, encrypted archives on close. See `modules/evidence/README.md`.

