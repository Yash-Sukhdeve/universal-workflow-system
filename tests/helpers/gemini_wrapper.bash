#!/bin/bash
# Gemini CLI Wrapper for Testing
# Real integration with Gemini CLI (gemini command)
# Supports actual API calls when available, mocking when not

# ============================================================================
# CONFIGURATION
# ============================================================================

# Gemini CLI command name
GEMINI_CLI="${GEMINI_CLI:-gemini}"

# Timeout for Gemini CLI calls (seconds)
GEMINI_TIMEOUT="${GEMINI_TIMEOUT:-60}"

# API availability flag
GEMINI_AVAILABLE=""

# Mock mode flag (set to "true" to force mock mode)
GEMINI_MOCK_MODE="${GEMINI_MOCK_MODE:-false}"

# ============================================================================
# AVAILABILITY CHECKS
# ============================================================================

# Check if Gemini CLI is installed and accessible
verify_gemini_available() {
    # Return cached result if available
    if [[ -n "$GEMINI_AVAILABLE" ]]; then
        [[ "$GEMINI_AVAILABLE" == "true" ]]
        return $?
    fi

    # Check for mock mode
    if [[ "$GEMINI_MOCK_MODE" == "true" ]]; then
        GEMINI_AVAILABLE="false"
        return 1
    fi

    # Check if gemini command exists
    if ! command -v "$GEMINI_CLI" &> /dev/null; then
        GEMINI_AVAILABLE="false"
        return 1
    fi

    # Try a simple test command
    if timeout 5 "$GEMINI_CLI" --version &> /dev/null; then
        GEMINI_AVAILABLE="true"
        return 0
    fi

    # Alternative: check if 'gemini' can run at all
    if timeout 5 "$GEMINI_CLI" --help &> /dev/null; then
        GEMINI_AVAILABLE="true"
        return 0
    fi

    GEMINI_AVAILABLE="false"
    return 1
}

# Skip test if Gemini is not available (BATS helper)
skip_if_no_gemini() {
    if ! verify_gemini_available; then
        skip "Gemini CLI not available"
    fi
}

# Get Gemini CLI version
get_gemini_version() {
    if verify_gemini_available; then
        "$GEMINI_CLI" --version 2>/dev/null | head -1
    else
        echo "not installed"
    fi
}

# ============================================================================
# WORKFLOW EXECUTION
# ============================================================================

# Run a Gemini workflow with a prompt
run_gemini_workflow() {
    local prompt="$1"
    local timeout="${2:-$GEMINI_TIMEOUT}"

    if [[ "$GEMINI_MOCK_MODE" == "true" ]] || ! verify_gemini_available; then
        mock_gemini_response "$prompt"
        return $?
    fi

    # Run real Gemini CLI
    timeout "$timeout" "$GEMINI_CLI" "$prompt" 2>&1
    return $?
}

# Run Gemini with a workflow file context
run_gemini_with_workflow() {
    local workflow_file="$1"
    local additional_prompt="${2:-}"
    local timeout="${3:-$GEMINI_TIMEOUT}"

    if [[ ! -f "$workflow_file" ]]; then
        echo "ERROR: Workflow file not found: $workflow_file" >&2
        return 1
    fi

    # Read workflow content
    local workflow_content
    workflow_content=$(cat "$workflow_file")

    # Combine with additional prompt
    local full_prompt="${workflow_content}"
    if [[ -n "$additional_prompt" ]]; then
        full_prompt="${workflow_content}\n\n${additional_prompt}"
    fi

    run_gemini_workflow "$full_prompt" "$timeout"
}

# Run Gemini with UWS context
run_gemini_with_uws_context() {
    local dir="${1:-$(pwd)}"
    local action="${2:-status}"
    local params="${3:-}"
    local timeout="${4:-$GEMINI_TIMEOUT}"

    # Build context from UWS state
    local context=""

    if [[ -f "${dir}/.workflow/state.yaml" ]]; then
        context+="Current workflow state:\n"
        context+=$(cat "${dir}/.workflow/state.yaml")
        context+="\n\n"
    fi

    if [[ -f "${dir}/.workflow/handoff.md" ]]; then
        context+="Handoff document:\n"
        context+=$(cat "${dir}/.workflow/handoff.md")
        context+="\n\n"
    fi

    # Build action prompt
    local action_prompt="Execute UWS action: ${action}"
    if [[ -n "$params" ]]; then
        action_prompt+=" with parameters: ${params}"
    fi

    local full_prompt="${context}${action_prompt}"

    run_gemini_workflow "$full_prompt" "$timeout"
}

