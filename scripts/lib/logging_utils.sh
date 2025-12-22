#!/bin/bash
# Logging Utility Library
# Provides structured logging for audit trail - RWF compliance (R1: Truthfulness)
# All operations are logged for complete traceability

set -euo pipefail

# Source dependencies
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/timestamp_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/timestamp_utils.sh"
fi

# Color codes
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# Log configuration
LOG_DIR="${LOG_DIR:-.workflow/logs}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_TO_STDERR="${LOG_TO_STDERR:-true}"
LOG_STRUCTURED="${LOG_STRUCTURED:-true}"
LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-10}"
LOG_MAX_FILES="${LOG_MAX_FILES:-5}"

# Log files
LOG_EXECUTION="${LOG_DIR}/execution.log"
LOG_ERRORS="${LOG_DIR}/errors.log"
LOG_DEBUG="${LOG_DIR}/debug.log"

# Log levels defined in get_log_level_value() function for better portability

# Current script name for logging context
LOG_SCRIPT="${LOG_SCRIPT:-$(basename "${BASH_SOURCE[1]:-unknown}")}"

#######################################
# Initialize logging system
# Creates log directory and files
# Returns:
#   0 on success
#######################################
log_init() {
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" || {
            echo -e "${RED}Error: Cannot create log directory: ${LOG_DIR}${NC}" >&2
            return 1
        }
    fi

    # Create log files if they don't exist
    touch "$LOG_EXECUTION" 2>/dev/null || true
    touch "$LOG_ERRORS" 2>/dev/null || true

    return 0
}

#######################################
# Convert log level to numeric value
# Arguments:
#   $1 - Log level name
# Returns:
#   Numeric level (0-4)
#######################################
get_log_level_value() {
    local level="${1:-INFO}"
    case "$level" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        FATAL) echo 4 ;;
        *)     echo 1 ;;
    esac
}

#######################################
# Check if log level should be logged
# Arguments:
#   $1 - Log level to check
# Returns:
#   0 if should log, 1 if should skip
#######################################
should_log() {
    local level="$1"
    local current_level
    local check_level
    current_level=$(get_log_level_value "$LOG_LEVEL")
    check_level=$(get_log_level_value "$level")

    (( check_level >= current_level ))
}

#######################################
# Get current timestamp for logging
# Returns:
#   ISO 8601 timestamp
#######################################
log_timestamp() {
    if declare -f get_iso_timestamp > /dev/null 2>&1; then
        get_iso_timestamp
    else
        date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z
    fi
}

#######################################
# Write structured log entry
# Arguments:
#   $1 - Log level (DEBUG, INFO, WARN, ERROR, FATAL)
#   $2 - Component/script name
#   $3 - Message
#   $4 - (Optional) Additional context as key=value pairs
# Returns:
#   0 on success
#######################################
log_write() {
    local level="$1"
    local component="$2"
    local message="$3"
    shift 3
    local context="$*"

    # Check log level
    if ! should_log "$level"; then
        return 0
    fi

    local timestamp
    timestamp=$(log_timestamp)

    # Structured format: TIMESTAMP|LEVEL|COMPONENT|MESSAGE|CONTEXT
    local log_entry
    if [[ "$LOG_STRUCTURED" == "true" ]]; then
        log_entry="${timestamp}|${level}|${component}|${message}"
        if [[ -n "$context" ]]; then
            log_entry="${log_entry}|${context}"
        fi
    else
        log_entry="[${timestamp}] [${level}] [${component}] ${message}"
        if [[ -n "$context" ]]; then
            log_entry="${log_entry} (${context})"
        fi
    fi

    # Write to appropriate log file
    local log_file="$LOG_EXECUTION"
    if [[ "$level" == "ERROR" || "$level" == "FATAL" ]]; then
        log_file="$LOG_ERRORS"
        # Also write to execution log for complete history
        echo "$log_entry" >> "$LOG_EXECUTION" 2>/dev/null || true
    elif [[ "$level" == "DEBUG" ]]; then
        log_file="$LOG_DEBUG"
    fi

    echo "$log_entry" >> "$log_file" 2>/dev/null || true

    # Output to stderr if enabled
    if [[ "$LOG_TO_STDERR" == "true" ]]; then
        local color
        case "$level" in
            DEBUG) color="$CYAN" ;;
            INFO)  color="$GREEN" ;;
            WARN)  color="$YELLOW" ;;
            ERROR) color="$RED" ;;
            FATAL) color="$RED" ;;
            *)     color="$NC" ;;
        esac

        if [[ "$LOG_STRUCTURED" == "true" ]]; then
            echo -e "${color}[${level}]${NC} ${message}" >&2
        else
            echo -e "${color}${log_entry}${NC}" >&2
        fi
    fi

    return 0
}

