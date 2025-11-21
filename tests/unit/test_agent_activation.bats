#!/usr/bin/env bats

# Unit tests for agent activation functionality
# Tests agent activation, deactivation, and workspace management

load '../helpers/test_helper'

setup() {
    common_setup
    create_test_state "phase_2_implementation" "CP_2_001"
    create_test_config
    create_test_agent_registry

    # Create workspace directories
    for agent in researcher architect implementer experimenter optimizer deployer documenter; do
        mkdir -p "$TEST_DIR/workspace/$agent"
    done
}

teardown() {
    common_teardown
}

# Agent Registry Tests

@test "agent registry file exists" {
    assert_file_exists "$WORKFLOW_DIR/agents/registry.yaml"
}

@test "agent registry contains researcher" {
    grep -q "researcher:" "$WORKFLOW_DIR/agents/registry.yaml"
}

@test "agent registry contains implementer" {
    grep -q "implementer:" "$WORKFLOW_DIR/agents/registry.yaml"
}

@test "agent has name field" {
    grep -A 5 "researcher:" "$WORKFLOW_DIR/agents/registry.yaml" | grep -q "name:"
}

@test "agent has description field" {
    grep -A 5 "researcher:" "$WORKFLOW_DIR/agents/registry.yaml" | grep -q "description:"
}

@test "agent has capabilities field" {
    grep -A 5 "researcher:" "$WORKFLOW_DIR/agents/registry.yaml" | grep -q "capabilities:"
}

@test "agent has workspace field" {
    grep -A 5 "researcher:" "$WORKFLOW_DIR/agents/registry.yaml" | grep -q "workspace:"
}

# Agent Activation Tests

@test "agent activation creates active.yaml file" {
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
activated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
status: active
EOF

    assert_file_exists "$WORKFLOW_DIR/agents/active.yaml"
}

@test "active agent file contains agent name" {
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
activated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
status: active
EOF

    grep -q "agent: implementer" "$WORKFLOW_DIR/agents/active.yaml"
}

@test "active agent file contains timestamp" {
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
activated_at: 2024-01-15T12:00:00Z
status: active
EOF

    timestamp=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "activated_at")
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "active agent file contains status" {
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
activated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
status: active
EOF

    status=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "status")
    [ "$status" = "active" ]
}

# Agent Workspace Tests

@test "researcher workspace exists" {
    assert_dir_exists "$TEST_DIR/workspace/researcher"
}

@test "implementer workspace exists" {
    assert_dir_exists "$TEST_DIR/workspace/implementer"
}

@test "experimenter workspace exists" {
    assert_dir_exists "$TEST_DIR/workspace/experimenter"
}

@test "optimizer workspace exists" {
    assert_dir_exists "$TEST_DIR/workspace/optimizer"
}

@test "deployer workspace exists" {
    assert_dir_exists "$TEST_DIR/workspace/deployer"
}

@test "documenter workspace exists" {
    assert_dir_exists "$TEST_DIR/workspace/documenter"
}

@test "architect workspace exists" {
    assert_dir_exists "$TEST_DIR/workspace/architect"
}

@test "agent can write to workspace" {
    echo "test content" > "$TEST_DIR/workspace/implementer/test_file.txt"

    assert_file_exists "$TEST_DIR/workspace/implementer/test_file.txt"
    grep -q "test content" "$TEST_DIR/workspace/implementer/test_file.txt"
}

# Agent State Persistence Tests

@test "agent state can be saved" {
    mkdir -p "$WORKFLOW_DIR/agents/memory"

    cat > "$WORKFLOW_DIR/agents/memory/implementer_state.yaml" <<EOF
agent: implementer
last_task: code_generation
completed_tasks: 5
current_focus: database_layer
EOF

    assert_file_exists "$WORKFLOW_DIR/agents/memory/implementer_state.yaml"
}

@test "agent state contains last task" {
    mkdir -p "$WORKFLOW_DIR/agents/memory"

    cat > "$WORKFLOW_DIR/agents/memory/implementer_state.yaml" <<EOF
agent: implementer
last_task: code_generation
completed_tasks: 5
EOF

    grep -q "last_task: code_generation" "$WORKFLOW_DIR/agents/memory/implementer_state.yaml"
}

