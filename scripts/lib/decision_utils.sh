#!/bin/bash
# Decision Logging Utility Library
# Provides structured decision, blocker, and assumption tracking
# RWF compliance (R1: Truthfulness) - Full decision audit trail

set -euo pipefail

# Source dependencies
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/timestamp_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/timestamp_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/logging_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging_utils.sh"
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

# Decision log configuration
DECISION_LOG_DIR="${DECISION_LOG_DIR:-.workflow/logs}"
DECISION_LOG_FILE="${DECISION_LOG_DIR}/decisions.log"

# Decision counter file
DECISION_COUNTER_FILE="${DECISION_LOG_DIR}/.decision_counter"

# Decision types
DECISION_TYPE_DECISION="decision"
DECISION_TYPE_BLOCKER="blocker"
DECISION_TYPE_ASSUMPTION="assumption"

#######################################
# Initialize decision logging
# Creates decision log directory and files
#######################################
decision_init() {
    if [[ ! -d "$DECISION_LOG_DIR" ]]; then
        mkdir -p "$DECISION_LOG_DIR" || return 1
    fi

    if [[ ! -f "$DECISION_LOG_FILE" ]]; then
        touch "$DECISION_LOG_FILE" || return 1
    fi

    if [[ ! -f "$DECISION_COUNTER_FILE" ]]; then
        echo "0" > "$DECISION_COUNTER_FILE"
    fi

    return 0
}

#######################################
# Generate unique decision ID
# Returns:
#   Decision ID (e.g., DEC-2025-001)
#######################################
generate_decision_id() {
    local year
    year=$(date +%Y)

    local counter=0
    if [[ -f "$DECISION_COUNTER_FILE" ]]; then
        counter=$(cat "$DECISION_COUNTER_FILE" 2>/dev/null || echo "0")
    fi

    counter=$((counter + 1))
    echo "$counter" > "$DECISION_COUNTER_FILE"

    printf "DEC-%s-%03d" "$year" "$counter"
}

#######################################
# Log a decision
# Arguments:
#   $1 - Summary (short description)
#   $2 - Category (architecture, implementation, research, etc.)
#   $3 - Rationale (why this decision was made)
#   $4 - (Optional) Alternatives considered (comma-separated)
#   $5 - (Optional) Agent name
#   $6 - (Optional) Checkpoint ID
# Returns:
#   Decision ID
#######################################
log_decision() {
    local summary="$1"
    local category="${2:-general}"
    local rationale="$3"
    local alternatives="${4:-}"
    local agent="${5:-}"
    local checkpoint="${6:-}"

    decision_init || return 1

    local decision_id
    decision_id=$(generate_decision_id)

    local timestamp
    timestamp=$(get_iso_timestamp 2>/dev/null || date -Iseconds)

    # Write YAML-formatted decision entry
    cat >> "$DECISION_LOG_FILE" << EOF
---
id: "${decision_id}"
timestamp: "${timestamp}"
type: "${DECISION_TYPE_DECISION}"
category: "${category}"
summary: "${summary}"
rationale: "${rationale}"
EOF

    if [[ -n "$alternatives" ]]; then
        echo "alternatives_considered:" >> "$DECISION_LOG_FILE"
        IFS=',' read -ra alts <<< "$alternatives"
        for alt in "${alts[@]}"; do
            echo "  - \"${alt# }\"" >> "$DECISION_LOG_FILE"
        done
    fi

    if [[ -n "$agent" ]]; then
        echo "agent: \"${agent}\"" >> "$DECISION_LOG_FILE"
    fi

    if [[ -n "$checkpoint" ]]; then
        echo "checkpoint: \"${checkpoint}\"" >> "$DECISION_LOG_FILE"
    fi

    echo "status: \"accepted\"" >> "$DECISION_LOG_FILE"
    echo "" >> "$DECISION_LOG_FILE"

    # Also log to execution log
    if declare -f log_info > /dev/null 2>&1; then
        log_info "decision" "Decision logged: ${summary}" "id=${decision_id} category=${category}"
    fi

    echo "$decision_id"
}

#######################################
# Log a blocker
# Arguments:
#   $1 - Description
#   $2 - Category (technical, dependency, information, human)
#   $3 - (Optional) Severity (low, medium, high, critical)
#   $4 - (Optional) Agent name
# Returns:
#   Blocker ID
#######################################
log_blocker() {
    local description="$1"
    local category="${2:-technical}"
    local severity="${3:-medium}"
    local agent="${4:-}"

    decision_init || return 1

    local blocker_id
    blocker_id=$(generate_decision_id)

    local timestamp
    timestamp=$(get_iso_timestamp 2>/dev/null || date -Iseconds)

    cat >> "$DECISION_LOG_FILE" << EOF
---
id: "${blocker_id}"
timestamp: "${timestamp}"
type: "${DECISION_TYPE_BLOCKER}"
category: "${category}"
description: "${description}"
severity: "${severity}"
status: "active"
EOF

    if [[ -n "$agent" ]]; then
        echo "agent: \"${agent}\"" >> "$DECISION_LOG_FILE"
    fi

    echo "resolution: null" >> "$DECISION_LOG_FILE"
    echo "resolved_at: null" >> "$DECISION_LOG_FILE"
    echo "" >> "$DECISION_LOG_FILE"

    # Log to execution log
    if declare -f log_warn > /dev/null 2>&1; then
        log_warn "blocker" "Blocker logged: ${description}" "id=${blocker_id} severity=${severity}"
    fi

    echo "$blocker_id"
}

