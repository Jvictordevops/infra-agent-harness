---
id: {{ID}}
type: {{TYPE}}
type_history: [{{TYPE}}@{{DATE}}]
company: {{COMPANY}}
status: active
tickets: []
repos: []
updated: {{DATE}}
---
> **Rules:** this README is the only rewritable doc (besides `training/` units, if any); nothing else in the work root except `LESSONS.md`.
> `RECORD/` is append-only (`YYYY-MM-DD.<slug>.<WIP|done>.md`); plan lives in `ROADMAP/<date>.md`; raw data in `evidence/`, scratch in `.tmp/`.
> Standard: [STANDARD.md](../../../STANDARD.md) · ids: objectives `N` · tasks `N.M`/`N.M.K` with their short name (§7) · validate with `bin/check-work`.

# {{TITLE}}

## Goal

TODO: 2-3 lines. What "done" means.

## Objectives

| Id | {{VOC_OBJECTIVE}} | {{VOC_DONE_WHEN}} |
|---|---|---|
| **1** | TODO | **1.1** TODO (each criterion = id of its verification task) |

## Status

Just opened ({{DATE}}).

## In progress

- Nothing yet.

## Next steps

From [ROADMAP/{{DATE}}.md](ROADMAP/{{DATE}}.md):

- **1.1** TODO

## Constraints

- TODO: restrictions / do-not-touch.

## Map

| File | What |
|---|---|
| [ROADMAP/{{DATE}}.md](ROADMAP/{{DATE}}.md) | Current roadmap revision |
<!-- type:inc -->

## Symptom

TODO

## Hypotheses

| Hypothesis | State (open/discarded/confirmed) | Record |
|---|---|---|
| TODO | open | — |

## Root cause

TODO. {{VOC_CONFIDENCE}}: {{VOC_CONFIDENCE_LOW}}
<!-- /type:inc -->
<!-- type:inv -->

## Question

TODO

## Evaluation criteria

- TODO

## Recommendation

TODO. {{VOC_CONFIDENCE}}: {{VOC_CONFIDENCE_LOW}}
<!-- /type:inv -->
<!-- type:poc -->

## Hypothesis to validate

TODO

## Go/no-go criteria

- TODO

## Verdict

Pending.
<!-- /type:poc -->
<!-- type:prj -->

## Scope

- In: TODO
- Out: TODO
<!-- /type:prj -->
