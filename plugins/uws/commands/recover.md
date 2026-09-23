---
description: Recover full UWS context after a session break
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws recover:*), Bash(git status:*)
---

Recovered UWS context:

!`${CLAUDE_PLUGIN_ROOT}/bin/uws recover 2>&1`

Handoff notes:

@.workflow/handoff.md

Git working tree:

!`git status --short --branch 2>/dev/null | head -20`

Based on this:
1. Summarise where the work left off (goal, phase, last checkpoint).
2. List the next actions in priority order.
3. Note blockers or anything in the handoff that looks out of date.
4. Ask whether to continue with the first next action.
