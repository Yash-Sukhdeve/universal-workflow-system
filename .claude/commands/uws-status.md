---
description: Display current UWS workflow status (phase, agent, checkpoint)
allowed-tools: Bash(./scripts/status.sh:*)
---

Run the UWS status script to show:
- Current workflow phase and progress
- Active agent and capabilities
- Latest checkpoint ID
- Enabled skills
- Git status summary

Execute: `./scripts/status.sh`

For verbose output with recent checkpoints, use: `./scripts/status.sh --verbose`
