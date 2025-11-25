# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Universal Workflow System (UWS) is a git-native workflow system for context-resilient AI-assisted development. It maintains context across sessions, survives context resets, and adapts to any project type. This repository also contains a **PROMISE 2026 research paper** (predictive models for workflow recovery) and replication package.

## Common Commands

### Testing
```bash
# Run all tests (requires BATS)
./tests/run_all_tests.sh

# Run specific test category
./tests/run_all_tests.sh -c unit
./tests/run_all_tests.sh -c integration
./tests/run_all_tests.sh -c system

# Run with ShellCheck linting
./tests/run_all_tests.sh -l

# Run individual test file
bats tests/unit/test_checkpoint.bats
```

### Benchmarks & Predictive Models
```bash
# Run full benchmark suite
./tests/benchmarks/benchmark_runner.sh

# Generate predictive dataset (3,000 recovery scenarios)
python3 tests/benchmarks/predictive_dataset_generator.py

# Train predictive models (recovery time, success classification)
python3 tests/benchmarks/train_predictive_models.py

# Generate LaTeX tables for paper
python3 tests/benchmarks/generate_paper_tables.py

# Additional analysis
python3 tests/benchmarks/ablation_study.py
python3 tests/benchmarks/sensitivity_analysis.py
python3 tests/benchmarks/baseline_benchmark.py
```

### Workflow Operations
```bash
./scripts/recover_context.sh            # Recover context after session break
./scripts/status.sh                     # Show current workflow status
./scripts/checkpoint.sh "message"       # Create checkpoint (also: list, restore, status)
./scripts/activate_agent.sh <agent>     # researcher|architect|implementer|experimenter|optimizer|deployer|documenter
./scripts/enable_skill.sh <skill>       # Enable specific skills
./scripts/init_workflow.sh              # Initialize workflow system
```

### Paper/LaTeX
```bash
cd paper && pdflatex main.tex && bibtex main && pdflatex main.tex && pdflatex main.tex
```

## Architecture

### State Files (`.workflow/`)
- `state.yaml` - Current phase, checkpoint, project metadata, agent status, health metrics
- `checkpoints.log` - Timestamped history: `TIMESTAMP | CP_ID | DESC`
- `handoff.md` - **Critical**: Human-readable context handoff for session continuity
- `agents/registry.yaml` - Agent definitions with capabilities and workspace paths
- `skills/catalog.yaml` - Skill definitions and chains
- `checkpoints/snapshots/<CP_ID>/` - Full state snapshots for each checkpoint

### Multi-Agent System
Seven agents (`researcher`, `architect`, `implementer`, `experimenter`, `optimizer`, `deployer`, `documenter`), each with:
- Defined capabilities and primary skills in `registry.yaml`
- Dedicated workspace: `workspace/<agent>/`
- Collaboration patterns (e.g., `research_to_implementation`, `full_ml_pipeline`)
- Transition rules controlling valid agent handoffs

### Phase System
Linear progression: `phase_1_planning` → `phase_2_implementation` → `phase_3_validation` → `phase_4_delivery` → `phase_5_maintenance`. Each phase tracked in `state.yaml` with status, timestamps, progress percentage, and deliverables.

### Checkpoint System
- IDs: `CP_<phase_num>_<seq>` (e.g., `CP_1_003`)
- `./scripts/checkpoint.sh create "msg"` - Creates snapshot with state, handoff, active agent, enabled skills
- `./scripts/checkpoint.sh restore CP_X_XXX` - Restores from snapshot (prompts for confirmation)
- Snapshots include git commit hash and branch at time of creation

## Test Infrastructure

BATS-based tests with shared helpers in `tests/helpers/test_helper.bash`:
- `setup_test_environment()` - Creates isolated temp directory with minimal workflow structure
- `create_full_test_environment()` - Complete fixture with all config files
- Custom assertions: `assert_file_contains`, `assert_less_than`, `assert_matches`
- `measure_time()` - Returns execution time in milliseconds

Results output as TAP format to `test-results/`.

## Research Artifacts

### Predictive Dataset (`artifacts/predictive_dataset/`)
3,000 annotated recovery scenarios with 18 features for ML research:
- `raw/` - JSON format
- `processed/` - CSV for scikit-learn

### Predictive Models (`artifacts/predictive_models/`)
- Recovery time regression (Gradient Boosting: MAE=1.1ms, R²=0.756)
- Recovery success classification (Gradient Boosting: AUC=0.912, F1=0.911)
- State completeness regression (MAE=8.79%)

### Paper (`paper/`)
PROMISE 2026 submission with:
- `sections/*-promise.tex` - Predictive model focus
- `tables/prediction_*.tex` - Auto-generated from benchmark results

## Session Workflow

1. Run `./scripts/recover_context.sh` at session start
2. Read `.workflow/handoff.md` for priority actions and critical context
3. Create checkpoints at milestones: `./scripts/checkpoint.sh "description"`
4. Update `handoff.md` before ending session with next actions and blockers

## Key Conventions

- Checkpoint before/after major changes
- State YAML uses `yq` when available, falls back to grep/sed
- Scripts source `lib/yaml_utils.sh` and `lib/validation_utils.sh` for shared utilities
- Benchmark JSON results enable statistical analysis with confidence intervals
