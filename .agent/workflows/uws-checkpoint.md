---
description: Create a checkpoint in the Universal Workflow System
---

# UWS Create Checkpoint

This workflow creates a new checkpoint to save the current progress.

**Arguments:**
- `message`: The description of the checkpoint (e.g., "Completed feature X")

1. Generate a new checkpoint ID.
2. Create a timestamp.
3. Append the checkpoint to `checkpoints.log`.
4. Update `state.yaml` with the new checkpoint ID and timestamp.

```bash
# This block assumes the user provides a message.
# If running manually, replace "CHECKPOINT_MESSAGE" with the actual message.
MSG="${1:-Auto-checkpoint}"

if [[ ! -f ".workflow/checkpoints.log" ]]; then
    echo "Error: Workflow not initialized."
    exit 1
fi

# Get current checkpoint info
LAST_CP=$(grep -oE "CP_[0-9]+_[0-9]+" .workflow/checkpoints.log 2>/dev/null | tail -1 || echo "CP_1_000")
PHASE=$(echo "$LAST_CP" | cut -d_ -f2)
SEQ=$(echo "$LAST_CP" | cut -d_ -f3 | sed 's/^0*//')
NEW_SEQ=$(printf "%03d" $((SEQ + 1)))
NEW_CP="CP_${PHASE}_${NEW_SEQ}"
TIMESTAMP=$(date -Iseconds)

# Create checkpoint entry
echo "${TIMESTAMP} | ${NEW_CP} | ${MSG}" >> .workflow/checkpoints.log

# Update state.yaml
if [[ -f ".workflow/state.yaml" ]]; then
    sed -i "s/current_checkpoint:.*/current_checkpoint: \"${NEW_CP}\"/" .workflow/state.yaml
    sed -i "s/last_updated:.*/last_updated: \"${TIMESTAMP}\"/" .workflow/state.yaml
fi

echo "Checkpoint ${NEW_CP} created: ${MSG}"
```
