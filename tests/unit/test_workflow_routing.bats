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
    grep -Eq 'current_phase: "?phase_3_validation"?$' "$STATE_FILE"
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

# --- record_active_agent / get_active_agent (replaces activate_agent.sh) ---

@test "record_active_agent writes the active_agent block and get_active_agent reads it" {
    record_active_agent architect "$STATE_FILE"
    grep -q '^active_agent:$' "$STATE_FILE"
    grep -q '^  name: "architect"$' "$STATE_FILE"
    grep -q '^  status: "active"$' "$STATE_FILE"
    grep -Eq '^  activated_at: "[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$STATE_FILE"
    [ "$(get_active_agent "$STATE_FILE")" = "architect" ]
}

@test "record_active_agent replaces an existing block (legacy extra keys) without touching other keys" {
    cat >> "$STATE_FILE" << 'YAML'
active_agent:
  name: "researcher"
  status: "active"
  tool_origin: "gemini"

metadata:
  created: "2026-01-01T00:00:00"
YAML
    record_active_agent implementer "$STATE_FILE"
    [ "$(grep -c '^active_agent:' "$STATE_FILE")" -eq 1 ]
    run grep -c 'tool_origin' "$STATE_FILE"
    [ "$output" = "0" ]
    grep -q '^  created: "2026-01-01T00:00:00"$' "$STATE_FILE"
    [ "$(get_phase_status phase_1_planning "$STATE_FILE")" = "active" ]
    [ "$(get_active_agent "$STATE_FILE")" = "implementer" ]
}

@test "record_active_agent replaces a flat active_agent scalar" {
    printf 'active_agent: "architect"\nsdlc_note: "kept"\n' >> "$STATE_FILE"
    record_active_agent deployer "$STATE_FILE"
    [ "$(grep -c '^active_agent' "$STATE_FILE")" -eq 1 ]
    grep -q '^sdlc_note: "kept"$' "$STATE_FILE"
    [ "$(get_active_agent "$STATE_FILE")" = "deployer" ]
}

@test "record_active_agent logs AGENT_DISPATCHED, which recovery does not list as a checkpoint" {
    printf '2026-01-01T00:00:00Z | CP_1_001 | Real work\n' > "${WORKFLOW_DIR}/checkpoints.log"
    record_active_agent researcher "$STATE_FILE"
    record_active_agent architect "$STATE_FILE"
    [ "$(grep -c '| AGENT_DISPATCHED | ' "${WORKFLOW_DIR}/checkpoints.log")" -eq 2 ]
    tail -1 "${WORKFLOW_DIR}/checkpoints.log" | grep -q '| AGENT_DISPATCHED | architect$'
    source "${SCRIPTS_DIR}/lib/hook_context.sh"
    run uws_real_checkpoints "${WORKFLOW_DIR}/checkpoints.log" 5
    [ "$output" = "2026-01-01T00:00:00Z | CP_1_001 | Real work" ]
}

@test "record_active_agent rejects an invalid name and leaves state untouched" {
    cp "$STATE_FILE" "${TEST_TMP_DIR}/before.yaml"
    run record_active_agent 'bad name"; echo pwned' "$STATE_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid agent name"* ]]
    run record_active_agent "" "$STATE_FILE"
    [ "$status" -ne 0 ]
    cmp "$STATE_FILE" "${TEST_TMP_DIR}/before.yaml"
}

@test "record_active_agent fails cleanly when the state file is missing" {
    run record_active_agent researcher "${TEST_TMP_DIR}/nope/state.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"state file not found"* ]]
    [ ! -e "${TEST_TMP_DIR}/nope" ]
}

@test "get_active_agent accepts unquoted (yq-written) names and is empty without a block" {
    [ -z "$(get_active_agent "$STATE_FILE")" ]
    printf 'active_agent:\n  name: optimizer\n  status: active\n' >> "$STATE_FILE"
    [ "$(get_active_agent "$STATE_FILE")" = "optimizer" ]
    printf 'active_agent:\n  name: null\n' > "${TEST_TMP_DIR}/null.yaml"
    [ -z "$(get_active_agent "${TEST_TMP_DIR}/null.yaml")" ]
}
