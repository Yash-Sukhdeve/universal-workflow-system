---
description: Recover UWS context after session break
allowed-tools: Bash(./scripts/recover_context.sh:*)
---

Recover workflow context by reading state files and handoff notes.

Execute: `./scripts/recover_context.sh`

This displays:
- Completeness score
- Current phase and checkpoint
- Active methodology and relevant phases
- Active agent status
- Handoff notes with next actions
- Methodology-aware suggestions

After recovery, read `.workflow/agents/active.yaml` and adopt the active agent's persona (mindset, voice, responsibilities).

If vector memory is configured, also query for relevant context:
  mcp__vector_memory_local__search_memories("current blockers", limit=3)
  mcp__vector_memory_local__search_memories("decisions PHASE <current>", category="architecture", limit=3)
  mcp__vector_memory_global__search_memories("<current technology/domain>", limit=3)
