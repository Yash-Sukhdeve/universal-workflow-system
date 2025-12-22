---
description: Initialize UWS workflow system for the current project
allowed-tools: Bash(./scripts/init_workflow.sh:*)
---

Initialize the Universal Workflow System for this project.

This will:
- Create `.workflow/` directory structure
- Initialize `state.yaml` with project metadata
- Set up checkpoint tracking
- Create handoff document template
- Configure agents and skills

Execute: `./scripts/init_workflow.sh`

For interactive mode with project type selection:
`./scripts/init_workflow.sh --interactive`
