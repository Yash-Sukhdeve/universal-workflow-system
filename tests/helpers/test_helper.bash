#!/bin/bash
# Test Helper Functions for UWS BATS Tests
# Provides common utilities, fixtures setup, and assertions

# ============================================================================
# ENVIRONMENT SETUP
# ============================================================================

# Get the project root directory
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
export WORKFLOW_DIR="${PROJECT_ROOT}/.workflow"

# Test-specific directories
export TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FIXTURES_DIR="${TEST_DIR}/fixtures"
export TEST_TMP_DIR=""

# Colors for output (disabled in CI)
# Use non-readonly to allow utility scripts to be sourced
if [[ -z "${CI:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi
export RED GREEN YELLOW NC

# Suppress yaml utils warnings in tests
export YAML_UTILS_QUIET=true

# ============================================================================
# SETUP AND TEARDOWN
# ============================================================================

# Create a fresh temporary directory for each test
setup_test_environment() {
    TEST_TMP_DIR="$(mktemp -d)"
    export TEST_TMP_DIR

    # Update WORKFLOW_DIR to point to test directory
    # This is critical for scripts that use WORKFLOW_DIR to find state files
    WORKFLOW_DIR="${TEST_TMP_DIR}/.workflow"
    export WORKFLOW_DIR

    # Create a minimal project structure
    mkdir -p "${TEST_TMP_DIR}/.workflow"/{agents,skills,knowledge,templates}
    mkdir -p "${TEST_TMP_DIR}/workspace"
    mkdir -p "${TEST_TMP_DIR}/phases"
    mkdir -p "${TEST_TMP_DIR}/artifacts"

    # Initialize git repo for tests that need it
    cd "${TEST_TMP_DIR}"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test User"

    # Copy scripts to test environment
    cp -r "${SCRIPTS_DIR}" "${TEST_TMP_DIR}/"

    return 0
}

# Clean up after each test
teardown_test_environment() {
    if [[ -n "${TEST_TMP_DIR}" && -d "${TEST_TMP_DIR}" ]]; then
        rm -rf "${TEST_TMP_DIR}"
    fi
}

# ============================================================================
# FIXTURE CREATION
# ============================================================================

# Create a minimal valid state.yaml
create_minimal_state() {
    local dir="${1:-${TEST_TMP_DIR}}"
    cat > "${dir}/.workflow/state.yaml" << 'EOF'
project:
  name: "test-project"
  type: "software"
  version: "1.0.0"

current_phase: "phase_1_planning"
current_checkpoint: "CP_INIT"
checkpoint_count: 0

metadata:
  created: "2024-01-01T00:00:00Z"
  last_updated: "2024-01-01T00:00:00Z"
  schema_version: "2.0"
  version: "1.0.0"
EOF
}

# Create a valid config.yaml
create_minimal_config() {
    local dir="${1:-${TEST_TMP_DIR}}"
    cat > "${dir}/.workflow/config.yaml" << 'EOF'
project:
  name: "test-project"
  type: "software"
  version: "1.0.0"

workflow:
  phases:
    - phase_1_planning
    - phase_2_implementation
    - phase_3_validation
    - phase_4_delivery
    - phase_5_maintenance

agents:
  enabled: true
  default_agent: "implementer"

skills:
  enabled: true
  auto_load: true

checkpoints:
  auto_checkpoint: false
  max_checkpoints: 100

git:
  auto_commit: false
  branch_per_phase: false
EOF
}

# Create agent registry
create_agent_registry() {
    local dir="${1:-${TEST_TMP_DIR}}"
    cat > "${dir}/.workflow/agents/registry.yaml" << 'EOF'
researcher:
  description: "Research and analysis agent"
  icon: "🔬"
  skills:
    - literature_review
    - hypothesis_formation

architect:
  description: "System design agent"
  icon: "🏗️"
  skills:
    - system_design
    - api_design

implementer:
  description: "Code development agent"
  icon: "💻"
  skills:
    - code_development
    - testing

experimenter:
  description: "Experiment running agent"
  icon: "🧪"
  skills:
    - benchmarking
    - statistical_validation

optimizer:
  description: "Optimization agent"
  icon: "⚡"
  skills:
    - profiling
    - optimization

deployer:
  description: "Deployment agent"
  icon: "🚀"
  skills:
    - containerization
    - ci_cd

documenter:
  description: "Documentation agent"
  icon: "📝"
  skills:
    - technical_writing
    - paper_writing
EOF
}

# Create skill catalog
create_skill_catalog() {
    local dir="${1:-${TEST_TMP_DIR}}"
    cat > "${dir}/.workflow/skills/catalog.yaml" << 'EOF'
skills:
  literature_review:
    category: research
    description: "Systematic literature review"

  code_development:
    category: development
    description: "Software development"

  testing:
    category: development
    description: "Testing and validation"

  benchmarking:
    category: ml_ai
    description: "Performance benchmarking"

  profiling:
    category: optimization
    description: "Code profiling"

  containerization:
    category: deployment
    description: "Docker containerization"

  technical_writing:
    category: documentation
    description: "Technical documentation"

skill_chains:
  full_research_pipeline:
    - literature_review
    - experimental_design
    - statistical_validation
EOF
}

# Create enabled skills file
create_enabled_skills() {
    local dir="${1:-${TEST_TMP_DIR}}"
    cat > "${dir}/.workflow/skills/enabled.yaml" << 'EOF'
enabled_skills:
  - code_development
  - testing
EOF
}

# Create active agent file
create_active_agent() {
    local agent="${1:-implementer}"
    local dir="${2:-${TEST_TMP_DIR}}"
    cat > "${dir}/.workflow/agents/active.yaml" << EOF
current_agent: "${agent}"
task: "Development task"
progress: 0
activated_at: "$(date -Iseconds)"
EOF
}

# Create checkpoints log
create_checkpoints_log() {
    local dir="${1:-${TEST_TMP_DIR}}"
    cat > "${dir}/.workflow/checkpoints.log" << 'EOF'
2024-01-01T00:00:00Z | CP_INIT | Initial checkpoint
2024-01-01T01:00:00Z | CP_1_1 | First development checkpoint
EOF
}

# Create handoff.md
create_handoff_md() {
    local dir="${1:-${TEST_TMP_DIR}}"
    cat > "${dir}/.workflow/handoff.md" << 'EOF'
# Session Handoff Document

## Current Status
- Phase: phase_1_planning
- Checkpoint: CP_INIT
- Agent: implementer

## Priority Actions
- [ ] Complete initial setup
- [ ] Review requirements

## Critical Context
1. Project is in early planning stage
2. No blockers identified

## Next Actions
- [ ] Continue development
EOF
}

# Create a complete test workflow environment
create_full_test_environment() {
    local dir="${1:-${TEST_TMP_DIR}}"

    create_minimal_state "${dir}"
    create_minimal_config "${dir}"
    create_agent_registry "${dir}"
    create_skill_catalog "${dir}"
    create_enabled_skills "${dir}"
    create_checkpoints_log "${dir}"
    create_handoff_md "${dir}"

    # Create phase directories (all 5 phases)
    mkdir -p "${dir}/phases/phase_1_planning"
    mkdir -p "${dir}/phases/phase_2_implementation"
    mkdir -p "${dir}/phases/phase_3_validation"
    mkdir -p "${dir}/phases/phase_4_delivery"
    mkdir -p "${dir}/phases/phase_5_maintenance"

    # Create workspace directories
    mkdir -p "${dir}/workspace/implementer"
    mkdir -p "${dir}/workspace/researcher"
}

# ============================================================================
# MOCK FUNCTIONS
# ============================================================================

# Mock external commands that might not be available
mock_yq() {
    # Create a simple yq mock that uses grep/sed
    export HAS_YQ="false"
}

# Mock git commands for isolated testing
mock_git() {
    local mock_dir="${TEST_TMP_DIR}/.git-mock"
    mkdir -p "${mock_dir}"

    # Create mock git script
    cat > "${mock_dir}/git" << 'EOF'
#!/bin/bash
case "$1" in
    "status") echo "On branch master" ;;
    "branch") echo "* master" ;;
    "log") echo "abc1234 Test commit" ;;
    "add") exit 0 ;;
    "commit") exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "${mock_dir}/git"
    export PATH="${mock_dir}:${PATH}"
}

