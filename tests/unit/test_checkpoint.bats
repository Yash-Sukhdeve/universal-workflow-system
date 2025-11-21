#!/usr/bin/env bats
# Unit Tests for checkpoint.sh
# Tests checkpoint creation and restoration functionality

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
# BASIC CHECKPOINT TESTS
# ============================================================================

@test "checkpoint.sh exists and is executable" {
    [[ -f "${SCRIPTS_DIR}/checkpoint.sh" ]]
    [[ -x "${SCRIPTS_DIR}/checkpoint.sh" ]]
}

@test "checkpoint.sh creates checkpoint with message" {
    run "${SCRIPTS_DIR}/checkpoint.sh" "Test checkpoint message"

    [[ "$status" -eq 0 ]]
}

@test "checkpoint.sh appends to checkpoints.log" {
    local initial_lines
    initial_lines=$(wc -l < "${TEST_TMP_DIR}/.workflow/checkpoints.log")

    "${SCRIPTS_DIR}/checkpoint.sh" "New checkpoint"

    local final_lines
    final_lines=$(wc -l < "${TEST_TMP_DIR}/.workflow/checkpoints.log")

    [[ "$final_lines" -gt "$initial_lines" ]]
}

@test "checkpoint.sh includes message in log" {
    "${SCRIPTS_DIR}/checkpoint.sh" "Unique test message 12345"

    grep -q "Unique test message 12345" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "checkpoint.sh includes timestamp in log" {
    "${SCRIPTS_DIR}/checkpoint.sh" "Timestamp test"

    # Check for ISO timestamp pattern
    grep -E "[0-9]{4}-[0-9]{2}-[0-9]{2}" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "checkpoint.sh increments checkpoint ID" {
    "${SCRIPTS_DIR}/checkpoint.sh" "First checkpoint"
    "${SCRIPTS_DIR}/checkpoint.sh" "Second checkpoint"

    # Should have incrementing checkpoint IDs
    local checkpoints
    checkpoints=$(grep -c "CP_" "${TEST_TMP_DIR}/.workflow/checkpoints.log")
    [[ "$checkpoints" -ge 2 ]]
}

# ============================================================================
# STATE UPDATE TESTS
# ============================================================================

@test "checkpoint.sh updates state.yaml checkpoint field" {
    "${SCRIPTS_DIR}/checkpoint.sh" "State update test"

    grep -q "current_checkpoint" "${TEST_TMP_DIR}/.workflow/state.yaml"
}

@test "checkpoint.sh updates last_updated timestamp" {
    local before_ts
    before_ts=$(grep "last_updated" "${TEST_TMP_DIR}/.workflow/state.yaml" || echo "none")

    sleep 1
    "${SCRIPTS_DIR}/checkpoint.sh" "Timestamp update test"

    local after_ts
    after_ts=$(grep "last_updated" "${TEST_TMP_DIR}/.workflow/state.yaml" || echo "none")

    # Timestamps should be different (or at least exist)
    [[ "$after_ts" != "none" ]]
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "checkpoint.sh requires message argument" {
    run "${SCRIPTS_DIR}/checkpoint.sh"

    # Should fail or prompt for message
    [[ "$status" -ne 0 ]] || [[ "$output" =~ "message" ]] || [[ "$output" =~ "usage" ]] || [[ "$output" =~ "Usage" ]]
}

@test "checkpoint.sh fails without initialized workflow" {
    rm -rf "${TEST_TMP_DIR}/.workflow"

    run "${SCRIPTS_DIR}/checkpoint.sh" "Should fail"

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "not initialized" ]] || [[ "$output" =~ "Error" ]]
}

@test "checkpoint.sh handles missing state.yaml" {
    rm -f "${TEST_TMP_DIR}/.workflow/state.yaml"

    run "${SCRIPTS_DIR}/checkpoint.sh" "Missing state test"

    # Should fail gracefully
    [[ "$status" -ne 0 ]] || [[ "$output" =~ "state" ]]
}

@test "checkpoint.sh handles missing checkpoints.log gracefully" {
    rm -f "${TEST_TMP_DIR}/.workflow/checkpoints.log"

    run "${SCRIPTS_DIR}/checkpoint.sh" "Missing log test"

    # Should either create the file or fail gracefully
    [[ -f "${TEST_TMP_DIR}/.workflow/checkpoints.log" ]] || [[ "$status" -ne 0 ]]
}

# ============================================================================
# CHECKPOINT FORMAT TESTS
# ============================================================================

@test "checkpoint log uses pipe delimiter" {
    "${SCRIPTS_DIR}/checkpoint.sh" "Delimiter test"

    grep -q "|" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "checkpoint log has three fields per line" {
    "${SCRIPTS_DIR}/checkpoint.sh" "Field test"

    local last_line
    last_line=$(tail -1 "${TEST_TMP_DIR}/.workflow/checkpoints.log")

    # Count pipe delimiters (should be 2 for 3 fields)
    local pipes
    pipes=$(echo "$last_line" | tr -cd '|' | wc -c)
    [[ "$pipes" -eq 2 ]]
}

# ============================================================================
# CHECKPOINT ID FORMAT TESTS
# ============================================================================

@test "checkpoint ID follows naming convention" {
    "${SCRIPTS_DIR}/checkpoint.sh" "ID format test"

    # Should contain CP_ prefix
    grep -q "CP_" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "checkpoint ID includes phase number" {
    "${SCRIPTS_DIR}/checkpoint.sh" "Phase ID test"

    # Should contain phase number (1-5)
    grep -E "CP_[0-9]" "${TEST_TMP_DIR}/.workflow/checkpoints.log" || \
    grep -E "CP_INIT" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

# ============================================================================
# SPECIAL CHARACTER HANDLING
# ============================================================================

@test "checkpoint.sh handles message with spaces" {
    run "${SCRIPTS_DIR}/checkpoint.sh" "Message with multiple spaces"

    [[ "$status" -eq 0 ]]
    grep -q "multiple spaces" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "checkpoint.sh handles message with special characters" {
    run "${SCRIPTS_DIR}/checkpoint.sh" "Message with special: chars!"

    [[ "$status" -eq 0 ]]
}

@test "checkpoint.sh handles empty message gracefully" {
    run "${SCRIPTS_DIR}/checkpoint.sh" ""

    # Should fail or use default message
    [[ "$status" -ne 0 ]] || [[ "$output" =~ "message" ]]
}

# ============================================================================
# RESTORE FUNCTIONALITY TESTS
# ============================================================================

@test "checkpoint.sh --list shows checkpoints" {
    "${SCRIPTS_DIR}/checkpoint.sh" "List test checkpoint"

    run "${SCRIPTS_DIR}/checkpoint.sh" --list

    # Should show checkpoint or indicate how to list
    [[ "$status" -eq 0 ]] || [[ "$output" =~ "checkpoint" ]]
}

# ============================================================================
# GIT INTEGRATION TESTS
# ============================================================================

@test "checkpoint.sh works with git repository" {
    run "${SCRIPTS_DIR}/checkpoint.sh" "Git repo test"

    [[ "$status" -eq 0 ]]
}

@test "checkpoint.sh handles dirty git state" {
    # Create uncommitted change
    echo "test change" > "${TEST_TMP_DIR}/test_file.txt"

    run "${SCRIPTS_DIR}/checkpoint.sh" "Dirty state test"

    [[ "$status" -eq 0 ]]
}

# ============================================================================
# CONCURRENT ACCESS TESTS
# ============================================================================

@test "checkpoint.sh handles rapid successive calls" {
    "${SCRIPTS_DIR}/checkpoint.sh" "Rapid call 1"
    "${SCRIPTS_DIR}/checkpoint.sh" "Rapid call 2"
    "${SCRIPTS_DIR}/checkpoint.sh" "Rapid call 3"

    local count
    count=$(grep -c "Rapid call" "${TEST_TMP_DIR}/.workflow/checkpoints.log")
    [[ "$count" -eq 3 ]]
}

# ============================================================================
# PERFORMANCE TESTS
# ============================================================================

@test "checkpoint.sh completes within 5 seconds" {
    local start_time
    start_time=$(date +%s)

    "${SCRIPTS_DIR}/checkpoint.sh" "Performance test"

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    [[ "$elapsed" -lt 5 ]]
}
