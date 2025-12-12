---
description: Manage the Software Development Life Cycle (SDLC)
---

# UWS SDLC Workflow

This workflow drives the project through a strict SDLC process with error handling.

**Arguments:**
- `action`: The action to perform (`start`, `next`, `status`, `fail`)
- `details`: Optional details or error message

1.  **Check Current Phase**: detailed status from `state.yaml`.
2.  **Handle Transition**: Move to next phase or handle error.

## Phases
1.  **Requirements**: Story defined?
2.  **Design**: Architecture/API defined?
3.  **Implementation**: Code written?
4.  **Verification**: Tests passed?
5.  **Deployment**: Deployed?

```bash
ACTION="${1:-status}"
DETAILS="${2:-}"

STATE_FILE=".workflow/state.yaml"

# Helper to read state
get_phase() {
    grep "^sdlc_phase:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "none"
}

current_phase=$(get_phase)

if [[ "$ACTION" == "status" ]]; then
    echo "Current SDLC Phase: $current_phase"
    if [[ "$current_phase" == "none" ]]; then
        echo "Not in active SDLC. Run 'uws-sdlc start' to begin."
    fi
    exit 0
fi

if [[ "$ACTION" == "start" ]]; then
    echo "sdlc_phase: requirements" >> "$STATE_FILE"
    echo "Starting SDLC: Requirements Phase"
    echo "Next: Define user stories and scope."
    exit 0
fi

if [[ "$ACTION" == "fail" ]]; then
    echo "⚠️ Failure reported in phase: $current_phase"
    echo "Details: $DETAILS"
    
    if [[ "$current_phase" == "verification" ]]; then
        # Regression: Go back to implementation
        sed -i "s/sdlc_phase:.*/sdlc_phase: \"implementation\"/" "$STATE_FILE"
        echo "🔄 Reverting to IMPLEMENTATION phase to fix bugs."
    elif [[ "$current_phase" == "deployment" ]]; then
        # Rollback: Go back to verification
        sed -i "s/sdlc_phase:.*/sdlc_phase: \"verification\"/" "$STATE_FILE"
        echo "🔄 Reverting to VERIFICATION phase for diagnostics."
    else
        echo "Stopping current phase to resolve blocking issues."
    fi
    exit 0
fi

if [[ "$ACTION" == "next" ]]; then
    case "$current_phase" in
        "requirements")
            new_phase="design"
            ;;
        "design")
            new_phase="implementation"
            ;;
        "implementation")
            new_phase="verification"
            ;;
        "verification")
            new_phase="deployment"
            ;;
        "deployment")
            new_phase="maintenance"
            ;;
        *)
            echo "Unknown phase or end of cycle."
            exit 1
            ;;
    esac
    
    sed -i "s/sdlc_phase:.*/sdlc_phase: \"$new_phase\"/" "$STATE_FILE"
    echo "✅ Advancing to: $new_phase"
fi
```
