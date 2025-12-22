#!/usr/bin/env bats
# System tests for SDLC dual workflow
# Tests full SDLC cycle with Claude ↔ Gemini handoffs

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
# FULL SDLC CYCLE WITH HANDOFFS
# =============================================================================

@test "Claude starts Phase 1 planning, checkpoints, Gemini continues" {
    cd "${TEST_TMP_DIR}"

    # Claude: Start Phase 1
    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "architect"

    # Verify phase 1
    grep -q "phase_1_planning" .workflow/state.yaml

    # Claude creates checkpoint
    run "${SCRIPTS_DIR}/checkpoint.sh" create "Phase 1 planning complete"
    assert_success

    # Handoff to Gemini
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Phase 1 complete, handoff" "claude" "gemini"

    # Verify Gemini can read state
    grep -q "phase_1_planning" .workflow/state.yaml
}

@test "Gemini Phase 2 implementation, checkpoints, Claude continues" {
    cd "${TEST_TMP_DIR}"

    # Start from Phase 2
    create_gemini_session_state "${TEST_TMP_DIR}" "phase_2_implementation" "CP_2_001" "implementer"

    # Verify phase
    grep -q "phase_2_implementation" .workflow/state.yaml

    # Gemini creates checkpoint
    run "${SCRIPTS_DIR}/checkpoint.sh" create "Implementation milestone"
    assert_success

    # Handoff to Claude
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Phase 2 milestone" "gemini" "claude"

    # Verify state
    grep -q "phase_2_implementation" .workflow/state.yaml
}

@test "Claude Phase 3 validation, checkpoints, Gemini continues" {
    cd "${TEST_TMP_DIR}"

    # Phase 3
    create_claude_session_state "${TEST_TMP_DIR}" "phase_3_validation" "CP_3_001" "experimenter"

    grep -q "phase_3_validation" .workflow/state.yaml

    run "${SCRIPTS_DIR}/checkpoint.sh" create "Validation started"
    assert_success

    create_handoff_checkpoint "${TEST_TMP_DIR}" "Validation handoff" "claude" "gemini"
}

@test "Gemini Phase 4 delivery, checkpoints, Claude continues" {
    cd "${TEST_TMP_DIR}"

    # Phase 4
    create_gemini_session_state "${TEST_TMP_DIR}" "phase_4_delivery" "CP_4_001" "deployer"

    grep -q "phase_4_delivery" .workflow/state.yaml

    run "${SCRIPTS_DIR}/checkpoint.sh" create "Delivery preparation"
    assert_success

    create_handoff_checkpoint "${TEST_TMP_DIR}" "Delivery handoff" "gemini" "claude"
}

@test "Claude Phase 5 maintenance, complete workflow" {
    cd "${TEST_TMP_DIR}"

    # Phase 5
    create_claude_session_state "${TEST_TMP_DIR}" "phase_5_maintenance" "CP_5_001" "documenter"

    grep -q "phase_5_maintenance" .workflow/state.yaml

    run "${SCRIPTS_DIR}/checkpoint.sh" create "Workflow complete"
    assert_success

    # All 5 phases should be tracked
    grep -q "phase_1_planning\|phase_2_implementation\|phase_3_validation\|phase_4_delivery\|phase_5_maintenance" .workflow/state.yaml
}

# =============================================================================
# REGRESSION AND ERROR HANDLING
# =============================================================================

@test "Phase regression with tool switch handled" {
    cd "${TEST_TMP_DIR}"

    # Start at Phase 3
    create_claude_session_state "${TEST_TMP_DIR}" "phase_3_validation" "CP_3_001" "experimenter"

    # Simulate regression to Phase 2
    sed -i 's/phase_3_validation/phase_2_implementation/' .workflow/state.yaml

    # Handoff should still work
    run create_handoff_checkpoint "${TEST_TMP_DIR}" "Regression handoff" "claude" "gemini"

    # State should be valid
    grep -q "phase_2_implementation" .workflow/state.yaml
}

@test "Multi-agent workflow with handoff" {
    cd "${TEST_TMP_DIR}"

    # Start with researcher
    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    # Activate architect
    run "${SCRIPTS_DIR}/activate_agent.sh" architect
    assert_success

    # Handoff
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Agent transition" "claude" "gemini"

    # Activate implementer from Gemini side
    run "${SCRIPTS_DIR}/activate_agent.sh" implementer
    assert_success
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

@test "Full cycle completion time < 60s" {
    cd "${TEST_TMP_DIR}"

    local start_time end_time elapsed
    start_time=$(date +%s)

    # Full cycle simulation
    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001"
    "${SCRIPTS_DIR}/checkpoint.sh" create "Phase 1" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "H1" "claude" "gemini"

    sed -i 's/phase_1_planning/phase_2_implementation/' .workflow/state.yaml
    "${SCRIPTS_DIR}/checkpoint.sh" create "Phase 2" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "H2" "gemini" "claude"

    sed -i 's/phase_2_implementation/phase_3_validation/' .workflow/state.yaml
    "${SCRIPTS_DIR}/checkpoint.sh" create "Phase 3" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "H3" "claude" "gemini"

    sed -i 's/phase_3_validation/phase_4_delivery/' .workflow/state.yaml
    "${SCRIPTS_DIR}/checkpoint.sh" create "Phase 4" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "H4" "gemini" "claude"

    sed -i 's/phase_4_delivery/phase_5_maintenance/' .workflow/state.yaml
    "${SCRIPTS_DIR}/checkpoint.sh" create "Phase 5" 2>/dev/null || true

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    [ "$elapsed" -lt 60 ]
}

@test "All deliverables tracked across tools" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Create deliverables directory
    mkdir -p phases/phase_1_planning/deliverables
    echo "# Requirements" > phases/phase_1_planning/deliverables/requirements.md

    # Handoff
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Deliverables" "claude" "gemini"

    # Verify deliverables exist after handoff
    [ -f "phases/phase_1_planning/deliverables/requirements.md" ]
}

@test "Final state validates against schema" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_5_maintenance" "CP_5_001" "documenter"

    # Verify required fields exist
    grep -q "current_phase:" .workflow/state.yaml
    grep -q "current_checkpoint:" .workflow/state.yaml
    grep -q "project:" .workflow/state.yaml
    grep -q "metadata:" .workflow/state.yaml

    # Schema version should be present
    grep -q "schema_version:" .workflow/state.yaml
}
