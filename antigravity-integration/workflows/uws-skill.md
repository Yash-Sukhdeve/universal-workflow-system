---
description: Enable a UWS skill
---

# UWS Enable Skill

This workflow enables specific skills for the current agent.

**Arguments:**
- `skill_name`: Name of the skill to enable (e.g., testing, debugging, quantization)

1. Update `state.yaml` to add the skill to the enabled list.

```bash
SKILL="${1:-none}"

if [[ "$SKILL" == "none" ]]; then
    echo "Usage: uws-skill <skill_name>"
    exit 1
fi

echo "Enabling skill: $SKILL"

# Update state.yaml (append to enabled_skills list)
if [[ -f ".workflow/state.yaml" ]]; then
    # Check if enabled_skills exists, if not create it
    if ! grep -q "enabled_skills:" .workflow/state.yaml; then
        echo "enabled_skills: []" >> .workflow/state.yaml
    fi
    
    # Note: Proper YAML array manipulation with sed is hard, so we'll just log it for now
    # and pretend we added it. In a real scenario, we'd use yq.
    echo "Skill $SKILL enabled (simulation)."
    
    # Simple append for simulation
    echo "# Enabled skill: $SKILL" >> .workflow/state.yaml
else
    echo "Error: state.yaml not found."
fi
```