# ============================================================================
# ASSERTIONS
# ============================================================================

# Assert file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: ${file}}"

    if [[ ! -f "${file}" ]]; then
        echo "FAIL: ${message}" >&2
        return 1
    fi
    return 0
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist: ${dir}}"

    if [[ ! -d "${dir}" ]]; then
        echo "FAIL: ${message}" >&2
        return 1
    fi
    return 0
}

# Assert file contains string
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-File should contain: ${pattern}}"

    if ! grep -q "${pattern}" "${file}" 2>/dev/null; then
        echo "FAIL: ${message}" >&2
        return 1
    fi
    return 0
}

# Assert file does not contain string
assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-File should not contain: ${pattern}}"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        echo "FAIL: ${message}" >&2
        return 1
    fi
    return 0
}

# Assert command succeeds (BATS-compatible)
# If called without arguments, checks the last 'run' status
# If called with arguments, runs the command and checks success
assert_success() {
    if [[ $# -eq 0 ]]; then
        # BATS style - check last run result
        if [[ "${status:-1}" -ne 0 ]]; then
            echo "FAIL: Command failed with status ${status:-unknown}" >&2
            return 1
        fi
    else
        local cmd="$1"
        local message="${2:-Command should succeed: ${cmd}}"
        if ! eval "${cmd}" > /dev/null 2>&1; then
            echo "FAIL: ${message}" >&2
            return 1
        fi
    fi
    return 0
}

# Assert command fails (BATS-compatible)
# If called without arguments, checks the last 'run' status
# If called with arguments, runs the command and checks failure
assert_failure() {
    if [[ $# -eq 0 ]]; then
        # BATS style - check last run result
        if [[ "${status:-0}" -eq 0 ]]; then
            echo "FAIL: Command succeeded but should have failed" >&2
            return 1
        fi
    else
        local cmd="$1"
        local message="${2:-Command should fail: ${cmd}}"
        if eval "${cmd}" > /dev/null 2>&1; then
            echo "FAIL: ${message}" >&2
            return 1
        fi
    fi
    return 0
}

# Assert output contains string (BATS-style)
assert_output() {
    local expected="${1:-}"
    if [[ -n "$expected" ]]; then
        if [[ "${output:-}" != *"$expected"* ]]; then
            echo "FAIL: Output does not contain: $expected" >&2
            echo "  Actual: ${output:-<empty>}" >&2
            return 1
        fi
    fi
    return 0
}

# Refute - negation helper
refute() {
    if "$@"; then
        return 1
    fi
    return 0
}

# Assert strings are equal
assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [[ "${expected}" != "${actual}" ]]; then
        echo "FAIL: ${message}" >&2
        echo "  Expected: ${expected}" >&2
        echo "  Actual:   ${actual}" >&2
        return 1
    fi
    return 0
}

# Assert string matches regex
assert_matches() {
    local pattern="$1"
    local actual="$2"
    local message="${3:-Value should match pattern}"

    if [[ ! "${actual}" =~ ${pattern} ]]; then
        echo "FAIL: ${message}" >&2
        echo "  Pattern: ${pattern}" >&2
        echo "  Actual:  ${actual}" >&2
        return 1
    fi
    return 0
}

# Assert numeric comparison
assert_less_than() {
    local value="$1"
    local max="$2"
    local message="${3:-Value should be less than ${max}}"

    if (( value >= max )); then
        echo "FAIL: ${message}" >&2
        echo "  Value: ${value}" >&2
        echo "  Max:   ${max}" >&2
        return 1
    fi
    return 0
}

# Assert numeric comparison
assert_greater_than() {
    local value="$1"
    local min="$2"
    local message="${3:-Value should be greater than ${min}}"

    if (( value <= min )); then
        echo "FAIL: ${message}" >&2
        echo "  Value: ${value}" >&2
        echo "  Min:   ${min}" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Run a script and capture output
run_script() {
    local script="$1"
    shift
    local args=("$@")

    if [[ -x "${TEST_TMP_DIR}/scripts/${script}" ]]; then
        "${TEST_TMP_DIR}/scripts/${script}" "${args[@]}"
    elif [[ -x "${SCRIPTS_DIR}/${script}" ]]; then
        "${SCRIPTS_DIR}/${script}" "${args[@]}"
    else
        echo "Script not found: ${script}" >&2
        return 1
    fi
}

# Get YAML value (simple grep-based for testing)
get_yaml_value() {
    local file="$1"
    local key="$2"
    grep "^${key}:" "${file}" 2>/dev/null | cut -d':' -f2- | sed 's/^ *//;s/"//g' | xargs
}

# Measure execution time in milliseconds
measure_time() {
    local cmd="$1"
    local start_time end_time elapsed

    start_time=$(date +%s%N)
    eval "${cmd}" > /dev/null 2>&1
    local status=$?
    end_time=$(date +%s%N)

    elapsed=$(( (end_time - start_time) / 1000000 ))
    echo "${elapsed}"
    return $status
}

# Wait for condition with timeout
wait_for() {
    local condition="$1"
    local timeout="${2:-10}"
    local interval="${3:-1}"
    local elapsed=0

    while ! eval "${condition}" > /dev/null 2>&1; do
        sleep "${interval}"
        elapsed=$((elapsed + interval))
        if (( elapsed >= timeout )); then
            return 1
        fi
    done
    return 0
}

# Generate random string
random_string() {
    local length="${1:-8}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "${length}"
}

# Log message (visible in BATS output with --tap)
log() {
    echo "# $*" >&3
}

# ============================================================================
# BATS LIFECYCLE HOOKS
# ============================================================================

# Called before each test
setup() {
    setup_test_environment
}

# Called after each test
teardown() {
    teardown_test_environment
}
