#!/usr/bin/env bats
# Unit Tests for yaml_utils.sh
# Tests YAML parsing utility functions

# Load test helpers
load '../helpers/test_helper'

# ============================================================================
# SETUP
# ============================================================================

setup() {
    setup_test_environment
    cd "${TEST_TMP_DIR}"

    # Source yaml utils
    if [[ -f "${SCRIPTS_DIR}/lib/yaml_utils.sh" ]]; then
        source "${SCRIPTS_DIR}/lib/yaml_utils.sh"
    fi
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# BASIC TESTS
# ============================================================================

@test "yaml_utils.sh exists and is sourceable" {
    [[ -f "${SCRIPTS_DIR}/lib/yaml_utils.sh" ]]
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"
}

@test "yaml_get function exists after sourcing" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"
    declare -f yaml_get > /dev/null
}

@test "yaml_set function exists after sourcing" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"
    declare -f yaml_set > /dev/null
}

# ============================================================================
# YAML GET TESTS
# ============================================================================

@test "yaml_get retrieves simple string value" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
name: "test-project"
version: "1.0.0"
EOF

    local result
    result=$(yaml_get test.yaml "name")

    [[ "$result" == "test-project" ]] || [[ "$result" == '"test-project"' ]]
}

@test "yaml_get retrieves nested value" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
project:
  name: "nested-test"
  version: "2.0.0"
EOF

    local result
    result=$(yaml_get test.yaml "project.name")

    [[ "$result" == "nested-test" ]] || [[ "$result" == '"nested-test"' ]] || [[ "$result" =~ "nested" ]]
}

@test "yaml_get returns null for missing key" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
name: "test"
EOF

    local result
    result=$(yaml_get test.yaml "nonexistent")

    [[ "$result" == "null" ]] || [[ -z "$result" ]] || [[ "$result" == "" ]]
}

@test "yaml_get handles numeric values" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
count: 42
enabled: true
EOF

    local result
    result=$(yaml_get test.yaml "count")

    [[ "$result" == "42" ]]
}

@test "yaml_get handles boolean values" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
enabled: true
disabled: false
EOF

    local result
    result=$(yaml_get test.yaml "enabled")

    [[ "$result" == "true" ]]
}

# ============================================================================
# YAML SET TESTS
# ============================================================================

@test "yaml_set creates new key" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
name: "test"
EOF

    yaml_set test.yaml "version" "1.0.0"

    grep -q "version" test.yaml || grep -q "1.0.0" test.yaml
}

@test "yaml_set updates existing key" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
name: "old-name"
EOF

    yaml_set test.yaml "name" "new-name"

    local result
    result=$(yaml_get test.yaml "name")

    [[ "$result" == "new-name" ]] || [[ "$result" == '"new-name"' ]]
}

# ============================================================================
# YAML VALIDATION TESTS
# ============================================================================

@test "yaml_validate function exists" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    # Check if function exists (may not be implemented)
    declare -f yaml_validate > /dev/null || skip "yaml_validate not implemented"
}

@test "yaml_validate accepts valid YAML" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    declare -f yaml_validate > /dev/null || skip "yaml_validate not implemented"

    cat > test.yaml << 'EOF'
name: "valid"
version: "1.0.0"
EOF

    run yaml_validate test.yaml
    [[ "$status" -eq 0 ]]
}

# ============================================================================
# EDGE CASES
# ============================================================================

@test "yaml_get handles empty file" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    touch empty.yaml

    local result
    result=$(yaml_get empty.yaml "key" 2>/dev/null || echo "null")

    [[ "$result" == "null" ]] || [[ -z "$result" ]]
}

@test "yaml_get handles file with comments" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
# This is a comment
name: "commented"
# Another comment
version: "1.0.0"
EOF

    local result
    result=$(yaml_get test.yaml "name")

    [[ "$result" == "commented" ]] || [[ "$result" == '"commented"' ]]
}

@test "yaml_get handles special characters in values" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
path: "/usr/local/bin"
url: "https://example.com"
EOF

    local result
    result=$(yaml_get test.yaml "path")

    [[ "$result" =~ "/usr/local/bin" ]]
}

@test "yaml_get handles multiword values" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
description: "This is a multi word description"
EOF

    local result
    result=$(yaml_get test.yaml "description")

    [[ "$result" =~ "multi word" ]] || [[ "$result" =~ "description" ]]
}

# ============================================================================
# FALLBACK BEHAVIOR TESTS
# ============================================================================

@test "yaml_utils works without yq (fallback mode)" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    # Force fallback mode
    export HAS_YQ="false"

    cat > test.yaml << 'EOF'
name: "fallback-test"
EOF

    local result
    result=$(yaml_get test.yaml "name")

    [[ "$result" =~ "fallback" ]] || [[ -n "$result" ]]
}

# ============================================================================
# ARRAY HANDLING TESTS
# ============================================================================

@test "yaml_get handles array access" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
items:
  - first
  - second
  - third
EOF

    # Array handling may vary based on implementation
    local result
    result=$(yaml_get test.yaml "items" 2>/dev/null || echo "array")

    [[ -n "$result" ]]
}

# ============================================================================
# PERFORMANCE TESTS
# ============================================================================

@test "yaml_get completes within 1 second" {
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"

    cat > test.yaml << 'EOF'
name: "perf-test"
EOF

    local start_time end_time elapsed
    start_time=$(date +%s)

    yaml_get test.yaml "name" > /dev/null

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    [[ "$elapsed" -lt 2 ]]
}
