---
name: parallel-review
description: "Review PRs or large changes in parallel, by directory or module, with small-model sub-agents. Use when a PR touches several independent areas (Terraform + Helm + CI) or the diff is over 500 lines."
---

## When to use

- A PR with changes in several independent directories.
- A diff over 500 lines.
- Changes in different areas (Terraform + Helm + CI workflows).

## How

Start one sub-agent on a small model per area or directory. Each one:
1. Reviews the changes of its area.
2. Checks them against the context standards (tags, naming, security) from `contexts/<name>/`.
3. Reports: approved / blocking / warning, with exact lines.

The parent agent merges the reports and gives the final verdict.

## Prompt template

```
Review the PR in parallel by area:
- Area 1: [path] — check [naming, tags, security, logic]
- Area 2: [path] — check [what]
- Area 3: [path] — check [what]

Criteria: [context standards: mandatory tags, naming conventions]
One small-model sub-agent per area. Each reports:
1. Blocking issues (with exact line)
2. Warnings
3. Verdict: APPROVED | CHANGES REQUESTED
```

## Do not use when

- The PR is small (<100 lines): an inline review is faster.
- The areas depend on each other: review sequentially.
