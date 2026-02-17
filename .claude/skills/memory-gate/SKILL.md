---
name: memory-gate
description: >
  Run generalizability gate after fixing non-trivial bugs or making
  architectural decisions. Evaluates whether lessons should be promoted
  from project-local to cross-project global memory.
  USE WHEN: A bug fix involves a named tool/library/pattern, or an
  architectural decision applies beyond this project.
user-invocable: false
---

# Generalizability Gate

After storing a bug-fix or architecture memory to local DB, evaluate:

Q1: Does the root cause involve a named tool, library, or
    architectural pattern (not just this project's code)?
Q2: Could someone hit this exact issue in a different project?
Q3: Can you state the lesson in one sentence WITHOUT referencing
    any file path, variable name, or project-specific term
    from THIS project?

ALL THREE = YES:
  Compose abstracted lesson (NO project file paths, NO project variable names):
    content="<TOOL_OR_PATTERN>: <root cause mechanism>
             FIX: <fix approach> APPLIES_TO: <scope>"
  Select server category using global mapping:
    anti-pattern -> architecture | tool-gotcha -> bug-fix |
    design-lesson -> architecture | library-compat -> other |
    workflow-improvement -> other
  Embed plan category in content: "CATEGORY: <plan-category> | ..."
  Select tags: [<root-cause-tag>, <scope-tag>, <fix-pattern-tag>] (NO colons)
  Call: mcp__vector_memory_global__store_memory(content, category, tags)

ANY = NO:
  Local store only. No global promotion.

CALIBRATION: After every 10 global promotions, run adversarial review:
  "Which of the last 10 global stores are actually project-specific?"
  For false promotions, store corrective entry:
    "SUPERSEDES: <summary>. REASON: project-specific."
  (No delete_memory tool -- supersede pattern only.)