# ============================================================================
# OUTPUT CAPTURE
# ============================================================================

# Capture Gemini output to file
capture_gemini_output() {
    local prompt="$1"
    local output_file="${2:-/tmp/gemini_output_$$.txt}"
    local timeout="${3:-$GEMINI_TIMEOUT}"

    run_gemini_workflow "$prompt" "$timeout" > "$output_file" 2>&1
    local status=$?

    echo "$output_file"
    return $status
}

# Capture both stdout and stderr separately
capture_gemini_output_split() {
    local prompt="$1"
    local stdout_file="${2:-/tmp/gemini_stdout_$$.txt}"
    local stderr_file="${3:-/tmp/gemini_stderr_$$.txt}"
    local timeout="${4:-$GEMINI_TIMEOUT}"

    if [[ "$GEMINI_MOCK_MODE" == "true" ]] || ! verify_gemini_available; then
        mock_gemini_response "$prompt" > "$stdout_file" 2> "$stderr_file"
        return $?
    fi

    timeout "$timeout" "$GEMINI_CLI" "$prompt" > "$stdout_file" 2> "$stderr_file"
    return $?
}

# Parse Gemini output for specific patterns
parse_gemini_output() {
    local output_file="$1"
    local pattern="$2"

    if [[ -f "$output_file" ]]; then
        grep -oE "$pattern" "$output_file"
    fi
}

# ============================================================================
# MOCK RESPONSES
# ============================================================================

# Generate mock Gemini response based on prompt
mock_gemini_response() {
    local prompt="$1"

    # Detect prompt type and generate appropriate mock response
    case "$prompt" in
        *"status"*|*"workflow state"*)
            cat << 'EOF'
Based on the workflow state, here's the current status:

## Workflow Status
- **Phase**: phase_1_planning
- **Checkpoint**: CP_1_001
- **Agent**: implementer (active)
- **Health**: healthy

## Next Steps
1. Continue with current phase work
2. Create checkpoint when milestone reached
3. Prepare for phase transition when ready

Status check complete.
EOF
            ;;
        *"checkpoint"*)
            cat << 'EOF'
Creating checkpoint...

## Checkpoint Created
- **ID**: CP_1_002
- **Timestamp**: $(date -Iseconds)
- **Message**: Checkpoint created by Gemini

State has been saved successfully.
EOF
            ;;
        *"recover"*|*"context"*)
            cat << 'EOF'
Recovering context from workflow state...

## Recovery Complete
- **Phase**: phase_1_planning
- **Checkpoint**: CP_1_001
- **Completeness**: 92%

Context has been successfully recovered. Ready to continue work.
EOF
            ;;
        *"agent"*)
            cat << 'EOF'
Agent activation processed.

## Agent Status
- **Current Agent**: researcher
- **Status**: active
- **Skills**: literature_review, hypothesis_formation

Agent is ready to assist with research tasks.
EOF
            ;;
        *"skill"*)
            cat << 'EOF'
Skill management complete.

## Enabled Skills
- code_development
- testing
- literature_review

Skills are now active and ready to use.
EOF
            ;;
        *"handoff"*)
            cat << 'EOF'
Handoff document updated.

## Handoff Summary
- Session prepared for handoff
- State saved
- Notes updated

Ready for tool switch.
EOF
            ;;
        *)
            cat << 'EOF'
Processing request...

## Response
I've analyzed the provided context and workflow state.
The system is functioning normally.

Please specify a more specific action if needed.
EOF
            ;;
    esac

    return 0
}

# Enable mock mode for testing without API
enable_gemini_mock() {
    GEMINI_MOCK_MODE="true"
    export GEMINI_MOCK_MODE
}

# Disable mock mode
disable_gemini_mock() {
    GEMINI_MOCK_MODE="false"
    export GEMINI_MOCK_MODE
}

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

# Verify Gemini output contains UWS context
verify_output_has_uws_context() {
    local output_file="$1"

    local found_context=0

    # Check for typical UWS markers
    grep -qi "phase" "$output_file" && ((found_context++))
    grep -qi "checkpoint" "$output_file" && ((found_context++))
    grep -qi "agent" "$output_file" && ((found_context++))
    grep -qi "status\|workflow\|state" "$output_file" && ((found_context++))

    # Require at least 2 markers
    if (( found_context >= 2 )); then
        return 0
    fi

    echo "ERROR: Output lacks UWS context (found $found_context markers)" >&2
    return 1
}

