#!/usr/bin/env bats
# Integration tests for Milestone 1: goal-driven phases, the hard deliverable
# gate, current_phase syncing, and checkpoint-ID advancement. These drive the
# REAL sdlc.sh + checkpoint.sh pipeline (the test class that was missing).

load '../helpers/test_helper'

setup() {
    setup_test_environment
    create_full_test_environment
    cd "${TEST_TMP_DIR}"

    # Goal-driven schema, with NO sdlc_phase yet so `sdlc start` works.
    cat > .workflow/state.yaml << 'EOF'
project_type: "llm"
goal: ""
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
last_updated: "2026-07-28T00:00:00"

phases:
  phase_1_planning:
    status: "active"
  phase_2_implementation:
    status: "pending"
  phase_3_validation:
    status: "pending"
  phase_4_delivery:
    status: "pending"
  phase_5_maintenance:
    status: "pending"

methodology_progress:

metadata:
  version: "1.1.0"
  created: "2026-07-28T00:00:00"
EOF
    [ -f .workflow/checkpoints.log ] || printf '# Checkpoint Log\n' > .workflow/checkpoints.log
}

teardown() { teardown_test_environment; }

@test "sdlc start sets current_phase and seeds the ledger" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    grep -q 'current_phase: "phase_1_planning"' .workflow/state.yaml
    grep -q '^sdlc_phase:' .workflow/state.yaml
    grep -q '^  sdlc_requirements:' .workflow/state.yaml
}

@test "next advances freely when NO goal is declared" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    run "${SCRIPTS_DIR}/sdlc.sh" next
    assert_success
    grep -q 'sdlc_phase: "design"' .workflow/state.yaml
}

@test "next is BLOCKED once a goal is declared with unmet deliverables" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" goal "make phases meaningful"
    run "${SCRIPTS_DIR}/sdlc.sh" next
    assert_failure
    # still at requirements
    grep -q 'sdlc_phase: "requirements"' .workflow/state.yaml
}

@test "check all deliverables then next advances; --force overrides" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" goal "make phases meaningful"
    "${SCRIPTS_DIR}/sdlc.sh" check 1
    "${SCRIPTS_DIR}/sdlc.sh" check 2
    "${SCRIPTS_DIR}/sdlc.sh" check 3
    run "${SCRIPTS_DIR}/sdlc.sh" next
    assert_success
    grep -q 'sdlc_phase: "design"' .workflow/state.yaml
    # at design (unmet), --force skips the gate
    run "${SCRIPTS_DIR}/sdlc.sh" next --force
    assert_success
    grep -q 'sdlc_phase: "implementation"' .workflow/state.yaml
}

@test "current_phase stays phase_1_planning across requirements->design" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" next   # design (no goal => free)
    grep -q 'current_phase: "phase_1_planning"' .workflow/state.yaml
    grep -q 'sdlc_phase: "design"' .workflow/state.yaml
}

@test "current_phase advances to phase_2 on design->implementation" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" goto implementation
    grep -q 'current_phase: "phase_2_implementation"' .workflow/state.yaml
}

@test "checkpoint ID reflects the current phase (CP_2_* after advancing) — regression" {
    "${SCRIPTS_DIR}/sdlc.sh" start
    "${SCRIPTS_DIR}/sdlc.sh" goto implementation   # current_phase -> phase_2
    run "${SCRIPTS_DIR}/checkpoint.sh" create "at implementation"
    assert_success
    grep -q "CP_2_" .workflow/checkpoints.log
}
