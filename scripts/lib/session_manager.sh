#!/bin/bash
# Session Manager - Multi-Agent Session Tracking
# Manages concurrent agent sessions for real-time dashboard monitoring

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Sessions file
SESSIONS_FILE="${PROJECT_ROOT}/.workflow/agents/sessions.yaml"

# Agent icons and colors
declare -A AGENT_ICONS=(
    ["researcher"]="🔬"
    ["architect"]="🏗️"
    ["implementer"]="💻"
    ["experimenter"]="🧪"
    ["optimizer"]="⚡"
    ["deployer"]="🚀"
    ["documenter"]="📝"
)

declare -A AGENT_COLORS=(
    ["researcher"]="#3498db"
    ["architect"]="#9b59b6"
    ["implementer"]="#2ecc71"
    ["experimenter"]="#e67e22"
    ["optimizer"]="#e74c3c"
    ["deployer"]="#1abc9c"
    ["documenter"]="#f1c40f"
)

# Ensure sessions file exists
ensure_sessions_file() {
    if [[ ! -f "$SESSIONS_FILE" ]]; then
        mkdir -p "$(dirname "$SESSIONS_FILE")"
        cat > "$SESSIONS_FILE" << 'EOF'
# Multi-Agent Session Tracking
sessions: []
history: []
config:
  max_concurrent_agents: 10
  history_retention_days: 7
  auto_cleanup: true
EOF
    fi
}

# Generate unique session ID
generate_session_id() {
    echo "sess_$(date +%s)_$$"
}

# Create a new agent session
# Usage: create_agent_session <agent_type> <task_description>
create_agent_session() {
    local agent_type="$1"
    local task="${2:-No task specified}"

    ensure_sessions_file

    local session_id
    session_id=$(generate_session_id)
    local timestamp
    timestamp=$(date -Iseconds)
    local icon="${AGENT_ICONS[$agent_type]:-🤖}"
    local color="${AGENT_COLORS[$agent_type]:-#888888}"

    # Create temp file with updated sessions
    local temp_file
    temp_file=$(mktemp)

    local added=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        echo "$line" >> "$temp_file"
        # Add session entry after "sessions:" line
        if [[ "$line" == "sessions:"* ]] && [[ "$added" == "false" ]]; then
            echo "  - id: \"${session_id}\"" >> "$temp_file"
            echo "    agent: \"${agent_type}\"" >> "$temp_file"
            echo "    icon: \"${icon}\"" >> "$temp_file"
            echo "    color: \"${color}\"" >> "$temp_file"
            echo "    task: \"${task}\"" >> "$temp_file"
            echo "    status: \"active\"" >> "$temp_file"
            echo "    progress: 0" >> "$temp_file"
            echo "    started_at: \"${timestamp}\"" >> "$temp_file"
            echo "    updated_at: \"${timestamp}\"" >> "$temp_file"
            added=true
        fi
    done < "$SESSIONS_FILE"

    # Handle empty sessions array
    if [[ "$added" == "false" ]]; then
        # File didn't have sessions: line, create new structure
        cat > "$temp_file" << EOF
# Multi-Agent Session Tracking
sessions:
  - id: "${session_id}"
    agent: "${agent_type}"
    icon: "${icon}"
    color: "${color}"
    task: "${task}"
    status: "active"
    progress: 0
    started_at: "${timestamp}"
    updated_at: "${timestamp}"

history: []

config:
  max_concurrent_agents: 10
  history_retention_days: 7
  auto_cleanup: true
EOF
    fi

    # Remove "sessions: []" line if present (empty array marker)
    sed -i 's/^sessions: \[\]/sessions:/' "$temp_file"

    mv "$temp_file" "$SESSIONS_FILE"

    echo "$session_id"

    # Notify via webhook if configured
    notify_session_change "agent_started" "$session_id" "$agent_type" "$task"
}

