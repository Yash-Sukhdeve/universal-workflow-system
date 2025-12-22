#!/bin/bash
# Dependency Validation Utility Library
# Provides pre-flight checks for required tools and environment
# RWF Compliance: R4 (Error-Free) - Validate dependencies before execution

set -euo pipefail

# Color codes for output (only set if not already defined)
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# Minimum bash version required
readonly MIN_BASH_VERSION="4.0"

# Required commands for core functionality
readonly CORE_DEPS=("grep" "sed" "date" "cat" "mkdir" "cp" "rm")

# Optional commands that enhance functionality
readonly OPTIONAL_DEPS=("yq" "git" "jq")

#######################################
# Check if a command exists
# Arguments:
#   $1 - Command name
# Returns:
#   0 if command exists, 1 otherwise
#######################################
command_exists() {
    command -v "$1" &> /dev/null
}

#######################################
# Get version of a command
# Arguments:
#   $1 - Command name
# Returns:
#   Version string or "unknown"
#######################################
get_command_version() {
    local cmd="$1"

    case "$cmd" in
        bash)
            echo "${BASH_VERSION:-unknown}"
            ;;
        git)
            git --version 2>/dev/null | head -1 | cut -d' ' -f3 || echo "unknown"
            ;;
        yq)
            yq --version 2>/dev/null | head -1 || echo "unknown"
            ;;
        jq)
            jq --version 2>/dev/null || echo "unknown"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

#######################################
# Compare version strings
# Arguments:
#   $1 - Version 1
#   $2 - Version 2
# Returns:
#   0 if v1 >= v2, 1 otherwise
#######################################
version_gte() {
    local v1="$1"
    local v2="$2"

    # Simple comparison - extract major.minor
    local v1_major v1_minor v2_major v2_minor
    v1_major=$(echo "$v1" | cut -d. -f1)
    v1_minor=$(echo "$v1" | cut -d. -f2 | cut -d- -f1 | cut -d'(' -f1)
    v2_major=$(echo "$v2" | cut -d. -f1)
    v2_minor=$(echo "$v2" | cut -d. -f2)

    # Default to 0 if extraction fails
    v1_major=${v1_major:-0}
    v1_minor=${v1_minor:-0}
    v2_major=${v2_major:-0}
    v2_minor=${v2_minor:-0}

    if (( v1_major > v2_major )); then
        return 0
    elif (( v1_major == v2_major && v1_minor >= v2_minor )); then
        return 0
    else
        return 1
    fi
}

#######################################
# Validate bash version meets minimum
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_bash_version() {
    local current_version="${BASH_VERSION:-0.0}"

    if version_gte "$current_version" "$MIN_BASH_VERSION"; then
        return 0
    else
        echo -e "${RED}Error: Bash version $MIN_BASH_VERSION or higher required.${NC}" >&2
        echo -e "  Current version: $current_version" >&2
        return 1
    fi
}

#######################################
# Validate all core dependencies exist
# Returns:
#   0 if all exist, 1 otherwise
#######################################
validate_core_dependencies() {
    local missing=()

    for dep in "${CORE_DEPS[@]}"; do
        if ! command_exists "$dep"; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies:${NC}" >&2
        for dep in "${missing[@]}"; do
            echo -e "  - $dep" >&2
        done
        return 1
    fi

    return 0
}

#######################################
# Check optional dependencies and report
# Returns:
#   Always 0 (warnings only)
#######################################
check_optional_dependencies() {
    local missing=()

    for dep in "${OPTIONAL_DEPS[@]}"; do
        if ! command_exists "$dep"; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]] && [[ "${DEPENDENCY_UTILS_QUIET:-false}" != "true" ]]; then
        echo -e "${YELLOW}Note: Optional dependencies not found:${NC}" >&2
        for dep in "${missing[@]}"; do
            case "$dep" in
                yq)
                    echo -e "  - yq (YAML parsing - using fallback)" >&2
                    ;;
                git)
                    echo -e "  - git (version control features disabled)" >&2
                    ;;
                jq)
                    echo -e "  - jq (JSON parsing - using fallback)" >&2
                    ;;
                *)
                    echo -e "  - $dep" >&2
                    ;;
            esac
        done
    fi

    return 0
}

#######################################
# Validate workflow directory structure
# Arguments:
#   $1 - Workflow directory path (optional, defaults to .workflow)
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_workflow_structure() {
    local workflow_dir="${1:-.workflow}"

    if [[ ! -d "$workflow_dir" ]]; then
        echo -e "${RED}Error: Workflow directory not found: $workflow_dir${NC}" >&2
        echo -e "  Run: ${CYAN}./scripts/init_workflow.sh${NC}" >&2
        return 1
    fi

    # Check for essential files
    local essential_files=("state.yaml")
    local missing=()

    for file in "${essential_files[@]}"; do
        if [[ ! -f "$workflow_dir/$file" ]]; then
            missing+=("$file")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing essential workflow files:${NC}" >&2
        for file in "${missing[@]}"; do
            echo -e "  - $workflow_dir/$file" >&2
        done
        return 1
    fi

    return 0
}

