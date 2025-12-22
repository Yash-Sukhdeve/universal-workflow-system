#!/bin/bash
# Schema Validation Utility Library
# Provides schema validation for YAML files - RWF compliance (R3: State Safety)
# Works with or without yq installed

set -euo pipefail

# Source dependencies
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/yaml_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/yaml_utils.sh"
fi

# Color codes - define each explicitly
RED="${RED:-\033[0;31m}"
YELLOW="${YELLOW:-\033[1;33m}"
GREEN="${GREEN:-\033[0;32m}"
BLUE="${BLUE:-\033[0;34m}"
NC="${NC:-\033[0m}"

# Schema directory
SCHEMA_DIR="${SCHEMA_DIR:-.workflow/schemas}"

# Validation result storage
declare -a SCHEMA_ERRORS=()
declare -a SCHEMA_WARNINGS=()

#######################################
# Clear validation results
#######################################
schema_clear_results() {
    SCHEMA_ERRORS=()
    SCHEMA_WARNINGS=()
}

#######################################
# Add a validation error
# Arguments:
#   $1 - Error message
#######################################
schema_add_error() {
    SCHEMA_ERRORS+=("$1")
}

#######################################
# Add a validation warning
# Arguments:
#   $1 - Warning message
#######################################
schema_add_warning() {
    SCHEMA_WARNINGS+=("$1")
}

#######################################
# Get validation error count
# Returns:
#   Number of errors
#######################################
schema_error_count() {
    echo "${#SCHEMA_ERRORS[@]}"
}

#######################################
# Get validation warning count
# Returns:
#   Number of warnings
#######################################
schema_warning_count() {
    echo "${#SCHEMA_WARNINGS[@]}"
}

#######################################
# Print validation results
#######################################
schema_print_results() {
    local error_count=${#SCHEMA_ERRORS[@]}
    local warning_count=${#SCHEMA_WARNINGS[@]}

    if (( error_count > 0 )); then
        echo -e "${RED}Validation errors (${error_count}):${NC}" >&2
        for error in "${SCHEMA_ERRORS[@]}"; do
            echo -e "  ${RED}- ${error}${NC}" >&2
        done
    fi

    if (( warning_count > 0 )); then
        echo -e "${YELLOW}Validation warnings (${warning_count}):${NC}" >&2
        for warning in "${SCHEMA_WARNINGS[@]}"; do
            echo -e "  ${YELLOW}- ${warning}${NC}" >&2
        done
    fi

    if (( error_count == 0 && warning_count == 0 )); then
        echo -e "${GREEN}Validation passed${NC}" >&2
    fi
}

#######################################
# Validate field exists and is not null
# Arguments:
#   $1 - YAML file path
#   $2 - Field path
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_required_field() {
    local file="$1"
    local field="$2"

    local value
    value=$(yaml_get "$file" "$field" 2>/dev/null || echo "null")

    if [[ "$value" == "null" || -z "$value" ]]; then
        schema_add_error "Required field missing or null: ${field}"
        return 1
    fi

    return 0
}

#######################################
# Validate field matches pattern
# Arguments:
#   $1 - Value to validate
#   $2 - Regex pattern
#   $3 - Field name (for error message)
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_pattern() {
    local value="$1"
    local pattern="$2"
    local field_name="$3"

    if [[ -z "$value" || "$value" == "null" ]]; then
        return 0  # Skip pattern check for empty values
    fi

    if [[ ! "$value" =~ $pattern ]]; then
        schema_add_error "Field '${field_name}' value '${value}' does not match pattern '${pattern}'"
        return 1
    fi

    return 0
}

#######################################
# Validate field type
# Arguments:
#   $1 - Value to validate
#   $2 - Expected type (string, integer, boolean, array, iso8601, string_or_null)
#   $3 - Field name
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_type() {
    local value="$1"
    local expected_type="$2"
    local field_name="$3"

    case "$expected_type" in
        string)
            if [[ -z "$value" ]]; then
                schema_add_error "Field '${field_name}' must be a non-empty string"
                return 1
            fi
            ;;
        string_or_null)
            # Always valid
            return 0
            ;;
        integer)
            if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
                schema_add_error "Field '${field_name}' must be an integer, got '${value}'"
                return 1
            fi
            ;;
        boolean)
            case "${value,,}" in
                true|false|yes|no|1|0)
                    return 0
                    ;;
                *)
                    schema_add_error "Field '${field_name}' must be boolean, got '${value}'"
                    return 1
                    ;;
            esac
            ;;
        array)
            # For arrays, we check if it starts with [ or has - items
            # This is a simplified check
            return 0
            ;;
        iso8601)
            if [[ -z "$value" || "$value" == "null" ]]; then
                return 0  # Null is acceptable
            fi
            if [[ ! "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}([+-][0-9]{2}:[0-9]{2}|Z)?)?$ ]]; then
                schema_add_error "Field '${field_name}' must be ISO 8601 date, got '${value}'"
                return 1
            fi
            ;;
        *)
            schema_add_warning "Unknown type '${expected_type}' for field '${field_name}'"
            ;;
    esac

    return 0
}