# Update session progress
# Usage: update_session_progress <session_id> <progress> [status] [task_update]
update_session_progress() {
    local session_id="$1"
    local progress="$2"
    local status="${3:-active}"
    local task_update="${4:-}"

    ensure_sessions_file

    local timestamp
    timestamp=$(date -Iseconds)

    # Update progress in sessions file
    if command -v yq &> /dev/null; then
        yq -i "(.sessions[] | select(.id == \"${session_id}\")).progress = ${progress}" "$SESSIONS_FILE"
        yq -i "(.sessions[] | select(.id == \"${session_id}\")).status = \"${status}\"" "$SESSIONS_FILE"
        yq -i "(.sessions[] | select(.id == \"${session_id}\")).updated_at = \"${timestamp}\"" "$SESSIONS_FILE"
        if [[ -n "$task_update" ]]; then
            yq -i "(.sessions[] | select(.id == \"${session_id}\")).task = \"${task_update}\"" "$SESSIONS_FILE"
        fi
    else
        # Fallback: recreate sessions file with updated values
        local temp_file
        temp_file=$(mktemp)

        local in_target_session=false
        while IFS= read -r line; do
            if [[ "$line" =~ id:.*\"${session_id}\" ]]; then
                in_target_session=true
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*id: ]] && [[ "$in_target_session" == "true" ]]; then
                in_target_session=false
            fi

            if [[ "$in_target_session" == "true" ]]; then
                if [[ "$line" =~ progress: ]]; then
                    echo "    progress: ${progress}" >> "$temp_file"
                elif [[ "$line" =~ status: ]]; then
                    echo "    status: \"${status}\"" >> "$temp_file"
                elif [[ "$line" =~ updated_at: ]]; then
                    echo "    updated_at: \"${timestamp}\"" >> "$temp_file"
                elif [[ -n "$task_update" ]] && [[ "$line" =~ task: ]]; then
                    echo "    task: \"${task_update}\"" >> "$temp_file"
                else
                    echo "$line" >> "$temp_file"
                fi
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$SESSIONS_FILE"

        mv "$temp_file" "$SESSIONS_FILE"
    fi

    # Notify
    notify_session_change "agent_progress" "$session_id" "" "" "$progress"
}

# End an agent session (complete or cancel)
# Usage: end_agent_session <session_id> [result: success|failed|cancelled]
end_agent_session() {
    local session_id="$1"
    local result="${2:-success}"

    ensure_sessions_file

    local timestamp
    timestamp=$(date -Iseconds)

    # Get session data before removing
    local agent_type task
    if command -v yq &> /dev/null; then
        agent_type=$(yq ".sessions[] | select(.id == \"${session_id}\") | .agent" "$SESSIONS_FILE" 2>/dev/null | tr -d '"')
        task=$(yq ".sessions[] | select(.id == \"${session_id}\") | .task" "$SESSIONS_FILE" 2>/dev/null | tr -d '"')
    else
        agent_type=$(grep -A5 "id: \"${session_id}\"" "$SESSIONS_FILE" | grep "agent:" | head -1 | sed 's/.*agent: "\([^"]*\)".*/\1/')
        task=$(grep -A5 "id: \"${session_id}\"" "$SESSIONS_FILE" | grep "task:" | head -1 | sed 's/.*task: "\([^"]*\)".*/\1/')
    fi

    # Move session to history
    local history_entry="  - id: \"${session_id}\"
    agent: \"${agent_type}\"
    task: \"${task}\"
    result: \"${result}\"
    completed_at: \"${timestamp}\""

    # Add to history
    if grep -q "^history: \[\]" "$SESSIONS_FILE"; then
        sed -i "s/^history: \[\]/history:\n${history_entry}/" "$SESSIONS_FILE"
    else
        sed -i "/^history:/a\\${history_entry}" "$SESSIONS_FILE"
    fi

    # Remove from active sessions
    if command -v yq &> /dev/null; then
        yq -i "del(.sessions[] | select(.id == \"${session_id}\"))" "$SESSIONS_FILE"
    else
        # Fallback: filter out the session
        local temp_file
        temp_file=$(mktemp)
        local skip_session=false
        local skip_count=0

        while IFS= read -r line; do
            if [[ "$line" =~ id:.*\"${session_id}\" ]]; then
                skip_session=true
                skip_count=0
            elif [[ "$skip_session" == "true" ]] && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*id: ]]; then
                skip_session=false
            fi

            if [[ "$skip_session" == "false" ]]; then
                # Skip the "  - " line that started the session
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*id:.*\"${session_id}\" ]]; then
                    continue
                fi
                echo "$line" >> "$temp_file"
            fi
        done < "$SESSIONS_FILE"

        mv "$temp_file" "$SESSIONS_FILE"
    fi

    # Notify
    notify_session_change "agent_completed" "$session_id" "$agent_type" "$task" "" "$result"
}

# List all active sessions
# Usage: list_active_sessions [format: json|yaml|table]
list_active_sessions() {
    local format="${1:-table}"

    ensure_sessions_file

    case "$format" in
        json)
            if command -v yq &> /dev/null; then
                yq -o json '.sessions' "$SESSIONS_FILE"
            else
                echo '{"error": "yq not installed, cannot output JSON"}'
            fi
            ;;
        yaml)
            if command -v yq &> /dev/null; then
                yq '.sessions' "$SESSIONS_FILE"
            else
                grep -A100 "^sessions:" "$SESSIONS_FILE" | grep -B100 "^history:" | head -n -1
            fi
            ;;
        table|*)
            echo ""
            echo "Active Agent Sessions"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            if command -v yq &> /dev/null; then
                local count
                count=$(yq '.sessions | length' "$SESSIONS_FILE")

                if [[ "$count" == "0" ]]; then
                    echo "  No active sessions"
                else
                    yq -r '.sessions[] | "\(.icon) \(.agent | . style \"bold\") [\(.status)]  \(.progress)%\n   Task: \(.task)\n   Started: \(.started_at)\n"' "$SESSIONS_FILE" 2>/dev/null || echo "  Error reading sessions"
                fi
            else
                if grep -q "^sessions: \[\]" "$SESSIONS_FILE"; then
                    echo "  No active sessions"
                else
                    grep -A10 "^sessions:" "$SESSIONS_FILE" | grep -E "agent:|task:|status:|progress:" | head -20
                fi
            fi

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            ;;
    esac
}