#######################################
# Log DEBUG message
# Arguments:
#   $1 - Component name
#   $2 - Message
#   $@ - Additional context
#######################################
log_debug() {
    local component="${1:-$LOG_SCRIPT}"
    local message="$2"
    shift 2 || true
    log_write "DEBUG" "$component" "$message" "$@"
}

#######################################
# Log INFO message
# Arguments:
#   $1 - Component name
#   $2 - Message
#   $@ - Additional context
#######################################
log_info() {
    local component="${1:-$LOG_SCRIPT}"
    local message="$2"
    shift 2 || true
    log_write "INFO" "$component" "$message" "$@"
}

#######################################
# Log WARN message
# Arguments:
#   $1 - Component name
#   $2 - Message
#   $@ - Additional context
#######################################
log_warn() {
    local component="${1:-$LOG_SCRIPT}"
    local message="$2"
    shift 2 || true
    log_write "WARN" "$component" "$message" "$@"
}

#######################################
# Log ERROR message
# Arguments:
#   $1 - Component name
#   $2 - Message
#   $@ - Additional context
#######################################
log_error() {
    local component="${1:-$LOG_SCRIPT}"
    local message="$2"
    shift 2 || true
    log_write "ERROR" "$component" "$message" "$@"
}

#######################################
# Log FATAL message (implies process will exit)
# Arguments:
#   $1 - Component name
#   $2 - Message
#   $@ - Additional context
#######################################
log_fatal() {
    local component="${1:-$LOG_SCRIPT}"
    local message="$2"
    shift 2 || true
    log_write "FATAL" "$component" "$message" "$@"
}

#######################################
# Log operation with timing
# Arguments:
#   $1 - Component name
#   $2 - Operation name
#   $3 - Status (start, success, failed)
#   $4 - (Optional) Duration in milliseconds
#   $@ - Additional context
#######################################
log_operation() {
    local component="$1"
    local operation="$2"
    local status="$3"
    local duration="${4:-}"
    shift 4 || true
    local context="$*"

    local message="Operation: ${operation}"
    local full_context="status=${status}"

    if [[ -n "$duration" ]]; then
        full_context="${full_context} duration=${duration}ms"
    fi

    if [[ -n "$context" ]]; then
        full_context="${full_context} ${context}"
    fi

    case "$status" in
        start)
            log_info "$component" "$message started" "$full_context"
            ;;
        success)
            log_info "$component" "$message completed" "$full_context"
            ;;
        failed)
            log_error "$component" "$message failed" "$full_context"
            ;;
        *)
            log_info "$component" "$message" "$full_context"
            ;;
    esac
}

#######################################
# Log checkpoint operation
# Arguments:
#   $1 - Action (create, restore, list)
#   $2 - Checkpoint ID
#   $3 - Status (success, failed)
#   $4 - (Optional) Additional message
#######################################
log_checkpoint() {
    local action="$1"
    local checkpoint_id="$2"
    local status="$3"
    local message="${4:-}"

    log_operation "checkpoint.sh" "checkpoint_${action}" "$status" "" \
        "checkpoint_id=${checkpoint_id}" \
        ${message:+"message=\"${message}\""}
}

#######################################
# Log agent operation
# Arguments:
#   $1 - Action (activate, deactivate, handoff)
#   $2 - Agent name
#   $3 - Status
#   $4 - (Optional) Additional context
#######################################
log_agent() {
    local action="$1"
    local agent_name="$2"
    local status="$3"
    local context="${4:-}"

    log_operation "activate_agent.sh" "agent_${action}" "$status" "" \
        "agent=${agent_name}" \
        ${context:+"${context}"}
}

