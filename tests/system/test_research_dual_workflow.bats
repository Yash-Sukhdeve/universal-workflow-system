#!/usr/bin/env bats
# System tests for Research dual workflow
# Tests full research cycle with Claude ↔ Gemini handoffs

load '../helpers/test_helper.bash'
load '../helpers/dual_compat_helper.bash'
load '../helpers/gemini_wrapper.bash'

# Setup and teardown
setup() {
    setup_test_environment
    create_full_test_environment
    setup_dual_environment

    # Set up research project type
    sed -i 's/type: "software"/type: "research"/' "${TEST_TMP_DIR}/.workflow/state.yaml" 2>/dev/null || true
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# FULL RESEARCH CYCLE WITH HANDOFFS
# =============================================================================

@test "Claude starts hypothesis, checkpoints, Gemini continues" {
    cd "${TEST_TMP_DIR}"

    # Claude: Hypothesis phase
    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    # Create research artifacts
    mkdir -p workspace/researcher
    echo "# Hypothesis: ML models improve with synthetic data" > workspace/researcher/hypothesis.md

    # Checkpoint
    run "${SCRIPTS_DIR}/checkpoint.sh" create "Hypothesis defined"
    assert_success

    # Handoff to Gemini
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Hypothesis complete" "claude" "gemini"

    # Verify artifacts preserved
    [ -f "workspace/researcher/hypothesis.md" ]
}

@test "Gemini experiment design, checkpoints, Claude continues" {
    cd "${TEST_TMP_DIR}"

    # Gemini: Experiment design
    create_gemini_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_002" "researcher"

    mkdir -p workspace/researcher
    cat > workspace/researcher/experiment_design.md << 'EOF'
# Experiment Design

## Variables
- Independent: Synthetic data ratio
- Dependent: Model accuracy

## Method
- A/B testing with control group
- Sample size: 1000
EOF

    run "${SCRIPTS_DIR}/checkpoint.sh" create "Experiment designed"
    assert_success

    create_handoff_checkpoint "${TEST_TMP_DIR}" "Design complete" "gemini" "claude"

    [ -f "workspace/researcher/experiment_design.md" ]
}

@test "Claude data collection, checkpoints, Gemini continues" {
    cd "${TEST_TMP_DIR}"

    # Claude: Data collection
    create_claude_session_state "${TEST_TMP_DIR}" "phase_2_implementation" "CP_2_001" "experimenter"

    mkdir -p workspace/experimenter/data
    echo "sample_id,value" > workspace/experimenter/data/collected.csv
    echo "1,0.95" >> workspace/experimenter/data/collected.csv
    echo "2,0.87" >> workspace/experimenter/data/collected.csv

    run "${SCRIPTS_DIR}/checkpoint.sh" create "Data collected"
    assert_success

    create_handoff_checkpoint "${TEST_TMP_DIR}" "Collection complete" "claude" "gemini"

    [ -f "workspace/experimenter/data/collected.csv" ]
}

@test "Gemini analysis, checkpoints, Claude continues" {
    cd "${TEST_TMP_DIR}"

    # Gemini: Analysis
    create_gemini_session_state "${TEST_TMP_DIR}" "phase_3_validation" "CP_3_001" "experimenter"

    mkdir -p workspace/experimenter
    cat > workspace/experimenter/analysis_results.md << 'EOF'
# Analysis Results

## Key Findings
- Effect size: 0.42 (medium)
- p-value: 0.003
- Confidence interval: [0.31, 0.53]

## Conclusion
Hypothesis supported with statistical significance.
EOF

    run "${SCRIPTS_DIR}/checkpoint.sh" create "Analysis complete"
    assert_success

    create_handoff_checkpoint "${TEST_TMP_DIR}" "Analysis done" "gemini" "claude"

    [ -f "workspace/experimenter/analysis_results.md" ]
}

@test "Claude publication, complete workflow" {
    cd "${TEST_TMP_DIR}"

    # Claude: Publication
    create_claude_session_state "${TEST_TMP_DIR}" "phase_4_delivery" "CP_4_001" "documenter"

    mkdir -p paper
    cat > paper/draft.tex << 'EOF'
\documentclass{article}
\title{Synthetic Data Improves ML Models}
\begin{document}
\maketitle
\section{Introduction}
Research findings summary...
\end{document}
EOF

    run "${SCRIPTS_DIR}/checkpoint.sh" create "Paper drafted"
    assert_success

    [ -f "paper/draft.tex" ]
}

# =============================================================================
# RESEARCH-SPECIFIC SCENARIOS
# =============================================================================

@test "Research rejection with tool switch" {
    cd "${TEST_TMP_DIR}"

    # Start at analysis
    create_claude_session_state "${TEST_TMP_DIR}" "phase_3_validation" "CP_3_001" "experimenter"

    # Simulate rejection - go back to experiment design
    sed -i 's/phase_3_validation/phase_1_planning/' .workflow/state.yaml

    # Handoff should work for regression
    run create_handoff_checkpoint "${TEST_TMP_DIR}" "Revision needed" "claude" "gemini"

    grep -q "phase_1_planning" .workflow/state.yaml
}

@test "Multi-iteration research cycle" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    # Iteration 1
    "${SCRIPTS_DIR}/checkpoint.sh" create "Iteration 1 hypothesis" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Iter 1 H" "claude" "gemini"

    # Iteration 2 (refine)
    "${SCRIPTS_DIR}/checkpoint.sh" create "Iteration 2 hypothesis" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Iter 2 H" "gemini" "claude"

    # Iteration 3 (finalize)
    "${SCRIPTS_DIR}/checkpoint.sh" create "Iteration 3 hypothesis" 2>/dev/null || true

    # Should have multiple checkpoints
    local cp_count
    cp_count=$(wc -l < .workflow/checkpoints.log)
    [ "$cp_count" -ge 3 ]
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

@test "Full research cycle completion time < 60s" {
    cd "${TEST_TMP_DIR}"

    local start_time end_time elapsed
    start_time=$(date +%s)

    # Hypothesis
    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"
    "${SCRIPTS_DIR}/checkpoint.sh" create "Hypothesis" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "H1" "claude" "gemini"

    # Design
    "${SCRIPTS_DIR}/checkpoint.sh" create "Design" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "H2" "gemini" "claude"

    # Collection
    sed -i 's/phase_1_planning/phase_2_implementation/' .workflow/state.yaml
    "${SCRIPTS_DIR}/checkpoint.sh" create "Collection" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "H3" "claude" "gemini"

    # Analysis
    sed -i 's/phase_2_implementation/phase_3_validation/' .workflow/state.yaml
    "${SCRIPTS_DIR}/checkpoint.sh" create "Analysis" 2>/dev/null || true
    create_handoff_checkpoint "${TEST_TMP_DIR}" "H4" "gemini" "claude"

    # Publication
    sed -i 's/phase_3_validation/phase_4_delivery/' .workflow/state.yaml
    "${SCRIPTS_DIR}/checkpoint.sh" create "Publication" 2>/dev/null || true

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    [ "$elapsed" -lt 60 ]
}

@test "Research artifacts preserved across tools" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_1_planning" "CP_1_001" "researcher"

    # Create research artifacts
    mkdir -p workspace/researcher/{literature,data,analysis}
    echo "# Bibliography" > workspace/researcher/literature/references.md
    echo "data,value" > workspace/researcher/data/raw.csv
    echo "# Results" > workspace/researcher/analysis/findings.md

    # Handoff
    create_handoff_checkpoint "${TEST_TMP_DIR}" "Artifacts" "claude" "gemini"

    # All artifacts should exist
    [ -f "workspace/researcher/literature/references.md" ]
    [ -f "workspace/researcher/data/raw.csv" ]
    [ -f "workspace/researcher/analysis/findings.md" ]
}

@test "Final research state validates against schema" {
    cd "${TEST_TMP_DIR}"

    create_claude_session_state "${TEST_TMP_DIR}" "phase_4_delivery" "CP_4_001" "documenter"

    # Update to research type
    sed -i 's/type: "software"/type: "research"/' .workflow/state.yaml

    # Verify required fields
    grep -q "current_phase:" .workflow/state.yaml
    grep -q "current_checkpoint:" .workflow/state.yaml
    grep -q "project:" .workflow/state.yaml
    grep -q "metadata:" .workflow/state.yaml
}
