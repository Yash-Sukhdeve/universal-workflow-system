---
description: Set up UWS in this project (.workflow/ state, checkpoints, handoff)
argument-hint: "[software|research|ml|llm|optimization|deployment|hybrid]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws init:*)
---

Initialise the Universal Workflow System in the current project. From the project
root, run exactly (this is the plugin's own `uws` CLI):

```bash
${CLAUDE_PLUGIN_ROOT}/bin/uws init $ARGUMENTS < /dev/null
```

With no project type the script auto-detects one (falling back to `hybrid`). It never
overwrites an existing `.workflow/`; if UWS is already set up, say so and stop.

Afterwards, tell the user what was created and suggest the next step:
`/uws:sdlc start` for software work or `/uws:research start` for research work.
Remind them to commit `.workflow/` so the state travels with the repository.
