#!/usr/bin/env bats
# Unit tests for scripts/migrate_state.sh — bringing a legacy/desynced
# state.yaml up to the goal-driven schema, idempotently and backup-first.

load '../helpers/test_helper'

setup() {
    setup_test_environment
    create_full_test_environment
    cd "${TEST_TMP_DIR}"

    # Reproduce the historical inconsistency: sdlc_phase advanced to maintenance
    # while current_phase was left stuck at phase_1_planning, no goal/phases block.
    cat > .workflow/state.yaml << 'EOF'
project_type: "llm"
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_021"
last_updated: "2026-02-23T15:08:43-05:00"

context_bridge:
  critical_info: []
  next_actions:
    - "Review project requirements"
  dependencies: []

metadata:
  version: "1.1.0"
  created: "2026-02-23T13:20:06-05:00"
sdlc_phase: "maintenance"
EOF
}

teardown() { teardown_test_environment; }

@test "migration adds goal, phases block, and methodology_progress" {
    run "${SCRIPTS_DIR}/migrate_state.sh"
    assert_success
    grep -q '^goal:' .workflow/state.yaml
    grep -q '^phases:' .workflow/state.yaml
    grep -q '^methodology_progress:' .workflow/state.yaml
}

@test "migration reconciles current_phase to match sdlc_phase (maintenance)" {
    "${SCRIPTS_DIR}/migrate_state.sh"
    grep -q 'current_phase: "phase_5_maintenance"' .workflow/state.yaml
    # earlier phases marked completed, phase_5 active
    source "${SCRIPTS_DIR}/lib/yaml_utils.sh"
    source "${SCRIPTS_DIR}/lib/workflow_routing.sh"
    [ "$(get_phase_status phase_1_planning .workflow/state.yaml)" = "completed" ]
    [ "$(get_phase_status phase_5_maintenance .workflow/state.yaml)" = "active" ]
}

@test "migration is idempotent (single goal + single phases block after 2 runs)" {
    "${SCRIPTS_DIR}/migrate_state.sh"
    "${SCRIPTS_DIR}/migrate_state.sh"
    grep -q 'current_phase: "phase_5_maintenance"' .workflow/state.yaml
    [ "$(grep -c '^goal:' .workflow/state.yaml)" -eq 1 ]
    [ "$(grep -c '^phases:' .workflow/state.yaml)" -eq 1 ]
    [ "$(grep -c '^methodology_progress:' .workflow/state.yaml)" -eq 1 ]
}

@test "migration creates a timestamped backup" {
    "${SCRIPTS_DIR}/migrate_state.sh"
    run bash -c 'ls .workflow/state.yaml.bak-* 2>/dev/null | wc -l'
    [ "$output" -ge 1 ]
}

@test "migration --clean prunes non-catalog enabled skills" {
    printf '  - foo\n' >> .workflow/skills/enabled.yaml
    "${SCRIPTS_DIR}/migrate_state.sh" --clean
    ! grep -qE '^  - foo$' .workflow/skills/enabled.yaml
    # a real catalog skill is kept
    grep -qE '^  - (code_development|testing)$' .workflow/skills/enabled.yaml
}
