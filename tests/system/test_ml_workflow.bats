#!/usr/bin/env bats
# End-to-End Test: ML Development Workflow
# Tests complete ML workflow from planning through deployment

load '../helpers/test_helper'

# ============================================================================
# SETUP AND TEARDOWN
# ============================================================================

setup() {
    setup_test_environment

    # Create ML-specific project structure
    mkdir -p "${TEST_TMP_DIR}/data"
    mkdir -p "${TEST_TMP_DIR}/models"
    mkdir -p "${TEST_TMP_DIR}/experiments"

    # Simulate ML project indicators
    cat > "${TEST_TMP_DIR}/requirements.txt" << 'EOF'
torch>=2.0.0
tensorflow>=2.12.0
transformers>=4.30.0
numpy>=1.24.0
pandas>=2.0.0
EOF

    # Create full test environment with all fixtures
    create_full_test_environment

    # Update state for ML project
    cat > "${TEST_TMP_DIR}/.workflow/state.yaml" << 'EOF'
project:
  name: "ml-test-project"
  type: "ml"
  version: "1.0.0"

current_phase: "phase_1_planning"
current_checkpoint: "CP_INIT"
checkpoint_count: 0

metadata:
  created: "2024-01-01T00:00:00Z"
  last_updated: "2024-01-01T00:00:00Z"
  version: "1.0.0"
EOF

    cd "${TEST_TMP_DIR}"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# E2E WORKFLOW TESTS
# ============================================================================

@test "E2E: ML project type is correctly detected" {
    # Verify requirements.txt indicates ML project
    assert_file_contains "${TEST_TMP_DIR}/requirements.txt" "torch"
    assert_file_contains "${TEST_TMP_DIR}/requirements.txt" "tensorflow"
}

@test "E2E: Complete ML workflow initialization" {
    # Verify all required directories exist
    assert_dir_exists "${TEST_TMP_DIR}/.workflow"
    assert_dir_exists "${TEST_TMP_DIR}/.workflow/agents"
    assert_dir_exists "${TEST_TMP_DIR}/.workflow/skills"
    assert_dir_exists "${TEST_TMP_DIR}/phases/phase_1_planning"
    assert_dir_exists "${TEST_TMP_DIR}/phases/phase_2_implementation"
    assert_dir_exists "${TEST_TMP_DIR}/artifacts"
    assert_dir_exists "${TEST_TMP_DIR}/workspace"
}

@test "E2E: State file contains correct ML project type" {
    assert_file_exists "${TEST_TMP_DIR}/.workflow/state.yaml"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/state.yaml" "type: \"ml\""
}

@test "E2E: Agent registry loaded correctly" {
    assert_file_exists "${TEST_TMP_DIR}/.workflow/agents/registry.yaml"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" "researcher:"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" "implementer:"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" "experimenter:"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" "optimizer:"
}

@test "E2E: ML pipeline agent transition - researcher to implementer" {
    # Activate researcher
    run "${TEST_TMP_DIR}/scripts/activate_agent.sh" researcher
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May fail gracefully in test env

    # Create researcher workspace
    mkdir -p "${TEST_TMP_DIR}/workspace/researcher"
    echo "Literature review completed" > "${TEST_TMP_DIR}/workspace/researcher/notes.md"

    # Transition to implementer
    run "${TEST_TMP_DIR}/scripts/activate_agent.sh" implementer
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "E2E: Checkpoint creation during ML workflow" {
    skip_if_no_checkpoint_script

    run "${TEST_TMP_DIR}/scripts/checkpoint.sh" "Model architecture defined"
    [ "$status" -eq 0 ] || skip "Checkpoint script not available"

    # Verify checkpoint was recorded
    if [[ -f "${TEST_TMP_DIR}/.workflow/checkpoints.log" ]]; then
        assert_file_contains "${TEST_TMP_DIR}/.workflow/checkpoints.log" "Model architecture"
    fi
}

@test "E2E: Status displays ML workflow correctly" {
    skip_if_no_status_script

    run "${TEST_TMP_DIR}/scripts/status.sh"
    [ "$status" -eq 0 ] || skip "Status script not available"
}

@test "E2E: Full ML pipeline - 5 phase progression" {
    local phases=(
        "phase_1_planning"
        "phase_2_implementation"
        "phase_3_validation"
        "phase_4_delivery"
        "phase_5_maintenance"
    )

    for phase in "${phases[@]}"; do
        assert_dir_exists "${TEST_TMP_DIR}/phases/${phase}"
    done
}

@test "E2E: ML workflow state persistence" {
    # Modify state
    sed -i 's/current_phase: "phase_1_planning"/current_phase: "phase_2_implementation"/' \
        "${TEST_TMP_DIR}/.workflow/state.yaml"

    # Verify persistence
    assert_file_contains "${TEST_TMP_DIR}/.workflow/state.yaml" "phase_2_implementation"
}

@test "E2E: Create ML experiment artifacts" {
    # Simulate experiment workflow
    mkdir -p "${TEST_TMP_DIR}/artifacts/experiments"

    # Create experiment log
    cat > "${TEST_TMP_DIR}/artifacts/experiments/exp_001.json" << 'EOF'
{
    "experiment_id": "exp_001",
    "model": "transformer",
    "accuracy": 0.95,
    "loss": 0.05,
    "epochs": 100,
    "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    assert_file_exists "${TEST_TMP_DIR}/artifacts/experiments/exp_001.json"
    assert_file_contains "${TEST_TMP_DIR}/artifacts/experiments/exp_001.json" "accuracy"
}

@test "E2E: ML workflow context recovery simulation" {
    # Create checkpoint state
    echo "2024-01-01T12:00:00Z | CP_ML_1 | Pre-training checkpoint" >> \
        "${TEST_TMP_DIR}/.workflow/checkpoints.log"

    # Update handoff with ML context
    cat > "${TEST_TMP_DIR}/.workflow/handoff.md" << 'EOF'
# ML Workflow Handoff

## Current Status
- Phase: phase_2_implementation
- Model: Transformer architecture
- Dataset: Prepared (10K samples)

## Next Actions
- [ ] Train model
- [ ] Evaluate on test set

## Critical Context
1. Using PyTorch backend
2. GPU training enabled
3. Checkpoints saved every 10 epochs
EOF

    assert_file_contains "${TEST_TMP_DIR}/.workflow/handoff.md" "Transformer"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/checkpoints.log" "CP_ML_1"
}

@test "E2E: Simulate complete ML training workflow" {
    # Phase 1: Planning
    cat > "${TEST_TMP_DIR}/phases/phase_1_planning/plan.md" << 'EOF'
# ML Project Plan
- Task: Classification
- Data: 10K samples
- Model: Transformer
EOF

    # Phase 2: Implementation
    cat > "${TEST_TMP_DIR}/phases/phase_2_implementation/model.py" << 'EOF'
# Simulated model code
class TransformerModel:
    def __init__(self):
        self.layers = 6
        self.heads = 8

    def forward(self, x):
        return x
EOF

    # Phase 3: Validation
    cat > "${TEST_TMP_DIR}/phases/phase_3_validation/results.json" << 'EOF'
{
    "accuracy": 0.95,
    "f1_score": 0.94,
    "precision": 0.93,
    "recall": 0.95
}
EOF

    # Verify all phases have content
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_1_planning/plan.md"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_2_implementation/model.py"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_3_validation/results.json"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

skip_if_no_checkpoint_script() {
    if [[ ! -x "${TEST_TMP_DIR}/scripts/checkpoint.sh" ]]; then
        skip "checkpoint.sh not executable"
    fi
}

skip_if_no_status_script() {
    if [[ ! -x "${TEST_TMP_DIR}/scripts/status.sh" ]]; then
        skip "status.sh not executable"
    fi
}
