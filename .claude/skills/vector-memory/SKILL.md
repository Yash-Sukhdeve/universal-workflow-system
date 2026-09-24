---
name: vector-memory
description: UWS vector-memory protocol for the mcp__vector_memory_local and mcp__vector_memory_global servers. Use when storing a memory (phase completion, bug resolution, agent handoff, verification), searching memories at session resume, choosing a category or tag, or doing memory maintenance, recovery or category migration.
---

# Vector Memory Protocol

## Overview
UWS uses two vector memory databases for semantic retrieval:
- **Local** (mcp__vector_memory_local): Project-specific memories
- **Global** (mcp__vector_memory_global): Cross-project generalizable lessons

Markdown/YAML files are ALWAYS the source of truth. Vector memory is a
read-optimized index. If they conflict, delete the vector memory entry.

## Atomic Memory Principle
Each store_memory() call: EXACTLY ONE idea, MAX 200 words.
Prefix local memories with "PHASE <N> <methodology_phase> | DOMAIN: <domain> | "
  where <N> = UWS overall phase (1-5), <methodology_phase> = research/SDLC phase name
  Example: "PHASE 2 experiment_design | DOMAIN: training | ..."
Prefix global memories with "<TOOL_OR_PATTERN>: "

## When to Store (Behavioral Directives)

**After completing a phase** (on_phase_complete):
  For each key outcome and decision in the phase:
    mcp__vector_memory_local__store_memory(
      content="PHASE <N> <methodology_phase> | DOMAIN: <d> | CATEGORY: phase-summary | OUTCOME: <description>",
      category="learning",
      tags=["phase-<N>", "<domain>"])
  For architectural decisions:
    category="architecture", content includes "CATEGORY: decision-adr"

**After fixing a non-trivial bug** (on_error_resolved):
  mcp__vector_memory_local__store_memory(
    content="PHASE <N> <methodology_phase> | DOMAIN: <d> | CATEGORY: bug-resolution | BUG: <symptom>
             ROOT_CAUSE: <cause> FIX: <fix> PREVENTION: <how>",
    category="bug-fix",
    tags=["phase-<N>", "bug", "<domain>"])
  THEN run Generalizability Gate (see below).

**After agent transition** (on_agent_handoff):
  Outgoing agent stores:
    mcp__vector_memory_local__store_memory(
      content="PHASE <N> <methodology_phase> | DOMAIN: handoff | CATEGORY: agent-handoff |
               HANDOFF <from>-><to>. KEY_DECISIONS: <list>
               OPEN_ISSUES: <list>",
      category="other",
      tags=["phase-<N>", "agent-<from>", "agent-<to>", "handoff"])
  Incoming agent queries:
    mcp__vector_memory_local__search_memories(
      query="decisions constraints phase <N>",
      category="architecture", limit=5)

**After verification/test run** (on_verification):
  mcp__vector_memory_local__store_memory(
    content="PHASE <N> <methodology_phase> | CATEGORY: verification | VERIFIED: <what> METHOD: <how>
             RESULT: <pass/fail> EVIDENCE: <summary>",
    category="other",
    tags=["phase-<N>", "verification"])

## Generalizability Gate
After storing a bug-fix or architecture memory to local DB, the
`memory-gate` skill auto-invokes (via description matching) to evaluate
3 questions. If all pass, an abstracted lesson is promoted to global DB.
If any fail, local only. See `.claude/skills/memory-gate/SKILL.md`.

## Session Resume (Enhanced)
At session start, after reading state.yaml and handoff.md:
  mcp__vector_memory_local__search_memories(
    query="blockers issues PHASE <current>", limit=5)
  mcp__vector_memory_local__search_memories(
    query="decisions PHASE <current>", category="architecture", limit=5)
  mcp__vector_memory_global__search_memories(
    query="<current technology/domain>", limit=3)

## R1 Evidence Extension
Before asserting facts about prior phases:
  mcp__vector_memory_local__search_memories("<claim>", limit=3)
  If relevant result found: cite as supporting evidence.
  If no result: say "No prior record" and verify from files.
  Never cite vector memory as sole evidence.

## Phase-End Distillation
At phase completion, run `/phase-distillation <N>` to review local
memories from the completed phase. The skill consolidates recurring
patterns, applies the generalizability gate, runs adversarial
calibration (supersede false promotions), and promotes passing lessons
to global DB. See `.claude/skills/phase-distillation/SKILL.md`.

## Server-Accepted Categories
The MCP server accepts: `code-solution` | `bug-fix` | `architecture` |
`learning` | `tool-usage` | `debugging` | `performance` | `security` | `other`

Custom categories are embedded in content strings via `CATEGORY: <name>` prefix.

**Local category mapping** (plan category -> server category):
- phase-summary -> `learning`
- decision-adr -> `architecture`
- bug-resolution -> `bug-fix`
- agent-handoff -> `other`
- verification -> `other`
- environment -> `tool-usage`

**Global category mapping**:
- anti-pattern -> `architecture`
- tool-gotcha -> `bug-fix`
- design-lesson -> `architecture`
- library-compat -> `other`
- workflow-improvement -> `other`

## Tag Format
Use hyphens, NOT colons in tags: `phase-2` (correct), `phase:2` (dropped by server).

## Memory Maintenance

LOCAL DB (per phase completion):
  mcp__vector_memory_local__get_memory_stats()
  IF total > 500: mcp__vector_memory_local__clear_old_memories(
    days_old=60, max_to_keep=500)

GLOBAL DB (quarterly, manual review):
  mcp__vector_memory_global__get_memory_stats()
  IF total > 200: Review manually. Remove outdated lessons.
  DO NOT use days_old for global -- old lessons are still valid.
  Only use max_to_keep=200 as safety cap.

## Recovery Procedures

**Local DB lost**:
1. Not catastrophic -- markdown/YAML files are source of truth.
2. Re-seed manually: read .workflow/handoff.md and .workflow/logs/decisions.log.
3. For each decision/bug documented in handoff.md, store to local DB.
4. Full re-indexing is manual but bounded by project size.

**Global DB lost**:
1. Lessons may also exist in CLAUDE.md auto-memory (~/.claude/MEMORY.md).
2. Re-seed from team documentation and known patterns.
3. Global DB grows slowly (~5-10 lessons per project). Loss is recoverable.

**Checkpoint restore (state reverts but vector DB does NOT)**:
1. Check mcp__vector_memory_local__get_memory_stats() for memory count.
2. If memories from future phases exist, they may cause confusion.
3. Option A (recommended): Ignore -- stale memories with future phase
   prefixes (e.g., "PHASE 4") rank low when searching for current
   phase (e.g., "PHASE 2"). The content prefix convention handles this.
4. Option B (nuclear): If contamination is severe, delete the DB file:
     rm <project_root>/memory/vector_memory.db
   Then re-seed from .workflow/handoff.md.
   NOTE: clear_old_memories() cannot wipe all entries (min days_old=1,
   min max_to_keep=100). Direct file deletion is the only full reset.

## Category Migration

If categories need to change in the future:
1. get_memory_stats() to get total count.
2. list_recent_memories(limit=<total>) to export all entries.
3. Record all memory content and categories externally.
4. Delete the DB file: rm <working_dir>/memory/vector_memory.db
   (clear_old_memories cannot wipe all: min days_old=1, min max_to_keep=100)
5. Re-store each memory with updated categories.
Keep category taxonomy stable. Prefer adding new categories over renaming.

