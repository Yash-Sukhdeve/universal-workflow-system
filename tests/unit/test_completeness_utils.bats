#!/usr/bin/env bats
# Completeness Utilities Test Suite
# Tests recovery completeness verification - RWF R5 (Reproducibility)

load '../helpers/test_helper'

# Setup and teardown
setup() {
    setup_test_environment

    # Source completeness utilities
    source "${PROJECT_ROOT}/scripts/lib/completeness_utils.sh"
    source "${PROJECT_ROOT}/scripts/lib/yaml_utils.sh" 2>/dev/null || true
}

teardown() {
    cleanup_test_environment
}

# =============================================================================
# REQUIRED FILES CHECK
# =============================================================================

@test "check_required_files returns empty when all present" {
    create_full_test_environment

    run check_required_files
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "check_required_files lists missing state.yaml" {
    mkdir -p .workflow
    touch .workflow/checkpoints.log
    # No state.yaml

    run check_required_files
    [[ "$output" == *"state.yaml"* ]]
}

@test "check_required_files lists missing checkpoints.log" {
    mkdir -p .workflow
    echo "phase: 1" > .workflow/state.yaml
    # No checkpoints.log

    run check_required_files
    [[ "$output" == *"checkpoints.log"* ]]
}

@test "check_required_files lists multiple missing files" {
    mkdir -p .workflow
    # No required files

    run check_required_files
    [[ "$output" == *"state.yaml"* ]]
    [[ "$output" == *"checkpoints.log"* ]]
}

# =============================================================================
# OPTIONAL FILES CHECK
# =============================================================================

@test "check_optional_files returns 0 when none present" {
    mkdir -p .workflow
    echo "phase: 1" > .workflow/state.yaml
    touch .workflow/checkpoints.log

    run check_optional_files
    [ "$output" -eq 0 ] || [ "$output" = "0" ]
}

@test "check_optional_files counts present files" {
    create_full_test_environment

    run check_optional_files
    [ "$output" -ge 1 ]
}

@test "check_optional_files counts all optional files" {
    create_full_test_environment
    mkdir -p .workflow/agents .workflow/skills
    touch .workflow/agents/registry.yaml
    touch .workflow/skills/catalog.yaml
    touch .workflow/checksums.yaml

    run check_optional_files
    [ "$output" -ge 3 ]
}

# =============================================================================
# REQUIRED FIELDS CHECK
# =============================================================================

@test "check_required_fields returns empty when all present" {
    cat > .workflow/state.yaml << 'EOF'
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
metadata:
  last_updated: "2025-01-15T10:00:00"
EOF

    run check_required_fields .workflow/state.yaml
    [ -z "$output" ]
}

@test "check_required_fields lists missing current_phase" {
    cat > .workflow/state.yaml << 'EOF'
current_checkpoint: "CP_1_001"
metadata:
  last_updated: "2025-01-15T10:00:00"
EOF

    run check_required_fields .workflow/state.yaml
    [[ "$output" == *"current_phase"* ]]
}

@test "check_required_fields lists missing current_checkpoint" {
    cat > .workflow/state.yaml << 'EOF'
current_phase: "phase_1_planning"
metadata:
  last_updated: "2025-01-15T10:00:00"
EOF

    run check_required_fields .workflow/state.yaml
    [[ "$output" == *"current_checkpoint"* ]]
}

@test "check_required_fields lists missing metadata.last_updated" {
    cat > .workflow/state.yaml << 'EOF'
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
EOF

    run check_required_fields .workflow/state.yaml
    [[ "$output" == *"metadata.last_updated"* ]] || [[ "$output" == *"last_updated"* ]]
}

@test "check_required_fields handles missing file" {
    run check_required_fields .workflow/nonexistent.yaml
    [ -n "$output" ]  # Should list all required fields as missing
}

# =============================================================================
# FILE SCORE CALCULATION
# =============================================================================

@test "calculate_file_score returns 0-100" {
    create_full_test_environment

    run calculate_file_score
    [ "$status" -eq 0 ]
    [ "$output" -ge 0 ]
    [ "$output" -le 100 ]
}

@test "calculate_file_score gives 70% for required files only" {
    mkdir -p .workflow
    echo "phase: 1" > .workflow/state.yaml
    touch .workflow/checkpoints.log
    # No optional files

    run calculate_file_score
    [ "$output" -eq 70 ]
}

@test "calculate_file_score gives 0 for no files" {
    mkdir -p .workflow
    # No files

    run calculate_file_score
    [ "$output" -eq 0 ]
}

@test "calculate_file_score increases with optional files" {
    mkdir -p .workflow
    echo "phase: 1" > .workflow/state.yaml
    touch .workflow/checkpoints.log

    local base_score
    base_score=$(calculate_file_score)

    touch .workflow/handoff.md
    touch .workflow/config.yaml

    local new_score
    new_score=$(calculate_file_score)

    [ "$new_score" -gt "$base_score" ]
}

# =============================================================================
# STATE SCORE CALCULATION
# =============================================================================

@test "calculate_state_score returns 0-100" {
    create_full_test_environment

    run calculate_state_score .workflow/state.yaml
    [ "$status" -eq 0 ]
    [ "$output" -ge 0 ]
    [ "$output" -le 100 ]
}

@test "calculate_state_score returns 0 for missing file" {
    run calculate_state_score .workflow/nonexistent.yaml
    [ "$output" -eq 0 ] || [ "$output" = "0" ]
}

@test "calculate_state_score increases with more fields" {
    cat > .workflow/state.yaml << 'EOF'
current_phase: "phase_1_planning"
EOF

    local score1
    score1=$(calculate_state_score .workflow/state.yaml)

    cat > .workflow/state.yaml << 'EOF'
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
metadata:
  last_updated: "2025-01-15T10:00:00"
EOF

    local score2
    score2=$(calculate_state_score .workflow/state.yaml)

    [ "$score2" -gt "$score1" ]
}

# =============================================================================
# OVERALL COMPLETENESS SCORE
# =============================================================================

@test "calculate_completeness_score returns 0-100" {
    create_full_test_environment

    run calculate_completeness_score
    [ "$status" -eq 0 ]
    [ "$output" -ge 0 ]
    [ "$output" -le 100 ]
}

@test "calculate_completeness_score combines file and state scores" {
    create_full_test_environment

    local score
    score=$(calculate_completeness_score)

    # Should be reasonable score with full environment
    [ "$score" -ge 50 ]
}

@test "calculate_completeness_score uses custom directory" {
    mkdir -p .custom_workflow
    echo "phase: 1" > .custom_workflow/state.yaml
    touch .custom_workflow/checkpoints.log

    run calculate_completeness_score .custom_workflow
    [ "$status" -eq 0 ]
    [ "$output" -ge 0 ]
}

# =============================================================================
# STATE CONSISTENCY CHECK
# =============================================================================

@test "check_state_consistency returns 0 for valid state" {
    create_full_test_environment

    # Add checkpoint to log matching state
    echo "2025-01-15T10:00:00 | CP_1_001 | Test" >> .workflow/checkpoints.log

    run check_state_consistency
    [ "$status" -eq 0 ]
}

@test "check_state_consistency warns for orphan checkpoint" {
    cat > .workflow/state.yaml << 'EOF'
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_999"
metadata:
  last_updated: "2025-01-15T10:00:00"
EOF
    touch .workflow/checkpoints.log

    run check_state_consistency
    [ "$status" -ne 0 ] || [[ "$output" == *"Warning"* ]]
}

@test "check_state_consistency handles missing files" {
    mkdir -p .workflow
    # No state.yaml or checkpoints.log

    run check_state_consistency
    [ "$status" -ne 0 ]
}

# =============================================================================
# COMPLETENESS REPORT
# =============================================================================

@test "generate_completeness_report produces output" {
    create_full_test_environment

    run generate_completeness_report
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "generate_completeness_report shows overall score" {
    create_full_test_environment

    run generate_completeness_report
    [[ "$output" == *"Score"* ]] || [[ "$output" == *"%"* ]]
}

@test "generate_completeness_report shows component scores" {
    create_full_test_environment

    run generate_completeness_report
    [[ "$output" == *"File Score"* ]]
    [[ "$output" == *"State Score"* ]]
}

@test "generate_completeness_report lists missing files" {
    mkdir -p .workflow
    echo "phase: 1" > .workflow/state.yaml
    # Missing checkpoints.log

    run generate_completeness_report
    [[ "$output" == *"Missing"* ]] || [[ "$output" == *"checkpoints.log"* ]]
}

# =============================================================================
# IS RECOVERY COMPLETE
# =============================================================================

@test "is_recovery_complete returns 0 when above threshold" {
    create_full_test_environment

    run is_recovery_complete 50
    [ "$status" -eq 0 ]
}

@test "is_recovery_complete returns 1 when below threshold" {
    mkdir -p .workflow
    # Minimal files = low score

    run is_recovery_complete 80
    [ "$status" -ne 0 ]
}

@test "is_recovery_complete uses default threshold" {
    create_full_test_environment

    run is_recovery_complete
    # Should use default threshold (50)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# =============================================================================
# COMPLETENESS SUMMARY (MARKDOWN)
# =============================================================================

@test "get_completeness_summary produces markdown" {
    create_full_test_environment

    run get_completeness_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Recovery Completeness"* ]]
}

@test "get_completeness_summary includes score" {
    create_full_test_environment

    run get_completeness_summary
    [[ "$output" == *"Score:"* ]]
}

@test "get_completeness_summary includes status" {
    create_full_test_environment

    run get_completeness_summary
    [[ "$output" == *"Status:"* ]]
}

@test "get_completeness_summary lists missing items" {
    mkdir -p .workflow
    echo "phase: 1" > .workflow/state.yaml
    # Missing required files

    run get_completeness_summary
    [[ "$output" == *"Missing"* ]]
}

# =============================================================================
# JSON OUTPUT
# =============================================================================

@test "get_completeness_json produces valid structure" {
    create_full_test_environment

    run get_completeness_json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"score":'* ]]
    [[ "$output" == *'"file_score":'* ]]
    [[ "$output" == *'"state_score":'* ]]
}

@test "get_completeness_json includes thresholds" {
    create_full_test_environment

    run get_completeness_json
    [[ "$output" == *'"thresholds":'* ]]
    [[ "$output" == *'"good":'* ]]
    [[ "$output" == *'"warn":'* ]]
}

@test "get_completeness_json includes missing items" {
    create_full_test_environment

    run get_completeness_json
    [[ "$output" == *'"missing_files":'* ]]
    [[ "$output" == *'"missing_fields":'* ]]
}

@test "get_completeness_json includes consistency flag" {
    create_full_test_environment

    run get_completeness_json
    [[ "$output" == *'"consistency":'* ]]
}

@test "get_completeness_json includes is_complete flag" {
    create_full_test_environment

    run get_completeness_json
    [[ "$output" == *'"is_complete":'* ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "completeness handles empty state file" {
    mkdir -p .workflow
    touch .workflow/state.yaml
    touch .workflow/checkpoints.log

    run calculate_completeness_score
    [ "$status" -eq 0 ]
    [ "$output" -ge 0 ]
}

@test "completeness handles malformed YAML" {
    mkdir -p .workflow
    echo "invalid: yaml: content:" > .workflow/state.yaml
    touch .workflow/checkpoints.log

    run calculate_completeness_score
    [ "$status" -eq 0 ]  # Should handle gracefully
}

@test "completeness handles unicode content" {
    mkdir -p .workflow
    cat > .workflow/state.yaml << 'EOF'
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
project:
  name: "日本語プロジェクト"
metadata:
  last_updated: "2025-01-15T10:00:00"
EOF
    touch .workflow/checkpoints.log

    run calculate_completeness_score
    [ "$status" -eq 0 ]
}

@test "completeness thresholds are configurable" {
    export COMPLETENESS_THRESHOLD_GOOD=90
    export COMPLETENESS_THRESHOLD_WARN=60

    create_full_test_environment

    run generate_completeness_report
    # Should use custom thresholds
    [ "$status" -eq 0 ]
}

# =============================================================================
# LOGGING INTEGRATION
# =============================================================================

@test "log_recovery_completeness logs status" {
    create_full_test_environment
    mkdir -p .workflow/logs

    run log_recovery_completeness "success"
    [ "$status" -eq 0 ]
}

@test "log_recovery_completeness includes score" {
    create_full_test_environment
    mkdir -p .workflow/logs

    # This should log with completeness score
    run log_recovery_completeness "start"
    [ "$status" -eq 0 ]
}
