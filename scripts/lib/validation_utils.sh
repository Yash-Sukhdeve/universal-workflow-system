#!/bin/bash
# Validation Utility Library
# Provides input validation and sanitization functions for workflow system

set -euo pipefail

# Source YAML utilities if available
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/yaml_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/yaml_utils.sh"
fi

# Color codes for output
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m' # No Color

# Validation result codes
readonly VALID=0
readonly INVALID=1

#######################################
# Validate agent name against registry
# Arguments:
#   $1 - Agent name to validate
#   $2 - (Optional) Path to registry file
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_agent() {
    local agent_name="$1"
    local registry_file="${2:-.workflow/agents/registry.yaml}"

    if [[ -z "$agent_name" ]]; then
        echo -e "${RED}Error: Agent name cannot be empty${NC}" >&2
        return $INVALID
    fi

    if [[ ! -f "$registry_file" ]]; then
        echo -e "${YELLOW}Warning: Registry file not found: ${registry_file}${NC}" >&2
        echo -e "${YELLOW}Skipping agent validation${NC}" >&2
        return $VALID
    fi

    # Check if agent exists in registry
    if grep -q "^${agent_name}:" "$registry_file" 2>/dev/null; then
        return $VALID
    else
        echo -e "${RED}Error: Unknown agent '${agent_name}'${NC}" >&2
        echo -e "${YELLOW}Available agents:${NC}" >&2
        grep "^[a-z_]*:" "$registry_file" | sed 's/:$//' | sed 's/^/  - /' >&2
        return $INVALID
    fi
}

#######################################
# Validate skill name against catalog
# Arguments:
#   $1 - Skill name to validate
#   $2 - (Optional) Path to catalog file
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_skill() {
    local skill_name="$1"
    local catalog_file="${2:-.workflow/skills/catalog.yaml}"

    if [[ -z "$skill_name" ]]; then
        echo -e "${RED}Error: Skill name cannot be empty${NC}" >&2
        return $INVALID
    fi

    if [[ ! -f "$catalog_file" ]]; then
        echo -e "${YELLOW}Warning: Catalog file not found: ${catalog_file}${NC}" >&2
        echo -e "${YELLOW}Skipping skill validation${NC}" >&2
        return $VALID
    fi

    # Check if skill exists in catalog
    if grep -q "^  ${skill_name}:" "$catalog_file" 2>/dev/null; then
        return $VALID
    else
        echo -e "${RED}Error: Unknown skill '${skill_name}'${NC}" >&2
        echo -e "${YELLOW}Run './scripts/enable_skill.sh --list' to see available skills${NC}" >&2
        return $INVALID
    fi
}

#######################################
# Validate phase name
# Arguments:
#   $1 - Phase name to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_phase() {
    local phase_name="$1"

    if [[ -z "$phase_name" ]]; then
        echo -e "${RED}Error: Phase name cannot be empty${NC}" >&2
        return $INVALID
    fi

    # Valid phases
    local valid_phases=(
        "phase_1_planning"
        "phase_2_implementation"
        "phase_3_validation"
        "phase_4_delivery"
        "phase_5_maintenance"
    )

    for valid_phase in "${valid_phases[@]}"; do
        if [[ "$phase_name" == "$valid_phase" ]]; then
            return $VALID
        fi
    done

    echo -e "${RED}Error: Invalid phase '${phase_name}'${NC}" >&2
    echo -e "${YELLOW}Valid phases:${NC}" >&2
    printf '  - %s\n' "${valid_phases[@]}" >&2
    return $INVALID
}

#######################################
# Validate checkpoint ID format
# Arguments:
#   $1 - Checkpoint ID to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_checkpoint_id() {
    local checkpoint_id="$1"

    if [[ -z "$checkpoint_id" ]]; then
        echo -e "${RED}Error: Checkpoint ID cannot be empty${NC}" >&2
        return $INVALID
    fi

    # Checkpoint ID format: CP_<phase>_<number> or CP_INIT
    if [[ "$checkpoint_id" =~ ^CP_([1-5]|INIT)(_[0-9]+)?$ ]]; then
        return $VALID
    else
        echo -e "${RED}Error: Invalid checkpoint ID format '${checkpoint_id}'${NC}" >&2
        echo -e "${YELLOW}Expected format: CP_<phase>_<number> (e.g., CP_1_001) or CP_INIT${NC}" >&2
        return $INVALID
    fi
}

#######################################
# Validate project type
# Arguments:
#   $1 - Project type to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_project_type() {
    local project_type="$1"

    if [[ -z "$project_type" ]]; then
        echo -e "${RED}Error: Project type cannot be empty${NC}" >&2
        return $INVALID
    fi

    # Valid project types
    local valid_types=(
        "research"
        "ml"
        "software"
        "llm"
        "optimization"
        "deployment"
        "hybrid"
    )

    for valid_type in "${valid_types[@]}"; do
        if [[ "$project_type" == "$valid_type" ]]; then
            return $VALID
        fi
    done

    echo -e "${RED}Error: Invalid project type '${project_type}'${NC}" >&2
    echo -e "${YELLOW}Valid types:${NC}" >&2
    printf '  - %s\n' "${valid_types[@]}" >&2
    return $INVALID
}