#######################################
# Validate state.yaml against schema
# Arguments:
#   $1 - State file path (default: .workflow/state.yaml)
#   $2 - (Optional) Strict mode (1=strict, 0=lenient)
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_state_schema() {
    local state_file="${1:-.workflow/state.yaml}"
    local strict="${2:-0}"

    schema_clear_results

    if [[ ! -f "$state_file" ]]; then
        schema_add_error "State file not found: ${state_file}"
        return 1
    fi

    # Basic YAML validation
    if declare -f yaml_validate > /dev/null 2>&1; then
        if ! yaml_validate "$state_file" 2>/dev/null; then
            schema_add_error "Invalid YAML syntax in ${state_file}"
            return 1
        fi
    fi

    # Required fields
    local required_fields=(
        "current_phase"
        "current_checkpoint"
        "metadata.schema_version"
        "metadata.last_updated"
    )

    for field in "${required_fields[@]}"; do
        validate_required_field "$state_file" "$field" || true
    done

    # Get values for pattern validation
    local current_phase current_checkpoint project_type agent_status health_status

    current_phase=$(yaml_get "$state_file" "current_phase" 2>/dev/null || echo "")
    current_checkpoint=$(yaml_get "$state_file" "current_checkpoint" 2>/dev/null || echo "")
    project_type=$(yaml_get "$state_file" "project.type" 2>/dev/null || echo "")
    agent_status=$(yaml_get "$state_file" "active_agent.status" 2>/dev/null || echo "")
    health_status=$(yaml_get "$state_file" "health.status" 2>/dev/null || echo "")

    # Pattern validation
    if [[ -n "$current_phase" && "$current_phase" != "null" ]]; then
        validate_pattern "$current_phase" "^phase_[1-5]_(planning|implementation|validation|delivery|maintenance)$" "current_phase"
    fi

    if [[ -n "$current_checkpoint" && "$current_checkpoint" != "null" ]]; then
        validate_pattern "$current_checkpoint" "^CP_([1-5]|INIT)(_[0-9]+)?$" "current_checkpoint"
    fi

    if [[ -n "$project_type" && "$project_type" != "null" ]]; then
        validate_pattern "$project_type" "^(research|ml|software|llm|optimization|deployment|hybrid)$" "project.type"
    fi

    if [[ -n "$agent_status" && "$agent_status" != "null" ]]; then
        validate_pattern "$agent_status" "^(active|inactive|suspended)$" "active_agent.status"
    fi

    if [[ -n "$health_status" && "$health_status" != "null" ]]; then
        validate_pattern "$health_status" "^(healthy|degraded|critical)$" "health.status"
    fi

    # Type validation for boolean fields
    local initialized debug_mode
    initialized=$(yaml_get "$state_file" "project.initialized" 2>/dev/null || echo "")
    debug_mode=$(yaml_get "$state_file" "features.debug_mode" 2>/dev/null || echo "")

    if [[ -n "$initialized" && "$initialized" != "null" ]]; then
        validate_type "$initialized" "boolean" "project.initialized"
    fi

    if [[ -n "$debug_mode" && "$debug_mode" != "null" ]]; then
        validate_type "$debug_mode" "boolean" "features.debug_mode"
    fi

    # Consistency checks
    local agent_name
    agent_name=$(yaml_get "$state_file" "active_agent.name" 2>/dev/null || echo "")

    if [[ "$agent_status" == "active" && ("$agent_name" == "null" || -z "$agent_name") ]]; then
        schema_add_error "Consistency: active_agent.status is 'active' but active_agent.name is null"
    fi

    # Print results if in strict mode or if there are errors
    local error_count
    error_count=$(schema_error_count)

    if [[ "$strict" == "1" ]] || (( error_count > 0 )); then
        schema_print_results
    fi

    if (( error_count > 0 )); then
        return 1
    fi

    return 0
}

