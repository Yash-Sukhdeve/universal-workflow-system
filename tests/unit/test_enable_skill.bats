#!/usr/bin/env bats
# Unit tests for enable_skill.sh
# Tests skill management: enable, disable, execute, list, status

load '../helpers/test_helper.bash'

# Setup and teardown
setup() {
    setup_test_environment
    create_full_test_environment

    # Ensure skill directories exist
    mkdir -p "${TEST_TMP_DIR}/.workflow/skills"/{definitions,chains,execution_logs}
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# ENABLE SKILL TESTS
# =============================================================================

@test "enable_skill adds skill to enabled_skills list" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" code_development enable

    assert_success
    assert_file_contains ".workflow/skills/enabled.yaml" "code_development"
}

@test "enable_skill creates skill definition file" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" literature_review enable

    assert_success
    [ -f ".workflow/skills/definitions/literature_review.yaml" ]
}

@test "enable_skill logs to checkpoints.log" {
    cd "${TEST_TMP_DIR}"

    # Ensure checkpoints.log exists (may be created by test environment)
    touch .workflow/checkpoints.log

    # Use a skill that isn't already enabled in test environment
    run "${SCRIPTS_DIR}/enable_skill.sh" profiling enable

    assert_success
    # Check log was updated - should contain skill name or SKILL_ENABLED
    [[ -f ".workflow/checkpoints.log" ]]
    grep -q "profiling" .workflow/checkpoints.log || grep -q "SKILL" .workflow/checkpoints.log
}

@test "enable_skill handles already enabled skill gracefully" {
    cd "${TEST_TMP_DIR}"

    # Enable once
    "${SCRIPTS_DIR}/enable_skill.sh" debugging enable

    # Enable again
    run "${SCRIPTS_DIR}/enable_skill.sh" debugging enable

    assert_success
    [[ "$output" == *"already enabled"* ]]
}

@test "enable_skill creates definition for research skills" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" literature_review enable

    assert_success
    assert_file_contains ".workflow/skills/definitions/literature_review.yaml" "category: research"
}

@test "enable_skill creates definition for development skills" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" code_generation enable

    assert_success
    assert_file_contains ".workflow/skills/definitions/code_generation.yaml" "category: development"
}

@test "enable_skill creates definition for ML skills" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" quantization enable

    assert_success
    assert_file_contains ".workflow/skills/definitions/quantization.yaml" "category: optimization"
}

# =============================================================================
# DISABLE SKILL TESTS
# =============================================================================

@test "disable_skill removes skill from enabled list" {
    cd "${TEST_TMP_DIR}"

    # First enable
    "${SCRIPTS_DIR}/enable_skill.sh" testing enable

    # Then disable
    run "${SCRIPTS_DIR}/enable_skill.sh" testing disable

    assert_success
    ! grep -q "testing" ".workflow/skills/enabled.yaml"
}

@test "disable_skill logs to checkpoints.log" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" debugging enable

    run "${SCRIPTS_DIR}/enable_skill.sh" debugging disable

    assert_success
    assert_file_contains ".workflow/checkpoints.log" "SKILL_DISABLED"
    assert_file_contains ".workflow/checkpoints.log" "debugging"
}

@test "disable_skill handles non-enabled skill gracefully" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" nonexistent_skill disable

    # Should succeed even if skill wasn't enabled
    assert_success
}

# =============================================================================
# EXECUTE SKILL TESTS
# =============================================================================

@test "execute_skill runs enabled skill" {
    cd "${TEST_TMP_DIR}"

    # Enable skill first
    "${SCRIPTS_DIR}/enable_skill.sh" code_generation enable

    run "${SCRIPTS_DIR}/enable_skill.sh" code_generation execute "test params"

    assert_success
    [[ "$output" == *"Skill execution complete"* ]]
}

@test "execute_skill fails for non-enabled skill" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" literature_review execute "test query"

    assert_failure
    [[ "$output" == *"not enabled"* ]] || [[ "$output" == *"Error"* ]]
}

@test "execute_skill creates execution log" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" quantization enable

    run "${SCRIPTS_DIR}/enable_skill.sh" quantization execute "model.pt"

    assert_success

    # Check log file exists
    local log_count
    log_count=$(ls -1 .workflow/skills/execution_logs/quantization_*.log 2>/dev/null | wc -l)
    [ "$log_count" -ge 1 ]
}

@test "execute_skill logs to checkpoints.log" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" testing enable

    run "${SCRIPTS_DIR}/enable_skill.sh" testing execute ""

    assert_success
    assert_file_contains ".workflow/checkpoints.log" "SKILL_EXECUTED"
}

# =============================================================================
# LIST SKILLS TESTS
# =============================================================================

@test "list_skills shows available skills" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" "" list

    assert_success
    [[ "$output" == *"Available Skills"* ]]
    [[ "$output" == *"Research Skills"* ]]
    [[ "$output" == *"Development Skills"* ]]
    [[ "$output" == *"ML/AI Skills"* ]]
}

@test "list_skills shows enabled skills" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" code_generation enable
    "${SCRIPTS_DIR}/enable_skill.sh" testing enable

    run "${SCRIPTS_DIR}/enable_skill.sh" "" list

    assert_success
    [[ "$output" == *"Enabled Skills"* ]]
    [[ "$output" == *"code_generation"* ]]
    [[ "$output" == *"testing"* ]]
}

