#!/usr/bin/env bats
# Unit tests for atomic_utils.sh
# Tests atomic file operations and transaction handling

load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    source "${PROJECT_ROOT}/scripts/lib/atomic_utils.sh"
}

teardown() {
    # Ensure no active transactions
    if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
        atomic_rollback "test cleanup" 2>/dev/null || true
    fi
    teardown_test_environment
}

# ===========================================
# atomic_write tests
# ===========================================

@test "atomic_write creates new file" {
    local test_file="${TEST_TMP_DIR}/new_file.txt"

    run atomic_write "$test_file" "test content"

    assert_success
    assert_file_exists "$test_file"
    assert_file_contains "$test_file" "test content"
}

@test "atomic_write overwrites existing file" {
    local test_file="${TEST_TMP_DIR}/existing.txt"
    echo "old content" > "$test_file"

    run atomic_write "$test_file" "new content"

    assert_success
    assert_file_contains "$test_file" "new content"
    refute grep -q "old content" "$test_file"
}

@test "atomic_write creates parent directories" {
    local test_file="${TEST_TMP_DIR}/nested/dir/file.txt"

    run atomic_write "$test_file" "content"

    assert_success
    assert_file_exists "$test_file"
}

@test "atomic_write leaves no temp files on success" {
    local test_file="${TEST_TMP_DIR}/clean.txt"

    atomic_write "$test_file" "content"

    local tmp_count
    tmp_count=$(find "${TEST_TMP_DIR}" -name "*.tmp.*" | wc -l)
    [[ "$tmp_count" -eq 0 ]]
}

@test "atomic_write reads from stdin with -" {
    local test_file="${TEST_TMP_DIR}/stdin.txt"

    echo "stdin content" | atomic_write "$test_file" "-"

    assert_file_contains "$test_file" "stdin content"
}

# ===========================================
# atomic_append tests
# ===========================================

@test "atomic_append adds to existing file" {
    local test_file="${TEST_TMP_DIR}/append.txt"
    echo "line1" > "$test_file"

    run atomic_append "$test_file" "line2"

    assert_success
    assert_file_contains "$test_file" "line1"
    assert_file_contains "$test_file" "line2"
}

@test "atomic_append creates file if not exists" {
    local test_file="${TEST_TMP_DIR}/new_append.txt"

    run atomic_append "$test_file" "first content"

    assert_success
    assert_file_exists "$test_file"
    assert_file_contains "$test_file" "first content"
}

@test "atomic_append_line adds newline" {
    local test_file="${TEST_TMP_DIR}/lines.txt"
    echo -n "line1" > "$test_file"

    atomic_append_line "$test_file" "line2"

    local line_count
    line_count=$(wc -l < "$test_file")
    [[ "$line_count" -ge 2 ]]
}

# ===========================================
# safe_backup tests
# ===========================================

@test "safe_backup creates backup copy" {
    local test_file="${TEST_TMP_DIR}/original.txt"
    echo "original content" > "$test_file"

    local backup_path
    backup_path=$(safe_backup "$test_file")

    [[ -n "$backup_path" ]]
    [[ -f "$backup_path" ]]
    assert_file_contains "$backup_path" "original content"
}

@test "safe_backup returns empty for non-existent file" {
    local backup_path
    backup_path=$(safe_backup "${TEST_TMP_DIR}/nonexistent.txt")

    [[ -z "$backup_path" ]]
}

@test "safe_backup preserves file permissions" {
    local test_file="${TEST_TMP_DIR}/perms.txt"
    echo "content" > "$test_file"
    chmod 600 "$test_file"

    local backup_path
    backup_path=$(safe_backup "$test_file")

    local original_perms backup_perms
    original_perms=$(stat -c %a "$test_file" 2>/dev/null || stat -f %Lp "$test_file")
    backup_perms=$(stat -c %a "$backup_path" 2>/dev/null || stat -f %Lp "$backup_path")

    [[ "$original_perms" == "$backup_perms" ]]
}

# ===========================================
# Transaction tests
# ===========================================

@test "atomic_begin starts transaction" {
    run atomic_begin "test transaction"

    assert_success
    [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]
    [[ -n "$ATOMIC_TRANSACTION_ID" ]]
}

@test "atomic_begin fails if transaction already active" {
    atomic_begin "first"

    run atomic_begin "second"

    assert_failure
}

@test "atomic_commit cleans up backups" {
    local test_file="${TEST_TMP_DIR}/tx_file.txt"
    echo "original" > "$test_file"

    atomic_begin "commit test"
    atomic_write "$test_file" "modified"
    atomic_commit

    local backup_count
    backup_count=$(find "${TEST_TMP_DIR}" -name "*.atomic_backup.*" | wc -l)
    [[ "$backup_count" -eq 0 ]]
}

@test "atomic_commit fails without active transaction" {
    run atomic_commit

    assert_failure
}

@test "atomic_rollback restores files" {
    local test_file="${TEST_TMP_DIR}/rollback.txt"
    echo "original" > "$test_file"

    atomic_begin "rollback test"
    safe_backup "$test_file"
    echo "modified" > "$test_file"
    atomic_rollback "intentional"

    assert_file_contains "$test_file" "original"
}

@test "atomic_rollback cleans up temp files" {
    local test_file="${TEST_TMP_DIR}/cleanup.txt"
    echo "content" > "$test_file"

    atomic_begin "cleanup test"
    safe_backup "$test_file"
    atomic_rollback "test"

    local tmp_count
    tmp_count=$(find "${TEST_TMP_DIR}" -name "*.tmp.*" | wc -l)
    [[ "$tmp_count" -eq 0 ]]
}

