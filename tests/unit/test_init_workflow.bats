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
    [[ -f "${SCRIPTS_DIR}/init_workflow.sh" ]] || false
    [[ -x "${SCRIPTS_DIR}/init_workflow.sh" ]] || false
}

@test "init_workflow.sh creates .workflow directory" {
    # Remove existing .workflow to test fresh init
    rm -rf "${TEST_TMP_DIR}/.workflow"

    # Use echo with newline to simulate selection "3" for software
    run bash -c "echo '3' | ${SCRIPTS_DIR}/init_workflow.sh"

    [[ -d "${TEST_TMP_DIR}/.workflow" ]] || [[ "$output" =~ "Workflow" ]] || false
}

@test "init_workflow.sh creates state.yaml" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/state.yaml" ]] || false
}

@test "init_workflow.sh creates config.yaml" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/config.yaml" ]] || false
}

@test "init_workflow.sh creates agents directory" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -d "${TEST_TMP_DIR}/.workflow/agents" ]] || false
}

@test "init_workflow.sh creates no retired agent/skill artifacts" {
    # skills/ (catalog, enabled list) and agents/active.yaml belonged to the
    # retired `uws skill` / `uws agent` commands; nothing reads them.
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [ -f "${TEST_TMP_DIR}/.workflow/state.yaml" ]
    [ ! -e "${TEST_TMP_DIR}/.workflow/skills" ]
    [ ! -e "${TEST_TMP_DIR}/.workflow/agents/active.yaml" ]
    # the knowledge/patterns.yaml scaffold is retired: the KB is docs/kb/ (uws kb)
    [ ! -e "${TEST_TMP_DIR}/.workflow/knowledge" ]
    run grep -E "skill_chains_enabled|auto_discover|auto_activate" "${TEST_TMP_DIR}/.workflow/config.yaml"
    [ "$status" -ne 0 ]
}

# ============================================================================
# PROJECT TYPE TESTS
# ============================================================================

@test "init_workflow.sh accepts 'software' project type" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ "$status" -eq 0 ]] || false
    grep -q "software" "${TEST_TMP_DIR}/.workflow/state.yaml" || \
    grep -q "software" "${TEST_TMP_DIR}/.workflow/config.yaml"
}

@test "init_workflow.sh accepts 'research' project type" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "research"

    [[ "$status" -eq 0 ]] || false
}

@test "init_workflow.sh accepts 'ml' project type" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "ml"

    [[ "$status" -eq 0 ]] || false
}

@test "init_workflow.sh accepts 'llm' project type" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "llm"

    [[ "$status" -eq 0 ]] || false
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

@test "init_workflow.sh creates no empty top-level directories in the project" {
    # archive/, artifacts/ and phases/ were never used; workspace/<role>/ is created by
    # orchestrate dispatch when a subagent needs it
    rm -rf "${TEST_TMP_DIR}/.workflow" "${TEST_TMP_DIR}/workspace" "${TEST_TMP_DIR}/phases" "${TEST_TMP_DIR}/artifacts"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"
    [ "$status" -eq 0 ]

    local d
    for d in archive artifacts phases workspace; do
        [ ! -e "${TEST_TMP_DIR}/${d}" ]
    done
    [ -f "${TEST_TMP_DIR}/.workflow/state.yaml" ]
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
    [[ "$status" -eq 0 ]] || [[ "$output" =~ "already" ]] || [[ "$output" =~ "exists" ]] || false
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
    [[ "$output" =~ "already" ]] || [[ "$output" =~ "exists" ]] || false
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "init_workflow.sh handles missing git gracefully" {
    # Create a mock git that always fails
    local mock_dir="${TEST_TMP_DIR}/mock_bin"
    mkdir -p "${mock_dir}"

    # Create a mock git script that returns failure
    cat > "${mock_dir}/git" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "${mock_dir}/git"

    # This test checks that the script handles git absence
    # Most scripts should work without git (just skip git-specific features)
    rm -rf "${TEST_TMP_DIR}/.workflow"

    # Prepend mock dir to PATH so our broken git is found first
    PATH="${mock_dir}:${PATH}" run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    # Script should succeed - git features are optional
    # Either succeeds and creates workflow, or output mentions git issue
    [[ -d "${TEST_TMP_DIR}/.workflow" ]] || [[ "$output" =~ "git" ]] || [[ "$output" =~ "Git" ]] || false
}

@test "init_workflow.sh creates checkpoints.log" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/checkpoints.log" ]] || false
}

# ============================================================================
# AGENT REGISTRY TESTS
# ============================================================================

@test "init_workflow.sh creates agent registry" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    [[ -f "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" ]] || false
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
# CLI WRAPPER TESTS
# ============================================================================

@test "generated ./uws wrapper retires agent/skill and routes orchestrate" {
    rm -rf "${TEST_TMP_DIR}/.workflow" "${TEST_TMP_DIR}/uws"

    UWS_NO_WRAPPER=false run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"
    [ -x "${TEST_TMP_DIR}/uws" ]

    run "${TEST_TMP_DIR}/uws" agent researcher
    [ "$status" -ne 0 ]
    [[ "$output" == *"retired"* ]] || false
    [[ "$output" == *"orchestrate dispatch"* ]] || false

    run "${TEST_TMP_DIR}/uws" skill testing
    [ "$status" -ne 0 ]
    [[ "$output" == *"Skills are native Claude Code skills"* ]] || false

    run "${TEST_TMP_DIR}/uws" orchestrate help
    [ "$status" -eq 0 ]
    [[ "$output" == *"dispatch"* ]] || false
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

    [[ "$status" -eq 0 ]] || false
    [[ -d "${TEST_TMP_DIR}/.workflow" ]] || false
}

@test "init_workflow.sh works in non-git directory" {
    rm -rf "${TEST_TMP_DIR}/.workflow"
    rm -rf "${TEST_TMP_DIR}/.git"

    cd "${TEST_TMP_DIR}"
    run "${SCRIPTS_DIR}/init_workflow.sh" <<< "software"

    # Should either succeed or give helpful message about git
    [[ "$status" -eq 0 ]] || [[ "$output" =~ "git" ]] || false
}
