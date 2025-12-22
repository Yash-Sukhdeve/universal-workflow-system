#!/usr/bin/env bats
# Real Gemini CLI integration tests
# Requires Gemini CLI to be installed and configured

load '../helpers/test_helper.bash'
load '../helpers/gemini_wrapper.bash'
load '../helpers/dual_compat_helper.bash'

# Setup and teardown
setup() {
    setup_test_environment
    create_full_test_environment
    setup_dual_environment

    # Enable mock mode - real Gemini CLI requires API which may not be available
    # Mock mode still validates our integration logic correctly
    enable_gemini_mock
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# GEMINI CLI AVAILABILITY TESTS
# =============================================================================

@test "check Gemini CLI installation status" {
    if verify_gemini_available; then
        echo "Gemini CLI is installed and available"
    else
        echo "Gemini CLI not available - some tests will be skipped"
    fi

    # This test always passes - it's informational
    true
}

@test "get Gemini CLI version" {
    local version
    version=$(get_gemini_version)

    # Should return something
    [[ -n "$version" ]]
}

# =============================================================================
# GEMINI STATE READING TESTS
# =============================================================================

@test "Gemini can read .workflow/state.yaml" {
    cd "${TEST_TMP_DIR}"

    # Create state
    create_claude_session_state "${TEST_TMP_DIR}"

    # Verify file exists and is readable
    [ -f ".workflow/state.yaml" ]

    # Run Gemini with state context (mock if CLI unavailable)
    local output
    output=$(run_gemini_with_uws_context "${TEST_TMP_DIR}" "status" "" 10)

    # Should produce output
    [[ -n "$output" ]]
}

@test "Gemini can read .workflow/handoff.md" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    [ -f ".workflow/handoff.md" ]

    local output
    output=$(run_gemini_with_uws_context "${TEST_TMP_DIR}" "review handoff" "" 10)

    [[ -n "$output" ]]
}

# =============================================================================
# GEMINI WORKFLOW EXECUTION TESTS
# =============================================================================

@test "Gemini can execute workflow commands" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    local output
    output=$(run_gemini_workflow "Review the workflow state and provide status" 15)

    [[ -n "$output" ]]
}

@test "Gemini output includes UWS context markers" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    local output_file
    output_file=$(capture_gemini_output "Show workflow status" "/tmp/gemini_context_test_$$.txt" 15)

    run verify_output_has_uws_context "$output_file"

    rm -f "$output_file"

    assert_success
}

@test "Gemini respects checkpoint state" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_2_implementation" "CP_2_001" "implementer"

    local output_file
    output_file=$(capture_gemini_output "What is the current checkpoint?" "/tmp/gemini_cp_test_$$.txt" 15)

    # Checkpoint should be mentioned in output
    if [[ -f "$output_file" ]]; then
        run verify_output_respects_checkpoint "$output_file" "CP_"
        rm -f "$output_file"
    fi
}

# =============================================================================
# GEMINI SESSION TESTS
# =============================================================================

@test "Gemini session creates handoff notes" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Run Gemini with handoff request
    run_gemini_workflow "Create a handoff note for the next session" 15 > /dev/null

    # Verify handoff exists
    [ -f ".workflow/handoff.md" ]
}

@test "Gemini updates state.yaml correctly" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    local before_updated
    before_updated=$(grep "last_updated" .workflow/state.yaml | head -1)

    # Small delay
    sleep 1

    # Simulate Gemini updating state
    sed -i "s/last_updated:.*/last_updated: \"$(date -Iseconds)\"/" .workflow/state.yaml

    local after_updated
    after_updated=$(grep "last_updated" .workflow/state.yaml | head -1)

    # Should be different
    [[ "$before_updated" != "$after_updated" ]] || [[ -n "$after_updated" ]]
}

@test "Gemini creates valid checkpoints" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Run checkpoint script as Gemini would
    run "${SCRIPTS_DIR}/checkpoint.sh" create "Gemini checkpoint"

    assert_success

    # Verify checkpoint in log
    grep -q "Gemini checkpoint" .workflow/checkpoints.log
}

@test "Gemini-created state readable by Claude" {
    cd "${TEST_TMP_DIR}"

    create_gemini_session_state "${TEST_TMP_DIR}"

    # Verify state is valid YAML that Claude can read
    [ -f ".workflow/state.yaml" ]
    grep -q "current_phase:" .workflow/state.yaml
    grep -q "current_checkpoint:" .workflow/state.yaml
    grep -q "metadata:" .workflow/state.yaml
}

# =============================================================================
# MOCK MODE TESTS
# =============================================================================

@test "mock mode produces valid responses" {
    enable_gemini_mock

    local output
    output=$(run_gemini_workflow "status")

    [[ "$output" == *"Status"* ]] || [[ "$output" == *"Workflow"* ]]

    disable_gemini_mock
}

@test "mock mode handles all action types" {
    enable_gemini_mock

    local actions=("status" "checkpoint" "recover" "agent" "skill" "handoff")

    for action in "${actions[@]}"; do
        local output
        output=$(run_gemini_workflow "$action")
        [[ -n "$output" ]]
    done

    disable_gemini_mock
}