#######################################
# Resolve a blocker
# Arguments:
#   $1 - Blocker ID
#   $2 - Resolution description
# Returns:
#   0 on success, 1 on failure
#######################################
resolve_blocker() {
    local blocker_id="$1"
    local resolution="$2"

    if [[ ! -f "$DECISION_LOG_FILE" ]]; then
        echo -e "${RED}Error: Decision log not found${NC}" >&2
        return 1
    fi

    local timestamp
    timestamp=$(get_iso_timestamp 2>/dev/null || date -Iseconds)

    # Append resolution entry
    cat >> "$DECISION_LOG_FILE" << EOF
---
type: "resolution"
blocker_id: "${blocker_id}"
resolved_at: "${timestamp}"
resolution: "${resolution}"
EOF
    echo "" >> "$DECISION_LOG_FILE"

    if declare -f log_info > /dev/null 2>&1; then
        log_info "blocker" "Blocker resolved" "id=${blocker_id}"
    fi

    return 0
}

#######################################
# Log an assumption
# Arguments:
#   $1 - Assumption statement
#   $2 - (Optional) Confidence level (low, medium, high)
#   $3 - (Optional) Verification method
#   $4 - (Optional) Agent name
# Returns:
#   Assumption ID
#######################################
log_assumption() {
    local statement="$1"
    local confidence="${2:-medium}"
    local verification="${3:-}"
    local agent="${4:-}"

    decision_init || return 1

    local assumption_id
    assumption_id=$(generate_decision_id)

    local timestamp
    timestamp=$(get_iso_timestamp 2>/dev/null || date -Iseconds)

    cat >> "$DECISION_LOG_FILE" << EOF
---
id: "${assumption_id}"
timestamp: "${timestamp}"
type: "${DECISION_TYPE_ASSUMPTION}"
statement: "${statement}"
confidence: "${confidence}"
status: "unverified"
EOF

    if [[ -n "$verification" ]]; then
        echo "verification_method: \"${verification}\"" >> "$DECISION_LOG_FILE"
    fi

    if [[ -n "$agent" ]]; then
        echo "agent: \"${agent}\"" >> "$DECISION_LOG_FILE"
    fi

    echo "" >> "$DECISION_LOG_FILE"

    if declare -f log_info > /dev/null 2>&1; then
        log_info "assumption" "Assumption logged: ${statement}" "id=${assumption_id} confidence=${confidence}"
    fi

    echo "$assumption_id"
}

