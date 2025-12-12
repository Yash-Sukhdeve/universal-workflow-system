---
description: Create a UWS checkpoint with state snapshot
allowed-tools: Bash(./scripts/checkpoint.sh:*)
argument-hint: <message>
---

Create a workflow checkpoint to preserve current state.

Arguments:
- $ARGUMENTS: Description of work completed (required)

Execute: `./scripts/checkpoint.sh create "$ARGUMENTS"`

This creates:
- Timestamped snapshot in .workflow/checkpoints/snapshots/
- Entry in checkpoints.log
- Manifest with file checksums
- Git commit hash reference
