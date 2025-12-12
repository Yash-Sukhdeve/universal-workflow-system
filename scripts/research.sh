#!/bin/bash
#
# Universal Workflow System - Research Core Script
#
# Usage: ./scripts/research.sh [action]
#

set -e

ACTION="${1:-status}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="${SCRIPT_DIR}/../.workflow"
STATE_FILE="${WORKFLOW_DIR}/state.yaml"

# Ensure workflow directory exists
if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "Error: Workflow not initialized."
    exit 1
fi

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
