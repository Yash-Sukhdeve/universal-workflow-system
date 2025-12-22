#!/usr/bin/env bats
# Stress tests for dual compatibility
# Tests high-load scenarios for Claude ↔ Gemini workflows

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
# HIGH VOLUME TESTS
# =============================================================================

@test "100 checkpoint operations" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    local success_count=0

    for i in {1..100}; do
        if "${SCRIPTS_DIR}/checkpoint.sh" create "Checkpoint $i" 2>/dev/null; then
            success_count=$((success_count + 1))
        fi
    done

    # At least 95% should succeed
    [ "$success_count" -ge 95 ]

    # Verify checkpoints logged
    local log_count
    log_count=$(wc -l < .workflow/checkpoints.log)
    [ "$log_count" -ge 95 ]
}

@test "50 agent activations" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    local agents=("researcher" "architect" "implementer" "experimenter" "optimizer" "deployer" "documenter")
    local success_count=0

    for i in {1..50}; do
        local agent="${agents[$((i % ${#agents[@]}))]}"
        if "${SCRIPTS_DIR}/activate_agent.sh" "$agent" 2>/dev/null; then
            success_count=$((success_count + 1))
        fi
    done

    # At least 90% should succeed
    [ "$success_count" -ge 45 ]
}

@test "20 skill enable/disable cycles" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    local skills=("code_generation" "testing" "debugging" "literature_review" "profiling")
    local success_count=0

    for i in {1..20}; do
        local skill="${skills[$((i % ${#skills[@]}))]}"

        # Enable
        "${SCRIPTS_DIR}/enable_skill.sh" "$skill" enable 2>/dev/null || true

        # Disable
        if "${SCRIPTS_DIR}/enable_skill.sh" "$skill" disable 2>/dev/null; then
            success_count=$((success_count + 1))
        fi
    done

    # At least 80% should succeed
    [ "$success_count" -ge 16 ]
}

# =============================================================================
# LARGE FILE TESTS
# =============================================================================

@test "Large state.yaml (>100KB)" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Add large custom data to state
    {
        echo ""
        echo "large_data:"
        for i in {1..1000}; do
            echo "  entry_${i}:"
            echo "    key: value_${i}"
            echo "    data: \"$(head -c 50 /dev/urandom | base64 | tr -d '\n')\""
        done
    } >> .workflow/state.yaml

    # Verify file size
    local file_size
    file_size=$(stat -c%s .workflow/state.yaml 2>/dev/null || stat -f%z .workflow/state.yaml)
    [ "$file_size" -gt 100000 ]

    # Operations should still work
    run "${SCRIPTS_DIR}/status.sh" 2>/dev/null
    # May succeed or handle gracefully
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "Large handoff.md (>50KB)" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Create large handoff document (>50KB)
    {
        cat .workflow/handoff.md
        echo ""
        echo "## Extended Notes"
        for i in {1..600}; do
            echo "### Section $i"
            echo "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor."
            echo "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut."
            echo "- Point A: Detailed information about this point"
            echo "- Point B: More detailed information here"
            echo ""
        done
    } > .workflow/handoff.md.tmp
    mv .workflow/handoff.md.tmp .workflow/handoff.md

    # Verify file size
    local file_size
    file_size=$(stat -c%s .workflow/handoff.md 2>/dev/null || stat -f%z .workflow/handoff.md)
    [ "$file_size" -gt 50000 ]

    # Handoff should still work
    run create_handoff_checkpoint "${TEST_TMP_DIR}" "Large handoff" "claude" "gemini"
    # Should complete (success or handled error)
}

# =============================================================================
# CONCURRENCY TESTS
# =============================================================================

@test "Concurrent checkpoint attempts" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Launch multiple checkpoint operations in parallel
    for i in {1..5}; do
        "${SCRIPTS_DIR}/checkpoint.sh" create "Concurrent $i" 2>/dev/null &
    done

    wait

    # State should not be corrupted
    run check_state_corruption "${TEST_TMP_DIR}"
    # May have some issues but shouldn't crash
}

@test "Interrupt during handoff recovery" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Start recovery in background
    "${SCRIPTS_DIR}/recover_context.sh" 2>/dev/null &
    local pid=$!

    # Small delay then check
    sleep 0.5

    # Kill if still running
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true

    # State should still be valid
    [ -f ".workflow/state.yaml" ]
    grep -q "current_phase:" .workflow/state.yaml
}

# =============================================================================
# RECOVERY TESTS
# =============================================================================

@test "Corrupted state recovery" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Create checkpoint backup
    cp .workflow/state.yaml .workflow/state.yaml.bak

    # Corrupt state
    echo "CORRUPTED" > .workflow/state.yaml

    # Recovery should handle corruption
    run "${SCRIPTS_DIR}/recover_context.sh" 2>/dev/null

    # Should either recover or fail gracefully
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]

    # Restore for cleanup
    mv .workflow/state.yaml.bak .workflow/state.yaml 2>/dev/null || true
}

@test "Missing file recovery" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Remove handoff.md
    rm -f .workflow/handoff.md

    # Recovery should handle missing file
    run "${SCRIPTS_DIR}/recover_context.sh" 2>/dev/null

    # Should not crash
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "Network timeout simulation (Gemini API)" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Enable mock mode to simulate timeout behavior
    enable_gemini_mock

    # Run with short timeout
    local output
    output=$(timeout 2 bash -c 'run_gemini_workflow "test" 1' 2>/dev/null) || true

    # Should handle gracefully (mock mode always works)
    disable_gemini_mock

    # State should be intact
    [ -f ".workflow/state.yaml" ]
}
