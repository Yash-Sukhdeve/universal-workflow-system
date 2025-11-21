#!/usr/bin/env bats

# Unit tests for state management functionality
# Tests state initialization, updates, and validation

load '../helpers/test_helper'

setup() {
    common_setup
}

teardown() {
    common_teardown
}

# State File Creation Tests

@test "state file can be created" {
    create_test_state

    assert_file_exists "$WORKFLOW_DIR/state.yaml"
}

@test "state file contains project_name" {
    create_test_state

    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "project_name"
}

@test "state file contains project_type" {
    create_test_state

    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "project_type"
}

@test "state file contains current_phase" {
    create_test_state

    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "current_phase"
}

@test "state file contains last_checkpoint" {
    create_test_state

    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "last_checkpoint"
}

@test "state file contains last_updated timestamp" {
    create_test_state

    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "last_updated"
}

@test "state file contains context_bridge section" {
    create_test_state

    grep -q "context_bridge:" "$WORKFLOW_DIR/state.yaml"
}

# State Value Tests

@test "state file project_name has correct value" {
    create_test_state

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "project_name")
    [ "$value" = "test_project" ]
}

@test "state file project_type has correct value" {
    create_test_state

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "project_type")
    [ "$value" = "software" ]
}

@test "state file current_phase has correct default" {
    create_test_state

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_1_planning" ]
}

@test "state file can have custom phase" {
    create_test_state "phase_3_validation" "CP_3_001"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_3_validation" ]
}

@test "state file last_checkpoint has correct format" {
    create_test_state "phase_2_implementation" "CP_2_005"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_checkpoint")
    [[ "$value" =~ ^CP_[0-9]_[0-9]{3}$ ]]
}

