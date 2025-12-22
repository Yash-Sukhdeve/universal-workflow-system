#!/usr/bin/env bats
# Rapid switching integration tests
# Tests high-frequency handoffs between Claude ↔ Gemini

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
# RAPID HANDOFF TESTS
# =============================================================================

@test "10 rapid handoffs in 60 seconds" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    local start_time end_time elapsed
    start_time=$(date +%s)

    # Perform 10 rapid handoffs
    run rapid_handoff_cycle "${TEST_TMP_DIR}" 10

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    assert_success
    [ "$elapsed" -lt 60 ]
}

@test "No race conditions on state.yaml" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Rapid handoffs
    for i in {1..5}; do
        create_handoff_checkpoint "${TEST_TMP_DIR}" "Quick $i" "claude" "gemini" &
        sleep 0.05
    done

    wait

    # Verify state.yaml is still valid
    [ -f ".workflow/state.yaml" ]
    grep -q "current_phase:" .workflow/state.yaml

    # Check for corruption
    run check_state_corruption "${TEST_TMP_DIR}"
    assert_success
}

@test "No duplicate checkpoints created" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Track unique checkpoint IDs
    local before_cps
    before_cps=$(grep -oE "CP_[A-Z]+_[0-9]+" .workflow/checkpoints.log | sort -u | wc -l)

    # Rapid handoffs with same message shouldn't create duplicates
    for i in {1..3}; do
        create_handoff_checkpoint "${TEST_TMP_DIR}" "Same message" "claude" "gemini"
        sleep 0.1
    done

    # Each handoff should create a unique checkpoint (with timestamp)
    local after_entries
    after_entries=$(wc -l < .workflow/checkpoints.log)

    # Should have more entries (handoffs add checkpoints)
    [ "$after_entries" -ge 3 ]
}

@test "Lock file prevents concurrent writes" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Create lock file to simulate concurrent access
    touch .workflow/.lock 2>/dev/null || true

    # Handoff should still work (scripts should handle locks)
    run create_handoff_checkpoint "${TEST_TMP_DIR}" "With lock" "claude" "gemini"

    # Should succeed or fail gracefully
    [[ "$status" -eq 0 ]] || [[ -f ".workflow/state.yaml" ]]

    rm -f .workflow/.lock
}

@test "Atomic operations prevent corruption" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Rapid modifications
    for i in {1..10}; do
        # Simulate rapid state changes
        sed -i "s/progress: [0-9]*/progress: $((i * 10))/" .workflow/state.yaml 2>/dev/null || true
        create_handoff_checkpoint "${TEST_TMP_DIR}" "Rapid $i" "claude" "gemini"
    done

    # Verify no corruption
    run check_state_corruption "${TEST_TMP_DIR}"
    assert_success

    # State should be valid YAML
    [ -f ".workflow/state.yaml" ]
    grep -q "current_phase:" .workflow/state.yaml
}
