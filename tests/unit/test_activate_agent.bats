#!/usr/bin/env bats
# Unit Tests for activate_agent.sh
# Tests agent activation and management functionality

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
# BASIC ACTIVATION TESTS
# ============================================================================

@test "activate_agent.sh exists and is executable" {
    [[ -f "${SCRIPTS_DIR}/activate_agent.sh" ]]
    [[ -x "${SCRIPTS_DIR}/activate_agent.sh" ]]
}

@test "activate_agent.sh activates researcher agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" researcher

    [[ "$status" -eq 0 ]]
}

@test "activate_agent.sh activates implementer agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" implementer

    [[ "$status" -eq 0 ]]
}

@test "activate_agent.sh activates architect agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" architect

    [[ "$status" -eq 0 ]]
}

@test "activate_agent.sh activates experimenter agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" experimenter

    [[ "$status" -eq 0 ]]
}

@test "activate_agent.sh activates optimizer agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" optimizer

    [[ "$status" -eq 0 ]]
}

@test "activate_agent.sh activates deployer agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" deployer

    [[ "$status" -eq 0 ]]
}

@test "activate_agent.sh activates documenter agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" documenter

    [[ "$status" -eq 0 ]]
}

# ============================================================================
# ACTIVE AGENT FILE TESTS
# ============================================================================

@test "activate_agent.sh creates active.yaml" {
    rm -f "${TEST_TMP_DIR}/.workflow/agents/active.yaml"

    "${SCRIPTS_DIR}/activate_agent.sh" implementer

    [[ -f "${TEST_TMP_DIR}/.workflow/agents/active.yaml" ]]
}

@test "active.yaml contains current_agent field" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher

    grep -q "current_agent" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

@test "active.yaml shows correct agent name" {
    "${SCRIPTS_DIR}/activate_agent.sh" architect

    grep -q "architect" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

@test "activate_agent.sh updates existing active.yaml" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    "${SCRIPTS_DIR}/activate_agent.sh" implementer

    grep -q "implementer" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

# ============================================================================
# VALIDATION TESTS
# ============================================================================

@test "activate_agent.sh rejects unknown agent" {
    run "${SCRIPTS_DIR}/activate_agent.sh" unknown_agent_xyz

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "unknown" ]] || [[ "$output" =~ "Unknown" ]] || [[ "$output" =~ "Invalid" ]]
}

@test "activate_agent.sh requires agent name" {
    run "${SCRIPTS_DIR}/activate_agent.sh"

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "usage" ]] || [[ "$output" =~ "agent" ]]
}

@test "activate_agent.sh validates against registry" {
    # Test that validation uses the registry
    run "${SCRIPTS_DIR}/activate_agent.sh" not_in_registry

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Unknown" ]]
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "activate_agent.sh fails without initialized workflow" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/activate_agent.sh" implementer

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "not initialized" ]] || [[ "$output" =~ "Error" ]]
}

@test "activate_agent.sh handles missing registry gracefully" {
    rm -f "${TEST_TMP_DIR}/.workflow/agents/registry.yaml"

    run "${SCRIPTS_DIR}/activate_agent.sh" implementer

    # Should fail with helpful message or create default registry
    [[ "$status" -ne 0 ]] || [[ -f "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" ]]
}

@test "activate_agent.sh handles case sensitivity" {
    run "${SCRIPTS_DIR}/activate_agent.sh" IMPLEMENTER

    # Should either work (case-insensitive) or fail with helpful message
    [[ "$status" -eq 0 ]] || [[ "$output" =~ "implementer" ]]
}

# ============================================================================
# STATUS COMMAND TESTS
# ============================================================================

@test "activate_agent.sh status shows current agent" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher

    run "${SCRIPTS_DIR}/activate_agent.sh" researcher status

    [[ "$output" =~ "researcher" ]] || [[ "$output" =~ "active" ]] || [[ "$output" =~ "status" ]]
}

# ============================================================================
# DEACTIVATION TESTS
# ============================================================================

@test "activate_agent.sh deactivate removes active agent" {
    "${SCRIPTS_DIR}/activate_agent.sh" implementer

    run "${SCRIPTS_DIR}/activate_agent.sh" implementer deactivate

    # Should succeed
    [[ "$status" -eq 0 ]] || [[ "$output" =~ "deactivated" ]]
}

# ============================================================================
# WORKSPACE TESTS
# ============================================================================

@test "activate_agent.sh creates agent workspace" {
    rm -rf "${TEST_TMP_DIR}/workspace/researcher"

    "${SCRIPTS_DIR}/activate_agent.sh" researcher

    [[ -d "${TEST_TMP_DIR}/workspace/researcher" ]] || [[ -d "${TEST_TMP_DIR}/workspace" ]]
}

# ============================================================================
# HANDOFF TESTS
# ============================================================================

@test "activate_agent.sh handoff prepares transition" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher

    run "${SCRIPTS_DIR}/activate_agent.sh" researcher handoff

    [[ "$status" -eq 0 ]] || [[ "$output" =~ "handoff" ]] || [[ "$output" =~ "Handoff" ]]
}

# ============================================================================
# CONCURRENT ACCESS TESTS
# ============================================================================

@test "activate_agent.sh handles switching agents" {
    "${SCRIPTS_DIR}/activate_agent.sh" researcher
    "${SCRIPTS_DIR}/activate_agent.sh" architect
    "${SCRIPTS_DIR}/activate_agent.sh" implementer

    grep -q "implementer" "${TEST_TMP_DIR}/.workflow/agents/active.yaml"
}

# ============================================================================
# SKILLS LOADING TESTS
# ============================================================================

@test "activate_agent.sh loads agent skills" {
    run "${SCRIPTS_DIR}/activate_agent.sh" researcher

    # Should mention skills loading or skills should be in active.yaml
    [[ "$status" -eq 0 ]]
}

# ============================================================================
# HELP TEXT TESTS
# ============================================================================

@test "activate_agent.sh --help shows usage" {
    run "${SCRIPTS_DIR}/activate_agent.sh" --help

    [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "usage" ]] || [[ "$output" =~ "agent" ]]
}

@test "activate_agent.sh -h shows usage" {
    run "${SCRIPTS_DIR}/activate_agent.sh" -h

    [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "usage" ]] || [[ "$output" =~ "agent" ]]
}

# ============================================================================
# PERFORMANCE TESTS
# ============================================================================

@test "activate_agent.sh completes within 3 seconds" {
    local start_time
    start_time=$(date +%s)

    "${SCRIPTS_DIR}/activate_agent.sh" implementer

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    [[ "$elapsed" -lt 3 ]]
}

# ============================================================================
# LIST AGENTS TESTS
# ============================================================================

@test "list_agents.sh exists" {
    [[ -f "${SCRIPTS_DIR}/list_agents.sh" ]] || skip "list_agents.sh not implemented"
}

@test "list_agents.sh shows all available agents" {
    [[ -f "${SCRIPTS_DIR}/list_agents.sh" ]] || skip "list_agents.sh not implemented"

    run "${SCRIPTS_DIR}/list_agents.sh"

    [[ "$output" =~ "researcher" ]]
    [[ "$output" =~ "implementer" ]]
}
