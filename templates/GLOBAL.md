# GLOBAL.md — always-loaded agent instructions

<!-- Copy to the root of your work repository and edit (with templates/root-pointer.md as AGENTS.md and CLAUDE.md). bin/link-harness links it as ~/.claude/CLAUDE.md
     and ~/.copilot/copilot-instructions.md, so it is loaded in every session: keep it under ~1,000 tokens.
     Detail goes on demand: contexts/<name>/AGENTS.md (skill init-context) and the harness docs/. -->

## Profile

TODO: 2-5 lines. Your role and stack, and one line per context (company, client, team or platform): region, environments, what is special (mandatory tags, no Kubernetes…).
Detail on demand: `contexts/<name>/AGENTS.md` (or `/init-context <name>`).

## Work protocol (`work/<context>/<YYYY-MM-DD.slug>/`)

- Starting a work (project, incident, investigation, proof of concept) → skill `new-project` (runs `bin/new-work`). Never create the folder by hand.
- Resuming or naming a work ("let's continue with X") → skill `load-project`; then suggest `/init-context <name>` from `company:`.
- Saving progress or ending a session ("save", "we're done") → skill `close-task` (ends with `bin/check-work`).
- `README.md` is the only rewritable doc and the entry point. The work root holds only `README.md` and `LESSONS.md`.
- `RECORD/` only grows: one new record per finding or decision (`YYYY-MM-DD.<slug>.<WIP|done>.md`); never edit a committed one (only rename WIP→done and add a banner).
- **Ids** (files and conversation): objectives `N` in `## Objectives`; tasks `N.M`/`N.M.K` (three levels at most), always with their short name. No `#n`, no letters as ids. A task's record carries `**Task:** <id> <name>`.
- Plan in `ROADMAP/<date>.md`. Starting a task: `[~]` after its id in the current revision and in README `In progress`; when done, strike it and drop it from `In progress`. Raw data in `evidence/`, scratch in `.tmp/`.
- Do not read `RECORD/` or `evidence/` unless the README links them and the task needs them.
- Rules: the harness `docs/method.md` (or `docs/method-full.md` with `method=full`). Tool notes: `docs/tools.md`.

## How to work

- Results from another agent or session: 1) summarise what they say, 2) propose what you would do and why, 3) wait for confirmation before editing or committing. Design decisions are always asked.
- Prompts for another agent are pasted in the chat as a code block, never saved to files.
- Commits: no AI attribution (tool `Co-authored-by` trailers, model or agent names); author and email are the user's. `hooks/commit-msg` enforces it.

## Confidence gate

Every conclusion ends with `Confidence: high|medium|low`. If low, state the uncertainty and propose the cheapest check. Hiding uncertainty is forbidden.

## Defensive

Before destructive commands (`terraform apply/destroy`, `kubectl delete/drain`, `helm uninstall`, `aws … delete-*/terminate-*`, `git push --force`, `git reset --hard`, `aws s3 rb/rm` without `--dryrun`): ask for explicit confirmation and show the exact command.
- **Read-only executor** (when the user asks, or the cloud role is admin): `bin/ro mode on` and every cloud or cluster access through `bin/ro <command>`, sub-agents included; the `ro-guard` hook blocks the rest and only the user turns the mode off. `docs/tools.md`.

## Output

Bullets, not paragraphs. Command first, explanation after. Do not repeat context. If "brief" → 3-5 lines. Troubleshooting: hypothesis + check, no narrated thinking.
- **Options** (in chat and in files): each with a short bold name (`**Own load balancer**`), always cited by that name; never "A/B/C" or "option 1/2".
