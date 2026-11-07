---
name: digest
description: "Summarise long outputs (logs, plans, diffs) in under 500 tokens with a small-model sub-agent. Use when an output is over ~1000 lines or you want an executive summary before digging in."
---

When the user invokes this skill, or an output is too long to analyse comfortably:

1. Start a sub-agent on a small model (Claude Code: `claude -p --model haiku`, or a sub-agent with that model).
2. Give it the content with this instruction:
   > "Summarise the following output in at most 500 tokens. Extract: critical errors, relevant warnings, key metrics and the 3-5 most important lines. Format: short bullets."
3. Return only the summary to the parent agent, not the original content.

**Use it for:**
- Logs over 500 lines.
- `terraform plan` with many resources.
- Large PR diffs.
- `kubectl describe` output or cluster events.

**Do not use it for:**
- Outputs under 100 lines (summarise inline).
- When the user needs the full output to copy and paste.
