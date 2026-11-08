---
name: troubleshoot
description: "Hypothesis-first troubleshooting protocol with a mandatory confidence gate. Use for any infrastructure diagnosis: Kubernetes, EKS, Terraform, GitOps, AWS."
---

## Protocol

1. **Hypotheses first** — before reading logs or running commands, state the 2-3 most likely causes, ordered by probability.
2. **Tiered reading** — start with the cheapest source:
   - Tier 1: current state (`kubectl get`, `terraform show`, `aws … describe-*`).
   - Tier 2: recent events and logs (`kubectl describe`, `kubectl logs --tail=50`).
   - Tier 3: historical logs or full traces, only if tiers 1-2 do not settle it.
3. **Parallel checks** — with several independent hypotheses, check them in parallel with sub-agents on a small model.
4. **Mandatory confidence gate** — every conclusion ends with a confidence level (in the repository language, e.g. `Confidence: high | medium | low`):
   - **High:** cause identified with direct evidence.
   - **Medium:** likely cause, some uncertainty left.
   - **Low:** unconfirmed hypothesis. State the uncertainty and propose the cheapest check.
5. **Forbidden:** hiding uncertainty behind confident answers, or proposing fixes without evidence.

In read-only mode, every cloud, cluster or remote command goes through `ro`.

## Answer format

```
Most likely cause: <cause>
Evidence: <what you found>
Checks run: <commands>
Proposed fix: <action>
Confidence: high|medium|low
```

If confidence is low:

```
Cheapest next check: <exact command>
```
