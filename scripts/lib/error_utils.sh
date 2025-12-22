#!/bin/bash
# Error Handling Utility Library
# Replaces silent failure patterns with explicit error handling
# RWF compliance (R4: Error-Free) - No silent failures

set -euo pipefail

# Source dependencies
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/logging_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging_utils.sh"
fi

# Color codes
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# Error handling configuration
ERROR_STRICT_MODE="${ERROR_STRICT_MODE:-true}"
ERROR_LOG_STACK="${ERROR_LOG_STACK:-true}"
ERROR_EXIT_ON_FATAL="${ERROR_EXIT_ON_FATAL:-true}"

# Error context
declare -a ERROR_STACK=()
ERROR_CONTEXT=""
ERROR_LAST_CODE=0
ERROR_LAST_MESSAGE=""

#######################################
# Set error context for better messages
# Arguments:
#   $1 - Context description
#######################################
set_error_context() {
    ERROR_CONTEXT="$1"
}

#######################################
# Clear error context
#######################################
clear_error_context() {
    ERROR_CONTEXT=""
}

#######################################
# Push error onto stack
# Arguments:
#   $1 - Error message
#   $2 - Exit code
#   $3 - (Optional) Source location
#######################################
push_error() {
    local message="$1"
    local code="${2:-1}"
    local source="${3:-${FUNCNAME[1]:-unknown}:${BASH_LINENO[0]:-0}}"

    ERROR_STACK+=("${source}|${code}|${message}")
    ERROR_LAST_CODE="$code"
    ERROR_LAST_MESSAGE="$message"
}

#######################################
# Get error stack as formatted string
# Returns:
#   Formatted error stack
#######################################
get_error_stack() {
    local output=""

    for entry in "${ERROR_STACK[@]}"; do
        IFS='|' read -r source code message <<< "$entry"
        output+="  at ${source}: [${code}] ${message}"$'\n'
    done

    echo "$output"
}

#######################################
# Clear error stack
#######################################
clear_error_stack() {
    ERROR_STACK=()
    ERROR_LAST_CODE=0
    ERROR_LAST_MESSAGE=""
}

#######################################
# Handle an error with logging and context
# Arguments:
#   $1 - Error message
#   $2 - (Optional) Exit code (default: 1)
#   $3 - (Optional) Action: log, warn, fatal (default: log)
# Returns:
#   Exit code on non-fatal, exits on fatal
#######################################
handle_error() {
    local message="$1"
    local code="${2:-1}"
    local action="${3:-log}"

    local source="${FUNCNAME[1]:-unknown}:${BASH_LINENO[0]:-0}"
    local full_message="$message"

    if [[ -n "$ERROR_CONTEXT" ]]; then
        full_message="[${ERROR_CONTEXT}] ${message}"
    fi

    # Push to error stack
    push_error "$message" "$code" "$source"

    # Log the error
    local component="${BASH_SOURCE[1]:-unknown}"
    component=$(basename "$component" .sh)

    case "$action" in
        warn)
            if declare -f log_warn > /dev/null 2>&1; then
                log_warn "$component" "$full_message" "exit_code=${code} source=${source}"
            else
                echo -e "${YELLOW}Warning: ${full_message}${NC}" >&2
            fi
            ;;
        fatal)
            if declare -f log_fatal > /dev/null 2>&1; then
                log_fatal "$component" "$full_message" "exit_code=${code} source=${source}"
            else
                echo -e "${RED}Fatal: ${full_message}${NC}" >&2
            fi

            if [[ "$ERROR_LOG_STACK" == "true" ]]; then
                echo -e "${RED}Error stack:${NC}" >&2
                get_error_stack >&2
            fi

            if [[ "$ERROR_EXIT_ON_FATAL" == "true" ]]; then
                exit "$code"
            fi
            ;;
        *)
            if declare -f log_error > /dev/null 2>&1; then
                log_error "$component" "$full_message" "exit_code=${code} source=${source}"
            else
                echo -e "${RED}Error: ${full_message}${NC}" >&2
            fi
            ;;
    esac

    return "$code"
}

#######################################
# Capture stderr from a command without hiding it
# REPLACES: cmd 2>/dev/null
# Arguments:
#   $@ - Command and arguments
# Returns:
#   Command exit code, stderr captured in CAPTURED_STDERR
#######################################
CAPTURED_STDERR=""
capture_error() {
    local temp_stderr
    temp_stderr=$(mktemp)

    # Run command, capture stderr
    "$@" 2>"$temp_stderr"
    local exit_code=$?

    CAPTURED_STDERR=$(cat "$temp_stderr")
    rm -f "$temp_stderr"

    # Log if there was stderr output
    if [[ -n "$CAPTURED_STDERR" && $exit_code -ne 0 ]]; then
        handle_error "Command failed: $* (stderr: ${CAPTURED_STDERR})" "$exit_code" "log"
    fi

    return $exit_code
}

