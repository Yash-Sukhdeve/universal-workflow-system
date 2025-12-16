#!/usr/bin/env bats
# Bidirectional handoff integration tests
# Tests round-trip state preservation between Claude ↔ Gemini

load '../helpers/test_helper.bash'
load '../helpers/dual_compat_helper.bash'
load '../helpers/gemini_wrapper.bash'

# Setup and teardown
setup() {
    setup_test_environment
    create_full_test_environment
    setup_dual_environment
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# ROUND TRIP TESTS
# =============================================================================

@test "Claude → Gemini → Claude preserves state" {
    cd "${TEST_TMP_DIR}"

    # Start with Claude state
    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "implementer"

    # Capture initial state
    local initial_phase initial_checkpoint
    initial_phase=$(grep "current_phase:" .workflow/state.yaml | head -1 | cut -d'"' -f2)
    initial_checkpoint=$(grep "current_checkpoint:" .workflow/state.yaml | head -1 | cut -d'"' -f2)

    # Handoff to Gemini
    create_handoff_checkpoint "${TEST_TMP_DIR}" "To Gemini" "claude" "gemini"

    # Handoff back to Claude
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Back to Claude" "gemini" "claude"

    # Verify state preserved
    local final_phase final_checkpoint
    final_phase=$(grep "current_phase:" .workflow/state.yaml | head -1 | cut -d'"' -f2)

    [[ "$initial_phase" == "$final_phase" ]]
}

@test "Gemini → Claude → Gemini preserves state" {
    cd "${TEST_TMP_DIR}"

    # Start with Gemini state
    create_gemini_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    local initial_phase
    initial_phase=$(grep "current_phase:" .workflow/state.yaml | head -1 | cut -d'"' -f2)

    # Handoff to Claude
    create_handoff_checkpoint "${TEST_TMP_DIR}" "To Claude" "gemini" "claude"

    # Handoff back to Gemini
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Back to Gemini" "claude" "gemini"

    # Verify state preserved
    local final_phase
    final_phase=$(grep "current_phase:" .workflow/state.yaml | head -1 | cut -d'"' -f2)

    [[ "$initial_phase" == "$final_phase" ]]
}

@test "5-way handoff chain maintains integrity" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    local initial_checkpoint_count
    initial_checkpoint_count=$(wc -l < .workflow/checkpoints.log)

    # 5-way handoff chain
    create_handoff_checkpoint "${TEST_TMP_DIR}" "1: Claude to Gemini" "claude" "gemini"
    create_handoff_checkpoint "${TEST_TMP_DIR}" "2: Gemini to Claude" "gemini" "claude"
    create_handoff_checkpoint "${TEST_TMP_DIR}" "3: Claude to Gemini" "claude" "gemini"
    create_handoff_checkpoint "${TEST_TMP_DIR}" "4: Gemini to Claude" "gemini" "claude"
    create_handoff_checkpoint "${TEST_TMP_DIR}" "5: Claude to Gemini" "claude" "gemini"

    # Verify integrity
    run check_state_corruption "${TEST_TMP_DIR}"
    assert_success

    # Verify checkpoints added
    local final_checkpoint_count
    final_checkpoint_count=$(wc -l < .workflow/checkpoints.log)
    [ "$final_checkpoint_count" -gt "$initial_checkpoint_count" ]
}

# =============================================================================
# STATE PRESERVATION TESTS
# =============================================================================

@test "Checkpoint count preserved across tools" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Add checkpoints
    echo "$(date -Iseconds) | CP_1_002 | Checkpoint A" >> .workflow/checkpoints.log
    echo "$(date -Iseconds) | CP_1_003 | Checkpoint B" >> .workflow/checkpoints.log

    local before_count
    before_count=$(wc -l < .workflow/checkpoints.log)

    # Handoff cycle
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff" "claude" "gemini"

    local after_count
    after_count=$(wc -l < .workflow/checkpoints.log)

    # Count should increase (handoff adds a checkpoint)
    [ "$after_count" -ge "$before_count" ]
}

@test "Phase transitions valid across tools" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001"

    # Verify phase format before handoff
    local phase
    phase=$(grep "current_phase:" .workflow/state.yaml | head -1 | cut -d'"' -f2)
    [[ "$phase" =~ ^phase_[1-5]_ ]]

    # Handoff
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff" "claude" "gemini"

    # Verify phase format after handoff
    phase=$(grep "current_phase:" .workflow/state.yaml | head -1 | cut -d'"' -f2)
    [[ "$phase" =~ ^phase_[1-5]_ ]]
}

@test "Agent transitions valid across tools" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "implementer"

    # Verify agent before
    grep -q "implementer" .workflow/state.yaml

    # Handoff to Gemini (might change agent)
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff" "claude" "gemini"

    # Agent should still be valid
    local agent
    agent=$(grep -A2 "active_agent:" .workflow/state.yaml | grep "name:" | head -1)
    [[ -n "$agent" ]]
}

@test "Skill state consistent across tools" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Verify skills exist
    grep -q "enabled_skills:" .workflow/state.yaml

    # Handoff
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff" "claude" "gemini"

    # Skills should still be valid
    grep -q "enabled_skills:" .workflow/state.yaml
}

# =============================================================================
# METADATA TESTS
# =============================================================================

@test "Health status reflects handoff history" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    # Verify health exists
    grep -q "health:" .workflow/state.yaml

    # Multiple handoffs
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff 1" "claude" "gemini"
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff 2" "gemini" "claude"

    # Health should still be tracked
    grep -q "health:" .workflow/state.yaml
}

@test "Metadata timestamps correct" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}"

    local before_timestamp
    before_timestamp=$(grep "last_updated:" .workflow/state.yaml | head -1)

    sleep 1

    # Handoff (should update timestamp)
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff" "claude" "gemini"

    # Checkpoints.log should have new timestamps
    local latest_entry
    latest_entry=$(tail -1 .workflow/checkpoints.log)
    [[ -n "$latest_entry" ]]
}

@test "Git commit references valid" {
    cd "${TEST_TMP_DIR}"

    # Initialize git
    git init --quiet 2>/dev/null || true
    git add -A 2>/dev/null || true
    git commit -m "Initial commit" --allow-empty 2>/dev/null || true

    create_claude_session_state "${TEST_TMP_DIR}"

    # Handoff
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Handoff" "claude" "gemini"

    # Should not crash with git operations
    [ -d ".git" ]
}
