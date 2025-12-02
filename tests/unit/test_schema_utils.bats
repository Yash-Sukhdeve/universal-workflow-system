#!/usr/bin/env bats
# Unit tests for schema_utils.sh
# Tests schema validation for workflow state files

load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    source "${PROJECT_ROOT}/scripts/lib/yaml_utils.sh"
    source "${PROJECT_ROOT}/scripts/lib/schema_utils.sh"
}

teardown() {
    teardown_test_environment
}

# ===========================================
# validate_state_schema tests
# ===========================================

@test "validate_state_schema passes for valid state" {
    create_minimal_state

    run validate_state_schema "${TEST_TMP_DIR}/.workflow/state.yaml"

    assert_success
}

@test "validate_state_schema fails for missing file" {
    run validate_state_schema "${TEST_TMP_DIR}/nonexistent.yaml"

    assert_failure
}

@test "validate_state_schema detects invalid phase" {
    create_minimal_state
    sed -i 's/phase_1_planning/invalid_phase/' "${TEST_TMP_DIR}/.workflow/state.yaml"

    run validate_state_schema "${TEST_TMP_DIR}/.workflow/state.yaml"

    assert_failure
    [[ "$output" =~ "does not match pattern" ]]
}

@test "validate_state_schema detects invalid checkpoint format" {
    create_minimal_state
    sed -i 's/CP_1_001/INVALID_CP/' "${TEST_TMP_DIR}/.workflow/state.yaml"

    run validate_state_schema "${TEST_TMP_DIR}/.workflow/state.yaml"

    assert_failure
}

@test "validate_state_schema accepts all valid project types" {
    local types=("research" "ml" "software" "llm" "optimization" "deployment" "hybrid")

    for type in "${types[@]}"; do
        create_minimal_state
        sed -i "s/type: software/type: ${type}/" "${TEST_TMP_DIR}/.workflow/state.yaml"

        run validate_state_schema "${TEST_TMP_DIR}/.workflow/state.yaml"
        assert_success
    done
}

@test "validate_state_schema detects invalid project type" {
    create_minimal_state
    sed -i 's/type: software/type: invalid_type/' "${TEST_TMP_DIR}/.workflow/state.yaml"

    run validate_state_schema "${TEST_TMP_DIR}/.workflow/state.yaml"

    assert_failure
}

@test "validate_state_schema validates agent status consistency" {
    create_minimal_state
    # Set agent status to active but no name
    cat >> "${TEST_TMP_DIR}/.workflow/state.yaml" << 'EOF'
active_agent:
  name: null
  status: active
EOF

    run validate_state_schema "${TEST_TMP_DIR}/.workflow/state.yaml"

    assert_failure
    [[ "$output" =~ "Consistency" ]]
}

# ===========================================
# validate_checkpoint_schema tests
# ===========================================

@test "validate_checkpoint_schema passes for valid metadata" {
    local metadata="${TEST_TMP_DIR}/metadata.yaml"
    cat > "$metadata" << 'EOF'
checkpoint_id: "CP_1_001"
created: "2025-12-01T10:30:15-05:00"
message: "Test checkpoint"
phase: "phase_1_planning"
git_commit: "abc1234"
EOF

    run validate_checkpoint_schema "$metadata"

    assert_success
}

@test "validate_checkpoint_schema fails for missing required field" {
    local metadata="${TEST_TMP_DIR}/metadata.yaml"
    cat > "$metadata" << 'EOF'
checkpoint_id: "CP_1_001"
message: "Test checkpoint"
EOF
    # Missing: created, phase

    run validate_checkpoint_schema "$metadata"

    assert_failure
}

@test "validate_checkpoint_schema validates git commit format" {
    local metadata="${TEST_TMP_DIR}/metadata.yaml"
    cat > "$metadata" << 'EOF'
checkpoint_id: "CP_1_001"
created: "2025-12-01T10:30:15-05:00"
phase: "phase_1_planning"
git_commit: "not-a-hash"
EOF

    run validate_checkpoint_schema "$metadata"

    assert_failure
}

@test "validate_checkpoint_schema accepts valid short git hash" {
    local metadata="${TEST_TMP_DIR}/metadata.yaml"
    cat > "$metadata" << 'EOF'
checkpoint_id: "CP_1_001"
created: "2025-12-01T10:30:15-05:00"
phase: "phase_1_planning"
git_commit: "a1b2c3d"
EOF

    run validate_checkpoint_schema "$metadata"

    assert_success
}

@test "validate_checkpoint_schema accepts valid long git hash" {
    local metadata="${TEST_TMP_DIR}/metadata.yaml"
    cat > "$metadata" << 'EOF'
checkpoint_id: "CP_1_001"
created: "2025-12-01T10:30:15-05:00"
phase: "phase_1_planning"
git_commit: "a1b2c3d4e5f6789012345678901234567890abcd"
EOF

    run validate_checkpoint_schema "$metadata"

    assert_success
}

# ===========================================
# validate_agent_schema tests
# ===========================================

@test "validate_agent_schema accepts all valid agents" {
    local agents=("researcher" "architect" "implementer" "experimenter" "optimizer" "deployer" "documenter")

    for agent in "${agents[@]}"; do
        run validate_agent_schema "$agent"
        assert_success
    done
}

@test "validate_agent_schema rejects invalid agent" {
    run validate_agent_schema "invalid_agent"

    assert_failure
}

# ===========================================
# validate_agent_transition tests
# ===========================================