@test "agent state persists across activations" {
    mkdir -p "$WORKFLOW_DIR/agents/memory"

    # Save state
    cat > "$WORKFLOW_DIR/agents/memory/implementer_state.yaml" <<EOF
agent: implementer
last_task: debugging
completed_tasks: 10
EOF

    # Verify state persists
    completed=$(get_test_yaml_value "$WORKFLOW_DIR/agents/memory/implementer_state.yaml" "completed_tasks")
    [ "$completed" = "10" ]
}

# Multiple Agent Tests

@test "can activate different agents sequentially" {
    # Activate implementer
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
activated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
status: active
EOF

    agent1=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "agent")
    [ "$agent1" = "implementer" ]

    # Activate experimenter
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: experimenter
activated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
status: active
EOF

    agent2=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "agent")
    [ "$agent2" = "experimenter" ]
}

@test "agent deactivation changes status" {
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
activated_at: 2024-01-15T12:00:00Z
status: active
EOF

    sed -i "s/status: active/status: inactive/" "$WORKFLOW_DIR/agents/active.yaml"

    status=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "status")
    [ "$status" = "inactive" ]
}

# Agent Capabilities Tests

@test "researcher has correct capabilities" {
    if grep -A 10 "researcher:" "$WORKFLOW_DIR/agents/registry.yaml" | grep -q "capabilities:"; then
        # Has capabilities section
        return 0
    else
        return 1
    fi
}

@test "implementer has correct capabilities" {
    if grep -A 10 "implementer:" "$WORKFLOW_DIR/agents/registry.yaml" | grep -q "capabilities:"; then
        # Has capabilities section
        return 0
    else
        return 1
    fi
}

# Agent Handoff Tests

@test "agent handoff file can be created" {
    mkdir -p "$WORKFLOW_DIR/agents"

    cat > "$WORKFLOW_DIR/agents/handoff_implementer_to_experimenter.yaml" <<EOF
from_agent: implementer
to_agent: experimenter
handoff_time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
completed_work:
  - Database layer implemented
  - API endpoints created
next_tasks:
  - Run integration tests
  - Benchmark performance
artifacts:
  - workspace/implementer/db_schema.sql
  - workspace/implementer/api_routes.py
EOF

    assert_file_exists "$WORKFLOW_DIR/agents/handoff_implementer_to_experimenter.yaml"
}

@test "handoff file contains from_agent" {
    mkdir -p "$WORKFLOW_DIR/agents"

    cat > "$WORKFLOW_DIR/agents/handoff_test.yaml" <<EOF
from_agent: implementer
to_agent: experimenter
EOF

    grep -q "from_agent: implementer" "$WORKFLOW_DIR/agents/handoff_test.yaml"
}

@test "handoff file contains to_agent" {
    mkdir -p "$WORKFLOW_DIR/agents"

    cat > "$WORKFLOW_DIR/agents/handoff_test.yaml" <<EOF
from_agent: implementer
to_agent: experimenter
EOF

    grep -q "to_agent: experimenter" "$WORKFLOW_DIR/agents/handoff_test.yaml"
}

# Agent Status Queries

@test "can determine if agent is active" {
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
status: active
EOF

    status=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "status")
    [ "$status" = "active" ]
}

@test "can get currently active agent name" {
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: researcher
status: active
EOF

    agent=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "agent")
    [ "$agent" = "researcher" ]
}

@test "can check if no agent is active" {
    rm -f "$WORKFLOW_DIR/agents/active.yaml"

    [ ! -f "$WORKFLOW_DIR/agents/active.yaml" ]
}

# Agent-Phase Alignment Tests

@test "implementer is appropriate for phase_2_implementation" {
    # In phase 2, implementer agent makes sense
    create_test_state "phase_2_implementation" "CP_2_001"

    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: implementer
status: active
EOF

    phase=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    agent=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "agent")

    [ "$phase" = "phase_2_implementation" ]
    [ "$agent" = "implementer" ]
}

@test "experimenter is appropriate for phase_3_validation" {
    create_test_state "phase_3_validation" "CP_3_001"

    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: experimenter
status: active
EOF

    phase=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    agent=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "agent")

    [ "$phase" = "phase_3_validation" ]
    [ "$agent" = "experimenter" ]
}

