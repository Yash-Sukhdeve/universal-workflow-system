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
python3 tests/benchmarks/analyze_results.py
python3 tests/benchmarks/repository_mining_study.py
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

### SDLC Workflow (Company OS)
```bash
./scripts/sdlc.sh status                # Show current SDLC phase
./scripts/sdlc.sh start                 # Begin SDLC at requirements phase
./scripts/sdlc.sh next                  # Advance to next phase
./scripts/sdlc.sh fail "reason"         # Report failure (triggers regression)
./scripts/sdlc.sh reset                 # Reset SDLC state
```

**SDLC Phases**: `requirements` → `design` → `implementation` → `verification` → `deployment` → `maintenance`

### Research Workflow (Scientific Method)
```bash
./scripts/research.sh status            # Show current research phase
./scripts/research.sh start             # Begin research at hypothesis phase
./scripts/research.sh next              # Advance to next phase
./scripts/research.sh reject "reason"   # Hypothesis rejected (triggers refinement)
./scripts/research.sh reset             # Reset research state
```

**Research Phases**: `hypothesis` → `literature_review` → `experiment_design` → `data_collection` → `analysis` → `peer_review` → `publication`

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

## Claude Code Plugin

UWS includes a Claude Code plugin for seamless integration. The plugin provides slash commands, automated hooks, and autonomous skills.

### Slash Commands
```
/uws-status              # Show workflow status (phase, agent, checkpoint)
/uws-checkpoint <msg>    # Create checkpoint with message
/uws-recover             # Recover context after session break
/uws-agent <name>        # Activate agent (researcher, architect, implementer, etc.)
/uws-skill <name>        # Enable/disable skills
/uws-handoff             # Prepare session handoff notes
```

### Automated Hooks
- **SessionStart**: Auto-runs `recover_context.sh` when Claude Code starts
- **PreCompact**: Auto-creates checkpoint before context compaction

### Skills (Autonomous Usage)
Claude can autonomously use these capabilities when appropriate:
- `workflow-checkpoint`: Creates checkpoints after completing major work
- `workflow-recovery`: Recovers context when state seems stale
- `workflow-status`: Checks state before major operations

### Plugin Files
```
.claude/
├── commands/           # Slash command definitions
├── skills/             # Autonomous skill definitions
└── settings.json       # Hook configuration

.claude-plugin/
├── plugin.json         # Plugin manifest
└── marketplace.json    # Distribution metadata
```

## Python Dependencies

For benchmarks and predictive modeling (install from `replication/requirements.txt`):
```bash
pip install -r replication/requirements.txt
```
Key packages: scikit-learn, pandas, scipy, numpy, statsmodels

## Replication Package (`replication/`)

Dockerized environment for reproducing paper results:
```bash
cd replication && docker build -t uws-replication . && docker run uws-replication
```
Contains pre-collected benchmark data organized as:
- `data/raw/` - Raw benchmark measurements (JSON)
- `data/processed/` - Statistical summaries and paper data
- `data/baselines/` - Baseline comparison results
- `data/ablation/` - Ablation study results
- `data/sensitivity/` - Sensitivity analysis results
- `expected_outputs/` - Expected values for validation

## Vector Memory Protocol

### Overview
UWS uses two vector memory databases for semantic retrieval:
- **Local** (mcp__vector_memory_local): Project-specific memories
- **Global** (mcp__vector_memory_global): Cross-project generalizable lessons

Markdown/YAML files are ALWAYS the source of truth. Vector memory is a
read-optimized index. If they conflict, delete the vector memory entry.

### Atomic Memory Principle
Each store_memory() call: EXACTLY ONE idea, MAX 200 words.
Prefix local memories with "PHASE <N> <methodology_phase> | DOMAIN: <domain> | "
  where <N> = UWS overall phase (1-5), <methodology_phase> = research/SDLC phase name
  Example: "PHASE 2 experiment_design | DOMAIN: training | ..."
Prefix global memories with "<TOOL_OR_PATTERN>: "

### When to Store (Behavioral Directives)

**After completing a phase** (on_phase_complete):
  For each key outcome and decision in the phase:
    mcp__vector_memory_local__store_memory(
      content="PHASE <N> <methodology_phase> | DOMAIN: <d> | CATEGORY: phase-summary | OUTCOME: <description>",
      category="learning",
      tags=["phase-<N>", "<domain>"])
  For architectural decisions:
    category="architecture", content includes "CATEGORY: decision-adr"

**After fixing a non-trivial bug** (on_error_resolved):
  mcp__vector_memory_local__store_memory(
    content="PHASE <N> <methodology_phase> | DOMAIN: <d> | CATEGORY: bug-resolution | BUG: <symptom>
             ROOT_CAUSE: <cause> FIX: <fix> PREVENTION: <how>",
    category="bug-fix",
    tags=["phase-<N>", "bug", "<domain>"])
  THEN run Generalizability Gate (see below).

**After agent transition** (on_agent_handoff):
  Outgoing agent stores:
    mcp__vector_memory_local__store_memory(
      content="PHASE <N> <methodology_phase> | DOMAIN: handoff | CATEGORY: agent-handoff |
               HANDOFF <from>-><to>. KEY_DECISIONS: <list>
               OPEN_ISSUES: <list>",
      category="other",
      tags=["phase-<N>", "agent-<from>", "agent-<to>", "handoff"])
  Incoming agent queries:
    mcp__vector_memory_local__search_memories(
      query="decisions constraints phase <N>",
      category="architecture", limit=5)

