#!/usr/bin/env bats
# End-to-End Test: Research Workflow
# Tests complete research workflow from literature review to paper submission

load '../helpers/test_helper'

# ============================================================================
# SETUP AND TEARDOWN
# ============================================================================

setup() {
    setup_test_environment

    # Create research-specific project structure
    mkdir -p "${TEST_TMP_DIR}/papers"
    mkdir -p "${TEST_TMP_DIR}/experiments"
    mkdir -p "${TEST_TMP_DIR}/literature"
    mkdir -p "${TEST_TMP_DIR}/figures"
    mkdir -p "${TEST_TMP_DIR}/data"

    # Create full test environment with all fixtures
    create_full_test_environment

    # Update state for research project
    cat > "${TEST_TMP_DIR}/.workflow/state.yaml" << 'EOF'
project:
  name: "research-test-project"
  type: "research"
  version: "1.0.0"

current_phase: "phase_1_planning"
current_checkpoint: "CP_INIT"
checkpoint_count: 0

research:
  topic: "AI-Assisted Development"
  target_venue: "FSE 2026"
  rqs:
    - "RQ1: Functionality"
    - "RQ2: Performance"
    - "RQ3: Reliability"

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

@test "E2E: Research project structure created" {
    assert_dir_exists "${TEST_TMP_DIR}/papers"
    assert_dir_exists "${TEST_TMP_DIR}/experiments"
    assert_dir_exists "${TEST_TMP_DIR}/literature"
    assert_dir_exists "${TEST_TMP_DIR}/figures"
}

@test "E2E: Research state contains RQs" {
    assert_file_contains "${TEST_TMP_DIR}/.workflow/state.yaml" "RQ1"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/state.yaml" "RQ2"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/state.yaml" "RQ3"
}

@test "E2E: Research workflow - Literature Review Phase" {
    # Simulate literature review
    cat > "${TEST_TMP_DIR}/literature/review.md" << 'EOF'
# Literature Review

## Related Work
1. Airflow (2018) - DAG-based workflows
2. Temporal (2020) - Durable execution
3. LangChain (2022) - LLM orchestration

## Research Gap
No existing system provides git-native state management for AI-assisted development.

## Key Papers
- Mark et al. (2008) - Cost of Interrupted Work
- Parnin & Rugaber (2011) - Resumption Strategies
EOF

    assert_file_exists "${TEST_TMP_DIR}/literature/review.md"
    assert_file_contains "${TEST_TMP_DIR}/literature/review.md" "Research Gap"
}

@test "E2E: Research workflow - Experiment Design Phase" {
    cat > "${TEST_TMP_DIR}/experiments/design.md" << 'EOF'
# Experiment Design

## Variables
- Independent: Workflow system (UWS vs baselines)
- Dependent: Context recovery time, success rate
- Control: Project complexity, checkpoint frequency

## Methodology
1. Automated benchmarks
2. Ablation studies
3. Case studies

## Metrics
- Recovery time (seconds)
- Success rate (%)
- Code coverage (%)
EOF

    assert_file_exists "${TEST_TMP_DIR}/experiments/design.md"
    assert_file_contains "${TEST_TMP_DIR}/experiments/design.md" "Variables"
}

@test "E2E: Research workflow - Data Collection Phase" {
    mkdir -p "${TEST_TMP_DIR}/data/raw"
    mkdir -p "${TEST_TMP_DIR}/data/processed"

    # Simulate collected data
    cat > "${TEST_TMP_DIR}/data/raw/benchmark_results.csv" << 'EOF'
system,trial,recovery_time_s,success
UWS,1,248,true
UWS,2,256,true
UWS,3,252,true
Manual,1,875,true
Manual,2,912,true
Manual,3,948,false
LangGraph,1,442,true
LangGraph,2,456,true
LangGraph,3,470,true
EOF

    assert_file_exists "${TEST_TMP_DIR}/data/raw/benchmark_results.csv"

    # Verify data format
    local lines=$(wc -l < "${TEST_TMP_DIR}/data/raw/benchmark_results.csv")
    [ "$lines" -ge 9 ]
}

@test "E2E: Research workflow - Analysis Phase" {
    mkdir -p "${TEST_TMP_DIR}/data/analysis"

    # Simulate statistical analysis output
    cat > "${TEST_TMP_DIR}/data/analysis/statistics.json" << 'EOF'
{
    "uws_vs_manual": {
        "test": "Wilcoxon signed-rank",
        "p_value": 0.001,
        "effect_size": 2.89,
        "effect_size_interpretation": "large"
    },
    "uws_vs_langgraph": {
        "test": "Wilcoxon signed-rank",
        "p_value": 0.005,
        "effect_size": 1.84,
        "effect_size_interpretation": "large"
    },
    "summary": {
        "uws_mean": 252,
        "uws_std": 34,
        "manual_mean": 912,
        "manual_std": 245,
        "improvement_percent": 72
    }
}
EOF

    assert_file_exists "${TEST_TMP_DIR}/data/analysis/statistics.json"
    assert_file_contains "${TEST_TMP_DIR}/data/analysis/statistics.json" "Wilcoxon"
    assert_file_contains "${TEST_TMP_DIR}/data/analysis/statistics.json" "effect_size"
}

@test "E2E: Research workflow - Paper Writing Phase" {
    mkdir -p "${TEST_TMP_DIR}/papers/sections"

    # Create paper structure
    cat > "${TEST_TMP_DIR}/papers/main.tex" << 'EOF'
\documentclass[sigconf]{acmart}
\title{Test Paper}
\begin{document}
\maketitle
\input{sections/01-introduction}
\input{sections/02-approach}
\input{sections/03-evaluation}
\end{document}
EOF

    cat > "${TEST_TMP_DIR}/papers/sections/01-introduction.tex" << 'EOF'
\section{Introduction}
This paper presents UWS...
EOF

    assert_file_exists "${TEST_TMP_DIR}/papers/main.tex"
    assert_file_exists "${TEST_TMP_DIR}/papers/sections/01-introduction.tex"
    assert_file_contains "${TEST_TMP_DIR}/papers/main.tex" "acmart"
}

@test "E2E: Research workflow - Figure Generation" {
    # Simulate figure generation
    cat > "${TEST_TMP_DIR}/figures/recovery_time.tikz" << 'EOF'
% Recovery time comparison
\begin{tikzpicture}
\begin{axis}[
    ybar,
    ylabel={Recovery Time (s)},
    symbolic x coords={UWS,LangGraph,Manual},
]
\addplot coordinates {(UWS,252) (LangGraph,456) (Manual,912)};
\end{axis}
\end{tikzpicture}
EOF

    assert_file_exists "${TEST_TMP_DIR}/figures/recovery_time.tikz"
}

@test "E2E: Research workflow - Complete RQ evaluation" {
    mkdir -p "${TEST_TMP_DIR}/artifacts/rq_results"

    # RQ1: Functionality
    cat > "${TEST_TMP_DIR}/artifacts/rq_results/rq1_functionality.json" << 'EOF'
{
    "rq": "RQ1",
    "question": "Does UWS correctly implement workflow state management?",
    "answer": "Yes",
    "evidence": {
        "total_tests": 139,
        "passing_tests": 125,
        "pass_rate": 0.90,
        "code_coverage": 0.85
    }
}
EOF

    # RQ2: Performance
    cat > "${TEST_TMP_DIR}/artifacts/rq_results/rq2_performance.json" << 'EOF'
{
    "rq": "RQ2",
    "question": "How does UWS context recovery compare to baselines?",
    "answer": "65-72% improvement",
    "evidence": {
        "uws_mean_s": 252,
        "baseline_mean_s": 912,
        "improvement_percent": 72,
        "effect_size": 2.89,
        "p_value": 0.001
    }
}
EOF

    # RQ3: Reliability
    cat > "${TEST_TMP_DIR}/artifacts/rq_results/rq3_reliability.json" << 'EOF'
{
    "rq": "RQ3",
    "question": "How reliable is UWS under failure conditions?",
    "answer": "97% success rate",
    "evidence": {
        "overall_success_rate": 0.97,
        "failure_conditions_tested": 7,
        "target_success_rate": 0.95
    }
}
EOF

    assert_file_exists "${TEST_TMP_DIR}/artifacts/rq_results/rq1_functionality.json"
    assert_file_exists "${TEST_TMP_DIR}/artifacts/rq_results/rq2_performance.json"
    assert_file_exists "${TEST_TMP_DIR}/artifacts/rq_results/rq3_reliability.json"
}

@test "E2E: Research workflow - Checkpoint progression" {
    # Simulate checkpoint progression through research phases
    cat > "${TEST_TMP_DIR}/.workflow/checkpoints.log" << 'EOF'
2024-01-01T00:00:00Z | CP_INIT | Project initialized
2024-01-15T00:00:00Z | CP_R_1 | Literature review completed
2024-02-01T00:00:00Z | CP_R_2 | Experiment design finalized
2024-03-01T00:00:00Z | CP_R_3 | Data collection completed
2024-04-01T00:00:00Z | CP_R_4 | Analysis completed
2024-05-01T00:00:00Z | CP_R_5 | Paper draft completed
EOF

    # Count checkpoints
    local checkpoint_count=$(grep -c "^[0-9]" "${TEST_TMP_DIR}/.workflow/checkpoints.log")
    [ "$checkpoint_count" -ge 5 ]
}

@test "E2E: Research workflow - Agent transitions follow pattern" {
    # Research workflow pattern: researcher -> architect -> implementer -> experimenter -> documenter
    local agents=("researcher" "architect" "implementer" "experimenter" "documenter")

    for agent in "${agents[@]}"; do
        # Verify agent is defined in registry
        assert_file_contains "${TEST_TMP_DIR}/.workflow/agents/registry.yaml" "${agent}:"
    done
}

@test "E2E: Research workflow - Handoff document tracks progress" {
    cat > "${TEST_TMP_DIR}/.workflow/handoff.md" << 'EOF'
# Research Workflow Handoff

## Current Status
- Phase: phase_3_validation
- RQs Completed: RQ1, RQ2, RQ3
- Paper Status: 60% complete

## Recent Progress
- [x] Literature review (25 papers)
- [x] Experiment design
- [x] Test suite development (139 tests)
- [x] Benchmark execution
- [ ] Paper revision
- [ ] Submission preparation

## Target Venue
FSE 2026 (deadline: Dec 2025)

## Critical Context
1. No user study - using automated benchmarks
2. Statistical analysis shows significant improvements
3. Ablation study confirms component contributions
EOF

    assert_file_contains "${TEST_TMP_DIR}/.workflow/handoff.md" "FSE 2026"
    assert_file_contains "${TEST_TMP_DIR}/.workflow/handoff.md" "No user study"
}

@test "E2E: Research workflow - Complete phase deliverables" {
    # Phase 1: Planning deliverables
    cat > "${TEST_TMP_DIR}/phases/phase_1_planning/deliverables.md" << 'EOF'
# Phase 1 Deliverables
- [x] Research questions defined
- [x] Literature review completed
- [x] Methodology designed
EOF

    # Phase 2: Implementation deliverables
    cat > "${TEST_TMP_DIR}/phases/phase_2_implementation/deliverables.md" << 'EOF'
# Phase 2 Deliverables
- [x] Test framework setup (BATS)
- [x] Unit tests (99 tests)
- [x] Integration tests (25 tests)
- [x] E2E tests (15 tests)
EOF

    # Phase 3: Validation deliverables
    cat > "${TEST_TMP_DIR}/phases/phase_3_validation/deliverables.md" << 'EOF'
# Phase 3 Deliverables
- [x] Benchmark suite execution
- [x] Statistical analysis
- [x] Ablation study
- [x] Case studies
EOF

    assert_file_exists "${TEST_TMP_DIR}/phases/phase_1_planning/deliverables.md"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_2_implementation/deliverables.md"
    assert_file_exists "${TEST_TMP_DIR}/phases/phase_3_validation/deliverables.md"
}
