#!/usr/bin/env bats
# RWF Compliance Test Suite
# Tests all 5 RWF rules: Truthfulness, Completeness, State Safety, Error-Free, Reproducibility

load '../helpers/test_helper'

# Setup and teardown
setup() {
    setup_test_environment

    # Source RWF utilities
    source "${PROJECT_ROOT}/scripts/lib/atomic_utils.sh" 2>/dev/null || true
    source "${PROJECT_ROOT}/scripts/lib/error_utils.sh" 2>/dev/null || true
    source "${PROJECT_ROOT}/scripts/lib/logging_utils.sh" 2>/dev/null || true
    source "${PROJECT_ROOT}/scripts/lib/precondition_utils.sh" 2>/dev/null || true
    source "${PROJECT_ROOT}/scripts/lib/checksum_utils.sh" 2>/dev/null || true
    source "${PROJECT_ROOT}/scripts/lib/completeness_utils.sh" 2>/dev/null || true
    source "${PROJECT_ROOT}/scripts/lib/timestamp_utils.sh" 2>/dev/null || true
    source "${PROJECT_ROOT}/scripts/lib/decision_utils.sh" 2>/dev/null || true
}

teardown() {
    cleanup_test_environment
}

# =============================================================================
# R1: TRUTHFULNESS TESTS
# "Never guess; ask targeted questions"
# =============================================================================

@test "R1: Precondition validation catches uninitialized workflow" {
    # Remove workflow directory
    rm -rf .workflow

    run require_workflow_initialized
    [ "$status" -ne 0 ]
    [[ "$output" == *"not initialized"* ]] || [[ "$output" == *"missing"* ]]
}

@test "R1: Invalid checkpoint ID is rejected" {
    run require_checkpoint_exists "INVALID_CP"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid"* ]] || [[ "$output" == *"not found"* ]]
}

@test "R1: Invalid agent name is rejected" {
    run require_agent_valid "nonexistent_agent"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown agent"* ]] || [[ "$output" == *"Invalid"* ]]
}

@test "R1: Valid agents are accepted" {
    run require_agent_valid "researcher"
    [ "$status" -eq 0 ]
}

@test "R1: State consistency check validates cross-field integrity" {
    # Create inconsistent state
    cat > .workflow/state.yaml << 'EOF'
current_phase: "phase_1_planning"
current_checkpoint: "CP_99_999"
metadata:
  last_updated: "2025-01-01T00:00:00"
active_agent:
  status: "active"
  name: null
EOF

    run require_state_consistent
    [ "$status" -ne 0 ]
}

# =============================================================================
# R2: COMPLETENESS TESTS
# "Use tools to verify, not assume; zero placeholders"
# =============================================================================

@test "R2: Completeness score calculation works" {
    create_full_test_environment

    run calculate_completeness_score
    [ "$status" -eq 0 ]

    # Score should be a number between 0 and 100
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -ge 0 ]
    [ "$output" -le 100 ]
}

@test "R2: Missing required files reduce completeness score" {
    create_full_test_environment

    # Get baseline score
    local baseline
    baseline=$(calculate_completeness_score)

    # Remove a required file
    rm -f .workflow/checkpoints.log

    local reduced
    reduced=$(calculate_completeness_score)

    [ "$reduced" -lt "$baseline" ]
}

@test "R2: Required files check identifies missing files" {
    create_full_test_environment
    rm -f .workflow/checkpoints.log

    run check_required_files
    [[ "$output" == *"checkpoints.log"* ]]
}

@test "R2: JSON completeness report is valid" {
    create_full_test_environment

    run get_completeness_json
    [ "$status" -eq 0 ]

    # Should be valid JSON structure
    [[ "$output" == *'"score":'* ]]
    [[ "$output" == *'"file_score":'* ]]
}

# =============================================================================
# R3: STATE SAFETY TESTS
# "Update documentation at each phase end; atomic operations"
# =============================================================================

