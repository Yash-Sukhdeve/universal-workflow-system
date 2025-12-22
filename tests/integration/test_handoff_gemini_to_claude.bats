#!/usr/bin/env bats
# Gemini → Claude handoff integration tests
# Tests seamless state transfer from Gemini Antigravity to Claude Code

load '../helpers/test_helper.bash'
load '../helpers/dual_compat_helper.bash'
load '../helpers/gemini_wrapper.bash'

# Setup and teardown
setup() {
    setup_test_environment
    create_full_test_environment
    setup_dual_environment
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# CHECKPOINT HANDOFF TESTS
# =============================================================================

@test "Gemini creates checkpoint, Claude reads it" {
    cd "${TEST_TMP_DIR}"

    # Create Gemini session state
    create_gemini_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    # Create handoff checkpoint
    local cp_id
    cp_id=$(create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff to Claude" "gemini" "claude")

    # Verify checkpoint exists
    [[ -n "$cp_id" ]]
    grep -q "$cp_id" .workflow/checkpoints.log
}

@test "Gemini's state.yaml readable by Claude" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Verify state.yaml is valid
    [ -f ".workflow/state.yaml" ]
    grep -q "current_phase:" .workflow/state.yaml
    grep -q "current_checkpoint:" .workflow/state.yaml
    grep -q "schema_version:" .workflow/state.yaml
}

@test "Gemini's handoff.md parsed by Claude" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Verify handoff.md structure
    [ -f ".workflow/handoff.md" ]
    grep -q "## " .workflow/handoff.md
    grep -q "Gemini" .workflow/handoff.md || grep -q "Session" .workflow/handoff.md
}

@test "Gemini's agent state preserved" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    # Verify agent state
    grep -q "researcher" .workflow/state.yaml
    grep -q "active" .workflow/state.yaml
}

@test "Gemini's enabled skills preserved" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Verify skills in state
    grep -q "enabled_skills:" .workflow/state.yaml
}

@test "Gemini's phase progress preserved" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}" "phase_2_implementation" "CP_2_001"

    # Verify phase info
    grep -q "phase_2_implementation" .workflow/state.yaml
}

@test "Gemini's checkpoint history accessible" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Add checkpoint history
    echo "$(date -Iseconds) | CP_1_002 | Research complete" >> .workflow/checkpoints.log
    echo "$(date -Iseconds) | CP_1_003 | Analysis done" >> .workflow/checkpoints.log

    # Verify history
    local checkpoint_count
    checkpoint_count=$(wc -l < .workflow/checkpoints.log)
    [ "$checkpoint_count" -ge 2 ]
}

# =============================================================================
# CLAUDE RECOVERY TESTS
# =============================================================================

@test "Claude recovers full context from Gemini state" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    # Run recovery
    run "${SCRIPTS_DIR}/recover_context.sh"

    assert_success
}

@test "Claude can continue from Gemini's phase" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    # Verify phase is accessible
    local current_phase
    current_phase=$(grep "current_phase:" .workflow/state.yaml | head -1 | cut -d'"' -f2)

    [[ "$current_phase" == "phase_1_planning" ]]
}

@test "Claude can complete Gemini's TODO items" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Verify handoff has actionable items
    grep -q "\[ \]" .workflow/handoff.md || grep -qE "Priority|Next|Action" .workflow/handoff.md
}

@test "Claude inherits Gemini's workspace state" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Create workspace artifacts from Gemini session
    mkdir -p workspace/researcher
    echo "# Research notes" > workspace/researcher/literature.md

    # Verify workspace exists
    [ -d "workspace/researcher" ]
    [ -f "workspace/researcher/literature.md" ]
}

# =============================================================================
# QUALITY METRICS TESTS
# =============================================================================

@test "Recovery completeness score >= 80%" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Calculate completeness
    local score
    score=$(calculate_recovery_completeness "${TEST_TMP_DIR}")

    [ "$score" -ge 80 ]
}

@test "Handoff time < 5 seconds" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Measure recovery time
    local elapsed
    elapsed=$(measure_handoff_time "${TEST_TMP_DIR}")

    assert_handoff_time_ok "$elapsed" 5000
}

@test "No state corruption after handoff" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Create handoff
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Testing corruption" "gemini" "claude"

    # Check for corruption
    run check_state_corruption "${TEST_TMP_DIR}"

    assert_success
}

@test "Multiple handoffs maintain integrity" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Perform 5 handoffs
    for i in {1..5}; do
        create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff $i" "gemini" "claude"
    done

    # Verify integrity
    run check_state_corruption "${TEST_TMP_DIR}"
    assert_success

    # Verify checkpoint count
    local cp_count
    cp_count=$(grep -c "HANDOFF" .workflow/checkpoints.log || echo "0")
    [ "$cp_count" -ge 5 ]
}
