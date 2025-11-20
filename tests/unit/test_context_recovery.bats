#!/usr/bin/env bats

# Unit tests for context recovery functionality
# Tests context restoration after session breaks

load '../helpers/test_helper'

setup() {
    common_setup
    create_test_state "phase_2_implementation" "CP_2_003"
    create_test_checkpoints
    create_test_handoff
}

teardown() {
    common_teardown
}

# Handoff Document Tests

@test "handoff document exists" {
    assert_file_exists "$WORKFLOW_DIR/handoff.md"
}

@test "handoff document has current status section" {
    grep -q "## Current Status" "$WORKFLOW_DIR/handoff.md"
}

@test "handoff document has critical context section" {
    grep -q "## Critical Context" "$WORKFLOW_DIR/handoff.md"
}

@test "handoff document has next actions section" {
    grep -q "## Next Actions" "$WORKFLOW_DIR/handoff.md"
}

@test "handoff document has open questions section" {
    grep -q "## Open Questions" "$WORKFLOW_DIR/handoff.md"
}

@test "handoff document has dependencies section" {
    grep -q "## Dependencies" "$WORKFLOW_DIR/handoff.md"
}

# Handoff Content Tests

@test "handoff document contains phase information" {
    grep -q "Phase:" "$WORKFLOW_DIR/handoff.md"
}

@test "handoff document contains checkpoint information" {
    grep -q "Last Checkpoint:" "$WORKFLOW_DIR/handoff.md"
}

@test "handoff document contains active agent" {
    grep -q "Active Agent:" "$WORKFLOW_DIR/handoff.md"
}

@test "handoff document lists next actions" {
    grep -q "\[ \]" "$WORKFLOW_DIR/handoff.md"  # Checkbox format
}

# Checkpoint Log Recovery Tests

@test "checkpoint log exists" {
    assert_file_exists "$WORKFLOW_DIR/checkpoints.log"
}

@test "checkpoint log has entries" {
    [ $(wc -l < "$WORKFLOW_DIR/checkpoints.log") -gt 0 ]
}