@test "validate_agent_transition allows researcher to architect" {
    run validate_agent_transition "researcher" "architect"
    assert_success
}

@test "validate_agent_transition allows researcher to implementer" {
    run validate_agent_transition "researcher" "implementer"
    assert_success
}

@test "validate_agent_transition allows any agent to documenter" {
    local agents=("researcher" "architect" "implementer" "experimenter" "optimizer" "deployer")

    for agent in "${agents[@]}"; do
        run validate_agent_transition "$agent" "documenter"
        assert_success
    done
}

@test "validate_agent_transition rejects invalid transition" {
    run validate_agent_transition "deployer" "researcher"
    assert_failure
}

@test "validate_agent_transition allows implementer to experimenter" {
    run validate_agent_transition "implementer" "experimenter"
    assert_success
}

@test "validate_agent_transition allows optimizer to deployer" {
    run validate_agent_transition "optimizer" "deployer"
    assert_success
}

@test "validate_agent_transition allows first activation (no current agent)" {
    run validate_agent_transition "" "researcher"
    assert_success
}

# ===========================================
# validate_pattern tests
# ===========================================

@test "validate_pattern matches valid phase pattern" {
    schema_clear_results

    run validate_pattern "phase_1_planning" "^phase_[1-5]_" "test_field"

    assert_success
    [[ $(schema_error_count) -eq 0 ]]
}

@test "validate_pattern fails on invalid pattern" {
    schema_clear_results

    run validate_pattern "invalid" "^phase_[1-5]_" "test_field"

    assert_failure
    [[ $(schema_error_count) -gt 0 ]]
}

@test "validate_pattern skips empty values" {
    schema_clear_results

    run validate_pattern "" "^required_pattern$" "test_field"

    assert_success
}

@test "validate_pattern skips null values" {
    schema_clear_results

    run validate_pattern "null" "^required_pattern$" "test_field"

    assert_success
}

# ===========================================
# validate_type tests
# ===========================================

@test "validate_type accepts valid integer" {
    schema_clear_results

    run validate_type "42" "integer" "test_field"

    assert_success
}

@test "validate_type rejects non-integer" {
    schema_clear_results

    run validate_type "not_a_number" "integer" "test_field"

    assert_failure
}

@test "validate_type accepts valid boolean values" {
    local booleans=("true" "false" "yes" "no" "1" "0")

    for val in "${booleans[@]}"; do
        schema_clear_results
        run validate_type "$val" "boolean" "test_field"
        assert_success
    done
}

@test "validate_type accepts valid iso8601 date" {
    schema_clear_results

    run validate_type "2025-12-01T10:30:15-05:00" "iso8601" "test_field"

    assert_success
}

@test "validate_type accepts iso8601 date only format" {
    schema_clear_results

    run validate_type "2025-12-01" "iso8601" "test_field"

    assert_success
}

@test "validate_type rejects invalid iso8601" {
    schema_clear_results

    run validate_type "12/01/2025" "iso8601" "test_field"

    assert_failure
}

@test "validate_type accepts string_or_null" {
    schema_clear_results

    run validate_type "null" "string_or_null" "test_field"

    assert_success
}

# ===========================================
# schema_*_results tests
# ===========================================

@test "schema_clear_results resets errors and warnings" {
    schema_add_error "test error"
    schema_add_warning "test warning"

    schema_clear_results

    [[ $(schema_error_count) -eq 0 ]]
    [[ $(schema_warning_count) -eq 0 ]]
}

@test "schema_error_count returns correct count" {
    schema_clear_results
    schema_add_error "error 1"
    schema_add_error "error 2"

    [[ $(schema_error_count) -eq 2 ]]
}

@test "schema_get_errors_json returns valid JSON" {
    schema_clear_results
    schema_add_error "test error 1"
    schema_add_error "test error 2"

    local json
    json=$(schema_get_errors_json)

    [[ "$json" == '["test error 1","test error 2"]' ]]
}

@test "schema_get_errors_json returns empty array when no errors" {
    schema_clear_results

    local json
    json=$(schema_get_errors_json)

    [[ "$json" == '[]' ]]
}

# ===========================================
# validate_all_schemas tests
# ===========================================

@test "validate_all_schemas validates workflow directory" {
    create_full_test_environment

    run validate_all_schemas "${TEST_TMP_DIR}/.workflow"

    # Should at least attempt validation
    [[ "$output" =~ "Validating" ]]
}

@test "validate_all_schemas handles missing directory" {
    run validate_all_schemas "${TEST_TMP_DIR}/nonexistent"

    # Should handle gracefully (no state.yaml found)
    [[ "$output" =~ "NOT FOUND" ]]
}

# ===========================================
# Edge case tests
# ===========================================

@test "schema validation handles special characters in values" {
    local metadata="${TEST_TMP_DIR}/metadata.yaml"
    cat > "$metadata" << 'EOF'
checkpoint_id: "CP_1_001"
created: "2025-12-01T10:30:15-05:00"
message: "Message with \"quotes\" and 'apostrophes'"
phase: "phase_1_planning"
EOF

    run validate_checkpoint_schema "$metadata"

    assert_success
}

@test "schema validation handles unicode in messages" {
    local metadata="${TEST_TMP_DIR}/metadata.yaml"
    cat > "$metadata" << 'EOF'
checkpoint_id: "CP_1_001"
created: "2025-12-01T10:30:15-05:00"
message: "Unicode test: café résumé"
phase: "phase_1_planning"
EOF

    run validate_checkpoint_schema "$metadata"

    assert_success
}