#######################################
# Validate file is readable
# Arguments:
#   $1 - File path
# Returns:
#   0 if readable, 1 otherwise
#######################################
validate_file_readable() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: $file${NC}" >&2
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        echo -e "${RED}Error: File not readable: $file${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Validate file is writable
# Arguments:
#   $1 - File path
# Returns:
#   0 if writable, 1 otherwise
#######################################
validate_file_writable() {
    local file="$1"

    if [[ -f "$file" ]]; then
        if [[ ! -w "$file" ]]; then
            echo -e "${RED}Error: File not writable: $file${NC}" >&2
            return 1
        fi
    else
        # Check if directory is writable
        local dir
        dir=$(dirname "$file")
        if [[ ! -w "$dir" ]]; then
            echo -e "${RED}Error: Directory not writable: $dir${NC}" >&2
            return 1
        fi
    fi

    return 0
}

#######################################
# Validate directory exists and is writable
# Arguments:
#   $1 - Directory path
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_directory_writable() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}Error: Directory not found: $dir${NC}" >&2
        return 1
    fi

    if [[ ! -w "$dir" ]]; then
        echo -e "${RED}Error: Directory not writable: $dir${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Run all pre-flight checks
# Arguments:
#   $1 - Workflow directory (optional)
# Returns:
#   0 if all pass, 1 otherwise
#######################################
run_preflight_checks() {
    local workflow_dir="${1:-.workflow}"
    local errors=0

    # Check bash version
    if ! validate_bash_version; then
        ((errors++))
    fi

    # Check core dependencies
    if ! validate_core_dependencies; then
        ((errors++))
    fi

    # Check optional dependencies (warnings only)
    check_optional_dependencies

    # Check workflow structure
    if ! validate_workflow_structure "$workflow_dir"; then
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}Pre-flight checks failed with $errors error(s)${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Require a specific command exists
# Arguments:
#   $1 - Command name
#   $2 - Error message (optional)
# Returns:
#   0 if exists, exits with 1 otherwise
#######################################
require_command() {
    local cmd="$1"
    local msg="${2:-Command '$cmd' is required but not found}"

    if ! command_exists "$cmd"; then
        echo -e "${RED}Error: $msg${NC}" >&2
        exit 1
    fi
}

#######################################
# Require workflow is initialized
# Arguments:
#   $1 - Workflow directory (optional)
# Returns:
#   0 if initialized, exits with 1 otherwise
#######################################
require_workflow_initialized() {
    local workflow_dir="${1:-.workflow}"

    if ! validate_workflow_structure "$workflow_dir"; then
        exit 1
    fi
}

#######################################
# Print dependency status report
#######################################
print_dependency_status() {
    echo -e "${CYAN}Dependency Status Report${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Bash version
    local bash_ver="${BASH_VERSION:-unknown}"
    if version_gte "$bash_ver" "$MIN_BASH_VERSION"; then
        echo -e "  ${GREEN}✓${NC} bash: $bash_ver"
    else
        echo -e "  ${RED}✗${NC} bash: $bash_ver (need >= $MIN_BASH_VERSION)"
    fi

    # Core dependencies
    echo -e ""
    echo -e "  ${CYAN}Core Dependencies:${NC}"
    for dep in "${CORE_DEPS[@]}"; do
        if command_exists "$dep"; then
            echo -e "    ${GREEN}✓${NC} $dep"
        else
            echo -e "    ${RED}✗${NC} $dep (MISSING)"
        fi
    done

    # Optional dependencies
    echo -e ""
    echo -e "  ${CYAN}Optional Dependencies:${NC}"
    for dep in "${OPTIONAL_DEPS[@]}"; do
        if command_exists "$dep"; then
            local ver
            ver=$(get_command_version "$dep")
            echo -e "    ${GREEN}✓${NC} $dep: $ver"
        else
            echo -e "    ${YELLOW}○${NC} $dep (not installed)"
        fi
    done

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f command_exists
    export -f get_command_version
    export -f version_gte
    export -f validate_bash_version
    export -f validate_core_dependencies
    export -f check_optional_dependencies
    export -f validate_workflow_structure
    export -f validate_file_readable
    export -f validate_file_writable
    export -f validate_directory_writable
    export -f run_preflight_checks
    export -f require_command
    export -f require_workflow_initialized
    export -f print_dependency_status
fi

# If run directly, print status
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_dependency_status
fi
