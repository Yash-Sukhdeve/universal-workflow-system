#!/usr/bin/env bats
# Checksum Utilities Test Suite
# Tests SHA256 checksum verification for state files - RWF R5 (Reproducibility)

load '../helpers/test_helper'

# Setup and teardown
setup() {
    setup_test_environment

    # Source checksum utilities
    source "${PROJECT_ROOT}/scripts/lib/checksum_utils.sh"
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# BASIC CHECKSUM CALCULATION
# =============================================================================

@test "calculate_checksum produces 64-character hex string" {
    echo "test content" > .workflow/test.yaml

    local checksum
    checksum=$(calculate_checksum .workflow/test.yaml)

    [ ${#checksum} -eq 64 ]
    [[ "$checksum" =~ ^[a-f0-9]+$ ]]
}

@test "calculate_checksum returns empty for missing file" {
    run calculate_checksum .workflow/nonexistent.yaml
    [ "$status" -ne 0 ]
    [ -z "$output" ] || [ "$output" = "" ]
}

@test "calculate_checksum is deterministic" {
    echo "deterministic content" > .workflow/test.yaml

    local hash1 hash2
    hash1=$(calculate_checksum .workflow/test.yaml)
    hash2=$(calculate_checksum .workflow/test.yaml)

    [ "$hash1" = "$hash2" ]
}

@test "calculate_checksum detects content changes" {
    echo "version 1" > .workflow/test.yaml
    local hash1
    hash1=$(calculate_checksum .workflow/test.yaml)

    echo "version 2" > .workflow/test.yaml
    local hash2
    hash2=$(calculate_checksum .workflow/test.yaml)

    [ "$hash1" != "$hash2" ]
}

@test "calculate_checksum different for different files" {
    echo "content A" > .workflow/file_a.yaml
    echo "content B" > .workflow/file_b.yaml

    local hash_a hash_b
    hash_a=$(calculate_checksum .workflow/file_a.yaml)
    hash_b=$(calculate_checksum .workflow/file_b.yaml)

    [ "$hash_a" != "$hash_b" ]
}

# =============================================================================
# STATE CHECKSUM (COMBINED)
# =============================================================================

@test "calculate_state_checksum combines multiple files" {
    create_full_test_environment

    run calculate_state_checksum .workflow
    [ "$status" -eq 0 ]
    [ ${#output} -eq 64 ]
}

@test "calculate_state_checksum changes when any file changes" {
    create_full_test_environment

    local hash1
    hash1=$(calculate_state_checksum .workflow)

    echo "modified" >> .workflow/state.yaml

    local hash2
    hash2=$(calculate_state_checksum .workflow)

    [ "$hash1" != "$hash2" ]
}

@test "calculate_state_checksum handles missing optional files" {
    mkdir -p .workflow
    echo "current_phase: phase_1" > .workflow/state.yaml
    # No handoff.md or checkpoints.log

    run calculate_state_checksum .workflow
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# =============================================================================
# STORE AND VERIFY CHECKSUMS
# =============================================================================

@test "store_checksums creates checksums.yaml" {
    create_full_test_environment

    run store_checksums .workflow
    [ "$status" -eq 0 ]
    [ -f .workflow/checksums.yaml ]
}

@test "store_checksums includes timestamp" {
    create_full_test_environment

    store_checksums .workflow

    run grep "generated:" .workflow/checksums.yaml
    [ "$status" -eq 0 ]
}

@test "store_checksums includes algorithm" {
    create_full_test_environment

    store_checksums .workflow

    run grep "algorithm:" .workflow/checksums.yaml
    [ "$status" -eq 0 ]
    [[ "$output" == *"sha256"* ]]
}

@test "store_checksums includes file entries" {
    create_full_test_environment

    store_checksums .workflow

    run grep "state.yaml" .workflow/checksums.yaml
    [ "$status" -eq 0 ]
}

@test "store_checksums includes combined checksum" {
    create_full_test_environment

    store_checksums .workflow

    run grep "combined:" .workflow/checksums.yaml
    [ "$status" -eq 0 ]
}

@test "verify_checksums succeeds with valid checksums" {
    create_full_test_environment

    store_checksums .workflow

    run verify_checksums .workflow
    [ "$status" -eq 0 ]
}

@test "verify_checksums fails when file modified" {
    create_full_test_environment

    store_checksums .workflow

    # Modify a file
    echo "tampered" >> .workflow/state.yaml

    run verify_checksums .workflow
    [ "$status" -ne 0 ]
}

@test "verify_checksums fails when file deleted" {
    create_full_test_environment
    echo "extra content" > .workflow/handoff.md

    store_checksums .workflow

    # Delete a file
    rm -f .workflow/handoff.md

    run verify_checksums .workflow
    [ "$status" -ne 0 ]
}

@test "verify_checksums warns when checksums.yaml missing" {
    create_full_test_environment

    run verify_checksums .workflow
    [ "$status" -ne 0 ]
    [[ "$output" == *"No checksums"* ]] || [[ "$output" == *"not found"* ]]
}

# =============================================================================
# SINGLE FILE VERIFICATION
# =============================================================================

@test "verify_file_checksum succeeds with correct hash" {
    echo "known content" > .workflow/test.yaml
    local expected
    expected=$(calculate_checksum .workflow/test.yaml)

    run verify_file_checksum .workflow/test.yaml "$expected"
    [ "$status" -eq 0 ]
}

@test "verify_file_checksum fails with wrong hash" {
    echo "known content" > .workflow/test.yaml

    run verify_file_checksum .workflow/test.yaml "0000000000000000000000000000000000000000000000000000000000000000"
    [ "$status" -ne 0 ]
    [[ "$output" == *"mismatch"* ]]
}

@test "verify_file_checksum fails for missing file" {
    run verify_file_checksum .workflow/nonexistent.yaml "anyhash"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# =============================================================================
# SNAPSHOT MANIFEST
# =============================================================================

@test "create_snapshot_manifest creates manifest.yaml" {
    mkdir -p .workflow/checkpoints/snapshots/CP_1_001
    echo "state content" > .workflow/checkpoints/snapshots/CP_1_001/state.yaml
    echo "handoff content" > .workflow/checkpoints/snapshots/CP_1_001/handoff.md

    run create_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_001
    [ "$status" -eq 0 ]
    [ -f .workflow/checkpoints/snapshots/CP_1_001/manifest.yaml ]
}

@test "create_snapshot_manifest includes version" {
    mkdir -p .workflow/checkpoints/snapshots/CP_1_002
    echo "state" > .workflow/checkpoints/snapshots/CP_1_002/state.yaml

    create_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_002

    run grep "version:" .workflow/checkpoints/snapshots/CP_1_002/manifest.yaml
    [ "$status" -eq 0 ]
    [[ "$output" == *"2.0"* ]]
}

@test "create_snapshot_manifest includes file checksums" {
    mkdir -p .workflow/checkpoints/snapshots/CP_1_003
    echo "state" > .workflow/checkpoints/snapshots/CP_1_003/state.yaml

    create_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_003

    run grep "checksum:" .workflow/checkpoints/snapshots/CP_1_003/manifest.yaml
    [ "$status" -eq 0 ]
}

@test "create_snapshot_manifest includes file count" {
    mkdir -p .workflow/checkpoints/snapshots/CP_1_004
    echo "state" > .workflow/checkpoints/snapshots/CP_1_004/state.yaml
    echo "handoff" > .workflow/checkpoints/snapshots/CP_1_004/handoff.md

    create_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_004

    run grep "total_files:" .workflow/checkpoints/snapshots/CP_1_004/manifest.yaml
    [ "$status" -eq 0 ]
}

@test "create_snapshot_manifest includes combined checksum" {
    mkdir -p .workflow/checkpoints/snapshots/CP_1_005
    echo "state" > .workflow/checkpoints/snapshots/CP_1_005/state.yaml

    create_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_005

    run grep "combined_checksum:" .workflow/checkpoints/snapshots/CP_1_005/manifest.yaml
    [ "$status" -eq 0 ]
}

@test "create_snapshot_manifest fails for nonexistent directory" {
    run create_snapshot_manifest .workflow/nonexistent
    [ "$status" -ne 0 ]
}

@test "verify_snapshot_manifest succeeds for valid snapshot" {
    mkdir -p .workflow/checkpoints/snapshots/CP_1_006
    echo "state" > .workflow/checkpoints/snapshots/CP_1_006/state.yaml

    create_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_006

    run verify_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_006
    [ "$status" -eq 0 ]
}

@test "verify_snapshot_manifest fails when file tampered" {
    mkdir -p .workflow/checkpoints/snapshots/CP_1_007
    echo "original" > .workflow/checkpoints/snapshots/CP_1_007/state.yaml

    create_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_007

    # Tamper with file
    echo "tampered" > .workflow/checkpoints/snapshots/CP_1_007/state.yaml

    run verify_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_007
    [ "$status" -ne 0 ]
}

@test "verify_snapshot_manifest handles v1 checkpoints gracefully" {
    # v1 checkpoint has no manifest
    mkdir -p .workflow/checkpoints/snapshots/CP_1_008
    echo "state" > .workflow/checkpoints/snapshots/CP_1_008/state.yaml

    run verify_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_008
    [ "$status" -eq 0 ]  # Should pass for v1 (no manifest = legacy)
}

# =============================================================================
# JSON OUTPUT
# =============================================================================

@test "get_checksums_json returns valid JSON structure" {
    create_full_test_environment

    run get_checksums_json .workflow
    [ "$status" -eq 0 ]
    [[ "$output" == *'"generated":'* ]]
    [[ "$output" == *'"algorithm":'* ]]
    [[ "$output" == *'"files":'* ]]
    [[ "$output" == *'"combined":'* ]]
}

@test "get_checksums_json includes timestamp" {
    create_full_test_environment

    local output
    output=$(get_checksums_json .workflow)

    [[ "$output" == *'"generated":'* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "checksums handle empty files" {
    touch .workflow/empty.yaml

    run calculate_checksum .workflow/empty.yaml
    [ "$status" -eq 0 ]
    [ ${#output} -eq 64 ]
}

@test "checksums handle large files" {
    # Create a larger file (100KB)
    dd if=/dev/urandom of=.workflow/large.yaml bs=1024 count=100 2>/dev/null

    run calculate_checksum .workflow/large.yaml
    [ "$status" -eq 0 ]
    [ ${#output} -eq 64 ]
}

@test "checksums handle special characters in content" {
    cat > .workflow/special.yaml << 'EOF'
key: "value with 'quotes' and \"escapes\""
unicode: "日本語テスト"
multiline: |
  line 1
  line 2
EOF

    run calculate_checksum .workflow/special.yaml
    [ "$status" -eq 0 ]
    [ ${#output} -eq 64 ]
}

@test "checksums handle files with spaces in path" {
    mkdir -p ".workflow/path with spaces"
    echo "content" > ".workflow/path with spaces/file.yaml"

    run calculate_checksum ".workflow/path with spaces/file.yaml"
    [ "$status" -eq 0 ]
    [ ${#output} -eq 64 ]
}
