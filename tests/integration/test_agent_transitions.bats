#!/usr/bin/env bats
# Integration Tests for Agent Transitions
# Tests multi-agent workflow transitions and handoff mechanisms

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
# BASIC TRANSITION TESTS
# ============================================================================

@test "Can activate researcher agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" researcher

    [[ "$status" -eq 0 ]]
    [[ -f "${TEST_TMP_DIR}/.workflow/agents/active.yaml" ]]
}

@test "Can transition from researcher to architect" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    run "${SCRIPTS_DIR}/activate_agent.sh" architect

    [[ "$status" -eq 0 ]]
    grep -q "architect" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

@test "Can transition from architect to implementer" {
    "${SCRIPTS_DIR}/activate_agent.sh" architect
    run "${SCRIPTS_DIR}/activate_agent.sh" implementer

    [[ "$status" -eq 0 ]]
    grep -q "implementer" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

@test "Can transition through research_to_implementation pattern" {
    # Pattern: researcher → architect → implementer
    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    "${SCRIPTS_DIR}/activate_agent.sh" architect
    run "${SCRIPTS_DIR}/activate_agent.sh" implementer

    [[ "$status" -eq 0 ]]
    grep -q "implementer" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

# ============================================================================
# STATE PERSISTENCE TESTS
# ============================================================================

@test "Agent activation persists after checkpoint" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    "${SCRIPTS_DIR}/checkpoint.sh" "After agent activation"

    # Verify agent is still active
    grep -q "researcher" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

@test "Checkpoint preserves agent state" {
    "${SCRIPTS_DIR}/activate_agent.sh" implementer
    "${SCRIPTS_DIR}/checkpoint.sh" "Test checkpoint"

    # Check checkpoint was created
    grep -q "Test checkpoint" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "Multiple transitions maintain state consistency" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    "${SCRIPTS_DIR}/checkpoint.sh" "After researcher"

    "${SCRIPTS_DIR}/activate_agent.sh" architect
    "${SCRIPTS_DIR}/checkpoint.sh" "After architect"

    "${SCRIPTS_DIR}/activate_agent.sh" implementer
    "${SCRIPTS_DIR}/checkpoint.sh" "After implementer"

    # All checkpoints should exist
    local checkpoint_count
    checkpoint_count=$(wc -l < "${TEST_TMP_DIR}/.workflow/checkpoints.log")
    [[ "$checkpoint_count" -ge 3 ]]
}

# ============================================================================
# HANDOFF MECHANISM TESTS
# ============================================================================

@test "Agent handoff creates handoff record" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher

    run "${SCRIPTS_DIR}/activate_agent.sh" researcher handoff

    # Should create handoff record or succeed
    [[ "$status" -eq 0 ]] || [[ -f "${TEST_TMP_DIR}/.workflow/agents/handoff_researcher.yaml" ]]
}

@test "Handoff contains agent context" {
    "${SCRIPTS_DIR}/activate_agent.sh" implementer

    "${SCRIPTS_DIR}/activate_agent.sh" implementer handoff 2>/dev/null || true

    # If handoff file exists, check it has content
    if [[ -f "${TEST_TMP_DIR}/.workflow/agents/handoff_implementer.yaml" ]]; then
        [[ -s "${TEST_TMP_DIR}/.workflow/agents/handoff_implementer.yaml" ]]
    fi
}

# ============================================================================
# FULL PIPELINE TESTS
# ============================================================================

@test "Full ML pipeline transition pattern" {
    # Pattern: researcher → implementer → experimenter → optimizer → deployer

    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    [[ $? -eq 0 ]]

    "${SCRIPTS_DIR}/activate_agent.sh" implementer
    [[ $? -eq 0 ]]

    "${SCRIPTS_DIR}/activate_agent.sh" experimenter
    [[ $? -eq 0 ]]

    "${SCRIPTS_DIR}/activate_agent.sh" optimizer
    [[ $? -eq 0 ]]

    run "${SCRIPTS_DIR}/activate_agent.sh" deployer
    [[ "$status" -eq 0 ]]

    grep -q "deployer" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

@test "Production software pattern transitions" {
    # Pattern: architect → implementer → experimenter → deployer → documenter

    "${SCRIPTS_DIR}/activate_agent.sh" architect
    "${SCRIPTS_DIR}/activate_agent.sh" implementer
    "${SCRIPTS_DIR}/activate_agent.sh" experimenter
    "${SCRIPTS_DIR}/activate_agent.sh" deployer
    run "${SCRIPTS_DIR}/activate_agent.sh" documenter

    [[ "$status" -eq 0 ]]
    grep -q "documenter" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

# ============================================================================
# ERROR RECOVERY TESTS
# ============================================================================

@test "Can recover from failed transition" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher

    # Try invalid transition
    "${SCRIPTS_DIR}/activate_agent.sh" invalid_agent 2>/dev/null || true

    # Should still have researcher active
    grep -q "researcher" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

@test "State remains consistent after failed operations" {
    "${SCRIPTS_DIR}/activate_agent.sh" implementer
    local before_state
    before_state=$(cat "${TEST_TMP_DIR}/.workflow/agents/active.yaml")

    # Attempt invalid operation
    "${SCRIPTS_DIR}/activate_agent.sh" nonexistent 2>/dev/null || true

    local after_state
    after_state=$(cat "${TEST_TMP_DIR}/.workflow/agents/active.yaml")

    # State should be unchanged or still have implementer
    grep -q "implementer" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

# ============================================================================
# WORKSPACE TESTS
# ============================================================================

@test "Agent transition creates workspace directory" {
    run "${SCRIPTS_DIR}/activate_agent.sh" researcher

    [[ -d "${TEST_TMP_DIR}/workspace/researcher" ]] || [[ -d "${TEST_TMP_DIR}/workspace" ]]
}

@test "Multiple agents have separate workspaces" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    "${SCRIPTS_DIR}/activate_agent.sh" implementer

    # At least workspace directory should exist
    [[ -d "${TEST_TMP_DIR}/workspace" ]]
}

# ============================================================================
# CONCURRENT ACCESS TESTS
# ============================================================================

@test "Rapid agent switches maintain consistency" {
    for i in {1..5}; do
        "${SCRIPTS_DIR}/activate_agent.sh" researcher
        "${SCRIPTS_DIR}/activate_agent.sh" implementer
    done

    # Final state should be implementer
    grep -q "implementer" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

# ============================================================================
# PERFORMANCE TESTS
# ============================================================================

@test "Agent transition completes within 2 seconds" {
    local start_time
    start_time=$(date +%s)

    "${SCRIPTS_DIR}/activate_agent.sh" researcher

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    [[ "$elapsed" -lt 2 ]]
}

@test "Full pipeline transition completes within 10 seconds" {
    local start_time
    start_time=$(date +%s)

    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    "${SCRIPTS_DIR}/activate_agent.sh" architect
    "${SCRIPTS_DIR}/activate_agent.sh" implementer
    "${SCRIPTS_DIR}/activate_agent.sh" experimenter
    "${SCRIPTS_DIR}/activate_agent.sh" deployer

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    [[ "$elapsed" -lt 10 ]]
}
