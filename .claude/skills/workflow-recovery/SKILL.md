---
name: workflow-recovery
description: >
  Recover workflow context when starting new sessions or when context seems stale.
  USE WHEN: Beginning work after a break, context appears incomplete,
  or need to understand current workflow state.
allowed-tools: Bash(./scripts/recover_context.sh:*)
---

# Workflow Recovery Skill

Recover context automatically when needed:
- At session start
- When workflow state is unclear
- After context compaction
- When handoff notes reference unknown work

Execute: `./scripts/recover_context.sh`