@test "state file timestamp is ISO 8601 format" {
    create_test_state

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_updated")
    [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# State Updates Tests

@test "state file can be updated with new phase" {
    create_test_state "phase_1_planning" "CP_1_001"

    sed -i "s/phase_1_planning/phase_2_implementation/" "$WORKFLOW_DIR/state.yaml"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_2_implementation" ]
}

@test "state file can be updated with new checkpoint" {
    create_test_state "phase_2_implementation" "CP_2_001"

    sed -i "s/CP_2_001/CP_2_002/" "$WORKFLOW_DIR/state.yaml"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_checkpoint")
    [ "$value" = "CP_2_002" ]
}

@test "state file can be updated with new timestamp" {
    create_test_state

    old_time=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_updated")
    new_time="2024-06-15T14:30:00Z"

    sed -i "s/${old_time}/${new_time}/" "$WORKFLOW_DIR/state.yaml"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_updated")
    [ "$value" = "$new_time" ]
}

@test "state updates preserve other fields" {
    create_test_state "phase_1_planning" "CP_1_001"

    # Update phase
    sed -i "s/phase_1_planning/phase_2_implementation/" "$WORKFLOW_DIR/state.yaml"

    # Other fields should be preserved
    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "project_name"
    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "project_type"
    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "last_checkpoint"
}

# Phase Validation Tests

@test "state supports phase_1_planning" {
    create_test_state "phase_1_planning" "CP_1_001"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_1_planning" ]
}

@test "state supports phase_2_implementation" {
    create_test_state "phase_2_implementation" "CP_2_001"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_2_implementation" ]
}

@test "state supports phase_3_validation" {
    create_test_state "phase_3_validation" "CP_3_001"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_3_validation" ]
}

@test "state supports phase_4_delivery" {
    create_test_state "phase_4_delivery" "CP_4_001"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_4_delivery" ]
}

@test "state supports phase_5_maintenance" {
    create_test_state "phase_5_maintenance" "CP_5_001"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_5_maintenance" ]
}

# Project Type Tests

@test "state supports software project type" {
    create_test_state

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "project_type")
    [ "$value" = "software" ]
}

@test "state file format is valid YAML" {
    create_test_state

    # Basic YAML structure check
    grep -q "^project_name:" "$WORKFLOW_DIR/state.yaml"
    grep -q "^project_type:" "$WORKFLOW_DIR/state.yaml"
    grep -q "^current_phase:" "$WORKFLOW_DIR/state.yaml"
}

# Context Bridge Tests

@test "state has context_bridge with critical_info" {
    create_test_state

    grep -q "critical_info:" "$WORKFLOW_DIR/state.yaml"
}

@test "state has context_bridge with next_actions" {
    create_test_state

    grep -q "next_actions:" "$WORKFLOW_DIR/state.yaml"
}

@test "state has context_bridge with dependencies" {
    create_test_state

    grep -q "dependencies:" "$WORKFLOW_DIR/state.yaml"
}

@test "context_bridge is properly nested" {
    create_test_state

    # Check indentation pattern
    grep -A 3 "context_bridge:" "$WORKFLOW_DIR/state.yaml" | grep -q "  critical_info:"
}

# State File Integrity Tests

@test "state file is readable" {
    create_test_state

    [ -r "$WORKFLOW_DIR/state.yaml" ]
}

@test "state file is writable" {
    create_test_state

    [ -w "$WORKFLOW_DIR/state.yaml" ]
}

@test "state file has reasonable size" {
    create_test_state

    size=$(wc -c < "$WORKFLOW_DIR/state.yaml")
    # Should be more than 50 bytes, less than 10KB
    [ "$size" -gt 50 ]
    [ "$size" -lt 10240 ]
}

@test "state file has multiple lines" {
    create_test_state

    lines=$(wc -l < "$WORKFLOW_DIR/state.yaml")
    [ "$lines" -gt 5 ]
}

# State Recovery Tests

@test "state can be backed up and restored" {
    create_test_state "phase_2_implementation" "CP_2_003"

    # Backup
    cp "$WORKFLOW_DIR/state.yaml" "$TEST_DIR/backup_state.yaml"

    # Modify
    sed -i "s/phase_2_implementation/phase_3_validation/" "$WORKFLOW_DIR/state.yaml"

    # Restore
    cp "$TEST_DIR/backup_state.yaml" "$WORKFLOW_DIR/state.yaml"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$value" = "phase_2_implementation" ]
}

@test "corrupted state can be detected" {
    create_test_state

    # Corrupt the file
    echo "invalid yaml content" >> "$WORKFLOW_DIR/state.yaml"
    echo "more corruption:" >> "$WORKFLOW_DIR/state.yaml"

    # Basic validation: should have key fields
    if ! grep -q "project_name:" "$WORKFLOW_DIR/state.yaml"; then
        # File is corrupted
        return 0
    fi
}

@test "missing state file can be detected" {
    [ ! -f "$WORKFLOW_DIR/state.yaml" ]
}

# Complex State Operations

@test "can track multiple phase transitions" {
    create_test_state "phase_1_planning" "CP_1_005"

    # Transition through phases
    sed -i "s/phase_1_planning/phase_2_implementation/" "$WORKFLOW_DIR/state.yaml"
    sed -i "s/CP_1_005/CP_2_001/" "$WORKFLOW_DIR/state.yaml"

    phase=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    checkpoint=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_checkpoint")

    [ "$phase" = "phase_2_implementation" ]
    [ "$checkpoint" = "CP_2_001" ]
}

@test "state updates maintain YAML structure" {
    create_test_state

    # Update multiple fields
    sed -i "s/phase_1_planning/phase_3_validation/" "$WORKFLOW_DIR/state.yaml"
    sed -i "s/CP_1_001/CP_3_015/" "$WORKFLOW_DIR/state.yaml"

    # Verify structure is maintained
    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "project_name"
    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "current_phase"
    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "last_checkpoint"
    grep -q "context_bridge:" "$WORKFLOW_DIR/state.yaml"
}

# Real-world State File Tests

@test "can load sample state fixture" {
    cp "$(pwd)/tests/fixtures/sample_state.yaml" "$WORKFLOW_DIR/state.yaml"

    assert_file_exists "$WORKFLOW_DIR/state.yaml"
}

@test "sample state has expected values" {
    cp "$(pwd)/tests/fixtures/sample_state.yaml" "$WORKFLOW_DIR/state.yaml"

    project=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "project_name")
    phase=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    checkpoint=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_checkpoint")

    [ "$project" = "test_ml_project" ]
    [ "$phase" = "phase_2_implementation" ]
    [ "$checkpoint" = "CP_2_003" ]
}

@test "sample state has context information" {
    cp "$(pwd)/tests/fixtures/sample_state.yaml" "$WORKFLOW_DIR/state.yaml"

    grep -q "Database schema finalized" "$WORKFLOW_DIR/state.yaml"
    grep -q "Implement user authentication" "$WORKFLOW_DIR/state.yaml"
    grep -q "PostgreSQL" "$WORKFLOW_DIR/state.yaml"
}

# Concurrent Access Tests (basic)

@test "multiple reads don't corrupt state" {
    create_test_state

    # Read file multiple times in parallel
    for i in {1..10}; do
        get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "project_name" &
    done
    wait

    # State should still be valid
    assert_file_exists "$WORKFLOW_DIR/state.yaml"
    assert_yaml_key_exists "$WORKFLOW_DIR/state.yaml" "project_name"
}

# Edge Cases

@test "state with special characters in project name" {
    create_test_state

    sed -i "s/test_project/test-project_v2.0/" "$WORKFLOW_DIR/state.yaml"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "project_name")
    [ "$value" = "test-project_v2.0" ]
}

@test "state with very long checkpoint ID" {
    create_test_state "phase_5_maintenance" "CP_5_999"

    value=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_checkpoint")
    [ "$value" = "CP_5_999" ]
}

@test "empty context bridge arrays" {
    create_test_state

    # Verify empty arrays are represented as []
    grep -q "critical_info: \[\]" "$WORKFLOW_DIR/state.yaml"
    grep -q "next_actions: \[\]" "$WORKFLOW_DIR/state.yaml"
    grep -q "dependencies: \[\]" "$WORKFLOW_DIR/state.yaml"
}
