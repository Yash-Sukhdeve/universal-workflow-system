---
description: Show this project's UWS workflow status (phase, checkpoint, recent activity)
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws status:*)
---

UWS status output for this project:

!`${CLAUDE_PLUGIN_ROOT}/bin/uws status 2>&1`

Summarise the status above in a few lines: goal, current phase, latest checkpoint,
and anything that needs attention. If it says no UWS project was found, tell the
user to run `/uws:init`.
