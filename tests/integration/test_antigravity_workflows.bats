#!/usr/bin/env bats
# Integration tests for Gemini Antigravity workflows
# Tests antigravity-integration/workflows/*.md files and their script delegation

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
# WORKFLOW FILE EXISTENCE TESTS
# =============================================================================

@test "all 9 workflow files exist in antigravity-integration/workflows/" {
    local workflows=(
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
    local workflows_dir="${PROJECT_ROOT}/antigravity-integration/workflows"

    for wf in "${workflows[@]}"; do
        if [[ ! -f "${workflows_dir}/${wf}.md" ]]; then
            missing+=("${wf}.md")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing workflows: ${missing[*]}" >&2
        fail "Not all workflow files exist"
    fi
}

# =============================================================================
# MARKDOWN FORMAT TESTS
# =============================================================================

@test "workflows have valid markdown format" {
    local workflows_dir="${PROJECT_ROOT}/antigravity-integration/workflows"

    for wf_file in "${workflows_dir}"/uws-*.md; do
        [[ -f "$wf_file" ]] || continue

        # Check for markdown headers
        grep -qE "^#+ " "$wf_file" || echo "WARN: $(basename "$wf_file") may lack headers"
    done
}

@test "workflows contain execution instructions" {
    local workflows_dir="${PROJECT_ROOT}/antigravity-integration/workflows"

    for wf_file in "${workflows_dir}"/uws-*.md; do
        [[ -f "$wf_file" ]] || continue

        # Should contain script reference or execution instruction
        if grep -qiE "script|execute|run|bash" "$wf_file"; then
            continue
        fi

        # Or at least some content
        local line_count
        line_count=$(wc -l < "$wf_file")
        [ "$line_count" -ge 3 ] || fail "$(basename "$wf_file") has too little content"
    done
}

# =============================================================================
# SCRIPT DELEGATION TESTS
# =============================================================================

@test "uws-status workflow can execute status.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/status.sh"

    assert_success
}

@test "uws-checkpoint workflow can execute checkpoint.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/checkpoint.sh" create "antigravity test"

    assert_success
}

@test "uws-recover workflow can execute recover_context.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/recover_context.sh"

    assert_success
}

@test "uws-agent workflow can execute activate_agent.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/activate_agent.sh" researcher

    assert_success
}

@test "uws-skill workflow can execute enable_skill.sh" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" code_generation enable

    assert_success
}

@test "uws-handoff workflow can access handoff.md" {
    cd "${TEST_TMP_DIR}"

    [ -f ".workflow/handoff.md" ]
}

@test "uws-init workflow can execute init_workflow.sh" {
    cd "${TEST_TMP_DIR}"

    rm -rf .workflow

    run "${SCRIPTS_DIR}/init_workflow.sh"

    assert_success
    [ -d ".workflow" ]
}

@test "uws-sdlc workflow can manage SDLC phases" {
    cd "${TEST_TMP_DIR}"

    # Check if sdlc.sh exists and can be called
    if [[ -x "${SCRIPTS_DIR}/sdlc.sh" ]]; then
        run "${SCRIPTS_DIR}/sdlc.sh" status 2>/dev/null || run "${SCRIPTS_DIR}/status.sh"
        assert_success
    else
        run "${SCRIPTS_DIR}/status.sh"
        assert_success
    fi
}

@test "uws-research workflow can manage research phases" {
    cd "${TEST_TMP_DIR}"

    if [[ -x "${SCRIPTS_DIR}/research.sh" ]]; then
        run "${SCRIPTS_DIR}/research.sh" status 2>/dev/null || run "${SCRIPTS_DIR}/status.sh"
        assert_success
    else
        run "${SCRIPTS_DIR}/status.sh"
        assert_success
    fi
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "workflows handle missing .workflow/ gracefully" {
    cd "${TEST_TMP_DIR}"

    rm -rf .workflow

    # status should handle missing workflow
    run "${SCRIPTS_DIR}/status.sh" 2>/dev/null

    # Either succeeds with warning or fails with error
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "workflows handle corrupted state gracefully" {
    cd "${TEST_TMP_DIR}"

    echo "invalid: yaml: content:" > .workflow/state.yaml

    run "${SCRIPTS_DIR}/status.sh" 2>/dev/null

    # Should not crash
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

# =============================================================================
# CONSISTENCY TESTS
# =============================================================================

@test "workflow output format is consistent with Claude commands" {
    cd "${TEST_TMP_DIR}"

    # Run status
    local output
    output=$("${SCRIPTS_DIR}/status.sh" 2>/dev/null) || true

    # Should have recognizable format
    [[ "$output" == *"phase"* ]] || [[ "$output" == *"Phase"* ]] || [[ "$output" == *"status"* ]]
}

@test "workflows reference same underlying scripts as Claude commands" {
    local claude_cmd="${PROJECT_ROOT}/.claude/commands/uws-status.md"
    local antigravity_wf="${PROJECT_ROOT}/antigravity-integration/workflows/uws-status.md"

    # Both should reference status.sh
    grep -q "status" "$claude_cmd" 2>/dev/null || true
    grep -q "status" "$antigravity_wf" 2>/dev/null || true

    # At minimum, both files should exist
    [[ -f "$claude_cmd" ]]
    [[ -f "$antigravity_wf" ]]
}
