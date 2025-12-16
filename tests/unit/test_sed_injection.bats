#!/usr/bin/env bats
# Security Tests for sed injection prevention
# Tests that special characters in input don't cause command injection

# Load test helpers
load '../helpers/test_helper'

# ============================================================================
# SETUP
# ============================================================================

setup() {
    setup_test_environment
    create_full_test_environment "${TEST_TMP_DIR}"
    cd "${TEST_TMP_DIR}"

    # Source yaml_utils to test safe_sed_replace
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh" 2>/dev/null || true
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# safe_sed_replace() FUNCTION TESTS
# ============================================================================

@test "safe_sed_replace function exists" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"
    declare -f safe_sed_replace > /dev/null
}

@test "safe_sed_replace handles forward slash in value" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    echo "test_key: old_value" > test.yaml
    safe_sed_replace test.yaml "test_key" "value/with/slashes"

    grep -q 'test_key: "value/with/slashes"' test.yaml
}

@test "safe_sed_replace handles ampersand in value" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    echo "test_key: old_value" > test.yaml
    safe_sed_replace test.yaml "test_key" "value&with&ampersands"

    grep -q 'test_key: "value&with&ampersands"' test.yaml
}

@test "safe_sed_replace handles backslash in value" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    echo "test_key: old_value" > test.yaml
    safe_sed_replace test.yaml "test_key" 'value\with\backslashes'

    grep -q 'backslash' test.yaml
}

@test "safe_sed_replace handles mixed special characters" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    echo "test_key: old_value" > test.yaml
    safe_sed_replace test.yaml "test_key" "path/to/file&more"

    grep -q 'test_key:' test.yaml
    # File should not be corrupted
    [[ -s test.yaml ]]
}

# ============================================================================
# CHECKPOINT INJECTION TESTS
# ============================================================================

@test "checkpoint handles message with forward slashes" {
    run "${SCRIPTS_DIR}/checkpoint.sh" "Fixed bug in src/lib/utils.js"

    [[ "$status" -eq 0 ]]
    grep -q "src/lib/utils.js" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "checkpoint handles message with ampersand" {
    run "${SCRIPTS_DIR}/checkpoint.sh" "Updated R&D module"

    [[ "$status" -eq 0 ]]
    grep -q "R&D" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "checkpoint handles message with special regex characters" {
    run "${SCRIPTS_DIR}/checkpoint.sh" "Fixed [issue] with (regex)"

    [[ "$status" -eq 0 ]]
    grep -q "issue" "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}

@test "checkpoint does not execute embedded commands" {
    # This should NOT create a file - if it does, we have command injection
    local malicious_msg='$(touch /tmp/pwned)'
    run "${SCRIPTS_DIR}/checkpoint.sh" "${malicious_msg}"

    # Should not have created the file
    [[ ! -f /tmp/pwned ]]

    # Cleanup just in case
    rm -f /tmp/pwned 2>/dev/null || true
}

@test "checkpoint does not execute backtick commands" {
    local malicious_msg='`touch /tmp/pwned2`'
    run "${SCRIPTS_DIR}/checkpoint.sh" "${malicious_msg}"

    [[ ! -f /tmp/pwned2 ]]
    rm -f /tmp/pwned2 2>/dev/null || true
}

# ============================================================================
# SDLC INJECTION TESTS
# ============================================================================

@test "sdlc.sh handles special characters in failure details" {
    # Reset and start SDLC first
    "${SCRIPTS_DIR}/sdlc.sh" reset 2>/dev/null || true
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next  # design
    "${SCRIPTS_DIR}/sdlc.sh" next  # implementation
    "${SCRIPTS_DIR}/sdlc.sh" next  # verification

    run "${SCRIPTS_DIR}/sdlc.sh" fail "Bug in /path/to/file"

    [[ "$status" -eq 0 ]]
}

@test "sdlc.sh does not execute embedded commands" {
    "${SCRIPTS_DIR}/sdlc.sh" reset 2>/dev/null || true
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next
    "${SCRIPTS_DIR}/sdlc.sh" next
    "${SCRIPTS_DIR}/sdlc.sh" next

    run "${SCRIPTS_DIR}/sdlc.sh" fail '$(touch /tmp/sdlc_pwned)'

    [[ ! -f /tmp/sdlc_pwned ]]
    rm -f /tmp/sdlc_pwned 2>/dev/null || true
}

# ============================================================================
# RESEARCH INJECTION TESTS
# ============================================================================

@test "research.sh handles special characters in rejection details" {
    "${SCRIPTS_DIR}/research.sh" reset 2>/dev/null || true
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    "${SCRIPTS_DIR}/research.sh" next  # data_collection
    "${SCRIPTS_DIR}/research.sh" next  # analysis

    run "${SCRIPTS_DIR}/research.sh" reject "p < 0.05 & CI overlaps"

    [[ "$status" -eq 0 ]]
}

@test "research.sh does not execute embedded commands" {
    "${SCRIPTS_DIR}/research.sh" reset 2>/dev/null || true
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next
    "${SCRIPTS_DIR}/research.sh" next
    "${SCRIPTS_DIR}/research.sh" next

    run "${SCRIPTS_DIR}/research.sh" reject '$(touch /tmp/research_pwned)'

    [[ ! -f /tmp/research_pwned ]]
    rm -f /tmp/research_pwned 2>/dev/null || true
}

# ============================================================================
# STATE FILE INTEGRITY TESTS
# ============================================================================

@test "state.yaml remains valid after special character operations" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    # Perform operations with special chars
    "${SCRIPTS_DIR}/checkpoint.sh" "Test/with/slashes"

    # State file should still be parseable
    [[ -f "${TEST_TMP_DIR}/.workflow/state.yaml" ]]

    # Should be able to read a value
    local phase
    phase=$(yaml_get "${TEST_TMP_DIR}/.workflow/state.yaml" "current_phase")
    [[ -n "$phase" ]]
}

@test "checkpoints.log remains valid after special character operations" {
    "${SCRIPTS_DIR}/checkpoint.sh" "Message & with / special < chars >"

    # Log file should still exist and have content
    [[ -s "${TEST_TMP_DIR}/.workflow/checkpoints.log" ]]

    # Should be readable
    wc -l < "${TEST_TMP_DIR}/.workflow/checkpoints.log"
}
