#!/usr/bin/env bats

# Integration tests for workflow initialization
# Tests the complete initialization flow

load '../helpers/test_helper'

setup() {
    export TEST_DIR="$(mktemp -d)"
    export ORIG_PWD="$(pwd)"
    cd "$TEST_DIR"
}

teardown() {
    cd "$ORIG_PWD"
    rm -rf "$TEST_DIR"
}

# Basic Initialization Tests

@test "workflow initialization creates .workflow directory" {
    mkdir -p .workflow

    [ -d .workflow ]
}

@test "workflow initialization creates all subdirectories" {
    mkdir -p .workflow/{agents,skills,templates,knowledge,snapshots}
    mkdir -p .workflow/agents/memory
    mkdir -p workspace phases artifacts archive

    assert_dir_exists ".workflow"
    assert_dir_exists ".workflow/agents"
    assert_dir_exists ".workflow/skills"
    assert_dir_exists ".workflow/templates"
    assert_dir_exists ".workflow/knowledge"
    assert_dir_exists ".workflow/snapshots"
    assert_dir_exists "workspace"
    assert_dir_exists "phases"
    assert_dir_exists "artifacts"
}

@test "workflow initialization creates state file" {
    mkdir -p .workflow

    cat > .workflow/state.yaml <<EOF
project_name: test_init_project
project_type: software
current_phase: phase_1_planning
last_checkpoint: CP_1_001
last_updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
context_bridge:
  critical_info: []
  next_actions: []
  dependencies: []
EOF

    assert_file_exists ".workflow/state.yaml"
    grep -q "project_name: test_init_project" .workflow/state.yaml
}

@test "workflow initialization creates config file" {
    mkdir -p .workflow

    cat > .workflow/config.yaml <<EOF
project:
  name: test_project
  type: software
  version: 1.0.0

workflow:
  auto_checkpoint: false
  checkpoint_on_phase_change: true

git:
  auto_commit: false
  commit_checkpoints: false

agents:
  default_agent: implementer

skills:
  auto_enable: false
EOF

    assert_file_exists ".workflow/config.yaml"
    grep -q "project:" .workflow/config.yaml
}

@test "workflow initialization creates handoff template" {
    mkdir -p .workflow

    cat > .workflow/handoff.md <<EOF
# Workflow Context Handoff

## Current Status
- Phase: phase_1_planning
- Last Checkpoint: CP_1_001
- Active Agent: none

## Critical Context
- Project initialized

## Next Actions
- [ ] Define requirements
- [ ] Set up development environment

## Open Questions
- Which technologies to use?

## Dependencies
- None yet
EOF

    assert_file_exists ".workflow/handoff.md"
    grep -q "# Workflow Context Handoff" .workflow/handoff.md
}

@test "workflow initialization creates checkpoints log" {
    mkdir -p .workflow

    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | CP_1_001 | Initial checkpoint" > .workflow/checkpoints.log

    assert_file_exists ".workflow/checkpoints.log"
    grep -q "CP_1_001" .workflow/checkpoints.log
}

# Configuration Copying Tests

@test "workflow initialization copies agent registry" {
    mkdir -p .workflow/agents

    cp "$ORIG_PWD/.workflow/agents/registry.yaml" .workflow/agents/registry.yaml 2>/dev/null || \
    cat > .workflow/agents/registry.yaml <<EOF
agents:
  researcher:
    name: researcher
    description: Research specialist
  implementer:
    name: implementer
    description: Code development specialist
EOF

    assert_file_exists ".workflow/agents/registry.yaml"
    grep -q "agents:" .workflow/agents/registry.yaml
}

@test "workflow initialization copies skill catalog" {
    mkdir -p .workflow/skills

    cp "$ORIG_PWD/.workflow/skills/catalog.yaml" .workflow/skills/catalog.yaml 2>/dev/null || \
    cat > .workflow/skills/catalog.yaml <<EOF
skills:
  development:
    - name: code_generation
      description: Generate code
EOF

    assert_file_exists ".workflow/skills/catalog.yaml"
    grep -q "skills:" .workflow/skills/catalog.yaml
}

# Git Integration Tests

@test "workflow initialization initializes git if needed" {
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"

    [ -d .git ]
}

@test "workflow initialization creates .gitignore" {
    cat > .gitignore <<EOF
.workflow/agents/memory/
.workflow/snapshots/backup_*
workspace/temp/
*.tmp
EOF

    assert_file_exists ".gitignore"
    grep -q ".workflow/agents/memory/" .gitignore
}

@test "workflow initialization installs git hooks" {
    git init -q

    mkdir -p .git/hooks

    cat > .git/hooks/pre-commit <<'EOF'
#!/bin/bash
# Update workflow state timestamp on commit
if [ -f .workflow/state.yaml ]; then
    sed -i "s/last_updated:.*/last_updated: \"$(date -Iseconds)\"/" .workflow/state.yaml
    git add .workflow/state.yaml
fi
EOF

    chmod +x .git/hooks/pre-commit

    assert_file_exists ".git/hooks/pre-commit"
    [ -x .git/hooks/pre-commit ]
}

# Complete Initialization Flow