# Verify Gemini respects checkpoint state
verify_output_respects_checkpoint() {
    local output_file="$1"
    local expected_checkpoint="$2"

    if grep -q "$expected_checkpoint" "$output_file"; then
        return 0
    fi

    echo "ERROR: Output does not reference checkpoint $expected_checkpoint" >&2
    return 1
}

# Verify Gemini output is actionable
verify_output_is_actionable() {
    local output_file="$1"

    # Check for action words or structured content
    if grep -qiE "(next step|action|todo|continue|proceed|create|update)" "$output_file"; then
        return 0
    fi

    echo "WARN: Output may not be actionable" >&2
    return 1
}

# ============================================================================
# STATE MODIFICATION HELPERS
# ============================================================================

# Parse Gemini output for state changes
extract_state_changes() {
    local output_file="$1"

    # Look for state change indicators
    echo "=== Extracted State Changes ==="

    # Checkpoint creation
    local new_checkpoint
    new_checkpoint=$(grep -oE "CP_[0-9]+_[0-9]+" "$output_file" | tail -1)
    if [[ -n "$new_checkpoint" ]]; then
        echo "checkpoint: $new_checkpoint"
    fi

    # Phase changes
    local new_phase
    new_phase=$(grep -oE "phase_[0-9]+_[a-z]+" "$output_file" | tail -1)
    if [[ -n "$new_phase" ]]; then
        echo "phase: $new_phase"
    fi

    # Agent changes
    local new_agent
    new_agent=$(grep -oE "(researcher|architect|implementer|experimenter|optimizer|deployer|documenter)" "$output_file" | tail -1)
    if [[ -n "$new_agent" ]]; then
        echo "agent: $new_agent"
    fi

    echo "=== End State Changes ==="
}

# Apply Gemini's suggested state changes to workflow
apply_state_changes() {
    local dir="$1"
    local output_file="$2"

    local changes
    changes=$(extract_state_changes "$output_file")

    # Extract and apply checkpoint
    local checkpoint
    checkpoint=$(echo "$changes" | grep "checkpoint:" | cut -d' ' -f2)
    if [[ -n "$checkpoint" && -f "${dir}/.workflow/state.yaml" ]]; then
        sed -i "s/current_checkpoint:.*/current_checkpoint: \"${checkpoint}\"/" "${dir}/.workflow/state.yaml"
    fi

    # Extract and apply phase
    local phase
    phase=$(echo "$changes" | grep "phase:" | cut -d' ' -f2)
    if [[ -n "$phase" && -f "${dir}/.workflow/state.yaml" ]]; then
        sed -i "s/current_phase:.*/current_phase: \"${phase}\"/" "${dir}/.workflow/state.yaml"
    fi

    return 0
}

# ============================================================================
# TEST ASSERTIONS
# ============================================================================

# Assert Gemini call succeeded
assert_gemini_success() {
    local status="$1"
    local output="${2:-}"

    if [[ "$status" -ne 0 ]]; then
        echo "FAIL: Gemini call failed with status $status" >&2
        if [[ -n "$output" ]]; then
            echo "Output: $output" >&2
        fi
        return 1
    fi
    return 0
}

# Assert Gemini output contains expected text
assert_gemini_output_contains() {
    local output_file="$1"
    local expected="$2"

    if grep -q "$expected" "$output_file"; then
        return 0
    fi

    echo "FAIL: Gemini output does not contain: $expected" >&2
    return 1
}

# Assert Gemini created valid state
assert_gemini_state_valid() {
    local dir="$1"

    if [[ ! -f "${dir}/.workflow/state.yaml" ]]; then
        echo "FAIL: state.yaml does not exist" >&2
        return 1
    fi

    # Basic YAML validation
    if ! grep -q "current_phase:" "${dir}/.workflow/state.yaml"; then
        echo "FAIL: state.yaml missing current_phase" >&2
        return 1
    fi

    if ! grep -q "current_checkpoint:" "${dir}/.workflow/state.yaml"; then
        echo "FAIL: state.yaml missing current_checkpoint" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f verify_gemini_available
export -f skip_if_no_gemini
export -f get_gemini_version
export -f run_gemini_workflow
export -f run_gemini_with_workflow
export -f run_gemini_with_uws_context
export -f capture_gemini_output
export -f capture_gemini_output_split
export -f parse_gemini_output
export -f mock_gemini_response
export -f enable_gemini_mock
export -f disable_gemini_mock
export -f verify_output_has_uws_context
export -f verify_output_respects_checkpoint
export -f verify_output_is_actionable
export -f extract_state_changes
export -f apply_state_changes
export -f assert_gemini_success
export -f assert_gemini_output_contains
export -f assert_gemini_state_valid
