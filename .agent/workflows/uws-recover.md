---
description: Recover full context from the Universal Workflow System
---

# UWS Recover Context

This workflow recovers the full context of the project after a session break.

1. Read `state.yaml` for high-level status.
2. Read the full `handoff.md` for detailed context and next actions.
3. Show recent checkpoints.
4. Show current git status.

```bash
echo "=== RECOVERING CONTEXT ==="

# 1. State
if [[ -f ".workflow/state.yaml" ]]; then
    echo "--- STATE ---"
    cat .workflow/state.yaml
else
    echo "Warning: No state.yaml found"
fi

# 2. Handoff
if [[ -f ".workflow/handoff.md" ]]; then
    echo -e "\n--- HANDOFF DOCUMENT ---"
    cat .workflow/handoff.md
else
    echo "Warning: No handoff.md found"
fi

# 3. Checkpoints
if [[ -f ".workflow/checkpoints.log" ]]; then
    echo -e "\n--- RECENT CHECKPOINTS ---"
    tail -n 5 .workflow/checkpoints.log
fi

# 4. Git Status
echo -e "\n--- GIT STATUS ---"
git status --short 2>/dev/null || echo "Not a git repository"
```
