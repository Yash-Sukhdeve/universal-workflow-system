---
description: Drive the SDLC workflow (requirements → design → implementation → verification → deployment → maintenance)
argument-hint: "<status|start|next|goto <phase>|fail <reason>|goal <text>|check|deliverables|reset>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws sdlc:*)
---

Run the UWS sdlc workflow with the user's arguments (`$ARGUMENTS`; use `status` if empty):

```bash
${CLAUDE_PLUGIN_ROOT}/bin/uws sdlc <arguments>
```

`next` is blocked while the current phase has unmet deliverables once a goal is set;
report what is missing rather than forcing it. Summarise the result for the user.
