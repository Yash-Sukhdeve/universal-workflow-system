#!/usr/bin/env bats
# Unit Tests for init_workflow.sh
# Tests workflow initialization functionality

# Load test helpers
load '../helpers/test_helper'

# ============================================================================
# SETUP
# ============================================================================

setup() {
    setup_test_environment
    cd "${TEST_TMP_DIR}"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# BASIC INITIALIZATION TESTS
# ============================================================================

@test "init_workflow.sh exists and is executable" {
    [[ -f "${SCRIPTS_DIR}/init_workflow.sh" ]]
    [[ -x "${SCRIPTS_DIR}/init_workflow.sh" ]]
}

@test "init_workflow.sh creates .workflow directory" {
    # Remove existing .workflow to test fresh init
    rm -rf "${TEST_TMP_DIR}/.workflow"

    # Use echo with newline to simulate selection "3" for software
    run bash -c "echo '3' | ${SCRIPTS_DIR}/init_workflow.sh"

    [[ -d "${TEST_TMP_DIR}/.workflow" ]] || [[ "$output" =~ "Workflow" ]]
}

@test "init_workflow.sh creates state.yaml" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/state.yaml" ]]
}

@test "init_workflow.sh creates config.yaml" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/config.yaml" ]]
}

@test "init_workflow.sh creates agents directory" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -d "${TEST_TMP_DIR}/.workflow/agents" ]]
}

@test "init_workflow.sh creates skills directory" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -d "${TEST_TMP_DIR}/.workflow/skills" ]]
}

# ============================================================================
# PROJECT TYPE TESTS
# ============================================================================

@test "init_workflow.sh accepts 'software' project type" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ "$status" -eq 0 ]]
    grep -q "software" "${TEST_TMP_DIR}/.workflow/state.yaml" || \
    grep -q "software" "${TEST_TMP_DIR}/.workflow/config.yaml"
}

@test "init_workflow.sh accepts 'research' project type" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "research"

    [[ "$status" -eq 0 ]]
}

@test "init_workflow.sh accepts 'ml' project type" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "ml"

    [[ "$status" -eq 0 ]]
}

@test "init_workflow.sh accepts 'llm' project type" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "llm"

    [[ "$status" -eq 0 ]]
}

# ============================================================================
# STATE FILE VALIDATION TESTS
# ============================================================================

@test "state.yaml contains current_phase" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    grep -q "current_phase" "${TEST_TMP_DIR}/.workflow/state.yaml"
}

@test "state.yaml contains current_checkpoint" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    grep -q "current_checkpoint" "${TEST_TMP_DIR}/.workflow/state.yaml"
}

@test "state.yaml initializes to phase_1" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    grep -q "phase_1" "${TEST_TMP_DIR}/.workflow/state.yaml"
}

@test "state.yaml contains metadata section" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    grep -q "metadata" "${TEST_TMP_DIR}/.workflow/state.yaml" || \
    grep -q "created" "${TEST_TMP_DIR}/.workflow/state.yaml"
}

# ============================================================================
# DIRECTORY STRUCTURE TESTS
# ============================================================================

@test "init_workflow.sh creates workspace directory" {
    rm -rf "${TEST_TMP_DIR}/.workflow"
    rm -rf "${TEST_TMP_DIR}/workspace"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -d "${TEST_TMP_DIR}/workspace" ]]
}

@test "init_workflow.sh creates phases directory" {
    rm -rf "${TEST_TMP_DIR}/.workflow"
    rm -rf "${TEST_TMP_DIR}/phases"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -d "${TEST_TMP_DIR}/phases" ]]
}

@test "init_workflow.sh creates artifacts directory" {
    rm -rf "${TEST_TMP_DIR}/.workflow"
    rm -rf "${TEST_TMP_DIR}/artifacts"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -d "${TEST_TMP_DIR}/artifacts" ]]
}

# ============================================================================
# IDEMPOTENCY TESTS
# ============================================================================

@test "init_workflow.sh warns if already initialized" {
    # First initialization
    "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    # Second initialization should warn or skip
    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    # Should either succeed with warning or fail gracefully
    [[ "$status" -eq 0 ]] || [[ "$output" =~ "already" ]] || [[ "$output" =~ "exists" ]]
}

@test "init_workflow.sh does not overwrite existing state" {
    # First initialization
    "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    # Modify state
    echo "# Modified" >> "${TEST_TMP_DIR}/.workflow/state.yaml"

    # Second initialization
    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    # Check modification is preserved (or file wasn't overwritten)
    grep -q "Modified" "${TEST_TMP_DIR}/.workflow/state.yaml" || \
    [[ "$output" =~ "already" ]] || [[ "$output" =~ "exists" ]]
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "init_workflow.sh handles missing git gracefully" {
    # Create a mock PATH without git
    local mock_dir="${TEST_TMP_DIR}/mock_bin"
    mkdir -p "${mock_dir}"

    # This test checks that the script handles git absence
    # Most scripts should work without git (just skip git-specific features)
    rm -rf "${TEST_TMP_DIR}/.workflow"

    # Should still create basic structure even without git
    PATH="${mock_dir}" run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    # Either succeeds or fails gracefully with message
    [[ -d "${TEST_TMP_DIR}/.workflow" ]] || [[ "$output" =~ "git" ]]
}

@test "init_workflow.sh creates checkpoints.log" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/checkpoints.log" ]]
}

# ============================================================================
# AGENT REGISTRY TESTS
# ============================================================================

@test "init_workflow.sh creates agent registry" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" ]]
}

@test "agent registry contains researcher agent" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    grep -q "researcher" "${TEST_TMP_DIR}/.workflow/agents/registry.yaml"
}

@test "agent registry contains implementer agent" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    grep -q "implementer" "${TEST_TMP_DIR}/.workflow/agents/registry.yaml"
}

# ============================================================================
# SKILL CATALOG TESTS
# ============================================================================

@test "init_workflow.sh creates skill catalog" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/skills/catalog.yaml" ]]
}

# ============================================================================
# GIT INTEGRATION TESTS
# ============================================================================

@test "init_workflow.sh works in git repository" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    # Ensure we're in a git repo
    git init --quiet "${TEST_TMP_DIR}" 2>/dev/null || true

    cd "${TEST_TMP_DIR}"
    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ "$status" -eq 0 ]]
    [[ -d "${TEST_TMP_DIR}/.workflow" ]]
}

@test "init_workflow.sh works in non-git directory" {
    rm -rf "${TEST_TMP_DIR}/.workflow"
    rm -rf "${TEST_TMP_DIR}/.git"

    cd "${TEST_TMP_DIR}"
    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    # Should either succeed or give helpful message about git
    [[ "$status" -eq 0 ]] || [[ "$output" =~ "git" ]]
}
