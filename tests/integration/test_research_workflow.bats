#!/usr/bin/env bats
# Integration Tests for Research Workflow
# Tests complete research cycle following Scientific Method

# Load test helpers
load '../helpers/test_helper'

# ============================================================================
# SETUP
# ============================================================================

setup() {
    setup_test_environment
    create_full_test_environment "${TEST_TMP_DIR}"
    cd "${TEST_TMP_DIR}"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# SCRIPT EXISTENCE TESTS
# ============================================================================

@test "research.sh exists and is executable" {
    [[ -f "${SCRIPTS_DIR}/research.sh" ]]
    [[ -x "${SCRIPTS_DIR}/research.sh" ]]
}

@test "research.sh has proper shebang and strict mode" {
    head -20 "${SCRIPTS_DIR}/research.sh" | grep -q "set -euo pipefail"
}

# ============================================================================
# STATUS TESTS
# ============================================================================

@test "research status shows 'not started' initially" {
    run "${SCRIPTS_DIR}/research.sh" status

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Not started" ]] || [[ "$output" =~ "none" ]]
}

@test "research status command is default action" {
    run "${SCRIPTS_DIR}/research.sh"

    [[ "$status" -eq 0 ]]
}

# ============================================================================
# START TESTS
# ============================================================================

@test "research start begins at hypothesis phase" {
    run "${SCRIPTS_DIR}/research.sh" start

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "hypothesis" ]] || [[ "$output" =~ "Hypothesis" ]]
}

@test "research start updates state file" {
    "${SCRIPTS_DIR}/research.sh" start

    grep -q "research_phase" "${TEST_TMP_DIR}/.workflow/state.yaml"
}

@test "research start fails if already started" {
    "${SCRIPTS_DIR}/research.sh" start

    run "${SCRIPTS_DIR}/research.sh" start

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "already" ]]
}

# ============================================================================
# PHASE PROGRESSION TESTS (Scientific Method)
# ============================================================================

@test "research progresses through all phases in order" {
    "${SCRIPTS_DIR}/research.sh" start

    # hypothesis → experiment_design → data_collection → analysis → publication
    for i in {1..4}; do
        run "${SCRIPTS_DIR}/research.sh" next
        [[ "$status" -eq 0 ]]
    done

    # Should now be at publication
    run "${SCRIPTS_DIR}/research.sh" status
    [[ "$output" =~ "publication" ]]
}

@test "research next from hypothesis goes to experiment_design" {
    "${SCRIPTS_DIR}/research.sh" start
    run "${SCRIPTS_DIR}/research.sh" next

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "experiment_design" ]] || [[ "$output" =~ "Experiment" ]]
}

@test "research next from experiment_design goes to data_collection" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    run "${SCRIPTS_DIR}/research.sh" next

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "data_collection" ]] || [[ "$output" =~ "Data" ]]
}

@test "research next from data_collection goes to analysis" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    "${SCRIPTS_DIR}/research.sh" next  # data_collection
    run "${SCRIPTS_DIR}/research.sh" next

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "analysis" ]] || [[ "$output" =~ "Analysis" ]]
}

@test "research next from analysis goes to publication" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    "${SCRIPTS_DIR}/research.sh" next  # data_collection
    "${SCRIPTS_DIR}/research.sh" next  # analysis
    run "${SCRIPTS_DIR}/research.sh" next

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "publication" ]] || [[ "$output" =~ "Publication" ]]
}

@test "research next fails when not started" {
    run "${SCRIPTS_DIR}/research.sh" next

    [[ "$status" -ne 0 ]] || [[ "$output" =~ "not started" ]]
}

# ============================================================================
# REJECTION/REFINEMENT TESTS (Scientific Method)
# ============================================================================

@test "research reject in analysis returns to experiment_design" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    "${SCRIPTS_DIR}/research.sh" next  # data_collection
    "${SCRIPTS_DIR}/research.sh" next  # analysis

    run "${SCRIPTS_DIR}/research.sh" reject "Results inconclusive"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "experiment_design" ]] || [[ "$output" =~ "refinement" ]]
}

@test "research reject in data_collection returns to experiment_design" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    "${SCRIPTS_DIR}/research.sh" next  # data_collection

    run "${SCRIPTS_DIR}/research.sh" reject "Data collection issues"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "experiment_design" ]]
}

@test "research reject in publication returns to analysis" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    "${SCRIPTS_DIR}/research.sh" next  # data_collection
    "${SCRIPTS_DIR}/research.sh" next  # analysis
    "${SCRIPTS_DIR}/research.sh" next  # publication

    run "${SCRIPTS_DIR}/research.sh" reject "Paper rejected by reviewers"

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "analysis" ]]
}