#######################################
# Execute command and log on failure
# REPLACES: cmd || true
# Arguments:
#   $1 - Context description
#   $@ - Command and arguments
# Returns:
#   Command exit code (does not fail the script)
#######################################
warn_on_failure() {
    local context="$1"
    shift

    # Run command and capture exit code before it's lost
    "$@"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        handle_error "${context}: Command '$*' failed" "$exit_code" "warn"
        return $exit_code
    fi

    return 0
}

#######################################
# Execute command and fail explicitly if it fails
# REPLACES: cmd (in set -e context)
# Arguments:
#   $1 - Context description
#   $@ - Command and arguments
# Returns:
#   Command exit code, exits on failure
#######################################
require_success() {
    local context="$1"
    shift

    # Run command and capture exit code before it's lost
    "$@"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        handle_error "${context}: Required command '$*' failed" "$exit_code" "fatal"
        return $exit_code
    fi

    return 0
}

#######################################
# Safe command execution with full error capture
# Arguments:
#   $@ - Command and arguments
# Returns:
#   Command exit code
# Sets:
#   SAFE_CMD_STDOUT - stdout output
#   SAFE_CMD_STDERR - stderr output
#   SAFE_CMD_EXIT - exit code
#######################################
SAFE_CMD_STDOUT=""
SAFE_CMD_STDERR=""
SAFE_CMD_EXIT=0

safe_command() {
    local temp_stdout temp_stderr
    temp_stdout=$(mktemp)
    temp_stderr=$(mktemp)

    "$@" >"$temp_stdout" 2>"$temp_stderr"
    SAFE_CMD_EXIT=$?

    SAFE_CMD_STDOUT=$(cat "$temp_stdout")
    SAFE_CMD_STDERR=$(cat "$temp_stderr")

    rm -f "$temp_stdout" "$temp_stderr"

    return $SAFE_CMD_EXIT
}

#######################################
# Try a command, execute fallback on failure
# Arguments:
#   $1 - Primary command
#   $2 - Fallback command
# Returns:
#   Exit code from whichever succeeded
#######################################
try_with_fallback() {
    local primary="$1"
    local fallback="$2"

    if eval "$primary" 2>/dev/null; then
        return 0
    fi

    local primary_code=$?

    if declare -f log_debug > /dev/null 2>&1; then
        log_debug "error_utils" "Primary command failed, trying fallback" "primary='${primary}'"
    fi

    if eval "$fallback"; then
        return 0
    fi

    local fallback_code=$?
    handle_error "Both primary and fallback commands failed" "$fallback_code" "log"
    return $fallback_code
}

#######################################
# Set up error trap for script
# Automatically logs unhandled errors
# Arguments:
#   $1 - (Optional) Custom error handler function name
#######################################
set_error_trap() {
    local handler="${1:-_default_error_trap}"

    trap "$handler" ERR
}

#######################################
# Default error trap handler
#######################################
_default_error_trap() {
    local exit_code=$?
    local line_no="${BASH_LINENO[0]}"
    local command="${BASH_COMMAND}"
    local script="${BASH_SOURCE[1]:-unknown}"

    handle_error "Unhandled error in ${script}:${line_no}: '${command}'" "$exit_code" "log"

    # Re-raise if in strict mode
    if [[ "$ERROR_STRICT_MODE" == "true" ]]; then
        exit "$exit_code"
    fi
}

#######################################
# Clear error trap
#######################################
clear_error_trap() {
    trap - ERR
}

#######################################
# Assert condition is true
# Arguments:
#   $1 - Condition (string to eval)
#   $2 - Error message if false
# Returns:
#   0 if true, 1 and error if false
#######################################
assert() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if ! eval "$condition"; then
        handle_error "Assertion failed: ${message} (condition: ${condition})" 1 "log"
        return 1
    fi

    return 0
}

#######################################
# Assert file exists
# Arguments:
#   $1 - File path
#   $2 - (Optional) Context message
# Returns:
#   0 if exists, 1 if not
#######################################
assert_file_exists() {
    local file="$1"
    local context="${2:-Required file}"

    if [[ ! -f "$file" ]]; then
        handle_error "${context} not found: ${file}" 1 "log"
        return 1
    fi

    return 0
}

