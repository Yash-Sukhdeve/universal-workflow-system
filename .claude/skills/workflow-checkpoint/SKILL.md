---
name: workflow-checkpoint
description: >
  Create workflow state checkpoints for context continuity.
  USE WHEN: Completing major work phases, before significant refactoring,
  when switching tasks, or to preserve important progress.
  Creates timestamped snapshots in .workflow/checkpoints/.
allowed-tools: Bash(./scripts/checkpoint.sh:*)
---

# Workflow Checkpoint Skill

Create checkpoints automatically at strategic points:
- After completing a research or implementation phase
- Before major code changes
- When summarizing work for handoff
- Before agent transitions

Execute: `./scripts/checkpoint.sh create "<description of completed work>"`