**After verification/test run** (on_verification):
  mcp__vector_memory_local__store_memory(
    content="PHASE <N> <methodology_phase> | CATEGORY: verification | VERIFIED: <what> METHOD: <how>
             RESULT: <pass/fail> EVIDENCE: <summary>",
    category="other",
    tags=["phase-<N>", "verification"])

### Generalizability Gate
After storing a bug-fix or architecture memory to local DB, the
`memory-gate` skill auto-invokes (via description matching) to evaluate
3 questions. If all pass, an abstracted lesson is promoted to global DB.
If any fail, local only. See `.claude/skills/memory-gate/SKILL.md`.

### Session Resume (Enhanced)
At session start, after reading state.yaml and handoff.md:
  mcp__vector_memory_local__search_memories(
    query="blockers issues PHASE <current>", limit=5)
  mcp__vector_memory_local__search_memories(
    query="decisions PHASE <current>", category="architecture", limit=5)
  mcp__vector_memory_global__search_memories(
    query="<current technology/domain>", limit=3)

### R1 Evidence Extension
Before asserting facts about prior phases:
  mcp__vector_memory_local__search_memories("<claim>", limit=3)
  If relevant result found: cite as supporting evidence.
  If no result: say "No prior record" and verify from files.
  Never cite vector memory as sole evidence.

### Phase-End Distillation
At phase completion, run `/phase-distillation <N>` to review local
memories from the completed phase. The skill consolidates recurring
patterns, applies the generalizability gate, runs adversarial
calibration (supersede false promotions), and promotes passing lessons
to global DB. See `.claude/skills/phase-distillation/SKILL.md`.

### Server-Accepted Categories
The MCP server accepts: `code-solution` | `bug-fix` | `architecture` |
`learning` | `tool-usage` | `debugging` | `performance` | `security` | `other`

Custom categories are embedded in content strings via `CATEGORY: <name>` prefix.

**Local category mapping** (plan category -> server category):
- phase-summary -> `learning`
- decision-adr -> `architecture`
- bug-resolution -> `bug-fix`
- agent-handoff -> `other`
- verification -> `other`
- environment -> `tool-usage`

**Global category mapping**:
- anti-pattern -> `architecture`
- tool-gotcha -> `bug-fix`
- design-lesson -> `architecture`
- library-compat -> `other`
- workflow-improvement -> `other`

### Tag Format
Use hyphens, NOT colons in tags: `phase-2` (correct), `phase:2` (dropped by server).

### Memory Maintenance

LOCAL DB (per phase completion):
  mcp__vector_memory_local__get_memory_stats()
  IF total > 500: mcp__vector_memory_local__clear_old_memories(
    days_old=60, max_to_keep=500)

GLOBAL DB (quarterly, manual review):
  mcp__vector_memory_global__get_memory_stats()
  IF total > 200: Review manually. Remove outdated lessons.
  DO NOT use days_old for global -- old lessons are still valid.
  Only use max_to_keep=200 as safety cap.

### Recovery Procedures

**Local DB lost**:
1. Not catastrophic -- markdown/YAML files are source of truth.
2. Re-seed manually: read .workflow/handoff.md and .workflow/logs/decisions.log.
3. For each decision/bug documented in handoff.md, store to local DB.
4. Full re-indexing is manual but bounded by project size.

**Global DB lost**:
1. Lessons may also exist in CLAUDE.md auto-memory (~/.claude/MEMORY.md).
2. Re-seed from team documentation and known patterns.
3. Global DB grows slowly (~5-10 lessons per project). Loss is recoverable.

**Checkpoint restore (state reverts but vector DB does NOT)**:
1. Check mcp__vector_memory_local__get_memory_stats() for memory count.
2. If memories from future phases exist, they may cause confusion.
3. Option A (recommended): Ignore -- stale memories with future phase
   prefixes (e.g., "PHASE 4") rank low when searching for current
   phase (e.g., "PHASE 2"). The content prefix convention handles this.
4. Option B (nuclear): If contamination is severe, delete the DB file:
     rm <project_root>/memory/memories.db
   Then re-seed from .workflow/handoff.md.
   NOTE: clear_old_memories() cannot wipe all entries (min days_old=1,
   min max_to_keep=100). Direct file deletion is the only full reset.

### Category Migration

If categories need to change in the future:
1. get_memory_stats() to get total count.
2. list_recent_memories(limit=<total>) to export all entries.
3. Record all memory content and categories externally.
4. Delete the DB file: rm <working_dir>/memory/memories.db
   (clear_old_memories cannot wipe all: min days_old=1, min max_to_keep=100)
5. Re-store each memory with updated categories.
Keep category taxonomy stable. Prefer adding new categories over renaming.

## Key Conventions

- Checkpoint before/after major changes
- State YAML uses `yq` when available, falls back to grep/sed
- Benchmark JSON results in `artifacts/benchmark_results/` enable statistical analysis with confidence intervals