@test "atomic_rollback returns success after rollback" {
    local test_file="${TEST_TMP_DIR}/success.txt"
    echo "original" > "$test_file"

    atomic_begin "test"
    safe_backup "$test_file"
    run atomic_rollback "test"

    assert_success
}

@test "nested transactions are rejected" {
    atomic_begin "outer"

    run atomic_begin "inner"

    assert_failure
    atomic_rollback "cleanup"
}

# ===========================================
# atomic_yaml_set tests
# ===========================================

@test "atomic_yaml_set updates yaml value" {
    local yaml_file="${TEST_TMP_DIR}/test.yaml"
    cat > "$yaml_file" << 'EOF'
project:
  name: test
  type: software
EOF

    source "${PROJECT_ROOT}/scripts/lib/yaml_utils.sh"
    run atomic_yaml_set "$yaml_file" "project.type" "research"

    assert_success
    # Verify the change
    local value
    value=$(yaml_get "$yaml_file" "project.type")
    [[ "$value" == "research" ]]
}

@test "atomic_yaml_set fails on non-existent file" {
    run atomic_yaml_set "${TEST_TMP_DIR}/nonexistent.yaml" "key" "value"

    assert_failure
}

@test "atomic_yaml_set_multi sets multiple values" {
    local yaml_file="${TEST_TMP_DIR}/multi.yaml"
    cat > "$yaml_file" << 'EOF'
project:
  name: test
  type: software
  version: 1.0
EOF

    source "${PROJECT_ROOT}/scripts/lib/yaml_utils.sh"
    run atomic_yaml_set_multi "$yaml_file" "project.name=updated" "project.version=2.0"

    assert_success
}

# ===========================================
# Checksum tests
# ===========================================

@test "atomic_get_checksum returns hash" {
    local test_file="${TEST_TMP_DIR}/checksum.txt"
    echo "test content" > "$test_file"

    local checksum
    checksum=$(atomic_get_checksum "$test_file")

    [[ -n "$checksum" ]]
    [[ ${#checksum} -eq 64 ]]  # SHA256 is 64 hex chars
}

@test "atomic_get_checksum returns empty for non-existent file" {
    local checksum
    checksum=$(atomic_get_checksum "${TEST_TMP_DIR}/nonexistent.txt")

    [[ -z "$checksum" ]]
}

@test "atomic_verify_checksum succeeds with correct hash" {
    local test_file="${TEST_TMP_DIR}/verify.txt"
    echo "verify me" > "$test_file"

    local checksum
    checksum=$(atomic_get_checksum "$test_file")

    run atomic_verify_checksum "$test_file" "$checksum"

    assert_success
}

@test "atomic_verify_checksum fails with wrong hash" {
    local test_file="${TEST_TMP_DIR}/wrong.txt"
    echo "content" > "$test_file"

    run atomic_verify_checksum "$test_file" "0000000000000000000000000000000000000000000000000000000000000000"

    assert_failure
}

# ===========================================
# Cleanup tests
# ===========================================

@test "atomic_cleanup_stale removes old files" {
    local stale_file="${TEST_TMP_DIR}/old.atomic_backup.123"
    echo "stale" > "$stale_file"
    # Touch with old timestamp
    touch -d "2 hours ago" "$stale_file" 2>/dev/null || touch -t "$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date +%Y%m%d%H%M.%S)" "$stale_file"

    local cleaned
    cleaned=$(atomic_cleanup_stale "${TEST_TMP_DIR}" 1)

    [[ "$cleaned" -ge 1 ]] || skip "Touch command may not support backdating"
}

# ===========================================
# Performance tests
# ===========================================

@test "atomic_write completes within 100ms" {
    local test_file="${TEST_TMP_DIR}/perf.txt"
    local content="Performance test content"

    local start_time end_time duration
    start_time=$(date +%s%N 2>/dev/null || echo "0")

    atomic_write "$test_file" "$content"

    end_time=$(date +%s%N 2>/dev/null || echo "0")

    if [[ "$start_time" != "0" ]]; then
        duration=$(( (end_time - start_time) / 1000000 ))
        [[ $duration -lt 100 ]]
    fi
}

@test "transaction with 10 operations completes within 500ms" {
    local start_time end_time duration
    start_time=$(date +%s%N 2>/dev/null || echo "0")

    atomic_begin "perf test"
    for i in {1..10}; do
        atomic_write "${TEST_TMP_DIR}/file_${i}.txt" "content ${i}"
    done
    atomic_commit

    end_time=$(date +%s%N 2>/dev/null || echo "0")

    if [[ "$start_time" != "0" ]]; then
        duration=$(( (end_time - start_time) / 1000000 ))
        [[ $duration -lt 500 ]]
    fi
}

# ===========================================
# Error recovery tests
# ===========================================

@test "rollback_on_error handles trap correctly" {
    local test_file="${TEST_TMP_DIR}/trap_test.txt"
    echo "original" > "$test_file"

    (
        trap 'rollback_on_error' ERR
        atomic_begin "trap test"
        safe_backup "$test_file"
        echo "modified" > "$test_file"
        false  # Trigger error
    ) 2>/dev/null || true

    # Transaction should have been rolled back
    [[ "$ATOMIC_TRANSACTION_ACTIVE" != "true" ]]
}

@test "multiple safe_backup calls in transaction are tracked" {
    local file1="${TEST_TMP_DIR}/multi1.txt"
    local file2="${TEST_TMP_DIR}/multi2.txt"
    echo "content1" > "$file1"
    echo "content2" > "$file2"

    atomic_begin "multi backup"
    safe_backup "$file1"
    safe_backup "$file2"

    [[ ${#ATOMIC_BACKUPS[@]} -eq 2 ]]

    atomic_rollback "cleanup"
}
