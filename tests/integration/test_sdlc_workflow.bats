#!/usr/bin/env bats
# Integration Tests for SDLC Workflow
# Tests complete SDLC cycle and failure regression

# Load test helpers
load '../helpers/test_helper'

# ============================================================================
# SETUP
# ============================================================================

setup() {
    setup_test_environment
    create_full_test_environment "${TEST_TMP_DIR}"
    cd "${TEST_TMP_DIR}"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# SCRIPT EXISTENCE TESTS
# ============================================================================

@test "sdlc.sh exists and is executable" {
    [[ -f "${SCRIPTS_DIR}/sdlc.sh" ]]
    [[ -x "${SCRIPTS_DIR}/sdlc.sh" ]]
}

@test "sdlc.sh has proper shebang and strict mode" {
    head -20 "${SCRIPTS_DIR}/sdlc.sh" | grep -q "set -euo pipefail"
}

# ============================================================================
# STATUS TESTS
# ============================================================================

@test "sdlc status shows 'not started' initially" {
    run "${SCRIPTS_DIR}/sdlc.sh" status

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Not started" ]] || [[ "$output" =~ "none" ]]
}

@test "sdlc status command is default action" {
    run "${SCRIPTS_DIR}/sdlc.sh"

    [[ "$status" -eq 0 ]]
}

# ============================================================================
# START TESTS
# ============================================================================

@test "sdlc start begins at requirements phase" {
    run "${SCRIPTS_DIR}/sdlc.sh" start

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "requirements" ]] || [[ "$output" =~ "Requirements" ]]
}

@test "sdlc start updates state file" {
    "${SCRIPTS_DIR}/sdlc.sh" start

    grep -q "sdlc_phase" "${TEST_TMP_DIR}/.workflow/state.yaml"
}

@test "sdlc start fails if already started" {
    "${SCRIPTS_DIR}/sdlc.sh" start

    run "${SCRIPTS_DIR}/sdlc.sh" start

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "already" ]]
}

# ============================================================================
# PHASE PROGRESSION TESTS
# ============================================================================

@test "sdlc progresses through all phases in order" {
    local phases=("requirements" "design" "implementation" "verification" "deployment" "maintenance")

    "${SCRIPTS_DIR}/sdlc.sh" start

    # Start at requirements, advance through each
    for i in {1..5}; do
        run "${SCRIPTS_DIR}/sdlc.sh" next
        [[ "$status" -eq 0 ]]
    done

    # Should now be at maintenance
    run "${SCRIPTS_DIR}/sdlc.sh" status
    [[ "$output" =~ "maintenance" ]]
}

@test "sdlc next from requirements goes to design" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    run "${SCRIPTS_DIR}/sdlc.sh" next

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "design" ]]
}

@test "sdlc next from design goes to implementation" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next  # design
    run "${SCRIPTS_DIR}/sdlc.sh" next

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "implementation" ]]
}

@test "sdlc next from implementation goes to verification" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next  # design
    "${SCRIPTS_DIR}/sdlc.sh" next  # implementation
    run "${SCRIPTS_DIR}/sdlc.sh" next

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "verification" ]]
}

@test "sdlc next fails when not started" {
    run "${SCRIPTS_DIR}/sdlc.sh" next

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "not started" ]]
}

# ============================================================================
# FAILURE REGRESSION TESTS
# ============================================================================

@test "sdlc fail in verification regresses to implementation" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next  # design
    "${SCRIPTS_DIR}/sdlc.sh" next  # implementation
    "${SCRIPTS_DIR}/sdlc.sh" next  # verification

    run "${SCRIPTS_DIR}/sdlc.sh" fail "Tests failed"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "implementation" ]]
}

@test "sdlc fail in deployment regresses to verification" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next  # design
    "${SCRIPTS_DIR}/sdlc.sh" next  # implementation
    "${SCRIPTS_DIR}/sdlc.sh" next  # verification
    "${SCRIPTS_DIR}/sdlc.sh" next  # deployment

    run "${SCRIPTS_DIR}/sdlc.sh" fail "Deployment crashed"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "verification" ]]
}

@test "sdlc fail in early phase doesn't regress" {
    "${SCRIPTS_DIR}/sdlc.sh" start  # requirements

    run "${SCRIPTS_DIR}/sdlc.sh" fail "Requirements unclear"

    [[ "$status" -eq 0 ]]
    # Should not mention reverting
    [[ ! "$output" =~ "Reverting" ]] || [[ "$output" =~ "No regression" ]] || [[ "$output" =~ "blocking" ]]
}

@test "sdlc fail includes details message" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next
    "${SCRIPTS_DIR}/sdlc.sh" next
    "${SCRIPTS_DIR}/sdlc.sh" next

    run "${SCRIPTS_DIR}/sdlc.sh" fail "Custom error message 12345"

    [[ "$output" =~ "Custom error message 12345" ]] || [[ "$output" =~ "12345" ]]
}

# ============================================================================
# RESET TESTS
# ============================================================================

@test "sdlc reset clears state" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next

    run "${SCRIPTS_DIR}/sdlc.sh" reset

    [[ "$status" -eq 0 ]]

    # Should show not started after reset
    run "${SCRIPTS_DIR}/sdlc.sh" status
    [[ "$output" =~ "Not started" ]] || [[ "$output" =~ "none" ]]
}

@test "sdlc reset allows new start" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" reset
    run "${SCRIPTS_DIR}/sdlc.sh" start

    [[ "$status" -eq 0 ]]
}

# ============================================================================
# HELP TESTS
# ============================================================================

@test "sdlc help shows usage" {
    run "${SCRIPTS_DIR}/sdlc.sh" help

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Usage" ]]
}

@test "sdlc --help shows usage" {
    run "${SCRIPTS_DIR}/sdlc.sh" --help

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Usage" ]]
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "sdlc handles unknown action gracefully" {
    run "${SCRIPTS_DIR}/sdlc.sh" invalid_action

    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "Unknown" ]] || [[ "$output" =~ "unknown" ]]
}

# ============================================================================
# FULL CYCLE INTEGRATION TEST
# ============================================================================

@test "complete SDLC cycle from start to maintenance" {
    # Start
    run "${SCRIPTS_DIR}/sdlc.sh" start
    [[ "$status" -eq 0 ]]

    # Progress through all phases
    for phase in design implementation verification deployment maintenance; do
        run "${SCRIPTS_DIR}/sdlc.sh" next
        [[ "$status" -eq 0 ]]
    done

    # Verify at maintenance
    run "${SCRIPTS_DIR}/sdlc.sh" status
    [[ "$output" =~ "maintenance" ]]

    # Try next at maintenance - should indicate complete
    run "${SCRIPTS_DIR}/sdlc.sh" next
    [[ "$output" =~ "complete" ]] || [[ "$output" =~ "maintenance" ]]
}

@test "SDLC cycle with failure and recovery" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next  # design
    "${SCRIPTS_DIR}/sdlc.sh" next  # implementation
    "${SCRIPTS_DIR}/sdlc.sh" next  # verification

    # Fail verification
    "${SCRIPTS_DIR}/sdlc.sh" fail "Tests failed"

    # Should be back at implementation
    run "${SCRIPTS_DIR}/sdlc.sh" status
    [[ "$output" =~ "implementation" ]]

    # Fix and continue
    run "${SCRIPTS_DIR}/sdlc.sh" next  # back to verification
    [[ "$output" =~ "verification" ]]
}