#######################################
# Validate checkpoint metadata against schema
# Arguments:
#   $1 - Metadata file path
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_checkpoint_schema() {
    local metadata_file="$1"

    schema_clear_results

    if [[ ! -f "$metadata_file" ]]; then
        schema_add_error "Metadata file not found: ${metadata_file}"
        return 1
    fi

    # Required fields
    local required_fields=(
        "checkpoint_id"
        "created"
        "phase"
    )

    for field in "${required_fields[@]}"; do
        validate_required_field "$metadata_file" "$field" || true
    done

    # Get values
    local checkpoint_id created phase git_commit

    checkpoint_id=$(yaml_get "$metadata_file" "checkpoint_id" 2>/dev/null || echo "")
    created=$(yaml_get "$metadata_file" "created" 2>/dev/null || echo "")
    phase=$(yaml_get "$metadata_file" "phase" 2>/dev/null || echo "")
    git_commit=$(yaml_get "$metadata_file" "git_commit" 2>/dev/null || echo "")

    # Pattern validation
    if [[ -n "$checkpoint_id" && "$checkpoint_id" != "null" ]]; then
        validate_pattern "$checkpoint_id" "^CP_([1-5]|INIT)(_[0-9]+)?$" "checkpoint_id"
    fi

    if [[ -n "$phase" && "$phase" != "null" ]]; then
        validate_pattern "$phase" "^phase_[1-5]_(planning|implementation|validation|delivery|maintenance)$" "phase"
    fi

    if [[ -n "$created" && "$created" != "null" ]]; then
        validate_type "$created" "iso8601" "created"
    fi

    if [[ -n "$git_commit" && "$git_commit" != "null" ]]; then
        validate_pattern "$git_commit" "^[a-f0-9]{7,40}$" "git_commit"
    fi

    local error_count
    error_count=$(schema_error_count)

    if (( error_count > 0 )); then
        schema_print_results
        return 1
    fi

    return 0
}

#######################################
# Validate agent name against schema
# Arguments:
#   $1 - Agent name
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_agent_schema() {
    local agent_name="$1"

    local valid_agents=(
        "researcher"
        "architect"
        "implementer"
        "experimenter"
        "optimizer"
        "deployer"
        "documenter"
    )

    for valid in "${valid_agents[@]}"; do
        if [[ "$agent_name" == "$valid" ]]; then
            return 0
        fi
    done

    echo -e "${RED}Error: Invalid agent '${agent_name}'${NC}" >&2
    echo -e "${YELLOW}Valid agents: ${valid_agents[*]}${NC}" >&2
    return 1
}

#######################################
# Validate agent transition
# Arguments:
#   $1 - Current agent
#   $2 - Target agent
# Returns:
#   0 if valid transition, 1 if invalid
#######################################
validate_agent_transition() {
    local from_agent="$1"
    local to_agent="$2"

    # Any agent can transition to documenter
    if [[ "$to_agent" == "documenter" ]]; then
        return 0
    fi

    # Transition rules
    case "$from_agent" in
        researcher)
            [[ "$to_agent" =~ ^(architect|implementer)$ ]] && return 0
            ;;
        architect)
            [[ "$to_agent" == "implementer" ]] && return 0
            ;;
        implementer)
            [[ "$to_agent" =~ ^(experimenter|optimizer)$ ]] && return 0
            ;;
        experimenter)
            [[ "$to_agent" =~ ^(optimizer|deployer)$ ]] && return 0
            ;;
        optimizer)
            [[ "$to_agent" =~ ^(deployer|experimenter)$ ]] && return 0
            ;;
        deployer)
            return 1  # deployer can only go to documenter
            ;;
        documenter)
            [[ "$to_agent" =~ ^(researcher|architect|implementer)$ ]] && return 0
            ;;
        *)
            # No active agent - any transition is valid
            return 0
            ;;
    esac

    echo -e "${RED}Error: Invalid transition from '${from_agent}' to '${to_agent}'${NC}" >&2
    return 1
}

