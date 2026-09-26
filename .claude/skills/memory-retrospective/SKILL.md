---
name: memory-retrospective
description: Review and curate global memory database at project completion
disable-model-invocation: true
---

# Project Retrospective

1. mcp__vector_memory_global__get_memory_stats()
   Note total count for limit parameter.

2. mcp__vector_memory_global__list_recent_memories(
     limit=<total_from_stats>)
   NOTE: Set limit to total count from stats to get ALL memories.

3. For each memory, identify project origin by inspecting content
   for tool/pattern names from the current project's domain.
   (Temporal proximity and domain overlap, not file paths.)

4. For each memory from this project's timeframe:
   a. Still accurate? → Keep
   b. Needs refinement? → Store improved version (old ranks lower)
   c. Project-specific? → Store corrective superseding memory:
      content="SUPERSEDES: <summary>. REASON: project-specific."
   d. Related to another? → Store merged consolidated version

   NOTE: No delete_memory tool. "Removal" = superseding entry.
   clear_old_memories cannot wipe a DB: the server rejects days_old < 1
   and max_to_keep < 100. For severe contamination, delete the DB file
   (<project_root>/memory/vector_memory.db) and re-store the valid
   memories from the review notes (see the vector-memory skill).

5. Document results in project completion notes.
