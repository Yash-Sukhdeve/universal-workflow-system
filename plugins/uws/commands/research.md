---
description: Drive the research workflow (hypothesis → literature review → experiment design → data collection → analysis → peer review → publication)
argument-hint: "<status|start|next|reject <reason>|goal <text>|check|deliverables|reset>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws research:*)
---

Run the UWS research workflow with the user's arguments (`$ARGUMENTS`; use `status` if empty):

```bash
${CLAUDE_PLUGIN_ROOT}/bin/uws research <arguments>
```

`next` is blocked while the current phase has unmet deliverables once a goal is set;
report what is missing rather than forcing it. In a project with `research/ledger/`,
`next` also runs the research team's evidence gate (see `/uws:research-check`); its
`--force "<reason>"` override is logged and is always refused at publication.
Summarise the result for the user.
