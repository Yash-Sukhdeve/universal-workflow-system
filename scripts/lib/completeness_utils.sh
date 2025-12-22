#!/bin/bash
# Completeness Verification Utility Library
# Validates recovery completeness and generates scores
# RWF compliance (R5: Reproducibility) - Verify complete recovery

set -euo pipefail

# Source dependencies
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/yaml_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/yaml_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/logging_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/checksum_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/checksum_utils.sh"
fi

# Color codes
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# Completeness thresholds
COMPLETENESS_THRESHOLD_GOOD="${COMPLETENESS_THRESHOLD_GOOD:-80}"
COMPLETENESS_THRESHOLD_WARN="${COMPLETENESS_THRESHOLD_WARN:-50}"

# Required and optional files
REQUIRED_FILES=(
    ".workflow/state.yaml"
    ".workflow/checkpoints.log"
)

OPTIONAL_FILES=(
    ".workflow/handoff.md"
    ".workflow/config.yaml"
    ".workflow/agents/registry.yaml"
    ".workflow/skills/catalog.yaml"
    ".workflow/checksums.yaml"
)

# Required state fields
REQUIRED_STATE_FIELDS=(
    "current_phase"
    "current_checkpoint"
    "metadata.last_updated"
)

# Important state fields (contribute to score)
IMPORTANT_STATE_FIELDS=(
    "project.type"
    "project.name"
    "active_agent.status"
    "session.context_recovered"
    "health.status"
)

#######################################
# Check if required files exist
# Returns:
#   Array of missing files
#######################################
check_required_files() {
    local missing=()

    for file in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing+=("$file")
        fi
    done

    echo "${missing[@]}"
}

#######################################
# Check if optional files exist
# Returns:
#   Count of existing optional files
#######################################
check_optional_files() {
    local count=0

    for file in "${OPTIONAL_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            ((count++))
        fi
    done

    echo "$count"
}

#######################################
# Check if required state fields are populated
# Arguments:
#   $1 - State file path
# Returns:
#   Array of missing fields
#######################################
check_required_fields() {
    local state_file="${1:-.workflow/state.yaml}"
    local missing=()

    if [[ ! -f "$state_file" ]]; then
        echo "${REQUIRED_STATE_FIELDS[@]}"
        return
    fi

    for field in "${REQUIRED_STATE_FIELDS[@]}"; do
        local value
        value=$(yaml_get "$state_file" "$field" 2>/dev/null || echo "null")

        if [[ "$value" == "null" || -z "$value" ]]; then
            missing+=("$field")
        fi
    done

    echo "${missing[@]}"
}

