#!/usr/bin/env bash

# Test Helper Functions for Universal Workflow System Tests
# Provides common utilities and setup functions for BATS tests

# Color codes for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color

# Common test setup
common_setup() {
    # Create temporary test directory
    export TEST_DIR="$(mktemp -d)"
    export WORKFLOW_DIR="$TEST_DIR/.workflow"
    export ORIG_PWD="$(pwd)"

    # Create workflow directory structure
    mkdir -p "$WORKFLOW_DIR"/{agents,skills,templates,knowledge}
    mkdir -p "$WORKFLOW_DIR/agents/memory"
    mkdir -p "$TEST_DIR"/{workspace,phases,artifacts,archive}

    # Set test environment variables
    export GIT_DIR="$TEST_DIR/.git"
    export GIT_WORK_TREE="$TEST_DIR"

    cd "$TEST_DIR"
}

# Common test teardown
common_teardown() {
    cd "$ORIG_PWD"
    rm -rf "$TEST_DIR"
}

# Create minimal state file
create_test_state() {
    local phase="${1:-phase_1_planning}"
    local checkpoint="${2:-CP_1_001}"

    cat > "$WORKFLOW_DIR/state.yaml" <<EOF
project_name: test_project
project_type: software
current_phase: $phase
last_checkpoint: $checkpoint
last_updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
context_bridge:
  critical_info: []
  next_actions: []
  dependencies: []
EOF
}

# Create test config file
create_test_config() {
    cat > "$WORKFLOW_DIR/config.yaml" <<EOF
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
}

# Create test checkpoints log
create_test_checkpoints() {
    cat > "$WORKFLOW_DIR/checkpoints.log" <<EOF
2024-01-01T10:00:00Z | CP_1_001 | Initial planning checkpoint
2024-01-02T14:30:00Z | CP_1_002 | Requirements finalized
2024-01-03T09:15:00Z | CP_2_001 | Implementation started
EOF
}

# Create test handoff document
create_test_handoff() {
    cat > "$WORKFLOW_DIR/handoff.md" <<EOF
# Workflow Context Handoff

## Current Status
- Phase: phase_2_implementation
- Last Checkpoint: CP_2_001
- Active Agent: implementer

## Critical Context
- Database schema designed
- API endpoints defined

## Next Actions
- [ ] Implement user authentication
- [ ] Set up database migrations

## Open Questions
- Which authentication method to use?

## Dependencies
- PostgreSQL database
- JWT library
EOF
}

# Create test agent registry
create_test_agent_registry() {
    cp "$ORIG_PWD/.workflow/agents/registry.yaml" "$WORKFLOW_DIR/agents/registry.yaml" 2>/dev/null || \
    cat > "$WORKFLOW_DIR/agents/registry.yaml" <<EOF
agents:
  researcher:
    name: researcher
    description: Research and analysis specialist
    capabilities:
      - literature_review
      - hypothesis_formation
    workspace: workspace/researcher

  implementer:
    name: implementer
    description: Code development specialist
    capabilities:
      - code_generation
      - debugging
    workspace: workspace/implementer
EOF
}

# Create test skill catalog
create_test_skill_catalog() {
    cp "$ORIG_PWD/.workflow/skills/catalog.yaml" "$WORKFLOW_DIR/skills/catalog.yaml" 2>/dev/null || \
    cat > "$WORKFLOW_DIR/skills/catalog.yaml" <<EOF
skills:
  research:
    - name: literature_review
      description: Search and analyze research papers

  development:
    - name: code_generation
      description: Generate code from specifications

    - name: debugging
      description: Debug and fix code issues
EOF
}

# Initialize test git repository
init_test_git() {
    cd "$TEST_DIR"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    [ -f "$file" ] || {
        echo "File does not exist: $file"
        return 1
    }
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    [ -d "$dir" ] || {
        echo "Directory does not exist: $dir"
        return 1
    }
}

# Assert string contains substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        echo "String does not contain expected substring"
        echo "Expected to find: $needle"
        echo "In: $haystack"
        return 1
    }
}

# Assert string matches regex
assert_matches() {
    local string="$1"
    local pattern="$2"
    [[ "$string" =~ $pattern ]] || {
        echo "String does not match pattern"
        echo "Pattern: $pattern"
        echo "String: $string"
        return 1
    }
}

# Assert YAML file has key
assert_yaml_key_exists() {
    local file="$1"
    local key="$2"

    grep -q "^${key}:" "$file" || {
        echo "YAML key not found: $key in $file"
        return 1
    }
}

# Get YAML value (simple parser for testing)
get_test_yaml_value() {
    local file="$1"
    local key="$2"

    grep "^${key}:" "$file" | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*$//'
}

# Assert YAML has value
assert_yaml_value() {
    local file="$1"
    local key="$2"
    local expected="$3"

    local actual=$(get_test_yaml_value "$file" "$key")

    [ "$actual" = "$expected" ] || {
        echo "YAML value mismatch for key: $key"
        echo "Expected: $expected"
        echo "Actual: $actual"
        return 1
    }
}

# Count lines in file
count_lines() {
    wc -l < "$1"
}

# Get last line of file
get_last_line() {
    tail -n 1 "$1"
}

# Assert exit code
assert_success() {
    [ "$status" -eq 0 ] || {
        echo "Command failed with exit code: $status"
        echo "Output: $output"
        return 1
    }
}

assert_failure() {
    [ "$status" -ne 0 ] || {
        echo "Command succeeded but was expected to fail"
        return 1
    }
}

# Mock date command for consistent testing
mock_date() {
    echo "2024-01-15T12:00:00Z"
}

# Load script with test environment
load_script() {
    local script="$1"

    # Source the script in test environment
    source "$ORIG_PWD/$script"
}

# Export all functions
export -f common_setup
export -f common_teardown
export -f create_test_state
export -f create_test_config
export -f create_test_checkpoints
export -f create_test_handoff
export -f create_test_agent_registry
export -f create_test_skill_catalog
export -f init_test_git
export -f assert_file_exists
export -f assert_dir_exists
export -f assert_contains
export -f assert_matches
export -f assert_yaml_key_exists
export -f get_test_yaml_value
export -f assert_yaml_value
export -f count_lines
export -f get_last_line
export -f assert_success
export -f assert_failure
export -f mock_date
export -f load_script
