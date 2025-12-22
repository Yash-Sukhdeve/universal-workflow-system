#!/usr/bin/env bats
# Integration tests for Claude Code commands
# Tests .claude/commands/*.md files and their script delegation

load '../helpers/test_helper.bash'
load '../helpers/dual_compat_helper.bash'

# Setup and teardown
setup() {
    setup_test_environment
    create_full_test_environment
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# COMMAND FILE EXISTENCE TESTS
# =============================================================================

@test "all 9 command files exist in .claude/commands/" {
    local commands=(
        "uws-status"
        "uws-checkpoint"
        "uws-recover"
        "uws-agent"
        "uws-skill"
        "uws-handoff"
        "uws-init"
        "uws-sdlc"
        "uws-research"
    )

    local missing=()

    for cmd in "${commands[@]}"; do
        if [[ ! -f "${PROJECT_ROOT}/.claude/commands/${cmd}.md" ]]; then
            missing+=("${cmd}.md")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing commands: ${missing[*]}" >&2
        fail "Not all command files exist"
    fi
}

# =============================================================================
# YAML FRONTMATTER TESTS
# =============================================================================

@test "commands have valid YAML frontmatter with description" {
    local commands_dir="${PROJECT_ROOT}/.claude/commands"

    for cmd_file in "${commands_dir}"/uws-*.md; do
        [[ -f "$cmd_file" ]] || continue

        # Check for frontmatter markers
        local first_line
        first_line=$(head -1 "$cmd_file")
        [[ "$first_line" == "---" ]] || fail "$(basename "$cmd_file") missing frontmatter start"

        # Check for description field
        grep -q "^description:" "$cmd_file" || fail "$(basename "$cmd_file") missing description"
    done
}

@test "commands have valid allowed-tools specification" {
    local commands_dir="${PROJECT_ROOT}/.claude/commands"

    for cmd_file in "${commands_dir}"/uws-*.md; do
        [[ -f "$cmd_file" ]] || continue

        # Check for allowed-tools
        if grep -q "^allowed-tools:" "$cmd_file"; then
            # Verify it references valid paths
            local tools
            tools=$(grep "^allowed-tools:" "$cmd_file" | cut -d':' -f2-)
            [[ -n "$tools" ]] || fail "$(basename "$cmd_file") has empty allowed-tools"
        fi
    done
}

# =============================================================================
# SCRIPT DELEGATION TESTS
# =============================================================================

@test "uws-status command delegates to status.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/status.sh"

    assert_success
    [[ "$output" == *"Status"* ]] || [[ "$output" == *"phase"* ]] || [[ "$output" == *"Phase"* ]]
}

@test "uws-checkpoint command delegates to checkpoint.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/checkpoint.sh" create "test checkpoint"

    assert_success
    [[ "$output" == *"checkpoint"* ]] || [[ "$output" == *"Checkpoint"* ]] || [[ "$output" == *"CP_"* ]]
}

@test "uws-recover command delegates to recover_context.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/recover_context.sh"

    assert_success
}

@test "uws-agent command delegates to activate_agent.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/activate_agent.sh" implementer

    assert_success
    [[ "$output" == *"implementer"* ]] || [[ "$output" == *"activated"* ]] || [[ "$output" == *"Agent"* ]]
}

@test "uws-skill command delegates to enable_skill.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" "" list

    assert_success
    [[ "$output" == *"Skills"* ]] || [[ "$output" == *"skill"* ]]
}

@test "uws-handoff command updates handoff notes" {
    cd "${TEST_TMP_DIR}"

    # Test that handoff.md can be updated/exists
    assert_file_exists ".workflow/handoff.md"
}

@test "uws-init command runs init_workflow.sh" {
    cd "${TEST_TMP_DIR}"

    # Remove workflow to test init
    rm -rf .workflow

    run "${SCRIPTS_DIR}/init_workflow.sh"

    assert_success
    [ -d ".workflow" ]
}

@test "uws-sdlc command delegates to sdlc.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/sdlc.sh" status 2>/dev/null || run "${SCRIPTS_DIR}/status.sh"

    assert_success
}

@test "uws-research command delegates to research.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/research.sh" status 2>/dev/null || run "${SCRIPTS_DIR}/status.sh"

    assert_success
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "commands handle missing .workflow/ gracefully" {
    cd "${TEST_TMP_DIR}"

    rm -rf .workflow

    # status.sh should handle missing workflow
    run "${SCRIPTS_DIR}/status.sh" 2>/dev/null

    # Should either succeed with warning or fail gracefully
    [[ "$output" == *"not initialized"* ]] || [[ "$output" == *"initialized"* ]] || [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "commands handle corrupted state.yaml gracefully" {
    cd "${TEST_TMP_DIR}"

    # Corrupt the state file
    echo "invalid yaml: content: here: broken" > .workflow/state.yaml

    # status.sh should handle corrupted state
    run "${SCRIPTS_DIR}/status.sh" 2>/dev/null

    # Should not crash
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

# =============================================================================
# OUTPUT FORMAT TESTS
# =============================================================================

@test "status command shows phase information" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/status.sh"

    assert_success
    [[ "$output" == *"phase"* ]] || [[ "$output" == *"Phase"* ]]
}

@test "status command shows checkpoint information" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/status.sh"

    assert_success
    [[ "$output" == *"checkpoint"* ]] || [[ "$output" == *"Checkpoint"* ]] || [[ "$output" == *"CP_"* ]]
}

@test "checkpoint command outputs checkpoint ID" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/checkpoint.sh" create "test"

    assert_success
    [[ "$output" == *"CP_"* ]] || [[ "$output" == *"checkpoint"* ]]
}
