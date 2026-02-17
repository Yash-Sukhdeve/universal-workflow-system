---
name: phase-distillation
description: Distill local memories into global lessons at phase completion
disable-model-invocation: true
argument-hint: "[phase-number]"
---

# Phase-End Knowledge Distillation

Distill memories from Phase $ARGUMENTS:

1. mcp__vector_memory_local__search_memories(
     query="PHASE $ARGUMENTS", limit=50)
   NOTE: Using search (not list_recent) to target phase via content prefix.

2. Group results by category.

3. For groups with 2+ entries sharing a root cause:
   Consolidate into ONE general lesson.
   Apply generalizability gate (3-question evaluation).

4. CALIBRATION CHECK: Review last 10 global promotions.
   "Which of these are actually project-specific? Be adversarial."
   For false promotions: store corrective memory with same category:
     content="SUPERSEDES: <original content summary>. REASON: project-specific."
   NOTE: Server has no delete_memory tool. Superseding entries rank
         higher for targeted queries, displacing false ones.

5. Store passing patterns to global DB.

6. Add to .workflow/handoff.md:
   "Phase $ARGUMENTS distillation: promoted M lessons to global knowledge"