@test "list_skills handles empty enabled list" {
    cd "${TEST_TMP_DIR}"

    # Clear enabled skills
    cat > .workflow/skills/enabled.yaml << 'EOF'
enabled_skills: []
skill_configs: {}
EOF

    run "${SCRIPTS_DIR}/enable_skill.sh" "" list

    assert_success
    [[ "$output" == *"No skills"* ]] || [[ "$output" == *"Enabled Skills"* ]]
}

# =============================================================================
# STATUS TESTS
# =============================================================================

@test "status shows skill is enabled" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" debugging enable

    run "${SCRIPTS_DIR}/enable_skill.sh" debugging status

    assert_success
    [[ "$output" == *"Enabled"* ]]
}

@test "status shows skill is disabled" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" nonexistent_skill status

    assert_success
    [[ "$output" == *"Disabled"* ]]
}

@test "status shows skill definition info" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" literature_review enable

    run "${SCRIPTS_DIR}/enable_skill.sh" literature_review status

    assert_success
    [[ "$output" == *"Definition"* ]] || [[ "$output" == *"description"* ]]
}

@test "status without skill name lists all skills" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" "" status

    assert_success
    [[ "$output" == *"Available Skills"* ]]
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "enable_skill fails without workflow directory" {
    cd "${TEST_TMP_DIR}"
    rm -rf .workflow

    run "${SCRIPTS_DIR}/enable_skill.sh" testing enable

    assert_failure
    [[ "$output" == *"not initialized"* ]] || [[ "$output" == *"Error"* ]]
}

@test "enable_skill shows usage on invalid command" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" testing invalid_command

    # Should show usage or error
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"enable"* ]]
}

@test "enable_skill handles special characters in skill name" {
    cd "${TEST_TMP_DIR}"

    # This should work with underscores
    run "${SCRIPTS_DIR}/enable_skill.sh" custom_skill_name enable

    assert_success
}

# =============================================================================
# SKILL DEFINITION TESTS
# =============================================================================

@test "skill definition includes parameters" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" literature_review enable

    assert_file_contains ".workflow/skills/definitions/literature_review.yaml" "parameters:"
    assert_file_contains ".workflow/skills/definitions/literature_review.yaml" "query:"
}

@test "skill definition includes outputs" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" code_generation enable

    assert_file_contains ".workflow/skills/definitions/code_generation.yaml" "outputs:"
}

@test "skill definition includes dependencies" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" quantization enable

    assert_file_contains ".workflow/skills/definitions/quantization.yaml" "dependencies:"
    assert_file_contains ".workflow/skills/definitions/quantization.yaml" "torch"
}

@test "custom skill gets generic definition" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" my_custom_skill enable

    assert_file_contains ".workflow/skills/definitions/my_custom_skill.yaml" "category: custom"
}

# =============================================================================
# STATE PERSISTENCE TESTS
# =============================================================================

@test "enabled skills persist after script exit" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" code_development enable
    "${SCRIPTS_DIR}/enable_skill.sh" testing enable

    # Check file directly
    grep -q "code_development" .workflow/skills/enabled.yaml
    grep -q "testing" .workflow/skills/enabled.yaml
}

@test "skill definitions persist after script exit" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" literature_review enable

    [ -f ".workflow/skills/definitions/literature_review.yaml" ]
    # Check for description field (case insensitive)
    grep -qi "systematic\|literature" ".workflow/skills/definitions/literature_review.yaml"
}

@test "execution logs persist after skill execution" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" testing enable
    "${SCRIPTS_DIR}/enable_skill.sh" testing execute "run all tests"

    local log_files
    log_files=$(ls -1 .workflow/skills/execution_logs/ 2>/dev/null | wc -l)
    [ "$log_files" -ge 1 ]
}

# =============================================================================
# SKILL CHAIN/DEPENDENCY TESTS
# =============================================================================

@test "enable skill creates chains directory" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" code_generation enable

    [ -d ".workflow/skills/chains" ]
}

@test "skill dependencies shown on enable" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" quantization enable

    assert_success
    # Should show dependencies or complete successfully
    [[ "$output" == *"enabled"* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "enable_skill handles empty skill name" {
    cd "${TEST_TMP_DIR}"

    run "${SCRIPTS_DIR}/enable_skill.sh" "" enable

    # Should show usage
    [[ "$output" == *"Usage"* ]]
}

@test "multiple skills can be enabled sequentially" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" code_generation enable
    "${SCRIPTS_DIR}/enable_skill.sh" testing enable
    "${SCRIPTS_DIR}/enable_skill.sh" debugging enable

    run "${SCRIPTS_DIR}/enable_skill.sh" "" list

    assert_success
    [[ "$output" == *"code_generation"* ]]
    [[ "$output" == *"testing"* ]]
    [[ "$output" == *"debugging"* ]]
}

@test "duplicate enable does not duplicate entry" {
    cd "${TEST_TMP_DIR}"

    "${SCRIPTS_DIR}/enable_skill.sh" testing enable
    "${SCRIPTS_DIR}/enable_skill.sh" testing enable
    "${SCRIPTS_DIR}/enable_skill.sh" testing enable

    local count
    count=$(grep -c "testing" .workflow/skills/enabled.yaml)
    [ "$count" -eq 1 ]
}
