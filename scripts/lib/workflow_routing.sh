#!/bin/bash
#
# Workflow Routing Library - Centralizes methodology/agent/phase routing
#
# Fixes: #1 (subsystem communication), #7 (agent defaults), #8 (transition validation)
#
# Usage: source this via source_lib "workflow_routing.sh"

# Guard against double-sourcing
if [[ "${_WORKFLOW_ROUTING_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_WORKFLOW_ROUTING_LOADED="true"

# Resolve paths relative to this library
_WR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_WR_WORKFLOW_DIR="${WORKFLOW_DIR:-${_WR_SCRIPT_DIR}/../.workflow}"

#######################################
# Map project type to active methodology
# Arguments: $1 - project type (from config/state)
# Returns: "research" | "sdlc" | "both"
#######################################
get_active_methodology() {
    local project_type="${1:-hybrid}"

    case "$project_type" in
        research)       echo "research" ;;
        ml|llm)         echo "both" ;;
        software)       echo "sdlc" ;;
        deployment)     echo "sdlc" ;;
        optimization)   echo "sdlc" ;;
        hybrid|*)       echo "both" ;;
    esac
}

#######################################
# Map methodology + phase to the right agent
# Arguments: $1 - methodology ("research"|"sdlc")
#            $2 - phase name
# Returns: agent name
#######################################
get_agent_for_phase() {
    local methodology="$1"
    local phase="$2"

    if [[ "$methodology" == "research" ]]; then
        case "$phase" in
            hypothesis)         echo "researcher" ;;
            literature_review)  echo "researcher" ;;
            experiment_design)  echo "researcher" ;;
            data_collection)    echo "experimenter" ;;
            analysis)           echo "experimenter" ;;
            peer_review)        echo "researcher" ;;
            publication)        echo "documenter" ;;
            *)                  echo "researcher" ;;
        esac
    elif [[ "$methodology" == "sdlc" ]]; then
        case "$phase" in
            requirements)       echo "architect" ;;
            design)             echo "architect" ;;
            implementation)     echo "implementer" ;;
            verification)       echo "experimenter" ;;
            deployment)         echo "deployer" ;;
            maintenance)        echo "deployer" ;;
            *)                  echo "architect" ;;
        esac
    else
        echo "researcher"
    fi
}

#######################################
# Get default agent for project type
# Reads agents.default_agent from config.yaml, falls back to type-based default
# Arguments: $1 - project type
# Returns: agent name
#######################################
get_default_agent() {
    local project_type="${1:-hybrid}"
    local config_file="${_WR_WORKFLOW_DIR}/config.yaml"

    # Try config.yaml first
    if [[ -f "$config_file" ]]; then
        local configured
        configured=$(grep "default_agent:" "$config_file" 2>/dev/null | head -1 | sed 's/.*default_agent: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | xargs)
        if [[ -n "$configured" && "$configured" != "null" ]]; then
            echo "$configured"
            return 0
        fi
    fi

    # Fallback based on project type
    case "$project_type" in
        research)       echo "researcher" ;;
        ml|llm)         echo "researcher" ;;
        software)       echo "architect" ;;
        deployment)     echo "deployer" ;;
        optimization)   echo "optimizer" ;;
        hybrid|*)       echo "architect" ;;
    esac
}

#######################################
# Validate agent transition against registry rules
# Arguments: $1 - from agent, $2 - to agent
# Returns: 0 if valid, 1 if invalid (prints warning)
#######################################
validate_agent_transition() {
    local from_agent="$1"
    local to_agent="$2"
    local registry="${_WR_WORKFLOW_DIR}/agents/registry.yaml"

    # Same agent is always valid
    [[ "$from_agent" == "$to_agent" ]] && return 0

    # No registry = allow all
    [[ ! -f "$registry" ]] && return 0

    # Check wildcard rules (any agent -> documenter)
    if grep -q "from: \"\*\"" "$registry" 2>/dev/null; then
        local wildcard_targets
        wildcard_targets=$(sed -n '/from: "\*"/,/condition:/{ /to:/{ s/.*to: \[//; s/\].*//; p; } }' "$registry" 2>/dev/null)
        if echo "$wildcard_targets" | grep -q "$to_agent" 2>/dev/null; then
            return 0
        fi
    fi

    # Check specific transition rules
    local allowed_targets
    allowed_targets=$(sed -n "/from: ${from_agent}/,/condition:/{ /to:/{ s/.*to: \[//; s/\].*//; p; } }" "$registry" 2>/dev/null)

    if [[ -z "$allowed_targets" ]]; then
        # No rule found for this agent = allow (open-world assumption)
        return 0
    fi

    if echo "$allowed_targets" | grep -q "$to_agent" 2>/dev/null; then
        return 0
    fi

    # Transition not in rules
    return 1
}

#######################################
# Check if a methodology is valid for the current project type
# Arguments: $1 - methodology ("research"|"sdlc")
# Returns: 0 if active, 1 if not
#######################################
is_methodology_active() {
    local methodology="$1"
    local state_file="${_WR_WORKFLOW_DIR}/state.yaml"

    # Read project type
    local project_type="hybrid"
    if [[ -f "$state_file" ]]; then
        project_type=$(grep "^  type:" "$state_file" 2>/dev/null | head -1 | sed 's/.*type: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | xargs)
        [[ -z "$project_type" ]] && project_type="hybrid"
    fi

    local active
    active=$(get_active_methodology "$project_type")

    [[ "$active" == "$methodology" || "$active" == "both" ]]
}