#######################################
# Assert directory exists
# Arguments:
#   $1 - Directory path
#   $2 - (Optional) Context message
# Returns:
#   0 if exists, 1 if not
#######################################
assert_dir_exists() {
    local dir="$1"
    local context="${2:-Required directory}"

    if [[ ! -d "$dir" ]]; then
        handle_error "${context} not found: ${dir}" 1 "log"
        return 1
    fi

    return 0
}

#######################################
# Assert variable is set
# Arguments:
#   $1 - Variable name
#   $2 - (Optional) Context message
# Returns:
#   0 if set, 1 if not
#######################################
assert_var_set() {
    local var_name="$1"
    local context="${2:-Required variable}"

    if [[ -z "${!var_name:-}" ]]; then
        handle_error "${context} not set: ${var_name}" 1 "log"
        return 1
    fi

    return 0
}

#######################################
# Format error for display
# Arguments:
#   $1 - Error message
#   $2 - (Optional) Error code
# Returns:
#   Formatted error string
#######################################
format_error() {
    local message="$1"
    local code="${2:-}"

    local output="${RED}Error${NC}"

    if [[ -n "$code" ]]; then
        output+=" [${code}]"
    fi

    if [[ -n "$ERROR_CONTEXT" ]]; then
        output+=" (${ERROR_CONTEXT})"
    fi

    output+=": ${message}"

    echo -e "$output"
}

#######################################
# Get last error information
# Returns:
#   Last error as "code|message"
#######################################
get_last_error() {
    echo "${ERROR_LAST_CODE}|${ERROR_LAST_MESSAGE}"
}

#######################################
# Check if there were any errors
# Returns:
#   0 if errors, 1 if no errors
#######################################
has_errors() {
    [[ ${#ERROR_STACK[@]} -gt 0 ]]
}

#######################################
# Print usage information
#######################################
error_usage() {
    cat << 'EOF'
Error Handling Utility Library - RWF Error-Free (R4)

Replaces silent failure patterns:
  cmd 2>/dev/null      -> capture_error cmd
  cmd || true          -> warn_on_failure "context" cmd
  cmd || echo "error"  -> require_success "context" cmd

Error Handling:
  handle_error <msg> [code] [action]   Handle error (log/warn/fatal)
  set_error_context <context>          Set context for messages
  clear_error_context                  Clear context

Command Execution:
  capture_error <cmd...>               Capture stderr, log on error
  warn_on_failure <ctx> <cmd...>       Log warning, continue
  require_success <ctx> <cmd...>       Log error, exit on failure
  safe_command <cmd...>                Full capture (stdout/stderr/exit)
  try_with_fallback <primary> <fallback>

Assertions:
  assert <condition> <message>         Assert condition is true
  assert_file_exists <path> [context]  Assert file exists
  assert_dir_exists <path> [context]   Assert directory exists
  assert_var_set <name> [context]      Assert variable is set

Error Stack:
  push_error <msg> <code> [source]     Add to error stack
  get_error_stack                      Get formatted stack
  clear_error_stack                    Clear stack
  has_errors                           Check if errors occurred
  get_last_error                       Get last error info

Error Trap:
  set_error_trap [handler]             Enable automatic error trap
  clear_error_trap                     Disable error trap

Configuration (env vars):
  ERROR_STRICT_MODE=true      Exit on unhandled errors
  ERROR_LOG_STACK=true        Log error stack on fatal
  ERROR_EXIT_ON_FATAL=true    Exit on fatal errors

Example:
  source scripts/lib/error_utils.sh

  set_error_context "checkpoint creation"
  set_error_trap

  # Old: yaml_set "$file" "$key" "$value" 2>/dev/null || true
  # New:
  warn_on_failure "update state" yaml_set "$file" "$key" "$value"

  # Old: if [ -f "$file" ]; then ...
  # New:
  assert_file_exists "$file" "State file" || exit 1

  clear_error_context
  clear_error_trap
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f set_error_context
    export -f clear_error_context
    export -f push_error
    export -f get_error_stack
    export -f clear_error_stack
    export -f handle_error
    export -f capture_error
    export -f warn_on_failure
    export -f require_success
    export -f safe_command
    export -f try_with_fallback
    export -f set_error_trap
    export -f clear_error_trap
    export -f _default_error_trap
    export -f assert
    export -f assert_file_exists
    export -f assert_dir_exists
    export -f assert_var_set
    export -f format_error
    export -f get_last_error
    export -f has_errors
    export -f error_usage
fi