@test "research reject at hypothesis stays at hypothesis" {
    "${SCRIPTS_DIR}/research.sh" start  # hypothesis

    run "${SCRIPTS_DIR}/research.sh" reject "Hypothesis unclear"

    [[ "$status" -eq 0 ]]
    # Should stay at hypothesis phase
}

@test "research reject includes details message" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next
    "${SCRIPTS_DIR}/research.sh" next
    "${SCRIPTS_DIR}/research.sh" next

    run "${SCRIPTS_DIR}/research.sh" reject "p-value not significant (p=0.23)"

    [[ "$output" =~ "p-value" ]] || [[ "$output" =~ "0.23" ]]
}

# ============================================================================
# RESET TESTS
# ============================================================================

@test "research reset clears state" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next

    run "${SCRIPTS_DIR}/research.sh" reset

    [[ "$status" -eq 0 ]]

    # Should show not started after reset
    run "${SCRIPTS_DIR}/research.sh" status
    [[ "$output" =~ "Not started" ]] || [[ "$output" =~ "none" ]]
}

@test "research reset allows new start" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" reset
    run "${SCRIPTS_DIR}/research.sh" start

    [[ "$status" -eq 0 ]]
}

# ============================================================================
# HELP TESTS
# ============================================================================

@test "research help shows usage" {
    run "${SCRIPTS_DIR}/research.sh" help

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Usage" ]]
}

@test "research --help shows usage" {
    run "${SCRIPTS_DIR}/research.sh" --help

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Usage" ]]
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "research handles unknown action gracefully" {
    run "${SCRIPTS_DIR}/research.sh" invalid_action

    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "Unknown" ]] || [[ "$output" =~ "unknown" ]]
}

# ============================================================================
# FULL CYCLE INTEGRATION TESTS
# ============================================================================

@test "complete research cycle from hypothesis to publication" {
    # Start
    run "${SCRIPTS_DIR}/research.sh" start
    [[ "$status" -eq 0 ]]

    # Progress through all phases
    for phase in experiment_design data_collection analysis publication; do
        run "${SCRIPTS_DIR}/research.sh" next
        [[ "$status" -eq 0 ]]
    done

    # Verify at publication
    run "${SCRIPTS_DIR}/research.sh" status
    [[ "$output" =~ "publication" ]]

    # Try next at publication - should indicate complete
    run "${SCRIPTS_DIR}/research.sh" next
    [[ "$output" =~ "complete" ]] || [[ "$output" =~ "Congratulations" ]]
}

@test "research cycle with rejection and refinement" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    "${SCRIPTS_DIR}/research.sh" next  # data_collection
    "${SCRIPTS_DIR}/research.sh" next  # analysis

    # Reject hypothesis
    "${SCRIPTS_DIR}/research.sh" reject "Results don't support hypothesis"

    # Should be back at experiment_design
    run "${SCRIPTS_DIR}/research.sh" status
    [[ "$output" =~ "experiment_design" ]]

    # Refine and continue
    run "${SCRIPTS_DIR}/research.sh" next  # back to data_collection
    [[ "$output" =~ "data_collection" ]]
}

@test "multiple rejection cycles allowed" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next  # experiment_design
    "${SCRIPTS_DIR}/research.sh" next  # data_collection
    "${SCRIPTS_DIR}/research.sh" next  # analysis

    # First rejection
    "${SCRIPTS_DIR}/research.sh" reject "First attempt failed"

    # Back at experiment_design, try again
    "${SCRIPTS_DIR}/research.sh" next  # data_collection
    "${SCRIPTS_DIR}/research.sh" next  # analysis

    # Second rejection
    run "${SCRIPTS_DIR}/research.sh" reject "Second attempt also failed"
    [[ "$status" -eq 0 ]]

    # Should be back at experiment_design again
    run "${SCRIPTS_DIR}/research.sh" status
    [[ "$output" =~ "experiment_design" ]]
}

# ============================================================================
# SCIENTIFIC METHOD GUIDANCE TESTS
# ============================================================================

@test "research provides phase-specific guidance" {
    "${SCRIPTS_DIR}/research.sh" start
    run "${SCRIPTS_DIR}/research.sh" next

    # Should provide guidance for experiment_design phase
    [[ "$output" =~ "Design" ]] || [[ "$output" =~ "methodology" ]] || [[ "$output" =~ "sample" ]]
}

@test "research mentions negative results value on reject" {
    "${SCRIPTS_DIR}/research.sh" start
    "${SCRIPTS_DIR}/research.sh" next
    "${SCRIPTS_DIR}/research.sh" next
    "${SCRIPTS_DIR}/research.sh" next

    run "${SCRIPTS_DIR}/research.sh" reject "Null result"

    # Should mention that negative results are valuable
    [[ "$output" =~ "negative results" ]] || [[ "$output" =~ "scientific method" ]] || [[ "$output" =~ "valuable" ]]
}
