---
name: parallel-audit
description: "Audit IaC across several repositories or contexts in parallel with small-model sub-agents. Cuts tokens roughly 40-55% against a sequential pass. Use to audit Terraform, Kubernetes or security policies in several repositories at once."
---

## When to use

- Auditing more than one repository or more than one context at a time.
- The task would take more than ~10K tokens sequentially.
- The repositories are independent of each other.

## How

Start one sub-agent on a small model per repository or per context. Each one:
1. Explores its target (Terraform, Helm charts, IAM policies, …).
2. Writes a structured report: critical findings, warnings, compliance with naming and tags.
3. Returns only that report to the parent agent.

The parent agent (a larger model if the consolidation is complex) merges the reports into one.

Standards come from each context (`contexts/<name>/AGENTS.md` and the files it lists, see `init-context`), never from memory.

## Prompt template

```
Audit [SCOPE] in parallel:
- Repositories: [list]
- What to check: [terraform naming/tags | security policies | helm values | cost]
- Criteria: [context standards: mandatory tags, naming conventions, …]

One small-model sub-agent per repository. Each reports:
1. Critical findings (blocking)
2. Warnings (improvable)
3. Compliance with the standards (%)
```

## Rough savings

| Scenario | Sequential | Parallel | Saving |
|---|---|---|---|
| 3 Terraform repositories | ~30K tokens | ~17K tokens | ~45% |
| Cost review of 7 AWS accounts | ~50K tokens | ~22K tokens | ~55% |
| Multi-directory PR review | varies | varies | 30-60% |

## Do not use when

- The repositories depend on each other (the output of one changes the analysis of another).
- The task is under ~5K tokens (the overhead does not pay off).
