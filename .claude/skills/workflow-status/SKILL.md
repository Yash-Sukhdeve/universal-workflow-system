---
name: workflow-status
description: >
  Check current workflow state before major operations.
  USE WHEN: Need to understand current phase, active agent,
  enabled skills, or recent checkpoints before proceeding.
allowed-tools: Bash(./scripts/status.sh:*)
---

# Workflow Status Skill

Check workflow state automatically:
- Before starting new tasks
- When agent context is needed
- To verify checkpoint status
- Before phase transitions

Execute: `./scripts/status.sh` or `./scripts/status.sh --verbose`