#######################################
# Get all open blockers
# Returns:
#   List of open blocker entries
#######################################
get_open_blockers() {
    if [[ ! -f "$DECISION_LOG_FILE" ]]; then
        return 0
    fi

    # Parse YAML entries to find active blockers
    # This is a simplified parser - looks for type: blocker with status: active
    awk '
        /^---$/ { in_entry = 1; entry = ""; is_blocker = 0; is_active = 0; next }
        in_entry && /^type: "?blocker"?/ { is_blocker = 1 }
        in_entry && /^status: "?active"?/ { is_active = 1 }
        in_entry && /^id:/ { id = $2; gsub(/"/, "", id) }
        in_entry && /^description:/ { desc = substr($0, 14); gsub(/"/, "", desc) }
        in_entry && /^severity:/ { sev = $2; gsub(/"/, "", sev) }
        in_entry && /^$/ {
            if (is_blocker && is_active) {
                print id "|" sev "|" desc
            }
            in_entry = 0
        }
    ' "$DECISION_LOG_FILE"
}

#######################################
# Get blockers count
# Returns:
#   Number of open blockers
#######################################
get_blocker_count() {
    get_open_blockers | wc -l | tr -d ' '
}

#######################################
# Get decisions by phase/checkpoint
# Arguments:
#   $1 - Checkpoint ID
# Returns:
#   Decisions for that checkpoint
#######################################
get_decisions_by_checkpoint() {
    local checkpoint_id="$1"

    if [[ ! -f "$DECISION_LOG_FILE" ]]; then
        return 0
    fi

    grep -A20 "checkpoint: \"${checkpoint_id}\"" "$DECISION_LOG_FILE" | \
        awk '/^---$/ { if (NR > 1) exit } { print }'
}

#######################################
# Get decisions by category
# Arguments:
#   $1 - Category
# Returns:
#   Decisions in that category
#######################################
get_decisions_by_category() {
    local category="$1"

    if [[ ! -f "$DECISION_LOG_FILE" ]]; then
        return 0
    fi

    grep -B5 -A15 "category: \"${category}\"" "$DECISION_LOG_FILE"
}

#######################################
# Get recent decisions
# Arguments:
#   $1 - Number of entries (default: 10)
# Returns:
#   Recent decision entries
#######################################
get_recent_decisions() {
    local count="${1:-10}"

    if [[ ! -f "$DECISION_LOG_FILE" ]]; then
        return 0
    fi

    # Get last N YAML entries
    awk -v count="$count" '
        /^---$/ { entries[++n] = "" }
        { entries[n] = entries[n] $0 "\n" }
        END {
            start = n - count + 1
            if (start < 1) start = 1
            for (i = start; i <= n; i++) {
                print entries[i]
            }
        }
    ' "$DECISION_LOG_FILE"
}

#######################################
# Format blocker for display
# Arguments:
#   $1 - Blocker line from get_open_blockers
#######################################
format_blocker() {
    local line="$1"
    local id desc sev

    IFS='|' read -r id sev desc <<< "$line"

    local color
    case "$sev" in
        critical) color="$RED" ;;
        high)     color="$YELLOW" ;;
        medium)   color="$CYAN" ;;
        *)        color="$NC" ;;
    esac

    echo -e "${color}[${sev^^}]${NC} ${id}: ${desc}"
}

#######################################
# Display open blockers
#######################################
display_open_blockers() {
    local blockers
    blockers=$(get_open_blockers)

    if [[ -z "$blockers" ]]; then
        echo -e "${GREEN}No open blockers${NC}"
        return 0
    fi

    echo -e "${YELLOW}Open Blockers:${NC}"
    while IFS= read -r line; do
        format_blocker "$line"
    done <<< "$blockers"
}

#######################################
# Get decision summary for handoff
# Returns:
#   Summary of recent decisions and open blockers
#######################################
get_decision_summary() {
    local blocker_count
    blocker_count=$(get_blocker_count)

    echo "## Decision Summary"
    echo ""
    echo "**Open Blockers:** ${blocker_count}"
    echo ""

    if (( blocker_count > 0 )); then
        echo "### Active Blockers"
        echo ""
        local blockers
        blockers=$(get_open_blockers)
        while IFS='|' read -r id sev desc; do
            echo "- [${sev}] ${id}: ${desc}"
        done <<< "$blockers"
        echo ""
    fi

    echo "### Recent Decisions"
    echo ""

    # Get last 5 decisions
    awk '
        /^---$/ { n++; entries[n] = "" }
        /^type: "?decision"?/ { is_decision[n] = 1 }
        /^summary:/ { summary[n] = substr($0, 10); gsub(/"/, "", summary[n]) }
        /^category:/ { category[n] = $2; gsub(/"/, "", category[n]) }
        END {
            count = 0
            for (i = n; i >= 1 && count < 5; i--) {
                if (is_decision[i]) {
                    print "- [" category[i] "] " summary[i]
                    count++
                }
            }
        }
    ' "$DECISION_LOG_FILE" 2>/dev/null || echo "No recent decisions"
}

#######################################
# Print usage information
#######################################
decision_usage() {
    cat << 'EOF'
Decision Logging Utility Library - RWF Truthfulness (R1)

Decision Types:
  decision   - A choice made between alternatives
  blocker    - An obstacle preventing progress
  assumption - A belief that needs verification

Logging Functions:
  log_decision <summary> <category> <rationale> [alts] [agent] [cp]
  log_blocker <description> [category] [severity] [agent]
  log_assumption <statement> [confidence] [verification] [agent]
  resolve_blocker <id> <resolution>

Query Functions:
  get_open_blockers           List active blockers
  get_blocker_count           Count of open blockers
  get_decisions_by_checkpoint <cp_id>
  get_decisions_by_category <category>
  get_recent_decisions [count]
  get_decision_summary        Summary for handoff

Display Functions:
  display_open_blockers       Show formatted blockers
  format_blocker <line>       Format single blocker

Categories:
  decision: architecture, implementation, research, testing, deployment
  blocker: technical, dependency, information, human
  assumption: (any)

Severity (blockers):
  low, medium, high, critical

Confidence (assumptions):
  low, medium, high

Example:
  source scripts/lib/decision_utils.sh

  # Log a decision
  log_decision \
      "Use gradient boosting for recovery prediction" \
      "architecture" \
      "Best cross-validation performance (AUC=0.912)" \
      "Random Forest,Logistic Regression" \
      "experimenter" \
      "CP_1_005"

  # Log a blocker
  blocker_id=$(log_blocker \
      "Cannot access production database" \
      "dependency" \
      "high" \
      "implementer")

  # Resolve blocker
  resolve_blocker "$blocker_id" "Obtained read-only credentials"

  # Log an assumption
  log_assumption \
      "Recovery time scales linearly with state size" \
      "medium" \
      "Benchmark with varying state sizes"
EOF
}

# Initialize on source
decision_init 2>/dev/null || true

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f decision_init
    export -f generate_decision_id
    export -f log_decision
    export -f log_blocker
    export -f resolve_blocker
    export -f log_assumption
    export -f get_open_blockers
    export -f get_blocker_count
    export -f get_decisions_by_checkpoint
    export -f get_decisions_by_category
    export -f get_recent_decisions
    export -f format_blocker
    export -f display_open_blockers
    export -f get_decision_summary
    export -f decision_usage
fi
