#!/bin/bash
# Timestamp Utility Library
# Provides consistent ISO 8601 timestamp handling - RWF compliance (R2: Completeness)
# Ensures all timestamp fields are populated and consistently formatted

set -euo pipefail

# Source dependencies
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/yaml_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/yaml_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/atomic_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/atomic_utils.sh"
fi

# Color codes
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
fi

#######################################
# Get current timestamp in ISO 8601 format
# Returns:
#   ISO 8601 timestamp (e.g., 2025-12-01T10:30:15-05:00)
#######################################
get_iso_timestamp() {
    # Try GNU date first, then BSD date
    if date -Iseconds 2>/dev/null; then
        return 0
    elif date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null; then
        return 0
    else
        # Fallback with manual timezone
        local tz_offset
        tz_offset=$(date +%z 2>/dev/null || echo "+0000")
        # Format timezone as +HH:MM
        tz_offset="${tz_offset:0:3}:${tz_offset:3:2}"
        echo "$(date +%Y-%m-%dT%H:%M:%S)${tz_offset}"
    fi
}

#######################################
# Get current timestamp in UTC
# Returns:
#   ISO 8601 timestamp in UTC (e.g., 2025-12-01T15:30:15Z)
#######################################
get_utc_timestamp() {
    if date -u -Iseconds 2>/dev/null | sed 's/+00:00$/Z/'; then
        return 0
    else
        echo "$(date -u +%Y-%m-%dT%H:%M:%S)Z"
    fi
}

#######################################
# Get current date in ISO 8601 format
# Returns:
#   ISO 8601 date (e.g., 2025-12-01)
#######################################
get_iso_date() {
    date +%Y-%m-%d
}

#######################################
# Validate ISO 8601 timestamp format
# Arguments:
#   $1 - Timestamp to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_timestamp() {
    local timestamp="$1"

    if [[ -z "$timestamp" || "$timestamp" == "null" ]]; then
        return 1
    fi

    # Full ISO 8601 with timezone
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([+-][0-9]{2}:[0-9]{2}|Z)$ ]]; then
        return 0
    fi

    # Date only
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 0
    fi

    # Without timezone (less strict)
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        return 0
    fi

    return 1
}

#######################################
# Calculate age of timestamp in seconds
# Arguments:
#   $1 - ISO 8601 timestamp
# Returns:
#   Age in seconds (stdout), 0 on error
#######################################
timestamp_age_seconds() {
    local timestamp="$1"

    if ! validate_timestamp "$timestamp"; then
        echo "0"
        return 1
    fi

    local ts_epoch now_epoch

    # Convert timestamp to epoch
    if date -d "$timestamp" +%s 2>/dev/null; then
        ts_epoch=$(date -d "$timestamp" +%s)
    elif date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%%[+-]*}" +%s 2>/dev/null; then
        # BSD date
        ts_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%%[+-]*}" +%s)
    else
        echo "0"
        return 1
    fi

    now_epoch=$(date +%s)
    echo $(( now_epoch - ts_epoch ))
}

#######################################
# Format timestamp for human display
# Arguments:
#   $1 - ISO 8601 timestamp
#   $2 - (Optional) Format (short, long, relative)
# Returns:
#   Formatted timestamp string
#######################################
format_timestamp() {
    local timestamp="$1"
    local format="${2:-short}"

    if [[ -z "$timestamp" || "$timestamp" == "null" ]]; then
        echo "never"
        return 0
    fi

    case "$format" in
        short)
            # Just date and time
            echo "${timestamp%%[+-]*}" | sed 's/T/ /'
            ;;
        long)
            # Full with timezone
            echo "$timestamp" | sed 's/T/ /'
            ;;
        relative)
            # Relative time (e.g., "5 minutes ago")
            local age
            age=$(timestamp_age_seconds "$timestamp")

            if (( age < 60 )); then
                echo "${age} seconds ago"
            elif (( age < 3600 )); then
                echo "$(( age / 60 )) minutes ago"
            elif (( age < 86400 )); then
                echo "$(( age / 3600 )) hours ago"
            else
                echo "$(( age / 86400 )) days ago"
            fi
            ;;
        *)
            echo "$timestamp"
            ;;
    esac
}