#######################################
# Calculate file completeness score
# Returns:
#   Score 0-100
#######################################
calculate_file_score() {
    local required_count=${#REQUIRED_FILES[@]}
    local optional_count=${#OPTIONAL_FILES[@]}

    local required_present=0
    for file in "${REQUIRED_FILES[@]}"; do
        [[ -f "$file" ]] && ((required_present++))
    done

    local optional_present=0
    for file in "${OPTIONAL_FILES[@]}"; do
        [[ -f "$file" ]] && ((optional_present++))
    done

    # Required files are 70% of score, optional are 30%
    local required_score=$((required_present * 70 / required_count))
    local optional_score=$((optional_present * 30 / optional_count))

    echo $((required_score + optional_score))
}

#######################################
# Calculate state completeness score
# Arguments:
#   $1 - State file path
# Returns:
#   Score 0-100
#######################################
calculate_state_score() {
    local state_file="${1:-.workflow/state.yaml}"

    if [[ ! -f "$state_file" ]]; then
        echo "0"
        return
    fi

    local required_count=${#REQUIRED_STATE_FIELDS[@]}
    local important_count=${#IMPORTANT_STATE_FIELDS[@]}

    local required_present=0
    for field in "${REQUIRED_STATE_FIELDS[@]}"; do
        local value
        value=$(yaml_get "$state_file" "$field" 2>/dev/null || echo "null")
        [[ "$value" != "null" && -n "$value" ]] && ((required_present++))
    done

    local important_present=0
    for field in "${IMPORTANT_STATE_FIELDS[@]}"; do
        local value
        value=$(yaml_get "$state_file" "$field" 2>/dev/null || echo "null")
        [[ "$value" != "null" && -n "$value" ]] && ((important_present++))
    done

    # Required fields are 60% of score, important are 40%
    local required_score=$((required_present * 60 / required_count))
    local important_score=$((important_present * 40 / important_count))

    echo $((required_score + important_score))
}

#######################################
# Calculate overall completeness score
# Arguments:
#   $1 - (Optional) Workflow directory
# Returns:
#   Score 0-100
#######################################
calculate_completeness_score() {
    local workflow_dir="${1:-.workflow}"
    local state_file="${workflow_dir}/state.yaml"

    local file_score
    file_score=$(calculate_file_score)

    local state_score
    state_score=$(calculate_state_score "$state_file")

    # File score is 40%, state score is 60%
    local total=$((file_score * 40 / 100 + state_score * 60 / 100))

    echo "$total"
}

#######################################
# Check consistency between state and checkpoints
# Returns:
#   0 if consistent, 1 if inconsistent
#######################################
check_state_consistency() {
    local state_file=".workflow/state.yaml"
    local checkpoint_log=".workflow/checkpoints.log"

    if [[ ! -f "$state_file" || ! -f "$checkpoint_log" ]]; then
        return 1
    fi

    local current_cp
    current_cp=$(yaml_get "$state_file" "current_checkpoint" 2>/dev/null || echo "")

    if [[ -z "$current_cp" || "$current_cp" == "null" ]]; then
        return 0  # No checkpoint set is valid
    fi

    # Check if current checkpoint exists in log (handle spaces around pipes)
    if ! grep -qE "\| *${current_cp} *\|" "$checkpoint_log" 2>/dev/null; then
        echo -e "${YELLOW}Warning: Current checkpoint ${current_cp} not in log${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Generate completeness report
# Arguments:
#   $1 - (Optional) Workflow directory
# Returns:
#   Formatted report
#######################################
generate_completeness_report() {
    local workflow_dir="${1:-.workflow}"
    local state_file="${workflow_dir}/state.yaml"

    local score
    score=$(calculate_completeness_score "$workflow_dir")

    local file_score
    file_score=$(calculate_file_score)

    local state_score
    state_score=$(calculate_state_score "$state_file")

    # Determine status color
    local status_color status_text
    if (( score >= COMPLETENESS_THRESHOLD_GOOD )); then
        status_color="$GREEN"
        status_text="GOOD"
    elif (( score >= COMPLETENESS_THRESHOLD_WARN )); then
        status_color="$YELLOW"
        status_text="PARTIAL"
    else
        status_color="$RED"
        status_text="INCOMPLETE"
    fi

    echo "═══════════════════════════════════════════"
    echo "  Completeness Report"
    echo "═══════════════════════════════════════════"
    echo ""
    echo -e "  Overall Score: ${status_color}${score}%${NC} [${status_text}]"
    echo ""
    echo "  Components:"
    echo "    File Score:  ${file_score}%"
    echo "    State Score: ${state_score}%"
    echo ""

    # List missing required files
    local missing_files
    missing_files=$(check_required_files)

    if [[ -n "$missing_files" ]]; then
        echo -e "  ${RED}Missing Required Files:${NC}"
        for file in $missing_files; do
            echo "    - $file"
        done
        echo ""
    fi

    # List missing required fields
    local missing_fields
    missing_fields=$(check_required_fields "$state_file")

    if [[ -n "$missing_fields" ]]; then
        echo -e "  ${YELLOW}Missing State Fields:${NC}"
        for field in $missing_fields; do
            echo "    - $field"
        done
        echo ""
    fi

    # Check consistency
    if check_state_consistency 2>/dev/null; then
        echo -e "  ${GREEN}State Consistency: OK${NC}"
    else
        echo -e "  ${YELLOW}State Consistency: Issues detected${NC}"
    fi

    # Check checksums if available
    if [[ -f "${workflow_dir}/checksums.yaml" ]]; then
        if verify_checksums "$workflow_dir" 2>/dev/null; then
            echo -e "  ${GREEN}Checksum Verification: OK${NC}"
        else
            echo -e "  ${RED}Checksum Verification: FAILED${NC}"
        fi
    else
        echo -e "  ${YELLOW}Checksum Verification: Not available${NC}"
    fi

    echo ""
    echo "═══════════════════════════════════════════"
}

#######################################
# Check if recovery is complete enough to proceed
# Arguments:
#   $1 - (Optional) Minimum score (default: COMPLETENESS_THRESHOLD_WARN)
# Returns:
#   0 if complete enough, 1 if not
#######################################
is_recovery_complete() {
    local min_score="${1:-$COMPLETENESS_THRESHOLD_WARN}"

    local score
    score=$(calculate_completeness_score)

    if (( score >= min_score )); then
        return 0
    fi

    return 1
}

#######################################
# Get completeness summary for handoff
# Returns:
#   Markdown summary
#######################################
get_completeness_summary() {
    local score
    score=$(calculate_completeness_score)

    local missing_files
    missing_files=$(check_required_files)

    local missing_fields
    missing_fields=$(check_required_fields)

    echo "## Recovery Completeness"
    echo ""
    echo "**Score:** ${score}%"
    echo ""

    if [[ -n "$missing_files" ]]; then
        echo "### Missing Files"
        for file in $missing_files; do
            echo "- $file"
        done
        echo ""
    fi

    if [[ -n "$missing_fields" ]]; then
        echo "### Missing Fields"
        for field in $missing_fields; do
            echo "- $field"
        done
        echo ""
    fi

    if is_recovery_complete; then
        echo "**Status:** Recovery complete, safe to proceed"
    else
        echo "**Status:** Recovery incomplete, manual verification recommended"
    fi
}

#######################################
# Get completeness as JSON
# Returns:
#   JSON object
#######################################
get_completeness_json() {
    local workflow_dir="${1:-.workflow}"

    local score file_score state_score
    score=$(calculate_completeness_score "$workflow_dir")
    file_score=$(calculate_file_score)
    state_score=$(calculate_state_score "${workflow_dir}/state.yaml")

    local missing_files missing_fields
    missing_files=$(check_required_files)
    missing_fields=$(check_required_fields "${workflow_dir}/state.yaml")

    local consistency="true"
    check_state_consistency 2>/dev/null || consistency="false"

    echo "{"
    echo "  \"score\": ${score},"
    echo "  \"file_score\": ${file_score},"
    echo "  \"state_score\": ${state_score},"
    echo "  \"thresholds\": {"
    echo "    \"good\": ${COMPLETENESS_THRESHOLD_GOOD},"
    echo "    \"warn\": ${COMPLETENESS_THRESHOLD_WARN}"
    echo "  },"
    echo "  \"missing_files\": ["

    local first=true
    for file in $missing_files; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    \"${file}\""
    done
    [[ "$first" == "false" ]] && echo ""

    echo "  ],"
    echo "  \"missing_fields\": ["

    first=true
    for field in $missing_fields; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    \"${field}\""
    done
    [[ "$first" == "false" ]] && echo ""

    echo "  ],"
    echo "  \"consistency\": ${consistency},"
    echo "  \"is_complete\": $(is_recovery_complete && echo "true" || echo "false")"
    echo "}"
}

#######################################
# Log recovery with completeness
# Arguments:
#   $1 - Status (start, success, partial, failed)
#######################################
log_recovery_completeness() {
    local status="$1"

    local score
    score=$(calculate_completeness_score)

    if declare -f log_recovery > /dev/null 2>&1; then
        log_recovery "$status" "$score"
    fi

    if declare -f log_info > /dev/null 2>&1; then
        log_info "completeness" "Recovery completeness: ${score}%" "status=${status}"
    fi
}

#######################################
# Print usage information
#######################################
completeness_usage() {
    cat << 'EOF'
Completeness Verification Utility Library - RWF Reproducibility (R5)

Score Calculation:
  calculate_completeness_score [dir]   Overall score (0-100)
  calculate_file_score                 File presence score
  calculate_state_score [file]         State field score
  is_recovery_complete [min_score]     Check if score meets threshold

Checks:
  check_required_files                 List missing required files
  check_optional_files                 Count existing optional files
  check_required_fields [file]         List missing state fields
  check_state_consistency              Verify cross-file consistency

Reports:
  generate_completeness_report [dir]   Formatted report
  get_completeness_summary             Markdown summary
  get_completeness_json [dir]          JSON format

Logging:
  log_recovery_completeness <status>   Log with completeness score

Configuration:
  COMPLETENESS_THRESHOLD_GOOD=80       Good score threshold
  COMPLETENESS_THRESHOLD_WARN=50       Warning score threshold

Example:
  source scripts/lib/completeness_utils.sh

  # Check before proceeding
  if is_recovery_complete 80; then
      echo "Recovery complete, proceeding..."
  else
      echo "Recovery incomplete:"
      generate_completeness_report
  fi

  # Log recovery
  log_recovery_completeness "success"
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f check_required_files
    export -f check_optional_files
    export -f check_required_fields
    export -f calculate_file_score
    export -f calculate_state_score
    export -f calculate_completeness_score
    export -f check_state_consistency
    export -f generate_completeness_report
    export -f is_recovery_complete
    export -f get_completeness_summary
    export -f get_completeness_json
    export -f log_recovery_completeness
    export -f completeness_usage
fi