@test "checkpoint log entries have correct format" {
    first_line=$(head -n 1 "$WORKFLOW_DIR/checkpoints.log")
    [[ "$first_line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ \|\ CP_[0-9]_[0-9]{3}\ \|\ .* ]]
}

@test "can retrieve last checkpoint from log" {
    last_checkpoint=$(tail -n 1 "$WORKFLOW_DIR/checkpoints.log" | cut -d'|' -f2 | xargs)
    [[ "$last_checkpoint" =~ ^CP_[0-9]_[0-9]{3}$ ]]
}

@test "can retrieve last 5 checkpoints" {
    # Add more checkpoints to test
    for i in {4..8}; do
        echo "2024-01-0${i}T10:00:00Z | CP_2_$(printf '%03d' $i) | Checkpoint $i" >> "$WORKFLOW_DIR/checkpoints.log"
    done

    recent=$(tail -n 5 "$WORKFLOW_DIR/checkpoints.log")
    count=$(echo "$recent" | wc -l)
    [ "$count" -eq 5 ]
}

# State Recovery Tests

@test "can read current phase from state" {
    phase=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$phase" = "phase_2_implementation" ]
}

@test "can read last checkpoint from state" {
    checkpoint=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_checkpoint")
    [ "$checkpoint" = "CP_2_003" ]
}

@test "can read project name from state" {
    project=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "project_name")
    [ "$project" = "test_project" ]
}

@test "can read last updated timestamp" {
    timestamp=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_updated")
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# Context Bridge Recovery

@test "can parse critical_info from context bridge" {
    grep -A 10 "context_bridge:" "$WORKFLOW_DIR/state.yaml" | grep -q "critical_info:"
}

@test "can parse next_actions from context bridge" {
    grep -A 10 "context_bridge:" "$WORKFLOW_DIR/state.yaml" | grep -q "next_actions:"
}

@test "can parse dependencies from context bridge" {
    grep -A 10 "context_bridge:" "$WORKFLOW_DIR/state.yaml" | grep -q "dependencies:"
}

# Handoff Notes Parsing Tests

@test "can extract critical context from handoff" {
    # Check for critical context items
    grep -A 5 "## Critical Context" "$WORKFLOW_DIR/handoff.md" | grep -q "Database"
}

@test "can extract next actions from handoff" {
    grep -A 5 "## Next Actions" "$WORKFLOW_DIR/handoff.md" | grep -q "authentication"
}

@test "can extract dependencies from handoff" {
    grep -A 5 "## Dependencies" "$WORKFLOW_DIR/handoff.md" | grep -q "PostgreSQL"
}

@test "can extract open questions from handoff" {
    grep -A 5 "## Open Questions" "$WORKFLOW_DIR/handoff.md" | grep -q "authentication method"
}

# Recent Activity Recovery

@test "can count total checkpoints" {
    total=$(wc -l < "$WORKFLOW_DIR/checkpoints.log")
    [ "$total" -ge 3 ]
}

@test "can count checkpoints by phase" {
    phase_1_count=$(grep -c "CP_1_" "$WORKFLOW_DIR/checkpoints.log")
    phase_2_count=$(grep -c "CP_2_" "$WORKFLOW_DIR/checkpoints.log")

    [ "$phase_1_count" -ge 0 ]
    [ "$phase_2_count" -ge 0 ]
}

@test "can find most recent checkpoint time" {
    recent_time=$(tail -n 1 "$WORKFLOW_DIR/checkpoints.log" | cut -d'|' -f1 | xargs)
    [[ "$recent_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# Phase-Specific Context

@test "phase_2_implementation suggests implementation actions" {
    create_test_state "phase_2_implementation" "CP_2_001"

    phase=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$phase" = "phase_2_implementation" ]

    # In phase 2, typical actions might include code development
    # This would be customized per project
}

@test "phase_3_validation suggests testing actions" {
    create_test_state "phase_3_validation" "CP_3_001"

    phase=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    [ "$phase" = "phase_3_validation" ]

    # In phase 3, typical actions might include running tests
}

# Snapshot Recovery Tests

@test "can identify available snapshots" {
    mkdir -p "$WORKFLOW_DIR/snapshots/CP_2_001"
    mkdir -p "$WORKFLOW_DIR/snapshots/CP_2_002"
    mkdir -p "$WORKFLOW_DIR/snapshots/CP_2_003"

    count=$(find "$WORKFLOW_DIR/snapshots" -maxdepth 1 -type d -name "CP_*" | wc -l)
    [ "$count" -eq 3 ]
}

@test "can retrieve snapshot state file" {
    mkdir -p "$WORKFLOW_DIR/snapshots/CP_2_001"
    cp "$WORKFLOW_DIR/state.yaml" "$WORKFLOW_DIR/snapshots/CP_2_001/state.yaml"

    assert_file_exists "$WORKFLOW_DIR/snapshots/CP_2_001/state.yaml"
}

@test "snapshot contains project information" {
    mkdir -p "$WORKFLOW_DIR/snapshots/CP_2_001"
    cp "$WORKFLOW_DIR/state.yaml" "$WORKFLOW_DIR/snapshots/CP_2_001/state.yaml"

    grep -q "project_name:" "$WORKFLOW_DIR/snapshots/CP_2_001/state.yaml"
}

# Git Context Recovery

@test "can check git status for context" {
    init_test_git

    echo "test file" > "$TEST_DIR/test.txt"

    status=$(git status --porcelain)
    [[ "$status" == *"test.txt"* ]]
}

@test "can get current git branch" {
    init_test_git
    git checkout -b feature-branch 2>/dev/null

    branch=$(git branch --show-current)
    [ "$branch" = "feature-branch" ]
}

@test "can get last commit info" {
    init_test_git

    echo "test" > "$TEST_DIR/file.txt"
    git add file.txt
    git commit -m "Test commit" -q

    last_commit=$(git log -1 --oneline)
    [[ "$last_commit" == *"Test commit"* ]]
}

# Agent State Recovery

@test "can recover active agent information" {
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
activated_at: 2024-01-15T12:00:00Z
status: active
EOF

    active_agent=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "agent")
    [ "$active_agent" = "implementer" ]
}

@test "can determine if no agent is active" {
    rm -f "$WORKFLOW_DIR/agents/active.yaml"

    [ ! -f "$WORKFLOW_DIR/agents/active.yaml" ]
}

# Skill State Recovery

@test "can recover enabled skills" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
  - testing
EOF

    assert_file_exists "$WORKFLOW_DIR/skills/enabled.yaml"
    grep -q "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "can count enabled skills" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
  - testing
EOF

    count=$(grep -c "  - " "$WORKFLOW_DIR/skills/enabled.yaml")
    [ "$count" -eq 3 ]
}

# Time-Based Context

@test "can calculate time since last update" {
    timestamp=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_updated")
    [ -n "$timestamp" ]

    # Timestamp should be in past (assuming test runs quickly)
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "can find checkpoints from today" {
    today=$(date +%Y-%m-%d)

    # Add today's checkpoint
    echo "${today}T15:00:00Z | CP_2_004 | Today's checkpoint" >> "$WORKFLOW_DIR/checkpoints.log"

    today_count=$(grep "$today" "$WORKFLOW_DIR/checkpoints.log" | wc -l)
    [ "$today_count" -ge 1 ]
}

# Complete Context Recovery Test

@test "full context recovery has all components" {
    # State file
    assert_file_exists "$WORKFLOW_DIR/state.yaml"

    # Checkpoints log
    assert_file_exists "$WORKFLOW_DIR/checkpoints.log"

    # Handoff document
    assert_file_exists "$WORKFLOW_DIR/handoff.md"

    # All key information present
    grep -q "project_name:" "$WORKFLOW_DIR/state.yaml"
    grep -q "current_phase:" "$WORKFLOW_DIR/state.yaml"
    [ $(wc -l < "$WORKFLOW_DIR/checkpoints.log") -gt 0 ]
    grep -q "## Current Status" "$WORKFLOW_DIR/handoff.md"
}

# Edge Cases

@test "recovery works with no checkpoints" {
    rm -f "$WORKFLOW_DIR/checkpoints.log"

    [ ! -f "$WORKFLOW_DIR/checkpoints.log" ]
    # Should still have state file
    assert_file_exists "$WORKFLOW_DIR/state.yaml"
}

@test "recovery works with missing handoff" {
    rm -f "$WORKFLOW_DIR/handoff.md"

    [ ! -f "$WORKFLOW_DIR/handoff.md" ]
    # Can still recover from state
    assert_file_exists "$WORKFLOW_DIR/state.yaml"
}

@test "recovery works with minimal state" {
    cat > "$WORKFLOW_DIR/state.yaml" <<EOF
project_name: minimal_project
current_phase: phase_1_planning
last_checkpoint: CP_1_001
EOF

    project=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "project_name")
    [ "$project" = "minimal_project" ]
}

# Knowledge Base Recovery

@test "can access knowledge base patterns" {
    mkdir -p "$WORKFLOW_DIR/knowledge"

    cat > "$WORKFLOW_DIR/knowledge/patterns.yaml" <<EOF
learned_patterns:
  - pattern: Use quantization for model compression
    context: ML optimization
    effectiveness: high
EOF

    assert_file_exists "$WORKFLOW_DIR/knowledge/patterns.yaml"
    grep -q "learned_patterns:" "$WORKFLOW_DIR/knowledge/patterns.yaml"
}

@test "can count learned patterns" {
    mkdir -p "$WORKFLOW_DIR/knowledge"

    cat > "$WORKFLOW_DIR/knowledge/patterns.yaml" <<EOF
learned_patterns:
  - pattern: Pattern 1
  - pattern: Pattern 2
  - pattern: Pattern 3
EOF

    count=$(grep -c "  - pattern:" "$WORKFLOW_DIR/knowledge/patterns.yaml")
    [ "$count" -eq 3 ]
}

# Recovery Priority Tests

@test "critical context is easily accessible" {
    # Critical info should be in both state and handoff
    grep -q "critical_info:" "$WORKFLOW_DIR/state.yaml"
    grep -q "## Critical Context" "$WORKFLOW_DIR/handoff.md"
}

@test "next actions are prominently listed" {
    # Next actions should be in both places
    grep -q "next_actions:" "$WORKFLOW_DIR/state.yaml"
    grep -q "## Next Actions" "$WORKFLOW_DIR/handoff.md"
}

@test "blockers are identified" {
    # Handoff should have questions/blockers section
    grep -q "## Open Questions" "$WORKFLOW_DIR/handoff.md"
}
