---
description: Save a UWS checkpoint of the current workflow state
argument-hint: "<message>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws checkpoint:*)
---

Create a checkpoint with the message: $ARGUMENTS

If the message is empty, write a one-sentence summary of the work done so far and use
that. Then run:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/uws checkpoint create "<message>"
```

Report the checkpoint ID it created.
