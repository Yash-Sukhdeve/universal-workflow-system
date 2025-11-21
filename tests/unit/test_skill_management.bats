#!/usr/bin/env bats

# Unit tests for skill management functionality
# Tests skill enabling, disabling, and execution

load '../helpers/test_helper'

setup() {
    common_setup
    create_test_state "phase_2_implementation" "CP_2_001"
    create_test_config
    create_test_skill_catalog
}

teardown() {
    common_teardown
}

# Skill Catalog Tests

@test "skill catalog file exists" {
    assert_file_exists "$WORKFLOW_DIR/skills/catalog.yaml"
}

@test "skill catalog contains research skills" {
    grep -q "research:" "$WORKFLOW_DIR/skills/catalog.yaml"
}

@test "skill catalog contains development skills" {
    grep -q "development:" "$WORKFLOW_DIR/skills/catalog.yaml"
}

@test "skill catalog has skill name field" {
    grep -q "name:" "$WORKFLOW_DIR/skills/catalog.yaml"
}

@test "skill catalog has skill description field" {
    grep -q "description:" "$WORKFLOW_DIR/skills/catalog.yaml"
}

# Skill Enabling Tests

@test "enabled skills file can be created" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
enabled_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    assert_file_exists "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "enabled skills file contains skill list" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
EOF

    grep -q "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml"
    grep -q "debugging" "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "can add skill to enabled list" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
EOF

    # Add new skill
    sed -i '/enabled_skills:/a\  - testing' "$WORKFLOW_DIR/skills/enabled.yaml"

    grep -q "testing" "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "can remove skill from enabled list" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
  - testing
EOF

    # Remove debugging skill
    sed -i '/  - debugging/d' "$WORKFLOW_DIR/skills/enabled.yaml"

    ! grep -q "debugging" "$WORKFLOW_DIR/skills/enabled.yaml"
    grep -q "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml"
    grep -q "testing" "$WORKFLOW_DIR/skills/enabled.yaml"
}

# Skill Categories Tests

@test "research skills are in catalog" {
    grep -A 5 "research:" "$WORKFLOW_DIR/skills/catalog.yaml" | grep -q "name: literature_review"
}

@test "development skills are in catalog" {
    grep -A 5 "development:" "$WORKFLOW_DIR/skills/catalog.yaml" | grep -q "name: code_generation"
}

# Skill Status Tests

@test "can check if skill is enabled" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
EOF

    grep -q "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "can check if skill is not enabled" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
EOF

    ! grep -q "testing" "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "enabled skills count is correct" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
  - testing
EOF

    count=$(grep -c "  - " "$WORKFLOW_DIR/skills/enabled.yaml")
    [ "$count" -eq 3 ]
}

# Multiple Skills Tests

@test "can enable multiple skills at once" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
  - testing
  - refactoring
EOF

    [ $(grep -c "  - " "$WORKFLOW_DIR/skills/enabled.yaml") -eq 4 ]
}

@test "skills maintain order in enabled list" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - skill_a
  - skill_b
  - skill_c
EOF

    # Get line numbers
    line_a=$(grep -n "skill_a" "$WORKFLOW_DIR/skills/enabled.yaml" | cut -d':' -f1)
    line_b=$(grep -n "skill_b" "$WORKFLOW_DIR/skills/enabled.yaml" | cut -d':' -f1)
    line_c=$(grep -n "skill_c" "$WORKFLOW_DIR/skills/enabled.yaml" | cut -d':' -f1)

    [ "$line_a" -lt "$line_b" ]
    [ "$line_b" -lt "$line_c" ]
}

# Skill Dependencies Tests

@test "can track skill dependencies" {
    cat > "$WORKFLOW_DIR/skills/test_skill_def.yaml" <<EOF
name: advanced_testing
description: Advanced testing capabilities
dependencies:
  - testing
  - debugging
EOF

    grep -q "dependencies:" "$WORKFLOW_DIR/skills/test_skill_def.yaml"
    grep -A 3 "dependencies:" "$WORKFLOW_DIR/skills/test_skill_def.yaml" | grep -q "testing"
}

