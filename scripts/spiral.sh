#!/bin/bash
#
# Universal Workflow System - Spiral SDLC Core
#
# Usage: ./scripts/spiral.sh [action]
#

set -e

ACTION="${1:-status}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="${SCRIPT_DIR}/../.workflow"
STATE_FILE="${WORKFLOW_DIR}/state.yaml"
PM_SCRIPT="${SCRIPT_DIR}/pm.sh"

# Ensure workflow directory exists
if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "Error: Workflow not initialized."
    exit 1
fi

# Helper to read state
get_quadrant() {
    grep "^spiral_quadrant:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "none"
}

get_cycle() {
    grep "^spiral_cycle:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "1"
}

current_quadrant=$(get_quadrant)
current_cycle=$(get_cycle)

if [[ "$ACTION" == "status" ]]; then
    echo "Spiral SDLC Status:"
    echo "  Cycle: $current_cycle"
    echo "  Quadrant: $current_quadrant"
    exit 0
fi

if [[ "$ACTION" == "start-cycle" ]]; then
    new_cycle=$((current_cycle + 1))
    
    # Update state
    if ! grep -q "spiral_quadrant:" "$STATE_FILE"; then
        echo "spiral_quadrant: planning" >> "$STATE_FILE"
        echo "spiral_cycle: 1" >> "$STATE_FILE"
        echo "Starting Spiral Cycle 1: Planning"
    else
        sed -i "s/spiral_cycle:.*/spiral_cycle: $new_cycle/" "$STATE_FILE"
        sed -i "s/spiral_quadrant:.*/spiral_quadrant: \"planning\"/" "$STATE_FILE"
        echo "Starting Spiral Cycle $new_cycle: Planning"
    fi
    exit 0
fi

if [[ "$ACTION" == "next" ]]; then
    case "$current_quadrant" in
        "planning")
            new_quadrant="risk_analysis"
            ;;
        "risk_analysis")
            new_quadrant="engineering"
            ;;
        "engineering")
            new_quadrant="evaluation"
            ;;
        "evaluation")
            echo "Cycle complete. Run 'start-cycle' to begin next iteration."
            exit 0
            ;;
        *)
            echo "Unknown quadrant or not started."
            exit 1
            ;;
    esac
    
    sed -i "s/spiral_quadrant:.*/spiral_quadrant: \"$new_quadrant\"/" "$STATE_FILE"
    echo "✅ Advancing to Quadrant: $new_quadrant"
    
    # Trigger side effects
    if [[ "$new_quadrant" == "risk_analysis" ]]; then
        echo "⚠️ Triggering Risk Analysis..."
        bash "$PM_SCRIPT" create "Risk Analysis for Cycle $current_cycle" "Risk" "High"
    fi
fi