#######################################
# Log recovery operation
# Arguments:
#   $1 - Status (start, success, partial, failed)
#   $2 - Completeness score (0-100)
#   $3 - (Optional) Details
#######################################
log_recovery() {
    local status="$1"
    local completeness="${2:-}"
    local details="${3:-}"

    log_operation "recover_context.sh" "context_recovery" "$status" "" \
        ${completeness:+"completeness=${completeness}%"} \
        ${details:+"details=\"${details}\""}
}

#######################################
# Rotate log file if too large
# Arguments:
#   $1 - Log file path
# Returns:
#   0 on success
#######################################
rotate_log() {
    local log_file="$1"

    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    local size_bytes
    size_bytes=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo "0")
    local max_bytes=$((LOG_MAX_SIZE_MB * 1024 * 1024))

    if (( size_bytes > max_bytes )); then
        local base_name="$log_file"
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)

        # Rotate existing files
        for ((i = LOG_MAX_FILES - 1; i >= 1; i--)); do
            local j=$((i + 1))
            if [[ -f "${base_name}.${i}" ]]; then
                if (( j >= LOG_MAX_FILES )); then
                    rm -f "${base_name}.${i}"
                else
                    mv "${base_name}.${i}" "${base_name}.${j}"
                fi
            fi
        done

        # Rotate current log
        mv "$log_file" "${base_name}.1"
        touch "$log_file"

        log_info "logging" "Rotated log file" "file=${log_file}"
    fi

    return 0
}

#######################################
# Rotate all log files
#######################################
rotate_all_logs() {
    rotate_log "$LOG_EXECUTION"
    rotate_log "$LOG_ERRORS"
    rotate_log "$LOG_DEBUG"
}

#######################################
# Get recent log entries
# Arguments:
#   $1 - Log file (execution, errors, debug)
#   $2 - Number of lines (default: 20)
#   $3 - (Optional) Filter pattern
# Returns:
#   Recent log entries
#######################################
get_recent_logs() {
    local log_type="${1:-execution}"
    local count="${2:-20}"
    local filter="${3:-}"

    local log_file
    case "$log_type" in
        execution) log_file="$LOG_EXECUTION" ;;
        errors)    log_file="$LOG_ERRORS" ;;
        debug)     log_file="$LOG_DEBUG" ;;
        *)         log_file="$log_type" ;;
    esac

    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    if [[ -n "$filter" ]]; then
        grep "$filter" "$log_file" | tail -n "$count"
    else
        tail -n "$count" "$log_file"
    fi
}