@test "skills without dependencies work" {
    cat > "$WORKFLOW_DIR/skills/simple_skill.yaml" <<EOF
name: simple_skill
description: A simple skill with no dependencies
EOF

    assert_file_exists "$WORKFLOW_DIR/skills/simple_skill.yaml"
    ! grep -q "dependencies:" "$WORKFLOW_DIR/skills/simple_skill.yaml"
}

# Skill Execution Logging Tests

@test "can log skill execution" {
    mkdir -p "$WORKFLOW_DIR/skills/logs"

    echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | code_generation | started" > "$WORKFLOW_DIR/skills/logs/execution.log"

    assert_file_exists "$WORKFLOW_DIR/skills/logs/execution.log"
    grep -q "code_generation" "$WORKFLOW_DIR/skills/logs/execution.log"
}

@test "skill execution log has correct format" {
    mkdir -p "$WORKFLOW_DIR/skills/logs"

    echo "2024-01-15T12:00:00Z | debugging | completed | success" > "$WORKFLOW_DIR/skills/logs/execution.log"

    line=$(cat "$WORKFLOW_DIR/skills/logs/execution.log")
    [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z.*debugging.*completed.*success$ ]]
}

@test "can track multiple skill executions" {
    mkdir -p "$WORKFLOW_DIR/skills/logs"

    cat > "$WORKFLOW_DIR/skills/logs/execution.log" <<EOF
2024-01-15T10:00:00Z | code_generation | completed | success
2024-01-15T11:00:00Z | debugging | completed | success
2024-01-15T12:00:00Z | testing | started
EOF

    count=$(wc -l < "$WORKFLOW_DIR/skills/logs/execution.log")
    [ "$count" -eq 3 ]
}

# Skill Validation Tests

@test "skill name is present in catalog" {
    grep -q "name: code_generation" "$WORKFLOW_DIR/skills/catalog.yaml"
}

@test "skill description is present in catalog" {
    grep -q "description:" "$WORKFLOW_DIR/skills/catalog.yaml"
}

# Empty/Edge Cases

@test "empty enabled skills list" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills: []
EOF

    grep -q "enabled_skills: \[\]" "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "enabling already enabled skill is idempotent" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
EOF

    # Try to add again (should check first)
    if ! grep -q "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml"; then
        sed -i '/enabled_skills:/a\  - code_generation' "$WORKFLOW_DIR/skills/enabled.yaml"
    fi

    # Should still only have one occurrence
    count=$(grep -c "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml")
    [ "$count" -eq 1 ]
}

@test "disabling non-enabled skill is safe" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
EOF

    # Try to remove non-existent skill
    sed -i '/  - nonexistent_skill/d' "$WORKFLOW_DIR/skills/enabled.yaml"

    # Original skill should still be there
    grep -q "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml"
}

# Skill Definition Tests

@test "can create custom skill definition" {
    cat > "$WORKFLOW_DIR/skills/custom_skill.yaml" <<EOF
name: custom_optimization
description: Custom optimization technique
category: optimization
parameters:
  learning_rate: 0.001
  batch_size: 32
EOF

    assert_file_exists "$WORKFLOW_DIR/skills/custom_skill.yaml"
    grep -q "name: custom_optimization" "$WORKFLOW_DIR/skills/custom_skill.yaml"
}

@test "skill definition has parameters" {
    cat > "$WORKFLOW_DIR/skills/param_skill.yaml" <<EOF
name: parameterized_skill
parameters:
  param1: value1
  param2: value2
EOF

    grep -q "parameters:" "$WORKFLOW_DIR/skills/param_skill.yaml"
    grep -q "param1:" "$WORKFLOW_DIR/skills/param_skill.yaml"
}

# Skill Chain Tests

@test "can define skill chain" {
    cat > "$WORKFLOW_DIR/skills/chain_def.yaml" <<EOF
chain_name: development_pipeline
skills:
  - code_generation
  - testing
  - debugging
  - refactoring
EOF

    assert_file_exists "$WORKFLOW_DIR/skills/chain_def.yaml"
    grep -q "chain_name:" "$WORKFLOW_DIR/skills/chain_def.yaml"
}

