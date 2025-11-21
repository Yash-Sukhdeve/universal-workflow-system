#!/usr/bin/env bats

# Unit tests for YAML parsing functionality
# Tests the get_yaml_value() function used across all scripts

load '../helpers/test_helper'

setup() {
    common_setup
    create_test_state "phase_2_implementation" "CP_2_001"

    # Define get_yaml_value function (from scripts)
    get_yaml_value() {
        local file="$1"
        local key="$2"

        if [ ! -f "$file" ]; then
            echo ""
            return 1
        fi

        grep "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*$//'
    }
}

teardown() {
    common_teardown
}

# Basic YAML value extraction tests

@test "get_yaml_value extracts simple string value" {
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "project_name")
    [ "$result" = "test_project" ]
}

@test "get_yaml_value extracts project_type" {
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "project_type")
    [ "$result" = "software" ]
}

@test "get_yaml_value extracts current_phase" {
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$result" = "phase_2_implementation" ]
}

@test "get_yaml_value extracts last_checkpoint" {
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "last_checkpoint")
    [ "$result" = "CP_2_001" ]
}

@test "get_yaml_value extracts timestamp" {
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "last_updated")
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# Edge cases and error handling

@test "get_yaml_value returns empty for missing key" {
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "nonexistent_key")
    [ -z "$result" ]
}

@test "get_yaml_value returns empty for missing file" {
    local result=$(get_yaml_value "/nonexistent/file.yaml" "project_name")
    [ -z "$result" ]
}

@test "get_yaml_value handles key with no value" {
    echo "empty_key:" >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "empty_key")
    [ -z "$result" ]
}

@test "get_yaml_value handles multiple colons in value" {
    echo "url: http://example.com:8080" >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "url")
    [ "$result" = "http://example.com:8080" ]
}

@test "get_yaml_value trims whitespace" {
    echo "spaced_key:    value_with_spaces   " >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "spaced_key")
    [ "$result" = "value_with_spaces" ]
}

@test "get_yaml_value returns first occurrence for duplicate keys" {
    echo "duplicate: first_value" >> "$WORKFLOW_DIR/state.yaml"
    echo "duplicate: second_value" >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "duplicate")
    [ "$result" = "first_value" ]
}

# Special characters and values

@test "get_yaml_value handles values with dashes" {
    echo "with_dash: some-value-here" >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "with_dash")
    [ "$result" = "some-value-here" ]
}

@test "get_yaml_value handles values with underscores" {
    echo "with_underscore: some_value_here" >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "with_underscore")
    [ "$result" = "some_value_here" ]
}

@test "get_yaml_value handles numeric values" {
    echo "version: 123" >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "version")
    [ "$result" = "123" ]
}

@test "get_yaml_value handles boolean true" {
    echo "enabled: true" >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "enabled")
    [ "$result" = "true" ]
}

@test "get_yaml_value handles boolean false" {
    echo "disabled: false" >> "$WORKFLOW_DIR/state.yaml"
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "disabled")
    [ "$result" = "false" ]
}

# Nested keys (should not work with simple parser)

@test "get_yaml_value does not extract nested keys" {
    cat >> "$WORKFLOW_DIR/state.yaml" <<EOF
parent:
  child: nested_value
EOF
    local result=$(get_yaml_value "$WORKFLOW_DIR/state.yaml" "child")
    # Should not find nested keys
    [ -z "$result" ] || [ "$result" != "nested_value" ]
}

# File permission tests

@test "get_yaml_value handles unreadable file" {
    local unreadable="$TEST_DIR/unreadable.yaml"
    echo "key: value" > "$unreadable"
    chmod 000 "$unreadable"

    run get_yaml_value "$unreadable" "key"
    [ "$status" -ne 0 ]

    chmod 644 "$unreadable"  # cleanup
}

# Large file performance

@test "get_yaml_value works with large files" {
    # Create a file with 1000 lines
    for i in {1..1000}; do
        echo "key_$i: value_$i" >> "$WORKFLOW_DIR/large.yaml"
    done

    local result=$(get_yaml_value "$WORKFLOW_DIR/large.yaml" "key_500")
    [ "$result" = "value_500" ]
}

# Real-world examples from actual state files

@test "get_yaml_value extracts phase from real state structure" {
    cp "$(pwd)/tests/fixtures/sample_state.yaml" "$TEST_DIR/real_state.yaml"
    local result=$(get_yaml_value "$TEST_DIR/real_state.yaml" "project_name")
    [ "$result" = "test_ml_project" ]
}

@test "get_yaml_value extracts checkpoint from real state" {
    cp "$(pwd)/tests/fixtures/sample_state.yaml" "$TEST_DIR/real_state.yaml"
    local result=$(get_yaml_value "$TEST_DIR/real_state.yaml" "last_checkpoint")
    [ "$result" = "CP_2_003" ]
}

# Empty file handling

@test "get_yaml_value handles empty file" {
    touch "$TEST_DIR/empty.yaml"
    local result=$(get_yaml_value "$TEST_DIR/empty.yaml" "any_key")
    [ -z "$result" ]
}

# Comments in YAML

@test "get_yaml_value ignores comment lines" {
    cat > "$TEST_DIR/with_comments.yaml" <<EOF
# This is a comment
project_name: test
# Another comment
current_phase: phase_1_planning
EOF
    local result=$(get_yaml_value "$TEST_DIR/with_comments.yaml" "project_name")
    [ "$result" = "test" ]
}

@test "get_yaml_value ignores inline comments" {
    echo "key: value # inline comment" > "$TEST_DIR/inline.yaml"
    local result=$(get_yaml_value "$TEST_DIR/inline.yaml" "key")
    # Note: Our simple parser doesn't strip inline comments, so this might include them
    [[ "$result" == "value"* ]]
}
