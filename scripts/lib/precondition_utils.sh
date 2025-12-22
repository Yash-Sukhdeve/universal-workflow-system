#!/bin/bash
# Precondition Validation Utility Library
# Validates preconditions before operations - RWF compliance (R1: Truthfulness)
# Never proceed without verifying requirements

set -euo pipefail

# Source dependencies
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/error_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/error_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/yaml_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/yaml_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/schema_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/schema_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/validation_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/validation_utils.sh"
fi

# Color codes
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
fi

# Precondition tracking
declare -a PRECONDITION_FAILURES=()
PRECONDITION_STRICT="${PRECONDITION_STRICT:-true}"

#######################################
# Clear precondition failures
#######################################
precondition_clear() {
    PRECONDITION_FAILURES=()
}

#######################################
# Add precondition failure
# Arguments:
#   $1 - Failure message
#######################################
precondition_add_failure() {
    PRECONDITION_FAILURES+=("$1")
}

#######################################
# Check if any preconditions failed
# Returns:
#   0 if failures exist, 1 if none
#######################################
precondition_has_failures() {
    [[ ${#PRECONDITION_FAILURES[@]} -gt 0 ]]
}

#######################################
# Get precondition failure count
# Returns:
#   Number of failures
#######################################
precondition_failure_count() {
    echo "${#PRECONDITION_FAILURES[@]}"
}

#######################################
# Print precondition failures
#######################################
precondition_print_failures() {
    if precondition_has_failures; then
        echo -e "${RED}Precondition failures:${NC}" >&2
        for failure in "${PRECONDITION_FAILURES[@]}"; do
            echo -e "  ${RED}- ${failure}${NC}" >&2
        done
    fi
}

#######################################
# Require workflow to be initialized
# Returns:
#   0 if initialized, 1 if not
#######################################
require_workflow_initialized() {
    if [[ ! -d ".workflow" ]]; then
        precondition_add_failure "Workflow not initialized: .workflow directory missing"
        echo -e "${RED}Error: Workflow not initialized${NC}" >&2
        echo -e "${YELLOW}Run './scripts/init_workflow.sh' to initialize${NC}" >&2
        return 1
    fi

    if [[ ! -f ".workflow/state.yaml" ]]; then
        precondition_add_failure "Workflow state missing: .workflow/state.yaml"
        echo -e "${RED}Error: Workflow state file missing${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Require checkpoint exists and is valid
# Arguments:
#   $1 - Checkpoint ID
# Returns:
#   0 if valid, 1 if not
#######################################
require_checkpoint_exists() {
    local checkpoint_id="$1"

    if [[ -z "$checkpoint_id" ]]; then
        precondition_add_failure "Checkpoint ID is empty"
        echo -e "${RED}Error: Checkpoint ID required${NC}" >&2
        return 1
    fi

    # Validate format
    if [[ ! "$checkpoint_id" =~ ^CP_([1-5]|INIT)(_[0-9]+)?$ ]]; then
        precondition_add_failure "Invalid checkpoint ID format: ${checkpoint_id}"
        echo -e "${RED}Error: Invalid checkpoint ID format: ${checkpoint_id}${NC}" >&2
        return 1
    fi

    # Check log entry
    if [[ ! -f ".workflow/checkpoints.log" ]]; then
        precondition_add_failure "Checkpoint log missing"
        echo -e "${RED}Error: No checkpoints exist${NC}" >&2
        return 1
    fi

    if ! grep -q "|${checkpoint_id}|" ".workflow/checkpoints.log" 2>/dev/null; then
        precondition_add_failure "Checkpoint not found in log: ${checkpoint_id}"
        echo -e "${RED}Error: Checkpoint ${checkpoint_id} not found${NC}" >&2
        return 1
    fi

    # Check snapshot directory
    local snapshot_dir=".workflow/checkpoints/snapshots/${checkpoint_id}"
    if [[ ! -d "$snapshot_dir" ]]; then
        precondition_add_failure "Checkpoint snapshot missing: ${checkpoint_id}"
        echo -e "${YELLOW}Warning: Snapshot directory missing for ${checkpoint_id}${NC}" >&2
        # Don't fail - checkpoint may be in log but not restorable
    fi

    return 0
}

#######################################
# Require agent is valid
# Arguments:
#   $1 - Agent name
# Returns:
#   0 if valid, 1 if not
#######################################
require_agent_valid() {
    local agent_name="$1"

    if [[ -z "$agent_name" ]]; then
        precondition_add_failure "Agent name is empty"
        echo -e "${RED}Error: Agent name required${NC}" >&2
        return 1
    fi

    # Validate agent name
    local valid_agents=("researcher" "architect" "implementer" "experimenter" "optimizer" "deployer" "documenter")
    local found=false

    # Use schema validation if available
    if declare -f validate_agent_schema > /dev/null 2>&1; then
        if validate_agent_schema "$agent_name" 2>/dev/null; then
            found=true
        fi
    else
        # Fallback validation
        for valid in "${valid_agents[@]}"; do
            if [[ "$agent_name" == "$valid" ]]; then
                found=true
                break
            fi
        done
    fi

    if [[ "$found" != "true" ]]; then
        precondition_add_failure "Unknown agent: ${agent_name}"
        echo -e "${RED}Error: Unknown agent '${agent_name}'${NC}" >&2
        echo -e "${YELLOW}Valid agents: ${valid_agents[*]}${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Require skill is available
# Arguments:
#   $1 - Skill name
# Returns:
#   0 if available, 1 if not
#######################################
require_skill_available() {
    local skill_name="$1"

    if [[ -z "$skill_name" ]]; then
        precondition_add_failure "Skill name is empty"
        echo -e "${RED}Error: Skill name required${NC}" >&2
        return 1
    fi

    # Check skill catalog
    local catalog=".workflow/skills/catalog.yaml"
    if [[ ! -f "$catalog" ]]; then
        precondition_add_failure "Skill catalog missing"
        echo -e "${YELLOW}Warning: Skill catalog not found${NC}" >&2
        return 0  # Don't fail if catalog missing
    fi

    if ! grep -q "^  ${skill_name}:" "$catalog" 2>/dev/null; then
        precondition_add_failure "Unknown skill: ${skill_name}"
        echo -e "${RED}Error: Unknown skill '${skill_name}'${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Require state is consistent
# Validates cross-field consistency
# Returns:
#   0 if consistent, 1 if not
#######################################
require_state_consistent() {
    local state_file="${1:-.workflow/state.yaml}"

    require_workflow_initialized || return 1

    local errors=0

    # Validate schema if available
    if declare -f validate_state_schema > /dev/null 2>&1; then
        if ! validate_state_schema "$state_file" 0 2>/dev/null; then
            precondition_add_failure "State file schema validation failed"
            ((errors++))
        fi
    fi

    # Check checkpoint consistency
    local current_cp
    current_cp=$(yaml_get "$state_file" "current_checkpoint" 2>/dev/null || echo "")

    if [[ -n "$current_cp" && "$current_cp" != "null" ]]; then
        # Verify checkpoint exists
        if [[ -f ".workflow/checkpoints.log" ]]; then
            if ! grep -q "|${current_cp}|" ".workflow/checkpoints.log" 2>/dev/null; then
                precondition_add_failure "Current checkpoint not in log: ${current_cp}"
                ((errors++))
            fi
        fi
    fi

    # Check agent consistency
    local agent_status agent_name
    agent_status=$(yaml_get "$state_file" "active_agent.status" 2>/dev/null || echo "inactive")
    agent_name=$(yaml_get "$state_file" "active_agent.name" 2>/dev/null || echo "null")

    if [[ "$agent_status" == "active" && ("$agent_name" == "null" || -z "$agent_name") ]]; then
        precondition_add_failure "Agent status is active but no agent name set"
        ((errors++))
    fi

    # Check phase validity
    local current_phase
    current_phase=$(yaml_get "$state_file" "current_phase" 2>/dev/null || echo "")

    if [[ -n "$current_phase" && "$current_phase" != "null" ]]; then
        if [[ ! "$current_phase" =~ ^phase_[1-5]_(planning|implementation|validation|delivery|maintenance)$ ]]; then
            precondition_add_failure "Invalid current phase: ${current_phase}"
            ((errors++))
        fi
    fi

    if (( errors > 0 )); then
        echo -e "${RED}Error: State consistency check failed (${errors} issues)${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Require git is clean (no uncommitted changes)
# Arguments:
#   $1 - (Optional) Strict mode (1=fail on uncommitted, 0=warn)
# Returns:
#   0 if clean, 1 if dirty
#######################################
require_git_clean() {
    local strict="${1:-0}"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        # Not a git repo - skip check
        return 0
    fi

    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        if [[ "$strict" == "1" ]]; then
            precondition_add_failure "Git has uncommitted changes"
            echo -e "${RED}Error: Uncommitted changes in git${NC}" >&2
            return 1
        else
            echo -e "${YELLOW}Warning: Uncommitted changes in git${NC}" >&2
        fi
    fi

    return 0
}

#######################################
# Require file is readable
# Arguments:
#   $1 - File path
#   $2 - (Optional) Description
# Returns:
#   0 if readable, 1 if not
#######################################
require_file_readable() {
    local file="$1"
    local description="${2:-File}"

    if [[ ! -f "$file" ]]; then
        precondition_add_failure "${description} not found: ${file}"
        echo -e "${RED}Error: ${description} not found: ${file}${NC}" >&2
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        precondition_add_failure "${description} not readable: ${file}"
        echo -e "${RED}Error: ${description} not readable: ${file}${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Require file is writable
# Arguments:
#   $1 - File path
#   $2 - (Optional) Description
# Returns:
#   0 if writable, 1 if not
#######################################
require_file_writable() {
    local file="$1"
    local description="${2:-File}"

    if [[ -f "$file" && ! -w "$file" ]]; then
        precondition_add_failure "${description} not writable: ${file}"
        echo -e "${RED}Error: ${description} not writable: ${file}${NC}" >&2
        return 1
    fi

    # Check parent directory if file doesn't exist
    if [[ ! -f "$file" ]]; then
        local parent
        parent=$(dirname "$file")
        if [[ ! -w "$parent" ]]; then
            precondition_add_failure "Cannot create ${description}: ${file} (directory not writable)"
            echo -e "${RED}Error: Cannot create ${description}: directory not writable${NC}" >&2
            return 1
        fi
    fi

    return 0
}

#######################################
# Require directory exists and is writable
# Arguments:
#   $1 - Directory path
#   $2 - (Optional) Description
# Returns:
#   0 if valid, 1 if not
#######################################
require_dir_writable() {
    local dir="$1"
    local description="${2:-Directory}"

    if [[ ! -d "$dir" ]]; then
        precondition_add_failure "${description} not found: ${dir}"
        echo -e "${RED}Error: ${description} not found: ${dir}${NC}" >&2
        return 1
    fi

    if [[ ! -w "$dir" ]]; then
        precondition_add_failure "${description} not writable: ${dir}"
        echo -e "${RED}Error: ${description} not writable: ${dir}${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Require command/tool is available
# Arguments:
#   $1 - Command name
#   $2 - (Optional) Install hint
# Returns:
#   0 if available, 1 if not
#######################################
require_command() {
    local cmd="$1"
    local hint="${2:-}"

    if ! command -v "$cmd" &> /dev/null; then
        precondition_add_failure "Required command not found: ${cmd}"
        echo -e "${RED}Error: Required command not found: ${cmd}${NC}" >&2
        if [[ -n "$hint" ]]; then
            echo -e "${YELLOW}Install with: ${hint}${NC}" >&2
        fi
        return 1
    fi

    return 0
}

#######################################
# Run all precondition checks for operation
# Arguments:
#   $1 - Operation name
#   $@ - Check functions to run
# Returns:
#   0 if all pass, 1 if any fail
#######################################
require_all() {
    local operation="$1"
    shift

    precondition_clear

    local failures=0

    for check in "$@"; do
        if ! $check; then
            ((failures++))
        fi
    done

    if (( failures > 0 )); then
        echo -e "${RED}Cannot proceed with ${operation}: ${failures} precondition(s) failed${NC}" >&2
        precondition_print_failures

        if [[ "$PRECONDITION_STRICT" == "true" ]]; then
            return 1
        fi
    fi

    return $failures
}

#######################################
# Print usage information
#######################################
precondition_usage() {
    cat << 'EOF'
Precondition Validation Utility Library - RWF Truthfulness (R1)

Workflow Preconditions:
  require_workflow_initialized     Verify .workflow exists with state
  require_checkpoint_exists <id>   Verify checkpoint is valid
  require_agent_valid <name>       Verify agent name is valid
  require_skill_available <name>   Verify skill exists in catalog
  require_state_consistent [file]  Verify state file consistency

File Preconditions:
  require_file_readable <path> [desc]   File exists and is readable
  require_file_writable <path> [desc]   File/parent is writable
  require_dir_writable <path> [desc]    Directory exists and writable

System Preconditions:
  require_git_clean [strict]       Verify git has no uncommitted changes
  require_command <cmd> [hint]     Verify command is available

Composite Checks:
  require_all <operation> <check1> <check2> ...

Failure Tracking:
  precondition_clear               Clear failures
  precondition_has_failures        Check if any failures
  precondition_failure_count       Get failure count
  precondition_print_failures      Print all failures

Configuration:
  PRECONDITION_STRICT=true         Fail on any precondition failure

Example:
  source scripts/lib/precondition_utils.sh

  # Single check
  require_workflow_initialized || exit 1

  # Multiple checks
  require_all "checkpoint restore" \
      require_workflow_initialized \
      "require_checkpoint_exists CP_1_005" \
      require_state_consistent

  # Custom check with context
  precondition_clear
  require_agent_valid "$agent"
  require_skill_available "$skill"

  if precondition_has_failures; then
      precondition_print_failures
      exit 1
  fi
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f precondition_clear
    export -f precondition_add_failure
    export -f precondition_has_failures
    export -f precondition_failure_count
    export -f precondition_print_failures
    export -f require_workflow_initialized
    export -f require_checkpoint_exists
    export -f require_agent_valid
    export -f require_skill_available
    export -f require_state_consistent
    export -f require_git_clean
    export -f require_file_readable
    export -f require_file_writable
    export -f require_dir_writable
    export -f require_command
    export -f require_all
    export -f precondition_usage
fi