#######################################
# Compare two timestamps
# Arguments:
#   $1 - First timestamp
#   $2 - Second timestamp
# Returns:
#   -1 if first < second, 0 if equal, 1 if first > second
#######################################
compare_timestamps() {
    local ts1="$1"
    local ts2="$2"

    # Handle null/empty
    if [[ -z "$ts1" || "$ts1" == "null" ]]; then
        if [[ -z "$ts2" || "$ts2" == "null" ]]; then
            echo "0"
        else
            echo "-1"
        fi
        return 0
    fi

    if [[ -z "$ts2" || "$ts2" == "null" ]]; then
        echo "1"
        return 0
    fi

    # Simple string comparison works for ISO 8601
    if [[ "$ts1" < "$ts2" ]]; then
        echo "-1"
    elif [[ "$ts1" > "$ts2" ]]; then
        echo "1"
    else
        echo "0"
    fi
}

#######################################
# Update timestamp field in YAML file
# Uses atomic operations if available
# Arguments:
#   $1 - YAML file path
#   $2 - Field path
#   $3 - (Optional) Specific timestamp (default: current)
# Returns:
#   0 on success, 1 on failure
#######################################
update_timestamp() {
    local file="$1"
    local field="$2"
    local timestamp="${3:-$(get_iso_timestamp)}"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: ${file}${NC}" >&2
        return 1
    fi

    # Use atomic_yaml_set if available
    if declare -f atomic_yaml_set > /dev/null 2>&1; then
        atomic_yaml_set "$file" "$field" "$timestamp"
    elif declare -f yaml_set > /dev/null 2>&1; then
        yaml_set "$file" "$field" "$timestamp"
    else
        echo -e "${RED}Error: No YAML set function available${NC}" >&2
        return 1
    fi
}

#######################################
# Ensure all timestamp fields are populated
# Fills null timestamps with current time or appropriate defaults
# Arguments:
#   $1 - State file path
# Returns:
#   Number of fields updated
#######################################
ensure_all_timestamps() {
    local state_file="${1:-.workflow/state.yaml}"
    local updated_count=0
    local current_ts
    current_ts=$(get_iso_timestamp)

    if [[ ! -f "$state_file" ]]; then
        echo -e "${RED}Error: State file not found: ${state_file}${NC}" >&2
        return 1
    fi

    # List of timestamp fields to check
    local timestamp_fields=(
        "metadata.last_updated"
        "project.init_date"
        "project.last_modified"
        "session.started_at"
        "session.last_active"
        "health.last_check"
    )

    # Use transaction if available
    local use_transaction=false
    if declare -f atomic_begin > /dev/null 2>&1; then
        atomic_begin "ensure_timestamps" && use_transaction=true
    fi

    for field in "${timestamp_fields[@]}"; do
        local value
        value=$(yaml_get "$state_file" "$field" 2>/dev/null || echo "null")

        if [[ "$value" == "null" || -z "$value" ]]; then
            if update_timestamp "$state_file" "$field" "$current_ts"; then
                ((updated_count++))
            fi
        fi
    done

    if [[ "$use_transaction" == "true" ]]; then
        atomic_commit
    fi

    echo "$updated_count"
}

#######################################
# Check for stale timestamps
# Reports fields with old timestamps
# Arguments:
#   $1 - State file path
#   $2 - Max age in hours (default: 24)
# Returns:
#   List of stale fields, one per line
#######################################
check_stale_timestamps() {
    local state_file="${1:-.workflow/state.yaml}"
    local max_age_hours="${2:-24}"
    local max_age_seconds=$((max_age_hours * 3600))

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    local timestamp_fields=(
        "metadata.last_updated"
        "session.last_active"
        "health.last_check"
    )

    for field in "${timestamp_fields[@]}"; do
        local value
        value=$(yaml_get "$state_file" "$field" 2>/dev/null || echo "null")

        if [[ "$value" != "null" && -n "$value" ]]; then
            local age
            age=$(timestamp_age_seconds "$value")

            if (( age > max_age_seconds )); then
                echo "${field}:$(format_timestamp "$value" relative)"
            fi
        fi
    done
}

#######################################
# Get session duration
# Calculates time between session start and now/end
# Arguments:
#   $1 - State file path
# Returns:
#   Duration in seconds
#######################################
get_session_duration() {
    local state_file="${1:-.workflow/state.yaml}"

    local started_at
    started_at=$(yaml_get "$state_file" "session.started_at" 2>/dev/null || echo "null")

    if [[ "$started_at" == "null" || -z "$started_at" ]]; then
        echo "0"
        return 0
    fi

    timestamp_age_seconds "$started_at"
}