# Get session count
get_session_count() {
    ensure_sessions_file

    if command -v yq &> /dev/null; then
        yq '.sessions | length' "$SESSIONS_FILE"
    else
        grep -c "^  - id:" "$SESSIONS_FILE" 2>/dev/null || echo "0"
    fi
}

# Get session by ID
get_session() {
    local session_id="$1"
    local format="${2:-json}"

    ensure_sessions_file

    if command -v yq &> /dev/null; then
        if [[ "$format" == "json" ]]; then
            yq -o json ".sessions[] | select(.id == \"${session_id}\")" "$SESSIONS_FILE"
        else
            yq ".sessions[] | select(.id == \"${session_id}\")" "$SESSIONS_FILE"
        fi
    else
        grep -A10 "id: \"${session_id}\"" "$SESSIONS_FILE" | head -10
    fi
}

# Notify dashboard of session changes (writes to event file for server to pick up)
notify_session_change() {
    local event_type="$1"
    local session_id="$2"
    local agent="${3:-}"
    local task="${4:-}"
    local progress="${5:-}"
    local result="${6:-}"

    local events_file="${PROJECT_ROOT}/.workflow/agents/events.json"
    local timestamp
    timestamp=$(date -Iseconds)

    # Create event
    local event="{\"event\": \"${event_type}\", \"timestamp\": \"${timestamp}\", \"data\": {\"session_id\": \"${session_id}\""

    [[ -n "$agent" ]] && event+=", \"agent\": \"${agent}\""
    [[ -n "$task" ]] && event+=", \"task\": \"${task}\""
    [[ -n "$progress" ]] && event+=", \"progress\": ${progress}"
    [[ -n "$result" ]] && event+=", \"result\": \"${result}\""

    event+="}}"

    # Append to events file (dashboard server will read and broadcast)
    echo "$event" >> "$events_file"

    # Keep only last 100 events
    if [[ -f "$events_file" ]]; then
        tail -100 "$events_file" > "${events_file}.tmp"
        mv "${events_file}.tmp" "$events_file"
    fi
}

# Clean up old history entries
cleanup_history() {
    local retention_days="${1:-7}"

    ensure_sessions_file

    local cutoff_date
    cutoff_date=$(date -d "-${retention_days} days" -Iseconds 2>/dev/null || date -v-${retention_days}d -Iseconds)

    if command -v yq &> /dev/null; then
        yq -i "del(.history[] | select(.completed_at < \"${cutoff_date}\"))" "$SESSIONS_FILE"
    fi

    echo "Cleaned up history entries older than ${retention_days} days"
}

# Export functions for use in other scripts
export -f create_agent_session
export -f update_session_progress
export -f end_agent_session
export -f list_active_sessions
export -f get_session_count
export -f get_session
export -f notify_session_change
export -f cleanup_history

# CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        create)
            create_agent_session "${2:-unknown}" "${3:-No task}"
            ;;
        update)
            update_session_progress "${2:-}" "${3:-0}" "${4:-active}" "${5:-}"
            ;;
        end)
            end_agent_session "${2:-}" "${3:-success}"
            ;;
        list)
            list_active_sessions "${2:-table}"
            ;;
        count)
            get_session_count
            ;;
        get)
            get_session "${2:-}" "${3:-json}"
            ;;
        cleanup)
            cleanup_history "${2:-7}"
            ;;
        help|*)
            echo "Session Manager - Multi-Agent Session Tracking"
            echo ""
            echo "Usage: $(basename "$0") <command> [args]"
            echo ""
            echo "Commands:"
            echo "  create <agent> <task>     Create new agent session"
            echo "  update <id> <progress>    Update session progress (0-100)"
            echo "  end <id> [result]         End session (success|failed|cancelled)"
            echo "  list [format]             List active sessions (table|json|yaml)"
            echo "  count                     Get active session count"
            echo "  get <id> [format]         Get session details"
            echo "  cleanup [days]            Clean up old history entries"
            echo ""
            ;;
    esac
fi
