---
description: Dispatch the current UWS phase to its subagent and route the artifact through the review gate
allowed-tools: Bash(./scripts/orchestrate.sh:*), Bash(./scripts/sdlc.sh:*), Bash(./scripts/research.sh:*), Bash(./scripts/review.sh:*), Task, Read, Write
argument-hint: [one-line task]
---

Invoke the **uws-orchestrate** skill to run the current UWS phase as an autonomous, checkpoint-gated step.

Task (optional): $ARGUMENTS

Steps:
1. `./scripts/orchestrate.sh status` — show resolved methodology/phase/agent.
2. `./scripts/orchestrate.sh dispatch "$ARGUMENTS"` — prepare the brief and read the `DISPATCH:` line.
3. Launch the named `uws-<role>` subagent on the brief; it writes its artifact under `workspace/<role>/`.
4. `./scripts/orchestrate.sh collect "<summary>"` — stage the change request.
5. STOP and show the user `./scripts/review.sh approve <CR-ID>`. Do not approve for them.
6. After approval: `check` the deliverables and `next` (the hard gate enforces completeness).
