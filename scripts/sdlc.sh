#!/bin/bash
#
# Universal Workflow System - SDLC Core Script
#
# Usage: ./scripts/sdlc.sh [action] [details]
#

set -e

ACTION="${1:-status}"
DETAILS="${2:-}"
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
    grep "^sdlc_phase:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "none"
}

current_phase=$(get_phase)

if [[ "$ACTION" == "status" ]]; then
    echo "Current SDLC Phase: $current_phase"
    if [[ "$current_phase" == "none" ]]; then
        echo "Not in active SDLC. Run 'start' to begin."
    fi
    exit 0
fi

if [[ "$ACTION" == "start" ]]; then
    if ! grep -q "sdlc_phase:" "$STATE_FILE"; then
        echo "sdlc_phase: requirements" >> "$STATE_FILE"
    else
        sed -i "s/sdlc_phase:.*/sdlc_phase: \"requirements\"/" "$STATE_FILE"
    fi
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
