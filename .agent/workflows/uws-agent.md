---
description: Activate a specialized UWS agent
---

# UWS Activate Agent

This workflow activates a specialized agent (Researcher, Architect, Implementer, etc.).

**Arguments:**
- `agent_name`: Name of the agent to activate (researcher, architect, implementer, experimenter, optimizer, deployer, documenter)

1. Verify agent existence.
2. Update `state.yaml` to reflect the active agent.
3. Switch workspace context if necessary (conceptually).

```bash
AGENT="${1:-implementer}"
VALID_AGENTS="researcher architect implementer experimenter optimizer deployer documenter"

if [[ ! " $VALID_AGENTS " =~ " $AGENT " ]]; then
    echo "Error: Invalid agent '$AGENT'. Valid agents: $VALID_AGENTS"
    exit 1
fi

echo "Activating agent: $AGENT"

# Update state.yaml
if [[ -f ".workflow/state.yaml" ]]; then
    # Simple sed to update or append active_agent
    if grep -q "active_agent:" .workflow/state.yaml; then
        sed -i "s/active_agent:.*/active_agent: \"$AGENT\"/" .workflow/state.yaml
    else
        echo "active_agent: \"$AGENT\"" >> .workflow/state.yaml
    fi
    echo "Agent set to $AGENT in state.yaml"
else
    echo "Error: state.yaml not found."
fi
```