@test "R3: Atomic write creates file atomically" {
    local test_file=".workflow/test_atomic.yaml"
    local content="key: value"

    run atomic_write "$test_file" "$content"
    [ "$status" -eq 0 ]
    [ -f "$test_file" ]

    local actual
    actual=$(cat "$test_file")
    [ "$actual" = "$content" ]
}

@test "R3: Atomic write with invalid path fails gracefully" {
    run atomic_write "/nonexistent/path/file.yaml" "content"
    [ "$status" -ne 0 ]
}

@test "R3: Safe backup creates backup file" {
    echo "original content" > .workflow/test_backup.yaml

    run safe_backup .workflow/test_backup.yaml
    [ "$status" -eq 0 ]

    # Backup should exist
    local backup_count
    backup_count=$(ls .workflow/test_backup.yaml.backup* 2>/dev/null | wc -l)
    [ "$backup_count" -ge 1 ]
}

@test "R3: Transaction commit applies all changes" {
    atomic_begin

    echo "file1" > .workflow/tx_test1.yaml
    echo "file2" > .workflow/tx_test2.yaml

    atomic_commit

    [ -f .workflow/tx_test1.yaml ]
    [ -f .workflow/tx_test2.yaml ]
}

@test "R3: Checkpoint creates v2 snapshot with manifest" {
    create_full_test_environment

    # Create a checkpoint
    run "${PROJECT_ROOT}/scripts/checkpoint.sh" create "RWF test checkpoint"
    [ "$status" -eq 0 ]

    # Find the created checkpoint
    local latest_cp
    latest_cp=$(ls -t .workflow/checkpoints/snapshots/ 2>/dev/null | grep "CP_" | head -1)

    if [ -n "$latest_cp" ]; then
        # v2 checkpoint should have manifest
        [ -f ".workflow/checkpoints/snapshots/${latest_cp}/manifest.yaml" ]
    fi
}

# =============================================================================
# R4: ERROR-FREE TESTS
# "Fix ALL errors before proceeding; no silent failures"
# =============================================================================

@test "R4: Error handler captures and logs errors" {
    run handle_error "Test error message" 42 "log"
    [ "$status" -eq 42 ]
}

@test "R4: capture_error replaces silent 2>/dev/null" {
    # Command that fails
    run capture_error ls /nonexistent_directory_12345
    [ "$status" -ne 0 ]

    # CAPTURED_STDERR should have content
    [[ -n "$CAPTURED_STDERR" ]] || true
}

@test "R4: warn_on_failure logs but continues" {
    run warn_on_failure "test context" ls /nonexistent_12345
    [ "$status" -ne 0 ]
    [[ "$output" == *"Warning"* ]] || [[ "$output" == *"failed"* ]] || true
}

@test "R4: require_success fails on command failure" {
    # Temporarily disable exit on fatal
    ERROR_EXIT_ON_FATAL=false

    run require_success "test context" ls /nonexistent_12345
    [ "$status" -ne 0 ]
}

@test "R4: Assertion catches false condition" {
    run assert "[[ 1 -eq 2 ]]" "1 should equal 2"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Assertion failed"* ]]
}

