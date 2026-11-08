---
name: close-task
description: "Use when the user wants to save or close a session: \"save progress\", \"let's wrap up\", \"note this down\", \"document what we did\", end of session. Persists progress, findings and decisions to the work README and RECORD/ (or the context knowledge base) and validates with check-work. Micro mode (default) or --full (Claude Code only)."
---

The repository that holds your works is `$IAH_REPO`, else the current git repository. The harness commands (`check-work`, `render-template`) are on the PATH through the plugin `bin/`.

## Usage

- `/close-task` — micro mode (default)
- `/close-task --full` — full session analysis with a small model (Claude Code only)
- `/close-task --dry-run` — show what would be saved, write nothing

## Micro mode (default)

Look through the current session for signals:

| Signal | Type |
|---|---|
| "We decided…", "we chose…", "let's go with…" | `decision` |
| Error solved, fix applied, root cause found | `incident` |
| Something that worked and can be repeated | `pattern` |
| Relevant finding inside a work (verified fact, cause, measure) | `finding` |
| "I like it this way", "I prefer…", "don't do…" | `feedback` |
| Progress on an open work | `progress` |

No signals → reply "Nothing to persist; session closed cleanly."

## Where each type goes

A work is a folder `work/<context>/<id>/` with a `README.md`. Record skeletons come from `render-template record` and `render-template decision`: they are in the repository language (`.harness.conf`), so keep their field names and headings as generated (`<Task>`, `<Open>`, `<Confidence>` below stand for them).

- `decision` → a new record in the work's `RECORD/`, `YYYY-MM-DD.decision-<slug>.done.md`, from `render-template decision TITLE="<title>"`: the `**<Task>:** <id> <short name>` line (decisions are tasks, "Decide …") · context · options (each with a bold name and `→ chosen/rejected: reason`, never letters or numbers) · decision · consequences · `## <Open>` · `<Confidence>:`. **Only if it applies to other works**, also one line in `contexts/<context>/decisions.md` linking the record. Without a work → append to `contexts/<context>/decisions.md`.
- `incident` → create `contexts/<context>/POSTMORTEM-YYYY-MM-DD-<slug>.md`.
- `pattern` → append to `contexts/<context>/patterns.md`.
- `feedback` → the memory of the agent tool you run in. Never in the repository.
- `finding` → one new record per finding in the work's `RECORD/`: `YYYY-MM-DD.<slug>.done.md` (or `.WIP.md` if still open), from `render-template record TITLE="<title that states something>"`. Keep the `**<Task>:**` line only if it belongs to a ROADMAP task; facts only if verified, linked to `evidence/`; `## <Open>` is mandatory.
- `progress` → in the work `README.md`, update `Status`, `In progress` and `Next steps` (the next 3-5 open items of the current `ROADMAP/` revision, as `- **<id>** <short name>`) and the frontmatter `updated:`. In the current ROADMAP, strike what is done, without `[~]` (`- ~~**1.3.4** …~~ → [record]`), and remove it from `In progress`; unfinished tasks keep `[~]` after their id and stay in `In progress`. New tasks get the next id of their objective (never reuse or renumber). Never `#id`: in prose, id + short name at the first mention.

Knowledge base entries (`decisions.md`, `patterns.md`) use this shape:

```markdown
## YYYY-MM-DD — <short title> [<tool>]

- **Type:** decision | incident | pattern
- **Tags:** terraform, eks, cost, security, …
- **Summary:** 80-120 words: what was decided/solved/learnt, why, and the actionable consequence.
```

## Which context

1. The work loaded in this session (`company:` of its README), or the one given to `/init-context`.
2. Else infer it from the current directory (a context card `contexts/<name>/AGENTS.md` that lists the repository).
3. If ambiguous, ask: "Which context does this belong to: <list of contexts/*/>, or global?"

## --full mode (Claude Code only)

Run a small model on the session (`claude -p --model haiku`) to find every signal, then write each entry as above.

## Tickets (only if the README has a non-empty `tickets:`)

After persisting a `progress` or `finding`, draft a short comment (bullets: what was done and its effect). Show the exact text and ask "Shall I post it on <ticket>?". Only with an OK, post it with the tracker integration the context card names. Never change state, fields, owner or iteration. If the integration fails, say so and close anyway.

## Final validation (mandatory if a work was written)

Before any commit, on every work you touched:

```bash
check-work --changed work/<context>/<id>
check-work work/<context>/<id>
```

- `--changed` also compares the working tree with HEAD (no `git add` needed): append-only `RECORD/`, banners and hints for new records. The second run checks the whole work (structure, frontmatter, numbering).
- `ERROR` → fix it (record name, file in the work root, frontmatter, README over 150 lines, invalid or undeclared task ids) and repeat until exit 0. Never edit a committed record: write a new one that links it; the only edits allowed are the banners under the title that `check-work` names.
- `WARN` → mention it in the final summary (`numbering: legacy` = work not migrated; the task-line hint is ignored when the record belongs to no task; `[~]` warnings ask to align README `In progress` with the `[~]` items).
