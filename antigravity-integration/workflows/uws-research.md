---
description: Manage the Research Methodology Lifecycle
---

# UWS Research Workflow

This workflow manages the Research Methodology lifecycle, enabling scientific rigor.

**Arguments:**
- `action`: `start`, `next`, `status`, `reject` (hypothesis failed)

## Phases
1.  **Hypothesis**: Define research question.
2.  **Experiment Design**: Setup metrics/baselines.
3.  **Data Collection**: Run experiments.
4.  **Analysis**: Statistical validation.
5.  **Publication**: Draft paper.

```bash
ACTION="${1:-status}"

STATE_FILE=".workflow/state.yaml"

# Helper to read state
get_phase() {
    grep "^research_phase:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "none"
}

current_phase=$(get_phase)

if [[ "$ACTION" == "status" ]]; then
    echo "Current Research Phase: $current_phase"
    exit 0
fi

if [[ "$ACTION" == "start" ]]; then
    if ! grep -q "research_phase:" "$STATE_FILE"; then
        echo "research_phase: hypothesis" >> "$STATE_FILE"
    else
        sed -i "s/research_phase:.*/research_phase: \"hypothesis\"/" "$STATE_FILE"
    fi
    echo "Starting Research: Hypothesis Phase"
    echo "Next: Formulate your research question and hypothesis."
    exit 0
fi

if [[ "$ACTION" == "reject" ]]; then
    echo "⚠️ Hypothesis Rejected/Issues Found"
    
    if [[ "$current_phase" == "analysis" ]]; then
        # Scientific Method: Negative results lead to new hypothesis or redesign
        echo "Analysis failed to support hypothesis."
        echo "Options:"
        echo "1. Refine experiment (Reverts to Experiment Design)"
        echo "2. Payout to negative result paper (Continues to Publication)"
        
        # Default behavior for now: Refine
        sed -i "s/research_phase:.*/research_phase: \"experiment_design\"/" "$STATE_FILE"
        echo "🔄 Reverting to EXPERIMENT DESIGN to refine approach."
    else
        echo "Marking current phase as blocked."
    fi
    exit 0
fi

if [[ "$ACTION" == "next" ]]; then
    case "$current_phase" in
        "hypothesis")
            new_phase="experiment_design"
            ;;
        "experiment_design")
            new_phase="data_collection"
            ;;
        "data_collection")
            new_phase="analysis"
            ;;
        "analysis")
            new_phase="publication"
            ;;
        "publication")
            echo "Research cycle complete! Congratulations."
            exit 0
            ;;
        *)
            echo "Unknown phase."
            exit 1
            ;;
    esac
    
    sed -i "s/research_phase:.*/research_phase: \"$new_phase\"/" "$STATE_FILE"
    echo "✅ Advancing to: $new_phase"
fi
```