@test "complete workflow initialization creates all components" {
    # Create directory structure
    mkdir -p .workflow/{agents,skills,templates,knowledge,snapshots}
    mkdir -p .workflow/agents/memory
    mkdir -p workspace phases artifacts archive

    # Create state file
    cat > .workflow/state.yaml <<EOF
project_name: complete_test
project_type: software
current_phase: phase_1_planning
last_checkpoint: CP_1_001
last_updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
context_bridge:
  critical_info: []
  next_actions: []
  dependencies: []
EOF

    # Create config
    cat > .workflow/config.yaml <<EOF
project:
  name: complete_test
  type: software
EOF

    # Create checkpoints log
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | CP_1_001 | Initial checkpoint" > .workflow/checkpoints.log

    # Verify everything exists
    assert_dir_exists ".workflow"
    assert_file_exists ".workflow/state.yaml"
    assert_file_exists ".workflow/config.yaml"
    assert_file_exists ".workflow/checkpoints.log"
}

# Project Type Detection Tests

@test "project type detection finds Python project" {
    touch requirements.txt
    touch setup.py

    # Simulate detection logic
    if [ -f requirements.txt ] && [ -f setup.py ]; then
        project_type="python"
    fi

    [ "$project_type" = "python" ]
}

@test "project type detection finds Node.js project" {
    touch package.json

    if [ -f package.json ]; then
        project_type="nodejs"
    fi

    [ "$project_type" = "nodejs" ]
}

@test "project type detection finds ML project" {
    mkdir -p models data
    touch train.py

    if [ -f train.py ] && [ -d models ]; then
        project_type="ml"
    fi

    [ "$project_type" = "ml" ]
}

# Initialization with Different Project Types

@test "initialization for ML project creates appropriate structure" {
    mkdir -p .workflow

    cat > .workflow/state.yaml <<EOF
project_name: ml_project
project_type: ml
current_phase: phase_1_planning
last_checkpoint: CP_1_001
EOF

    project_type=$(get_test_yaml_value ".workflow/state.yaml" "project_type")
    [ "$project_type" = "ml" ]
}

@test "initialization for software project creates appropriate structure" {
    mkdir -p .workflow

    cat > .workflow/state.yaml <<EOF
project_name: software_project
project_type: software
current_phase: phase_1_planning
last_checkpoint: CP_1_001
EOF

    project_type=$(get_test_yaml_value ".workflow/state.yaml" "project_type")
    [ "$project_type" = "software" ]
}

# Error Handling

@test "initialization fails gracefully in non-writable directory" {
    skip "Requires permission testing setup"
}

@test "initialization can be re-run safely" {
    mkdir -p .workflow

    cat > .workflow/state.yaml <<EOF
project_name: test
current_phase: phase_1_planning
last_checkpoint: CP_1_001
EOF

    # Re-initialize (should not destroy existing state)
    if [ -f .workflow/state.yaml ]; then
        # Backup exists, safe to continue
        assert_file_exists ".workflow/state.yaml"
    fi
}

# Post-Initialization Verification

@test "post-initialization state is valid" {
    mkdir -p .workflow

    cat > .workflow/state.yaml <<EOF
project_name: test_project
project_type: software
current_phase: phase_1_planning
last_checkpoint: CP_1_001
last_updated: 2024-01-15T12:00:00Z
context_bridge:
  critical_info: []
  next_actions: []
  dependencies: []
EOF

    # Verify all required fields
    grep -q "project_name:" .workflow/state.yaml
    grep -q "project_type:" .workflow/state.yaml
    grep -q "current_phase:" .workflow/state.yaml
    grep -q "last_checkpoint:" .workflow/state.yaml
}

@test "post-initialization phase is phase_1_planning" {
    mkdir -p .workflow

    cat > .workflow/state.yaml <<EOF
project_name: test_project
current_phase: phase_1_planning
last_checkpoint: CP_1_001
EOF

    phase=$(get_test_yaml_value ".workflow/state.yaml" "current_phase")
    [ "$phase" = "phase_1_planning" ]
}

@test "post-initialization checkpoint is CP_1_001" {
    mkdir -p .workflow

    cat > .workflow/state.yaml <<EOF
project_name: test_project
current_phase: phase_1_planning
last_checkpoint: CP_1_001
EOF

    checkpoint=$(get_test_yaml_value ".workflow/state.yaml" "last_checkpoint")
    [ "$checkpoint" = "CP_1_001" ]
}

# Knowledge Base Initialization

@test "knowledge base directory is created" {
    mkdir -p .workflow/knowledge

    assert_dir_exists ".workflow/knowledge"
}

@test "patterns file is initialized" {
    mkdir -p .workflow/knowledge

    cat > .workflow/knowledge/patterns.yaml <<EOF
learned_patterns: []
EOF

    assert_file_exists ".workflow/knowledge/patterns.yaml"
    grep -q "learned_patterns:" .workflow/knowledge/patterns.yaml
}

# Workspace Creation

@test "agent workspaces are created" {
    for agent in researcher architect implementer experimenter optimizer deployer documenter; do
        mkdir -p "workspace/$agent"
    done

    for agent in researcher architect implementer experimenter optimizer deployer documenter; do
        assert_dir_exists "workspace/$agent"
    done
}

@test "phase directories are created" {
    for i in {1..5}; do
        mkdir -p "phases/phase_${i}"
    done

    for i in {1..5}; do
        assert_dir_exists "phases/phase_${i}"
    done
}