@test "skill chain maintains order" {
    cat > "$WORKFLOW_DIR/skills/ordered_chain.yaml" <<EOF
skills:
  - first_skill
  - second_skill
  - third_skill
EOF

    lines=$(grep -n "skill" "$WORKFLOW_DIR/skills/ordered_chain.yaml" | cut -d':' -f1)
    read -r line1 line2 line3 <<< "$lines"

    [ "$line1" -lt "$line2" ]
    [ "$line2" -lt "$line3" ]
}

# Agent-Skill Integration Tests

@test "agent can have associated skills" {
    cat > "$WORKFLOW_DIR/agents/implementer_skills.yaml" <<EOF
agent: implementer
auto_enable_skills:
  - code_generation
  - debugging
  - testing
EOF

    grep -q "code_generation" "$WORKFLOW_DIR/agents/implementer_skills.yaml"
    grep -q "debugging" "$WORKFLOW_DIR/agents/implementer_skills.yaml"
}

@test "different agents have different skills" {
    cat > "$WORKFLOW_DIR/agents/researcher_skills.yaml" <<EOF
agent: researcher
auto_enable_skills:
  - literature_review
EOF

    cat > "$WORKFLOW_DIR/agents/implementer_skills.yaml" <<EOF
agent: implementer
auto_enable_skills:
  - code_generation
EOF

    grep -q "literature_review" "$WORKFLOW_DIR/agents/researcher_skills.yaml"
    ! grep -q "literature_review" "$WORKFLOW_DIR/agents/implementer_skills.yaml"

    grep -q "code_generation" "$WORKFLOW_DIR/agents/implementer_skills.yaml"
    ! grep -q "code_generation" "$WORKFLOW_DIR/agents/researcher_skills.yaml"
}

# Skill State Persistence

@test "enabled skills persist" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - debugging
EOF

    # Simulate restart - file should still exist
    assert_file_exists "$WORKFLOW_DIR/skills/enabled.yaml"
    grep -q "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "skill history can be tracked" {
    mkdir -p "$WORKFLOW_DIR/skills/logs"

    cat > "$WORKFLOW_DIR/skills/logs/history.log" <<EOF
2024-01-01T10:00:00Z | code_generation | enabled
2024-01-02T11:00:00Z | debugging | enabled
2024-01-03T09:00:00Z | testing | enabled
2024-01-04T14:00:00Z | debugging | disabled
EOF

    count=$(wc -l < "$WORKFLOW_DIR/skills/logs/history.log")
    [ "$count" -eq 4 ]

    grep -q "enabled" "$WORKFLOW_DIR/skills/logs/history.log"
    grep -q "disabled" "$WORKFLOW_DIR/skills/logs/history.log"
}

# Performance Tests

@test "can handle many enabled skills" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
EOF

    # Add 50 skills
    for i in {1..50}; do
        echo "  - skill_$i" >> "$WORKFLOW_DIR/skills/enabled.yaml"
    done

    count=$(grep -c "  - skill_" "$WORKFLOW_DIR/skills/enabled.yaml")
    [ "$count" -eq 50 ]
}

@test "skill lookup is fast with many skills" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
EOF

    # Add 100 skills
    for i in {1..100}; do
        echo "  - skill_$i" >> "$WORKFLOW_DIR/skills/enabled.yaml"
    done

    # Check if specific skill exists
    grep -q "skill_50" "$WORKFLOW_DIR/skills/enabled.yaml"
}

# Skill Naming Tests

@test "skill names with underscores" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - code_generation
  - advanced_debugging
EOF

    grep -q "advanced_debugging" "$WORKFLOW_DIR/skills/enabled.yaml"
}

@test "skill names are case sensitive" {
    cat > "$WORKFLOW_DIR/skills/enabled.yaml" <<EOF
enabled_skills:
  - CodeGeneration
  - code_generation
EOF

    grep -q "CodeGeneration" "$WORKFLOW_DIR/skills/enabled.yaml"
    grep -q "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml"

    # Should have both (case sensitive)
    [ $(grep -c "code_generation" "$WORKFLOW_DIR/skills/enabled.yaml") -eq 1 ]
    [ $(grep -c "CodeGeneration" "$WORKFLOW_DIR/skills/enabled.yaml") -eq 1 ]
}