#######################################
# Format duration for display
# Arguments:
#   $1 - Duration in seconds
# Returns:
#   Human-readable duration
#######################################
format_duration() {
    local seconds="$1"

    if (( seconds < 60 )); then
        echo "${seconds}s"
    elif (( seconds < 3600 )); then
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${mins}m ${secs}s"
    elif (( seconds < 86400 )); then
        local hours=$((seconds / 3600))
        local mins=$(( (seconds % 3600) / 60 ))
        echo "${hours}h ${mins}m"
    else
        local days=$((seconds / 86400))
        local hours=$(( (seconds % 86400) / 3600 ))
        echo "${days}d ${hours}h"
    fi
}

#######################################
# Touch session activity timestamp
# Updates session.last_active to current time
# Arguments:
#   $1 - State file path (default: .workflow/state.yaml)
# Returns:
#   0 on success
#######################################
touch_session() {
    local state_file="${1:-.workflow/state.yaml}"

    update_timestamp "$state_file" "session.last_active"
}

#######################################
# Start session tracking
# Sets session.started_at and session.last_active
# Arguments:
#   $1 - State file path
#   $2 - (Optional) Session ID
# Returns:
#   0 on success
#######################################
start_session() {
    local state_file="${1:-.workflow/state.yaml}"
    local session_id="${2:-session_$(date +%s)_$$}"
    local current_ts
    current_ts=$(get_iso_timestamp)

    if [[ ! -f "$state_file" ]]; then
        echo -e "${RED}Error: State file not found${NC}" >&2
        return 1
    fi

    # Use transaction if available
    if declare -f atomic_begin > /dev/null 2>&1; then
        atomic_begin "start_session"
        atomic_yaml_set "$state_file" "session.id" "$session_id"
        atomic_yaml_set "$state_file" "session.started_at" "$current_ts"
        atomic_yaml_set "$state_file" "session.last_active" "$current_ts"
        atomic_yaml_set "$state_file" "session.context_recovered" "true"
        atomic_commit
    else
        yaml_set "$state_file" "session.id" "$session_id"
        yaml_set "$state_file" "session.started_at" "$current_ts"
        yaml_set "$state_file" "session.last_active" "$current_ts"
        yaml_set "$state_file" "session.context_recovered" "true"
    fi

    return 0
}

#######################################
# Print usage information
#######################################
timestamp_usage() {
    cat << 'EOF'
Timestamp Utility Library - RWF Completeness (R2)

Timestamp Generation:
  get_iso_timestamp            Get current ISO 8601 timestamp with timezone
  get_utc_timestamp            Get current UTC timestamp
  get_iso_date                 Get current date only

Validation & Comparison:
  validate_timestamp <ts>      Validate ISO 8601 format
  compare_timestamps <a> <b>   Compare two timestamps (-1, 0, 1)
  timestamp_age_seconds <ts>   Get age in seconds

Formatting:
  format_timestamp <ts> [fmt]  Format for display (short, long, relative)
  format_duration <secs>       Format duration (e.g., "2h 15m")

State Management:
  update_timestamp <file> <field> [ts]   Update timestamp field
  ensure_all_timestamps [file]           Fill null timestamps
  check_stale_timestamps [file] [hours]  Report stale fields
  touch_session [file]                   Update session.last_active
  start_session [file] [session_id]      Initialize session timestamps
  get_session_duration [file]            Get session duration in seconds

Example:
  source scripts/lib/timestamp_utils.sh

  # Get current timestamp
  ts=$(get_iso_timestamp)
  echo "Current: $ts"

  # Update state file
  update_timestamp ".workflow/state.yaml" "metadata.last_updated"

  # Check for stale fields
  check_stale_timestamps ".workflow/state.yaml" 24

  # Format for display
  echo "Session started $(format_timestamp "$ts" relative)"
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f get_iso_timestamp
    export -f get_utc_timestamp
    export -f get_iso_date
    export -f validate_timestamp
    export -f timestamp_age_seconds
    export -f format_timestamp
    export -f compare_timestamps
    export -f update_timestamp
    export -f ensure_all_timestamps
    export -f check_stale_timestamps
    export -f get_session_duration
    export -f format_duration
    export -f touch_session
    export -f start_session
    export -f timestamp_usage
fi
