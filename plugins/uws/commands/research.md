---
description: Drive the research workflow (hypothesis → literature review → experiment design → data collection → analysis → peer review → publication)
argument-hint: "<status|start|next|goto <phase>|reject <reason>|goal <text>|check|deliverables|reset>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws research:*)
---

Run the UWS research workflow with the user's arguments (`$ARGUMENTS`; use `status` if empty):

```bash
${CLAUDE_PLUGIN_ROOT}/bin/uws research <arguments>
```

`next` is blocked while the current phase has unmet deliverables once a goal is set;
report what is missing rather than forcing it. Summarise the result for the user.
