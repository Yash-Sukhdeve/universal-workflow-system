---
description: Prepare UWS handoff document for session end
---

# UWS Handoff

This workflow helps you prepare the handoff document before ending your session.

1. Read the current `handoff.md`.
2. Update it with:
    - Current status.
    - Work completed.
    - Next actions (prioritized).
    - Blockers.
    - Critical context.

**Instructions:**
The agent should read the existing handoff, then rewrite it with updated information based on the work done in the current session.

```bash
if [[ -f ".workflow/handoff.md" ]]; then
    echo "=== CURRENT HANDOFF ==="
    cat .workflow/handoff.md
else
    echo "No handoff document found. Creating new one..."
    # The agent should create the file content in the next step
fi
```
