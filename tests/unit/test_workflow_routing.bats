#!/usr/bin/env bats
# Unit tests for the Milestone 1 phase-sync + goal-driven helpers in
# scripts/lib/workflow_routing.sh (uws_phase_for_methodology, get/set_phase_status,
# set_uws_phase, the deliverable ledger, gate_enabled).

load '../helpers/test_helper'

setup() {
    setup_test_environment
    cd "${TEST_TMP_DIR}"

    mkdir -p .workflow
    cat > .workflow/state.yaml << 'EOF'
project_type: "llm"
goal: ""
current_phase: "phase_1_planning"
sdlc_phase: "requirements"

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
EOF
    export STATE_FILE="${TEST_TMP_DIR}/.workflow/state.yaml"
    export WORKFLOW_DIR="${TEST_TMP_DIR}/.workflow"

    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"
    source "${SCRIPTS_DIR}/lib/workflow_routing.sh"
}

teardown() { teardown_test_environment; }

# --- uws_phase_for_methodology: the 6->5 and 7->5 collapse ---

@test "sdlc requirements and design both map to phase_1_planning" {
    [ "$(uws_phase_for_methodology sdlc requirements)" = "phase_1_planning" ]
    [ "$(uws_phase_for_methodology sdlc design)" = "phase_1_planning" ]
}

@test "sdlc implementation/verification/deployment/maintenance map correctly" {
    [ "$(uws_phase_for_methodology sdlc implementation)" = "phase_2_implementation" ]
    [ "$(uws_phase_for_methodology sdlc verification)" = "phase_3_validation" ]
    [ "$(uws_phase_for_methodology sdlc deployment)" = "phase_4_delivery" ]
    [ "$(uws_phase_for_methodology sdlc maintenance)" = "phase_5_maintenance" ]
}

@test "research phases collapse into the 5 UWS phases" {
    [ "$(uws_phase_for_methodology research hypothesis)" = "phase_1_planning" ]
    [ "$(uws_phase_for_methodology research literature_review)" = "phase_1_planning" ]
    [ "$(uws_phase_for_methodology research experiment_design)" = "phase_1_planning" ]
    [ "$(uws_phase_for_methodology research data_collection)" = "phase_2_implementation" ]
    [ "$(uws_phase_for_methodology research analysis)" = "phase_3_validation" ]
    [ "$(uws_phase_for_methodology research peer_review)" = "phase_4_delivery" ]
    [ "$(uws_phase_for_methodology research publication)" = "phase_5_maintenance" ]
}

# --- get/set phase status round-trip (honors the indentation contract) ---

@test "get_phase_status reads the initial board" {
    [ "$(get_phase_status phase_1_planning "$STATE_FILE")" = "active" ]
    [ "$(get_phase_status phase_3_validation "$STATE_FILE")" = "pending" ]
}

@test "set_phase_status round-trips a single phase without touching others" {
    set_phase_status phase_3_validation completed "$STATE_FILE"
    [ "$(get_phase_status phase_3_validation "$STATE_FILE")" = "completed" ]
    [ "$(get_phase_status phase_2_implementation "$STATE_FILE")" = "pending" ]
    [ "$(get_phase_status phase_4_delivery "$STATE_FILE")" = "pending" ]
}

@test "set_uws_phase advances current_phase and marks earlier phases completed" {
    set_uws_phase phase_3_validation "$STATE_FILE"
    grep -q 'current_phase: "phase_3_validation"' "$STATE_FILE"
    [ "$(get_phase_status phase_1_planning "$STATE_FILE")" = "completed" ]
    [ "$(get_phase_status phase_2_implementation "$STATE_FILE")" = "completed" ]
    [ "$(get_phase_status phase_3_validation "$STATE_FILE")" = "active" ]
    [ "$(get_phase_status phase_4_delivery "$STATE_FILE")" = "pending" ]
}

# --- deliverable ledger ---

@test "mp_ensure seeds an entry and deliverables_remaining reflects total" {
    mp_ensure sdlc requirements 3 "$STATE_FILE"
    grep -q '^  sdlc_requirements: {total: 3, done: \[\]}' "$STATE_FILE"
    [ "$(deliverables_remaining sdlc requirements "$STATE_FILE")" = "3" ]
}

@test "mark_deliverable is idempotent and decrements remaining" {
    mp_ensure sdlc requirements 3 "$STATE_FILE"
    mark_deliverable sdlc requirements 1 "$STATE_FILE"
    mark_deliverable sdlc requirements 3 "$STATE_FILE"
    mark_deliverable sdlc requirements 3 "$STATE_FILE"   # idempotent
    [ "$(deliverables_remaining sdlc requirements "$STATE_FILE")" = "1" ]
}

@test "ledger edits do not corrupt the phases board" {
    mp_ensure sdlc requirements 3 "$STATE_FILE"
    mark_deliverable sdlc requirements 2 "$STATE_FILE"
    [ "$(get_phase_status phase_1_planning "$STATE_FILE")" = "active" ]
    [ "$(get_phase_status phase_5_maintenance "$STATE_FILE")" = "pending" ]
}

# --- gate_enabled: goal-driven activation ---

@test "gate_enabled is false with empty goal, true once a goal is declared" {
    run gate_enabled "$STATE_FILE"
    [ "$status" -ne 0 ]
    yaml_set "$STATE_FILE" goal "ship the thing"
    run gate_enabled "$STATE_FILE"
    [ "$status" -eq 0 ]
}
