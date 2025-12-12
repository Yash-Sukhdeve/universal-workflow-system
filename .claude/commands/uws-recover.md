---
description: Recover UWS context after session break
allowed-tools: Bash(./scripts/recover_context.sh:*)
---

Recover workflow context by reading state files and handoff notes.

Execute: `./scripts/recover_context.sh`

This displays:
- Completeness score
- Current phase and checkpoint
- Active agent status
- Handoff notes with next actions
- Phase-specific suggestions