#######################################
# Get schema errors as JSON array
# Returns:
#   JSON array of errors
#######################################
schema_get_errors_json() {
    local json="["
    local first=true

    for error in "${SCHEMA_ERRORS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi
        # Escape quotes in error message
        local escaped="${error//\"/\\\"}"
        json+="\"${escaped}\""
    done

    json+="]"
    echo "$json"
}

#######################################
# Validate all workflow state files
# Returns:
#   0 if all valid, 1 if any invalid
#######################################
validate_all_schemas() {
    local workflow_dir="${1:-.workflow}"
    local all_valid=true

    echo -e "${BLUE}Validating workflow schemas...${NC}" >&2

    # Validate state.yaml
    if [[ -f "${workflow_dir}/state.yaml" ]]; then
        echo -n "  state.yaml: " >&2
        if validate_state_schema "${workflow_dir}/state.yaml"; then
            echo -e "${GREEN}OK${NC}" >&2
        else
            echo -e "${RED}FAILED${NC}" >&2
            all_valid=false
        fi
    else
        echo -e "  ${YELLOW}state.yaml: NOT FOUND${NC}" >&2
    fi

    # Validate checkpoint metadata files
    if [[ -d "${workflow_dir}/checkpoints/snapshots" ]]; then
        for snapshot_dir in "${workflow_dir}/checkpoints/snapshots"/*/; do
            if [[ -d "$snapshot_dir" ]]; then
                local cp_name
                cp_name=$(basename "$snapshot_dir")
                local metadata="${snapshot_dir}metadata.yaml"

                if [[ -f "$metadata" ]]; then
                    echo -n "  checkpoint ${cp_name}: " >&2
                    if validate_checkpoint_schema "$metadata"; then
                        echo -e "${GREEN}OK${NC}" >&2
                    else
                        echo -e "${RED}FAILED${NC}" >&2
                        all_valid=false
                    fi
                fi
            fi
        done
    fi

    if [[ "$all_valid" == "true" ]]; then
        echo -e "${GREEN}All schemas validated successfully${NC}" >&2
        return 0
    else
        echo -e "${RED}Schema validation failed${NC}" >&2
        return 1
    fi
}

#######################################
# Print usage information
#######################################
schema_usage() {
    cat << 'EOF'
Schema Validation Utility Library - RWF State Safety (R3)

Validation Functions:
  validate_state_schema [file] [strict]    Validate state.yaml
  validate_checkpoint_schema <file>        Validate checkpoint metadata
  validate_agent_schema <agent>            Validate agent name
  validate_agent_transition <from> <to>    Validate agent transition
  validate_all_schemas [workflow_dir]      Validate all workflow files

Field Validation:
  validate_required_field <file> <field>   Check field exists
  validate_pattern <value> <regex> <name>  Check value matches pattern
  validate_type <value> <type> <name>      Check value type

Result Functions:
  schema_clear_results                     Clear validation results
  schema_error_count                       Get error count
  schema_warning_count                     Get warning count
  schema_print_results                     Print validation results
  schema_get_errors_json                   Get errors as JSON

Valid Types:
  string, string_or_null, integer, boolean, array, iso8601

Example:
  source scripts/lib/schema_utils.sh

  # Validate state file
  if validate_state_schema ".workflow/state.yaml" 1; then
      echo "State is valid"
  else
      echo "Validation failed: $(schema_error_count) errors"
  fi

  # Check agent transition
  validate_agent_transition "researcher" "implementer"
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f schema_clear_results
    export -f schema_add_error
    export -f schema_add_warning
    export -f schema_error_count
    export -f schema_warning_count
    export -f schema_print_results
    export -f validate_required_field
    export -f validate_pattern
    export -f validate_type
    export -f validate_state_schema
    export -f validate_checkpoint_schema
    export -f validate_agent_schema
    export -f validate_agent_transition
    export -f schema_get_errors_json
    export -f validate_all_schemas
    export -f schema_usage
fi
