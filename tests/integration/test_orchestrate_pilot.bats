#!/usr/bin/env bats
# Integration tests for scripts/orchestrate.sh — the controller that binds the
# UWS spine to real subagent dispatch and the submit->review gate.

load '../helpers/test_helper'

setup() {
    setup_test_environment
    create_full_test_environment
    cd "${TEST_TMP_DIR}"

    cat > .workflow/state.yaml << 'EOF'
project_type: "llm"
goal: ""
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"

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
  created: "2026-07-28T00:00:00"
EOF
    [ -f .workflow/checkpoints.log ] || printf '# log\n' > .workflow/checkpoints.log

    "${SCRIPTS_DIR}/sdlc.sh" start >/dev/null 2>&1
    "${SCRIPTS_DIR}/sdlc.sh" goal "lightweight Linux face-unlock: welcome back Yash; others blocked" >/dev/null 2>&1
}

teardown() { teardown_test_environment; }

@test "orchestrate status resolves the researcher for the requirements phase" {
    run "${SCRIPTS_DIR}/orchestrate.sh" status
    assert_success
    echo "$output" | grep -q "researcher"
    echo "$output" | grep -q "requirements"
}

@test "orchestrate dispatch writes a TASK.md brief and prints a DISPATCH line" {
    run "${SCRIPTS_DIR}/orchestrate.sh" dispatch "Build a face-unlock system" "docs/pilot/requirements.md"
    assert_success
    echo "$output" | grep -q "DISPATCH: agent=researcher"
    echo "$output" | grep -q "subagent=.claude/agents/uws-researcher.md"
    [ -f workspace/researcher/TASK.md ]
    grep -q "Deliverables" workspace/researcher/TASK.md
}

@test "the uws-researcher subagent definition exists and embeds the persona" {
    [ -f "${PROJECT_ROOT}/.claude/agents/uws-researcher.md" ]
    grep -q "^name: uws-researcher" "${PROJECT_ROOT}/.claude/agents/uws-researcher.md"
    grep -q "Output Contract" "${PROJECT_ROOT}/.claude/agents/uws-researcher.md"
}

@test "orchestrate collect stages a change request once an artifact exists" {
    "${SCRIPTS_DIR}/orchestrate.sh" dispatch "Build a face-unlock system" "docs/pilot/requirements.md" >/dev/null 2>&1
    mkdir -p workspace/researcher/docs/pilot
    printf '# Requirements\n\nREQ-1: ...\n' > workspace/researcher/docs/pilot/requirements.md
    run "${SCRIPTS_DIR}/orchestrate.sh" collect "researcher: requirements draft"
    assert_success
    run bash -c 'ls .uws/crs/ 2>/dev/null | wc -l'
    [ "$output" -ge 1 ]
    # regression: the transient TASK.md brief must NOT be staged into the CR
    run bash -c 'cat .uws/crs/CR-*/patch.diff 2>/dev/null | grep -c "TASK.md" || true'
    [ "$output" -eq 0 ]
    [ ! -f workspace/researcher/TASK.md ]
}

@test "the deliverable gate blocks advancement in the pilot until checks" {
    run "${SCRIPTS_DIR}/sdlc.sh" next
    assert_failure
    grep -q 'sdlc_phase: "requirements"' .workflow/state.yaml
}
