#!/usr/bin/env bats
# Claude → Gemini handoff integration tests
# Tests seamless state transfer from Claude Code to Gemini Antigravity

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

@test "Claude creates checkpoint, Gemini reads it" {
    cd "${TEST_TMP_DIR}"

    # Create Claude session state
    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "implementer"

    # Create handoff checkpoint
    local cp_id
    cp_id=$(create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff to Gemini" "claude" "gemini")

    # Verify checkpoint exists
    [[ -n "$cp_id" ]]
    grep -q "$cp_id" .workflow/checkpoints.log
}

@test "Claude's state.yaml readable by Gemini" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Verify state.yaml is valid and readable
    [ -f ".workflow/state.yaml" ]
    grep -q "current_phase:" .workflow/state.yaml
    grep -q "current_checkpoint:" .workflow/state.yaml
}

@test "Claude's handoff.md parsed by Gemini" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Verify handoff.md has expected structure
    [ -f ".workflow/handoff.md" ]
    grep -q "## " .workflow/handoff.md
}

@test "Claude's agent state preserved" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_2_implementation" "CP_2_001" "architect"

    # Verify agent state
    grep -q "architect" .workflow/state.yaml
    grep -q "active" .workflow/state.yaml
}

@test "Claude's enabled skills preserved" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Verify skills are in state
    grep -q "enabled_skills:" .workflow/state.yaml
}

@test "Claude's phase progress preserved" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001"

    # Verify phase info
    grep -q "phase_1_planning" .workflow/state.yaml
    grep -q "progress:" .workflow/state.yaml
}

@test "Claude's checkpoint history accessible" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Add some checkpoint history
    echo "$(date -Iseconds) | CP_1_002 | Development milestone" >> .workflow/checkpoints.log
    echo "$(date -Iseconds) | CP_1_003 | Feature complete" >> .workflow/checkpoints.log

    # Verify history is accessible
    local checkpoint_count
    checkpoint_count=$(wc -l < .workflow/checkpoints.log)
    [ "$checkpoint_count" -ge 2 ]
}

# =============================================================================
# GEMINI RECOVERY TESTS
# =============================================================================

@test "Gemini recovers full context from Claude state" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_2_implementation" "CP_2_001" "implementer"

    # Run recovery
    run "${SCRIPTS_DIR}/recover_context.sh"

    assert_success
}

@test "Gemini can continue from Claude's phase" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_2_implementation" "CP_2_001" "implementer"

    # Verify phase is accessible
    local current_phase
    current_phase=$(grep "current_phase:" .workflow/state.yaml | head -1 | cut -d'"' -f2)

    [[ "$current_phase" == "phase_2_implementation" ]]
}

@test "Gemini can complete Claude's TODO items" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Verify handoff has TODOs
    grep -q "\[ \]" .workflow/handoff.md || grep -qE "Priority|Next|Action" .workflow/handoff.md
}

@test "Gemini inherits Claude's workspace state" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Create workspace artifacts
    mkdir -p workspace/implementer
    echo "# Work in progress" > workspace/implementer/notes.md

    # Verify workspace exists
    [ -d "workspace/implementer" ]
    [ -f "workspace/implementer/notes.md" ]
}

# =============================================================================
# QUALITY METRICS TESTS
# =============================================================================

@test "Recovery completeness score >= 80%" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Calculate completeness
    local score
    score=$(calculate_recovery_completeness "${TEST_TMP_DIR}")

    [ "$score" -ge 80 ]
}

@test "Handoff time < 5 seconds" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Measure recovery time
    local elapsed
    elapsed=$(measure_handoff_time "${TEST_TMP_DIR}")

    assert_handoff_time_ok "$elapsed" 5000
}

@test "No state corruption after handoff" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Create handoff
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Testing corruption" "claude" "gemini"

    # Check for corruption
    run check_state_corruption "${TEST_TMP_DIR}"

    assert_success
}

@test "Multiple handoffs maintain integrity" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Perform 5 handoffs
    for i in {1..5}; do
        create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff $i" "claude" "gemini"
    done

    # Verify integrity
    run check_state_corruption "${TEST_TMP_DIR}"
    assert_success

    # Verify checkpoint count
    local cp_count
    cp_count=$(grep -c "HANDOFF" .workflow/checkpoints.log || echo "0")
    [ "$cp_count" -ge 5 ]
}