#######################################
# Validate file path exists
# Arguments:
#   $1 - File path to validate
#   $2 - (Optional) Human-readable file description
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_file_exists() {
    local file_path="$1"
    local description="${2:-File}"

    if [[ -z "$file_path" ]]; then
        echo -e "${RED}Error: File path cannot be empty${NC}" >&2
        return $INVALID
    fi

    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}Error: ${description} not found: ${file_path}${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate directory exists
# Arguments:
#   $1 - Directory path to validate
#   $2 - (Optional) Human-readable directory description
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_dir_exists() {
    local dir_path="$1"
    local description="${2:-Directory}"

    if [[ -z "$dir_path" ]]; then
        echo -e "${RED}Error: Directory path cannot be empty${NC}" >&2
        return $INVALID
    fi

    if [[ ! -d "$dir_path" ]]; then
        echo -e "${RED}Error: ${description} not found: ${dir_path}${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Sanitize file path (prevent directory traversal)
# Arguments:
#   $1 - File path to sanitize
# Returns:
#   Sanitized path
#######################################
sanitize_path() {
    local path="$1"

    # Remove any ../ sequences
    path="${path//..\/}"
    path="${path//..\\/}"

    # Remove leading /
    path="${path#/}"

    # Remove any null bytes
    path="${path//\\x00/}"

    echo "$path"
}

#######################################
# Validate string is alphanumeric with underscores/hyphens
# Arguments:
#   $1 - String to validate
#   $2 - (Optional) Field name for error message
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_identifier() {
    local value="$1"
    local field_name="${2:-Identifier}"

    if [[ -z "$value" ]]; then
        echo -e "${RED}Error: ${field_name} cannot be empty${NC}" >&2
        return $INVALID
    fi

    if [[ ! "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: ${field_name} must contain only letters, numbers, underscores, and hyphens${NC}" >&2
        echo -e "${YELLOW}Got: '${value}'${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate workflow is initialized
# Returns:
#   0 if initialized, 1 if not
#######################################
validate_workflow_initialized() {
    if [[ ! -d ".workflow" ]]; then
        echo -e "${RED}Error: Workflow not initialized${NC}" >&2
        echo -e "${YELLOW}Run './scripts/init_workflow.sh' to initialize${NC}" >&2
        return $INVALID
    fi

    if [[ ! -f ".workflow/state.yaml" ]]; then
        echo -e "${RED}Error: Workflow state file not found${NC}" >&2
        echo -e "${YELLOW}Run './scripts/init_workflow.sh' to initialize${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate git repository
# Returns:
#   0 if in git repo, 1 if not
#######################################
validate_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository${NC}" >&2
        echo -e "${YELLOW}Initialize git with: git init${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate number is within range
# Arguments:
#   $1 - Number to validate
#   $2 - Minimum value (inclusive)
#   $3 - Maximum value (inclusive)
#   $4 - (Optional) Field name for error message
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_number_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local field_name="${4:-Value}"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: ${field_name} must be a number${NC}" >&2
        echo -e "${YELLOW}Got: '${value}'${NC}" >&2
        return $INVALID
    fi

    if (( value < min )) || (( value > max )); then
        echo -e "${RED}Error: ${field_name} must be between ${min} and ${max}${NC}" >&2
        echo -e "${YELLOW}Got: ${value}${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate YAML file syntax
# Arguments:
#   $1 - YAML file path
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_yaml_file() {
    local file_path="$1"

    validate_file_exists "$file_path" "YAML file" || return $INVALID

    # Use yaml_validate from yaml_utils.sh if available
    if declare -f yaml_validate > /dev/null 2>&1; then
        yaml_validate "$file_path" || return $INVALID
    else
        # Basic validation
        if grep -q $'\t' "$file_path"; then
            echo -e "${RED}Error: YAML file contains tabs: ${file_path}${NC}" >&2
            return $INVALID
        fi
    fi

    return $VALID
}

#######################################
# Validate required environment variable
# Arguments:
#   $1 - Variable name
#   $2 - (Optional) Error message
# Returns:
#   0 if set, 1 if not
#######################################
validate_env_var() {
    local var_name="$1"
    local error_msg="${2:-Environment variable ${var_name} must be set}"

    if [[ -z "${!var_name:-}" ]]; then
        echo -e "${RED}Error: ${error_msg}${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate email address format
# Arguments:
#   $1 - Email address to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_email() {
    local email="$1"

    if [[ -z "$email" ]]; then
        echo -e "${RED}Error: Email address cannot be empty${NC}" >&2
        return $INVALID
    fi

    # Basic email validation regex
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}Error: Invalid email address format: ${email}${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate URL format
# Arguments:
#   $1 - URL to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_url() {
    local url="$1"

    if [[ -z "$url" ]]; then
        echo -e "${RED}Error: URL cannot be empty${NC}" >&2
        return $INVALID
    fi

    # Basic URL validation
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,} ]]; then
        echo -e "${RED}Error: Invalid URL format: ${url}${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate date format (ISO 8601)
# Arguments:
#   $1 - Date string to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_date_iso8601() {
    local date_str="$1"

    if [[ -z "$date_str" ]]; then
        echo -e "${RED}Error: Date cannot be empty${NC}" >&2
        return $INVALID
    fi

    # ISO 8601 format: YYYY-MM-DDTHH:MM:SS±HH:MM or YYYY-MM-DD
    if [[ ! "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}([+-][0-9]{2}:[0-9]{2}|Z)?)?$ ]]; then
        echo -e "${RED}Error: Invalid ISO 8601 date format: ${date_str}${NC}" >&2
        echo -e "${YELLOW}Expected: YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS±HH:MM${NC}" >&2
        return $INVALID
    fi

    return $VALID
}

#######################################
# Validate boolean value
# Arguments:
#   $1 - Value to validate
#   $2 - (Optional) Field name for error message
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_boolean() {
    local value="$1"
    local field_name="${2:-Boolean value}"

    case "${value,,}" in
        true|false|yes|no|1|0|on|off)
            return $VALID
            ;;
        *)
            echo -e "${RED}Error: ${field_name} must be a boolean${NC}" >&2
            echo -e "${YELLOW}Expected: true/false, yes/no, 1/0, or on/off${NC}" >&2
            echo -e "${YELLOW}Got: '${value}'${NC}" >&2
            return $INVALID
            ;;
    esac
}

#######################################
# Validate checkpoint file exists and is restorable
# Arguments:
#   $1 - Checkpoint ID
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_checkpoint_restorable() {
    local checkpoint_id="$1"

    validate_checkpoint_id "$checkpoint_id" || return $INVALID

    # Check if checkpoint exists in log
    if [[ ! -f ".workflow/checkpoints.log" ]]; then
        echo -e "${RED}Error: No checkpoints exist${NC}" >&2
        return $INVALID
    fi

    if ! grep -q "^[^|]*|${checkpoint_id}|" ".workflow/checkpoints.log" 2>/dev/null; then
        echo -e "${RED}Error: Checkpoint ${checkpoint_id} not found${NC}" >&2
        echo -e "${YELLOW}Run './scripts/checkpoint.sh list' to see available checkpoints${NC}" >&2
        return $INVALID
    fi

    # Check if snapshot exists
    local snapshot_dir=".workflow/checkpoints/snapshots/${checkpoint_id}"
    if [[ ! -d "$snapshot_dir" ]]; then
        echo -e "${YELLOW}Warning: Snapshot directory not found for ${checkpoint_id}${NC}" >&2
        echo -e "${YELLOW}Checkpoint may not be fully restorable${NC}" >&2
    fi

    return $VALID
}

#######################################
# Print usage information
#######################################
validation_usage() {
    cat << EOF
Validation Utility Library

Functions:
  validate_agent <name> [registry_file]              Validate agent name
  validate_skill <name> [catalog_file]               Validate skill name
  validate_phase <name>                              Validate phase name
  validate_checkpoint_id <id>                        Validate checkpoint ID format
  validate_project_type <type>                       Validate project type
  validate_file_exists <path> [description]          Check file exists
  validate_dir_exists <path> [description]           Check directory exists
  sanitize_path <path>                               Sanitize file path
  validate_identifier <value> [field_name]           Validate alphanumeric identifier
  validate_workflow_initialized                      Check workflow is initialized
  validate_git_repo                                  Check in git repository
  validate_number_range <value> <min> <max> [name]  Validate number range
  validate_yaml_file <path>                          Validate YAML syntax
  validate_env_var <var_name> [error_msg]           Check env var is set
  validate_email <email>                             Validate email format
  validate_url <url>                                 Validate URL format
  validate_date_iso8601 <date>                       Validate ISO 8601 date
  validate_boolean <value> [field_name]             Validate boolean value
  validate_checkpoint_restorable <id>                Check checkpoint can be restored

Return Codes:
  0 - Valid
  1 - Invalid

Example:
  source scripts/lib/validation_utils.sh
  validate_agent "researcher" || exit 1
  validate_phase "phase_1_planning" || exit 1
  sanitized=$(sanitize_path "../../etc/passwd")
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f validate_agent
    export -f validate_skill
    export -f validate_phase
    export -f validate_checkpoint_id
    export -f validate_project_type
    export -f validate_file_exists
    export -f validate_dir_exists
    export -f sanitize_path
    export -f validate_identifier
    export -f validate_workflow_initialized
    export -f validate_git_repo
    export -f validate_number_range
    export -f validate_yaml_file
    export -f validate_env_var
    export -f validate_email
    export -f validate_url
    export -f validate_date_iso8601
    export -f validate_boolean
    export -f validate_checkpoint_restorable
    export -f validation_usage
fi
