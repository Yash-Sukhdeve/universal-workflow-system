---
description: Check the status of the Universal Workflow System
---

# UWS Status Check

This workflow checks the current state of the Universal Workflow System.

1. Check if the `.workflow` directory exists.
2. Read the `state.yaml` file to get the current phase and checkpoint.
3. Read the last few lines of `checkpoints.log` to see recent activity.
4. Read the `handoff.md` summary if available.

```bash
# Check if state file exists
if [[ -f ".workflow/state.yaml" ]]; then
    echo "=== Workflow State ==="
    cat .workflow/state.yaml
    echo ""
else
    echo "No workflow state found. Run initialization?"
fi

# Check checkpoints
if [[ -f ".workflow/checkpoints.log" ]]; then
    echo "=== Recent Checkpoints ==="
    tail -n 5 .workflow/checkpoints.log
    echo ""
fi

# Check handoff
if [[ -f ".workflow/handoff.md" ]]; then
    echo "=== Handoff Summary ==="
    head -n 20 .workflow/handoff.md
    echo ""
fi
```
