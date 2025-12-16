#!/bin/bash
# Dual Compatibility Test Helper
# Functions for testing Claude Code ↔ Gemini Antigravity handoff
# Supports "tag team" seamless switching between AI tools

# ============================================================================
# ENVIRONMENT SETUP
# ============================================================================

# Get the project root directory
DUAL_COMPAT_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DUAL_COMPAT_PROJECT_ROOT

# Paths for dual environment
export CLAUDE_COMMANDS_DIR="${DUAL_COMPAT_PROJECT_ROOT}/.claude/commands"
export ANTIGRAVITY_WORKFLOWS_DIR="${DUAL_COMPAT_PROJECT_ROOT}/antigravity-integration/workflows"

# Test timing thresholds
export HANDOFF_TIME_THRESHOLD_MS=5000  # 5 seconds max for handoff
export RECOVERY_COMPLETENESS_MIN=80     # 80% minimum completeness score

# ============================================================================
# DUAL ENVIRONMENT SETUP
# ============================================================================

# Create dual-tool test environment with both Claude and Antigravity structures
setup_dual_environment() {
    local dir="${1:-${TEST_TMP_DIR}}"

    # Create Claude Code structure
    mkdir -p "${dir}/.claude/commands"
    mkdir -p "${dir}/.claude/skills"

    # Create Antigravity structure
    mkdir -p "${dir}/.agent/workflows"
    mkdir -p "${dir}/.uws"

    # Create shared workflow directory
    mkdir -p "${dir}/.workflow"/{agents,skills,checkpoints/snapshots}

    # Copy Claude commands if they exist
    if [[ -d "${CLAUDE_COMMANDS_DIR}" ]]; then
        cp -r "${CLAUDE_COMMANDS_DIR}"/*.md "${dir}/.claude/commands/" 2>/dev/null || true
    fi

    # Copy Antigravity workflows if they exist
    if [[ -d "${ANTIGRAVITY_WORKFLOWS_DIR}" ]]; then
        cp -r "${ANTIGRAVITY_WORKFLOWS_DIR}"/*.md "${dir}/.agent/workflows/" 2>/dev/null || true
    fi

    # Create UWS version marker for Antigravity
    echo "1.0.0" > "${dir}/.uws/version"

    return 0
}

# Create state that simulates a Claude session
create_claude_session_state() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local phase="${2:-phase_1_planning}"
    local checkpoint="${3:-CP_1_001}"
    local agent="${4:-implementer}"

    cat > "${dir}/.workflow/state.yaml" << EOF
current_phase: "${phase}"
current_checkpoint: "${checkpoint}"
project:
  name: "dual-compat-test"
  type: "software"
  initialized: true
active_agent:
  name: "${agent}"
  status: "active"
  tool_origin: "claude"
enabled_skills:
  - code_development
  - testing
phases:
  phase_1_planning: { status: "active", progress: 50 }
  phase_2_implementation: { status: "pending", progress: 0 }
  phase_3_validation: { status: "pending", progress: 0 }
  phase_4_delivery: { status: "pending", progress: 0 }
  phase_5_maintenance: { status: "pending", progress: 0 }
health:
  status: "healthy"
session:
  tool: "claude"
  context_recovered: true
  last_handoff: null
metadata:
  schema_version: "2.0"
  last_updated: "$(date -Iseconds)"
  created_by: "claude"
EOF

    # Create handoff document
    cat > "${dir}/.workflow/handoff.md" << EOF
# Session Handoff Document

## Session Info
- **Tool**: Claude Code
- **Phase**: ${phase}
- **Checkpoint**: ${checkpoint}
- **Agent**: ${agent}

## Current Status
Working on ${phase} with ${agent} agent.

## Priority Actions
- [ ] Continue development work
- [ ] Create checkpoint before switching tools

## Critical Context
1. This session was created by Claude Code
2. State is ready for Gemini handoff

## Next Actions
- [ ] Review and continue from current checkpoint
EOF

    # Create checkpoint log
    cat > "${dir}/.workflow/checkpoints.log" << EOF
$(date -Iseconds) | CP_INIT | Initial checkpoint
$(date -Iseconds) | ${checkpoint} | Claude session checkpoint
EOF
}

# Create state that simulates a Gemini session
create_gemini_session_state() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local phase="${2:-phase_1_planning}"
    local checkpoint="${3:-CP_1_001}"
    local agent="${4:-researcher}"

    cat > "${dir}/.workflow/state.yaml" << EOF
current_phase: "${phase}"
current_checkpoint: "${checkpoint}"
project:
  name: "dual-compat-test"
  type: "software"
  initialized: true
active_agent:
  name: "${agent}"
  status: "active"
  tool_origin: "gemini"
enabled_skills:
  - literature_review
  - experimental_design
phases:
  phase_1_planning: { status: "active", progress: 50 }
  phase_2_implementation: { status: "pending", progress: 0 }
  phase_3_validation: { status: "pending", progress: 0 }
  phase_4_delivery: { status: "pending", progress: 0 }
  phase_5_maintenance: { status: "pending", progress: 0 }
health:
  status: "healthy"
session:
  tool: "gemini"
  context_recovered: true
  last_handoff: null
metadata:
  schema_version: "2.0"
  last_updated: "$(date -Iseconds)"
  created_by: "gemini"
EOF

    # Create handoff document
    cat > "${dir}/.workflow/handoff.md" << EOF
# Session Handoff Document

## Session Info
- **Tool**: Gemini Antigravity
- **Phase**: ${phase}
- **Checkpoint**: ${checkpoint}
- **Agent**: ${agent}

## Current Status
Working on ${phase} with ${agent} agent.

## Priority Actions
- [ ] Continue research/development work
- [ ] Create checkpoint before switching tools

## Critical Context
1. This session was created by Gemini Antigravity
2. State is ready for Claude handoff

## Next Actions
- [ ] Review and continue from current checkpoint
EOF

    # Create checkpoint log
    cat > "${dir}/.workflow/checkpoints.log" << EOF
$(date -Iseconds) | CP_INIT | Initial checkpoint
$(date -Iseconds) | ${checkpoint} | Gemini session checkpoint
EOF
}

# ============================================================================
# SESSION SIMULATION
# ============================================================================

# Simulate a Claude session - runs a command and captures state
simulate_claude_session() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local action="${2:-status}"

    local command_file="${dir}/.claude/commands/uws-${action}.md"
    local script=""

    # Parse command file to get script to run
    if [[ -f "$command_file" ]]; then
        # Extract script path from command file
        script=$(grep -oE '\./scripts/[a-z_]+\.sh' "$command_file" | head -1)
    fi

    # Fallback to direct script mapping
    if [[ -z "$script" ]]; then
        case "$action" in
            status) script="./scripts/status.sh" ;;
            checkpoint) script="./scripts/checkpoint.sh" ;;
            recover) script="./scripts/recover_context.sh" ;;
            agent) script="./scripts/activate_agent.sh" ;;
            skill) script="./scripts/enable_skill.sh" ;;
            handoff) script="./scripts/handoff.sh" ;;
            *) script="./scripts/status.sh" ;;
        esac
    fi

    # Run the script if it exists
    if [[ -x "${dir}/${script}" ]]; then
        cd "${dir}"
        "${dir}/${script}" 2>&1
        return $?
    elif [[ -x "${DUAL_COMPAT_PROJECT_ROOT}/${script}" ]]; then
        cd "${dir}"
        WORKFLOW_DIR="${dir}/.workflow" "${DUAL_COMPAT_PROJECT_ROOT}/${script}" 2>&1
        return $?
    fi

    return 1
}

# Simulate a Gemini session - runs workflow and captures state
simulate_gemini_session() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local action="${2:-status}"

    local workflow_file="${dir}/.agent/workflows/uws-${action}.md"
    local script=""

    # Parse workflow file to get script to run
    if [[ -f "$workflow_file" ]]; then
        script=$(grep -oE '\./scripts/[a-z_]+\.sh' "$workflow_file" | head -1)
    fi

    # Fallback to direct script mapping
    if [[ -z "$script" ]]; then
        case "$action" in
            status) script="./scripts/status.sh" ;;
            checkpoint) script="./scripts/checkpoint.sh" ;;
            recover) script="./scripts/recover_context.sh" ;;
            agent) script="./scripts/activate_agent.sh" ;;
            skill) script="./scripts/enable_skill.sh" ;;
            handoff) script="./scripts/handoff.sh" ;;
            *) script="./scripts/status.sh" ;;
        esac
    fi

    # Run the script if it exists
    if [[ -x "${dir}/${script}" ]]; then
        cd "${dir}"
        "${dir}/${script}" 2>&1
        return $?
    elif [[ -x "${DUAL_COMPAT_PROJECT_ROOT}/${script}" ]]; then
        cd "${dir}"
        WORKFLOW_DIR="${dir}/.workflow" "${DUAL_COMPAT_PROJECT_ROOT}/${script}" 2>&1
        return $?
    fi

    return 1
}

# ============================================================================
# STATE VERIFICATION
# ============================================================================

# Capture current state as JSON-like structure for comparison
capture_state_snapshot() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local output_file="${2:-/tmp/state_snapshot_$$.txt}"

    {
        echo "=== STATE SNAPSHOT ==="
        echo "timestamp: $(date -Iseconds)"
        echo ""

        if [[ -f "${dir}/.workflow/state.yaml" ]]; then
            echo "--- state.yaml ---"
            cat "${dir}/.workflow/state.yaml"
            echo ""
        fi

        if [[ -f "${dir}/.workflow/handoff.md" ]]; then
            echo "--- handoff.md (first 20 lines) ---"
            head -20 "${dir}/.workflow/handoff.md"
            echo ""
        fi

        if [[ -f "${dir}/.workflow/checkpoints.log" ]]; then
            echo "--- checkpoints.log ---"
            cat "${dir}/.workflow/checkpoints.log"
            echo ""
        fi

        echo "=== END SNAPSHOT ==="
    } > "$output_file"

    echo "$output_file"
}

# Verify state continuity between two snapshots
verify_state_continuity() {
    local before_file="$1"
    local after_file="$2"
    local strict="${3:-false}"

    local errors=0

    # Extract key values from before state
    local before_phase before_checkpoint before_agent
    before_phase=$(grep "current_phase:" "$before_file" | head -1 | cut -d'"' -f2)
    before_checkpoint=$(grep "current_checkpoint:" "$before_file" | head -1 | cut -d'"' -f2)
    before_agent=$(grep -A2 "active_agent:" "$before_file" | grep "name:" | head -1 | cut -d'"' -f2)

    # Extract key values from after state
    local after_phase after_checkpoint after_agent
    after_phase=$(grep "current_phase:" "$after_file" | head -1 | cut -d'"' -f2)
    after_checkpoint=$(grep "current_checkpoint:" "$after_file" | head -1 | cut -d'"' -f2)
    after_agent=$(grep -A2 "active_agent:" "$after_file" | grep "name:" | head -1 | cut -d'"' -f2)

    # Verify phase preserved
    if [[ "$before_phase" != "$after_phase" ]]; then
        echo "ERROR: Phase changed from '$before_phase' to '$after_phase'" >&2
        ((errors++))
    fi

    # Checkpoint should be same or newer
    if [[ "$strict" == "true" && "$before_checkpoint" != "$after_checkpoint" ]]; then
        echo "WARN: Checkpoint changed from '$before_checkpoint' to '$after_checkpoint'" >&2
    fi

    # Agent may change but should be valid
    if [[ -n "$before_agent" && -z "$after_agent" ]]; then
        echo "ERROR: Agent lost during handoff (was '$before_agent')" >&2
        ((errors++))
    fi

    return $errors
}

# ============================================================================
# HANDOFF OPERATIONS
# ============================================================================

# Create a handoff checkpoint with metadata
create_handoff_checkpoint() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local message="${2:-Handoff checkpoint}"
    local source_tool="${3:-claude}"
    local target_tool="${4:-gemini}"

    local checkpoint_id="CP_HANDOFF_$(date +%s)"
    local timestamp=$(date -Iseconds)

    # Update state with handoff info
    if [[ -f "${dir}/.workflow/state.yaml" ]]; then
        # Add handoff metadata
        cat >> "${dir}/.workflow/state.yaml" << EOF

# Handoff metadata
handoff:
  checkpoint_id: "${checkpoint_id}"
  source_tool: "${source_tool}"
  target_tool: "${target_tool}"
  timestamp: "${timestamp}"
  message: "${message}"
EOF
    fi

    # Log the checkpoint
    echo "${timestamp} | ${checkpoint_id} | HANDOFF: ${source_tool} -> ${target_tool}: ${message}" >> "${dir}/.workflow/checkpoints.log"

    # Create snapshot directory
    local snapshot_dir="${dir}/.workflow/checkpoints/snapshots/${checkpoint_id}"
    mkdir -p "$snapshot_dir"

    # Copy state files to snapshot
    cp "${dir}/.workflow/state.yaml" "${snapshot_dir}/" 2>/dev/null || true
    cp "${dir}/.workflow/handoff.md" "${snapshot_dir}/" 2>/dev/null || true

    echo "$checkpoint_id"
}

# Verify checkpoint is readable by both tools
verify_checkpoint_readable() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local checkpoint_id="${2:-}"

    local errors=0

    # Check state.yaml is valid YAML
    if [[ -f "${dir}/.workflow/state.yaml" ]]; then
        if ! grep -q "current_phase:" "${dir}/.workflow/state.yaml"; then
            echo "ERROR: state.yaml missing current_phase" >&2
            ((errors++))
        fi
        if ! grep -q "current_checkpoint:" "${dir}/.workflow/state.yaml"; then
            echo "ERROR: state.yaml missing current_checkpoint" >&2
            ((errors++))
        fi
    else
        echo "ERROR: state.yaml does not exist" >&2
        ((errors++))
    fi

    # Check handoff.md is valid markdown
    if [[ -f "${dir}/.workflow/handoff.md" ]]; then
        if ! grep -q "# " "${dir}/.workflow/handoff.md"; then
            echo "ERROR: handoff.md has no headers" >&2
            ((errors++))
        fi
    else
        echo "WARN: handoff.md does not exist" >&2
    fi

    # Check checkpoints.log exists and has entries
    if [[ -f "${dir}/.workflow/checkpoints.log" ]]; then
        if [[ ! -s "${dir}/.workflow/checkpoints.log" ]]; then
            echo "ERROR: checkpoints.log is empty" >&2
            ((errors++))
        fi
    else
        echo "WARN: checkpoints.log does not exist" >&2
    fi

    # Check snapshot if checkpoint_id provided
    if [[ -n "$checkpoint_id" ]]; then
        local snapshot_dir="${dir}/.workflow/checkpoints/snapshots/${checkpoint_id}"
        if [[ ! -d "$snapshot_dir" ]]; then
            echo "ERROR: Snapshot directory for ${checkpoint_id} does not exist" >&2
            ((errors++))
        fi
    fi

    return $errors
}

# ============================================================================
# TIMING AND PERFORMANCE
# ============================================================================

# Measure handoff time in milliseconds
measure_handoff_time() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local action="${2:-recover}"

    local start_time end_time elapsed

    start_time=$(date +%s%N)

    # Run recovery
    if [[ -x "${dir}/scripts/recover_context.sh" ]]; then
        cd "${dir}"
        WORKFLOW_DIR="${dir}/.workflow" "${dir}/scripts/recover_context.sh" > /dev/null 2>&1
    elif [[ -x "${DUAL_COMPAT_PROJECT_ROOT}/scripts/recover_context.sh" ]]; then
        cd "${dir}"
        WORKFLOW_DIR="${dir}/.workflow" "${DUAL_COMPAT_PROJECT_ROOT}/scripts/recover_context.sh" > /dev/null 2>&1
    fi

    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))

    echo "$elapsed"
}

# Assert handoff time is within threshold
assert_handoff_time_ok() {
    local elapsed="$1"
    local threshold="${2:-$HANDOFF_TIME_THRESHOLD_MS}"

    if (( elapsed > threshold )); then
        echo "FAIL: Handoff time ${elapsed}ms exceeds threshold ${threshold}ms" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# COMPLETENESS SCORING
# ============================================================================

# Calculate recovery completeness score (0-100)
calculate_recovery_completeness() {
    local dir="${1:-${TEST_TMP_DIR}}"

    local score=0
    local max_score=100

    # state.yaml exists and has required fields (40 points)
    if [[ -f "${dir}/.workflow/state.yaml" ]]; then
        score=$((score + 10))
        grep -q "current_phase:" "${dir}/.workflow/state.yaml" && score=$((score + 10))
        grep -q "current_checkpoint:" "${dir}/.workflow/state.yaml" && score=$((score + 10))
        grep -q "metadata:" "${dir}/.workflow/state.yaml" && score=$((score + 10))
    fi

    # handoff.md exists and has content (20 points)
    if [[ -f "${dir}/.workflow/handoff.md" ]]; then
        score=$((score + 10))
        grep -q "## " "${dir}/.workflow/handoff.md" && score=$((score + 10))
    fi

    # checkpoints.log exists (10 points)
    if [[ -f "${dir}/.workflow/checkpoints.log" && -s "${dir}/.workflow/checkpoints.log" ]]; then
        score=$((score + 10))
    fi

    # config.yaml exists (10 points)
    if [[ -f "${dir}/.workflow/config.yaml" ]]; then
        score=$((score + 10))
    fi

    # agents/registry.yaml exists (10 points)
    if [[ -f "${dir}/.workflow/agents/registry.yaml" ]]; then
        score=$((score + 10))
    fi

    # skills/catalog.yaml exists (10 points)
    if [[ -f "${dir}/.workflow/skills/catalog.yaml" ]]; then
        score=$((score + 10))
    fi

    echo "$score"
}

# Assert completeness meets minimum threshold
assert_completeness_ok() {
    local score="$1"
    local threshold="${2:-$RECOVERY_COMPLETENESS_MIN}"

    if (( score < threshold )); then
        echo "FAIL: Completeness score ${score}% below threshold ${threshold}%" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# TOOL-SPECIFIC HELPERS
# ============================================================================

# Check if Claude commands are installed
verify_claude_commands_installed() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local required_commands=("status" "checkpoint" "recover" "agent" "skill" "handoff")
    local missing=()

    for cmd in "${required_commands[@]}"; do
        if [[ ! -f "${dir}/.claude/commands/uws-${cmd}.md" ]]; then
            missing+=("uws-${cmd}.md")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing Claude commands: ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# Check if Antigravity workflows are installed
verify_antigravity_workflows_installed() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local required_workflows=("status" "checkpoint" "recover" "agent" "skill" "handoff")
    local missing=()

    for wf in "${required_workflows[@]}"; do
        if [[ ! -f "${dir}/.agent/workflows/uws-${wf}.md" ]]; then
            missing+=("uws-${wf}.md")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing Antigravity workflows: ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# RAPID SWITCHING HELPERS
# ============================================================================

# Perform rapid handoff cycle
rapid_handoff_cycle() {
    local dir="${1:-${TEST_TMP_DIR}}"
    local cycles="${2:-5}"
    local tool="claude"

    local errors=0

    for ((i=1; i<=cycles; i++)); do
        # Create handoff checkpoint
        local cp_id
        if [[ "$tool" == "claude" ]]; then
            cp_id=$(create_handoff_checkpoint "$dir" "Cycle $i" "claude" "gemini")
            tool="gemini"
        else
            cp_id=$(create_handoff_checkpoint "$dir" "Cycle $i" "gemini" "claude")
            tool="claude"
        fi

        # Verify checkpoint readable
        if ! verify_checkpoint_readable "$dir" "$cp_id"; then
            echo "ERROR: Checkpoint verification failed at cycle $i" >&2
            ((errors++))
        fi

        # Small delay to prevent race conditions
        sleep 0.1
    done

    return $errors
}

# Check for state corruption after rapid switching
check_state_corruption() {
    local dir="${1:-${TEST_TMP_DIR}}"

    local errors=0

    # Check state.yaml is valid
    if [[ -f "${dir}/.workflow/state.yaml" ]]; then
        # Check for YAML syntax errors (basic check)
        if ! grep -E "^[a-z_]+:" "${dir}/.workflow/state.yaml" > /dev/null; then
            echo "ERROR: state.yaml appears corrupted (no valid keys found)" >&2
            ((errors++))
        fi

        # Check for duplicate keys (sign of corruption)
        local dup_keys
        dup_keys=$(grep -E "^current_phase:" "${dir}/.workflow/state.yaml" | wc -l)
        if (( dup_keys > 1 )); then
            echo "ERROR: state.yaml has duplicate current_phase keys" >&2
            ((errors++))
        fi
    fi

    # Check checkpoints.log for duplicates
    if [[ -f "${dir}/.workflow/checkpoints.log" ]]; then
        local total_lines unique_lines
        total_lines=$(wc -l < "${dir}/.workflow/checkpoints.log")
        unique_lines=$(sort -u "${dir}/.workflow/checkpoints.log" | wc -l)

        # Allow some duplicates but not excessive
        if (( total_lines > unique_lines * 2 )); then
            echo "WARN: checkpoints.log may have excessive duplicates" >&2
        fi
    fi

    return $errors
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f setup_dual_environment
export -f create_claude_session_state
export -f create_gemini_session_state
export -f simulate_claude_session
export -f simulate_gemini_session
export -f capture_state_snapshot
export -f verify_state_continuity
export -f create_handoff_checkpoint
export -f verify_checkpoint_readable
export -f measure_handoff_time
export -f assert_handoff_time_ok
export -f calculate_recovery_completeness
export -f assert_completeness_ok
export -f verify_claude_commands_installed
export -f verify_antigravity_workflows_installed
export -f rapid_handoff_cycle
export -f check_state_corruption