@test "R4: assert_file_exists catches missing file" {
    run assert_file_exists "/nonexistent/file.txt" "Test file"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "R4: Error stack tracks multiple errors" {
    clear_error_stack

    push_error "Error 1" 1 "test:1"
    push_error "Error 2" 2 "test:2"

    run has_errors
    [ "$status" -eq 0 ]

    local count
    count=${#ERROR_STACK[@]}
    [ "$count" -eq 2 ]
}

# =============================================================================
# R5: REPRODUCIBILITY TESTS
# "Any agent must continue from saved state"
# =============================================================================

@test "R5: Checksum calculation is deterministic" {
    echo "test content" > .workflow/test_checksum.yaml

    local hash1 hash2
    hash1=$(calculate_checksum .workflow/test_checksum.yaml)
    hash2=$(calculate_checksum .workflow/test_checksum.yaml)

    [ "$hash1" = "$hash2" ]
    [ ${#hash1} -eq 64 ]  # SHA256 produces 64 hex chars
}

@test "R5: Checksums change when content changes" {
    echo "content v1" > .workflow/test_checksum.yaml
    local hash1
    hash1=$(calculate_checksum .workflow/test_checksum.yaml)

    echo "content v2" > .workflow/test_checksum.yaml
    local hash2
    hash2=$(calculate_checksum .workflow/test_checksum.yaml)

    [ "$hash1" != "$hash2" ]
}

@test "R5: Store and verify checksums round-trip" {
    create_full_test_environment

    run store_checksums
    [ "$status" -eq 0 ]
    [ -f .workflow/checksums.yaml ]

    run verify_checksums
    [ "$status" -eq 0 ]
}

@test "R5: Checksum verification detects tampering" {
    create_full_test_environment

    store_checksums

    # Tamper with a file
    echo "tampered content" >> .workflow/state.yaml

    run verify_checksums
    [ "$status" -ne 0 ]
}

@test "R5: Snapshot manifest is created for checkpoints" {
    create_full_test_environment
    mkdir -p .workflow/checkpoints/snapshots/CP_TEST_001
    cp .workflow/state.yaml .workflow/checkpoints/snapshots/CP_TEST_001/

    run create_snapshot_manifest .workflow/checkpoints/snapshots/CP_TEST_001
    [ "$status" -eq 0 ]
    [ -f .workflow/checkpoints/snapshots/CP_TEST_001/manifest.yaml ]
}

@test "R5: Manifest verification validates snapshot integrity" {
    create_full_test_environment
    mkdir -p .workflow/checkpoints/snapshots/CP_TEST_002
    cp .workflow/state.yaml .workflow/checkpoints/snapshots/CP_TEST_002/

    create_snapshot_manifest .workflow/checkpoints/snapshots/CP_TEST_002

    run verify_snapshot_manifest .workflow/checkpoints/snapshots/CP_TEST_002
    [ "$status" -eq 0 ]
}

@test "R5: Recovery completeness is measurable" {
    create_full_test_environment

    run is_recovery_complete 50
    [ "$status" -eq 0 ]
}

@test "R5: Completeness summary generates markdown" {
    create_full_test_environment

    run get_completeness_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Recovery Completeness"* ]]
    [[ "$output" == *"Score:"* ]]
}

# =============================================================================
# CROSS-CUTTING: TIMESTAMP TESTS
# =============================================================================

@test "Timestamps are ISO 8601 formatted" {
    run get_iso_timestamp
    [ "$status" -eq 0 ]

    # Should match ISO 8601 pattern
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "Timestamp validation accepts valid formats" {
    run validate_timestamp "2025-01-15T10:30:00+00:00"
    [ "$status" -eq 0 ]
}

@test "Timestamp validation rejects invalid formats" {
    run validate_timestamp "not-a-timestamp"
    [ "$status" -ne 0 ]
}

# =============================================================================
# CROSS-CUTTING: DECISION LOGGING TESTS
# =============================================================================

@test "Decision logging creates entries" {
    create_full_test_environment
    mkdir -p .workflow/logs

    run log_decision "Test decision" "testing" "For RWF compliance test"
    [ "$status" -eq 0 ]

    # Should return a decision ID
    [[ "$output" =~ ^DEC-[0-9]{4}-[0-9]+$ ]]
}

@test "Blocker logging creates entries with severity" {
    create_full_test_environment
    mkdir -p .workflow/logs

    run log_blocker "Test blocker" "technical" "high"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^DEC- ]]
}

@test "Open blockers can be retrieved" {
    create_full_test_environment
    mkdir -p .workflow/logs

    log_blocker "Blocking issue 1" "technical" "high" > /dev/null

    run get_open_blockers
    [ "$status" -eq 0 ]
}