#######################################
# Search logs
# Arguments:
#   $1 - Search pattern
#   $2 - (Optional) Log type (execution, errors, all)
#   $3 - (Optional) Max results
# Returns:
#   Matching log entries
#######################################
search_logs() {
    local pattern="$1"
    local log_type="${2:-all}"
    local max_results="${3:-100}"

    case "$log_type" in
        execution)
            grep -h "$pattern" "$LOG_EXECUTION" 2>/dev/null | head -n "$max_results"
            ;;
        errors)
            grep -h "$pattern" "$LOG_ERRORS" 2>/dev/null | head -n "$max_results"
            ;;
        all)
            grep -h "$pattern" "$LOG_DIR"/*.log 2>/dev/null | head -n "$max_results"
            ;;
    esac
}

#######################################
# Get log statistics
# Returns:
#   Log statistics as key=value pairs
#######################################
get_log_stats() {
    local exec_lines=0 error_lines=0 exec_size=0 error_size=0

    if [[ -f "$LOG_EXECUTION" ]]; then
        exec_lines=$(wc -l < "$LOG_EXECUTION" 2>/dev/null || echo "0")
        exec_size=$(stat -f%z "$LOG_EXECUTION" 2>/dev/null || stat -c%s "$LOG_EXECUTION" 2>/dev/null || echo "0")
    fi

    if [[ -f "$LOG_ERRORS" ]]; then
        error_lines=$(wc -l < "$LOG_ERRORS" 2>/dev/null || echo "0")
        error_size=$(stat -f%z "$LOG_ERRORS" 2>/dev/null || stat -c%s "$LOG_ERRORS" 2>/dev/null || echo "0")
    fi

    echo "execution_entries=${exec_lines}"
    echo "error_entries=${error_lines}"
    echo "execution_size_bytes=${exec_size}"
    echo "error_size_bytes=${error_size}"
}

#######################################
# Clear old log entries
# Arguments:
#   $1 - Max age in days
# Returns:
#   Number of lines removed
#######################################
clear_old_logs() {
    local max_age_days="${1:-30}"
    local cutoff_date
    cutoff_date=$(date -d "-${max_age_days} days" +%Y-%m-%d 2>/dev/null || \
                  date -v-${max_age_days}d +%Y-%m-%d 2>/dev/null || \
                  echo "")

    if [[ -z "$cutoff_date" ]]; then
        echo -e "${YELLOW}Warning: Cannot calculate cutoff date${NC}" >&2
        return 0
    fi

    local removed=0

    for log_file in "$LOG_EXECUTION" "$LOG_ERRORS"; do
        if [[ -f "$log_file" ]]; then
            local temp_file="${log_file}.tmp"
            local before_count after_count

            before_count=$(wc -l < "$log_file")

            # Keep only entries with dates >= cutoff
            awk -F'|' -v cutoff="$cutoff_date" '
                $1 >= cutoff || $1 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ { print }
            ' "$log_file" > "$temp_file"

            mv "$temp_file" "$log_file"

            after_count=$(wc -l < "$log_file")
            removed=$((removed + before_count - after_count))
        fi
    done

    echo "$removed"
}

#######################################
# Print usage information
#######################################
logging_usage() {
    cat << 'EOF'
Logging Utility Library - RWF Truthfulness (R1)

Configuration (environment variables):
  LOG_DIR          Log directory (default: .workflow/logs)
  LOG_LEVEL        Minimum level to log (DEBUG, INFO, WARN, ERROR, FATAL)
  LOG_TO_STDERR    Output to stderr (true/false)
  LOG_STRUCTURED   Use structured format (true/false)
  LOG_MAX_SIZE_MB  Max log file size before rotation
  LOG_MAX_FILES    Number of rotated files to keep

Basic Logging:
  log_debug <component> <message> [context]   Debug level
  log_info <component> <message> [context]    Info level
  log_warn <component> <message> [context]    Warning level
  log_error <component> <message> [context]   Error level
  log_fatal <component> <message> [context]   Fatal level

Structured Logging:
  log_operation <component> <op> <status> [duration] [context]
  log_checkpoint <action> <id> <status> [message]
  log_agent <action> <agent> <status> [context]
  log_recovery <status> [completeness] [details]

Log Management:
  log_init                                    Initialize logging
  rotate_log <file>                           Rotate single log
  rotate_all_logs                             Rotate all logs
  get_recent_logs [type] [count] [filter]     Get recent entries
  search_logs <pattern> [type] [max]          Search logs
  get_log_stats                               Get statistics
  clear_old_logs [days]                       Remove old entries

Log Format (structured):
  TIMESTAMP|LEVEL|COMPONENT|MESSAGE|key=value key=value

Example:
  source scripts/lib/logging_utils.sh
  log_init

  log_info "checkpoint.sh" "Creating checkpoint" "id=CP_1_009"
  log_operation "checkpoint.sh" "create" "success" "45" "id=CP_1_009"
  log_checkpoint "create" "CP_1_009" "success" "Manual checkpoint"
EOF
}

# Initialize logging on source
log_init 2>/dev/null || true

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f log_init
    export -f get_log_level_value
    export -f should_log
    export -f log_timestamp
    export -f log_write
    export -f log_debug
    export -f log_info
    export -f log_warn
    export -f log_error
    export -f log_fatal
    export -f log_operation
    export -f log_checkpoint
    export -f log_agent
    export -f log_recovery
    export -f rotate_log
    export -f rotate_all_logs
    export -f get_recent_logs
    export -f search_logs
    export -f get_log_stats
    export -f clear_old_logs
    export -f logging_usage
fi