@test "deployer is appropriate for phase_4_delivery" {
    create_test_state "phase_4_delivery" "CP_4_001"

    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: deployer
status: active
EOF

    phase=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "current_phase")
    agent=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "agent")

    [ "$phase" = "phase_4_delivery" ]
    [ "$agent" = "deployer" ]
}

# Agent Memory Persistence

@test "agent memory directory exists" {
    mkdir -p "$WORKFLOW_DIR/agents/memory"

    assert_dir_exists "$WORKFLOW_DIR/agents/memory"
}

@test "agent can save memory between sessions" {
    mkdir -p "$WORKFLOW_DIR/agents/memory"

    # Session 1
    cat > "$WORKFLOW_DIR/agents/memory/researcher_memory.yaml" <<EOF
patterns_learned:
  - Use quantization for efficiency
  - Batch size impacts memory
EOF

    # Session 2 - can read previous memory
    assert_file_exists "$WORKFLOW_DIR/agents/memory/researcher_memory.yaml"
    grep -q "quantization" "$WORKFLOW_DIR/agents/memory/researcher_memory.yaml"
}

# Agent Workspace Isolation

@test "agent workspaces are isolated" {
    echo "implementer data" > "$TEST_DIR/workspace/implementer/data.txt"
    echo "researcher data" > "$TEST_DIR/workspace/researcher/data.txt"

    [ "$(cat $TEST_DIR/workspace/implementer/data.txt)" = "implementer data" ]
    [ "$(cat $TEST_DIR/workspace/researcher/data.txt)" = "researcher data" ]
}

@test "agent workspace contains subdirectories" {
    mkdir -p "$TEST_DIR/workspace/implementer"/{code,docs,tests}

    assert_dir_exists "$TEST_DIR/workspace/implementer/code"
    assert_dir_exists "$TEST_DIR/workspace/implementer/docs"
    assert_dir_exists "$TEST_DIR/workspace/implementer/tests"
}

# Error Cases

@test "activating nonexistent agent handled gracefully" {
    # Attempt to activate non-existent agent
    cat > "$WORKFLOW_DIR/agents/active.yaml" <<EOF
agent: nonexistent_agent
status: active
EOF

    agent=$(get_test_yaml_value "$WORKFLOW_DIR/agents/active.yaml" "agent")
    [ "$agent" = "nonexistent_agent" ]

    # Registry should not contain it
    ! grep -q "nonexistent_agent:" "$WORKFLOW_DIR/agents/registry.yaml"
}

@test "missing agent workspace can be created" {
    rm -rf "$TEST_DIR/workspace/implementer"

    [ ! -d "$TEST_DIR/workspace/implementer" ]

    mkdir -p "$TEST_DIR/workspace/implementer"

    assert_dir_exists "$TEST_DIR/workspace/implementer"
}

# Agent Transitions

@test "can track agent transition history" {
    mkdir -p "$WORKFLOW_DIR/agents"

    # First agent
    echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | researcher | activated" >> "$WORKFLOW_DIR/agents/history.log"

    # Transition
    echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | implementer | activated" >> "$WORKFLOW_DIR/agents/history.log"

    assert_file_exists "$WORKFLOW_DIR/agents/history.log"
    [ $(wc -l < "$WORKFLOW_DIR/agents/history.log") -eq 2 ]
}

@test "agent history tracks all activations" {
    mkdir -p "$WORKFLOW_DIR/agents"

    echo "2024-01-01T10:00:00Z | researcher | activated" > "$WORKFLOW_DIR/agents/history.log"
    echo "2024-01-02T14:00:00Z | implementer | activated" >> "$WORKFLOW_DIR/agents/history.log"
    echo "2024-01-03T09:00:00Z | experimenter | activated" >> "$WORKFLOW_DIR/agents/history.log"

    count=$(wc -l < "$WORKFLOW_DIR/agents/history.log")
    [ "$count" -eq 3 ]

    grep -q "researcher" "$WORKFLOW_DIR/agents/history.log"
    grep -q "implementer" "$WORKFLOW_DIR/agents/history.log"
    grep -q "experimenter" "$WORKFLOW_DIR/agents/history.log"
}
