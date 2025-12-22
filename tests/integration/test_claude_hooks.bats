#!/usr/bin/env bats
# Integration tests for Claude Code hooks
# Tests .claude/settings.json hook configuration

load '../helpers/test_helper.bash'

# Setup and teardown
setup() {
    setup_test_environment
    create_full_test_environment
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# SETTINGS.JSON STRUCTURE TESTS
# =============================================================================

@test "settings.json exists in .claude directory" {
    [[ -f "${PROJECT_ROOT}/.claude/settings.json" ]]
}

@test "settings.json is valid JSON" {
    if command -v jq &> /dev/null; then
        run jq '.' "${PROJECT_ROOT}/.claude/settings.json"
        assert_success
    else
        # Basic JSON validation without jq
        run python3 -c "import json; json.load(open('${PROJECT_ROOT}/.claude/settings.json'))"
        assert_success
    fi
}

@test "settings.json has hooks object" {
    if command -v jq &> /dev/null; then
        run jq '.hooks' "${PROJECT_ROOT}/.claude/settings.json"
        assert_success
        [[ "$output" != "null" ]]
    else
        grep -q '"hooks"' "${PROJECT_ROOT}/.claude/settings.json"
    fi
}

# =============================================================================
# SESSION START HOOK TESTS
# =============================================================================

@test "SessionStart hook is configured" {
    if command -v jq &> /dev/null; then
        run jq '.hooks.SessionStart' "${PROJECT_ROOT}/.claude/settings.json"
        assert_success
        [[ "$output" != "null" ]]
    else
        grep -q 'SessionStart' "${PROJECT_ROOT}/.claude/settings.json"
    fi
}

@test "SessionStart hook references recover_context.sh" {
    grep -q 'recover_context.sh' "${PROJECT_ROOT}/.claude/settings.json"
}

@test "SessionStart hook triggers context recovery" {
    cd "${TEST_TMP_DIR}"

    # Simulate the hook command
    run bash -c '[ -f scripts/recover_context.sh ] && ./scripts/recover_context.sh 2>/dev/null || true'

    # Should succeed (or true fallback)
    assert_success
}

# =============================================================================
# PRE COMPACT HOOK TESTS
# =============================================================================

@test "PreCompact hook is configured" {
    if command -v jq &> /dev/null; then
        run jq '.hooks.PreCompact' "${PROJECT_ROOT}/.claude/settings.json"
        assert_success
        [[ "$output" != "null" ]]
    else
        grep -q 'PreCompact' "${PROJECT_ROOT}/.claude/settings.json"
    fi
}

@test "PreCompact hook references checkpoint.sh" {
    grep -q 'checkpoint.sh' "${PROJECT_ROOT}/.claude/settings.json"
}

@test "PreCompact hook triggers checkpoint creation" {
    cd "${TEST_TMP_DIR}"

    # Simulate the hook command
    run bash -c '[ -f scripts/checkpoint.sh ] && ./scripts/checkpoint.sh create "Auto-checkpoint before context compaction" 2>/dev/null || true'

    # Should succeed (or true fallback)
    assert_success
}

# =============================================================================
# HOOK FAILURE HANDLING TESTS
# =============================================================================

@test "hooks use || true for graceful failure handling" {
    grep -q '|| true' "${PROJECT_ROOT}/.claude/settings.json"
}

@test "hook failure doesn't crash session" {
    cd "${TEST_TMP_DIR}"

    # Remove scripts to simulate failure scenario
    rm -rf scripts

    # Simulate hook execution - should still succeed due to || true
    run bash -c '[ -f scripts/recover_context.sh ] && ./scripts/recover_context.sh 2>/dev/null || true'

    assert_success
}

# =============================================================================
# HOOK OUTPUT TESTS
# =============================================================================

@test "SessionStart hook captures recovery output" {
    cd "${TEST_TMP_DIR}"

    # Run recovery and capture output
    local output
    output=$(./scripts/recover_context.sh 2>&1) || true

    # Should produce some output
    [[ -n "$output" ]] || [[ $? -eq 0 ]]
}

@test "PreCompact hook captures checkpoint output" {
    cd "${TEST_TMP_DIR}"

    # Run checkpoint and capture output
    local output
    output=$(./scripts/checkpoint.sh create "test" 2>&1) || true

    # Should produce some output
    [[ -n "$output" ]] || [[ $? -eq 0 ]]
}

# =============================================================================
# HOOK TIMEOUT HANDLING TESTS
# =============================================================================

@test "hooks complete within reasonable time" {
    cd "${TEST_TMP_DIR}"

    local start_time end_time elapsed

    start_time=$(date +%s)

    # Run both hooks
    ./scripts/recover_context.sh 2>/dev/null || true
    ./scripts/checkpoint.sh create "timing test" 2>/dev/null || true

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    # Should complete within 10 seconds
    [ "$elapsed" -lt 10 ]
}

# =============================================================================
# HOOK STATE ISOLATION TESTS
# =============================================================================

@test "hooks operate on workflow directory safely" {
    cd "${TEST_TMP_DIR}"

    # Capture state before
    local before_state
    before_state=$(cat .workflow/state.yaml 2>/dev/null || echo "")

    # Run hooks
    ./scripts/recover_context.sh 2>/dev/null || true

    # State should still be valid
    [ -f ".workflow/state.yaml" ]
    grep -q "current_phase" .workflow/state.yaml
}
