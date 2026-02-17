# Example: Python ML Research Project

This walkthrough demonstrates using UWS for a machine learning research project, cycling through the 7-phase research workflow with agent handoffs and checkpoints.

## Prerequisites

- UWS installed (`./install.sh` from repo root, or use scripts directly)
- Bash 4.0+, Git 2.0+

## Walkthrough

### 1. Initialize the project

```bash
mkdir my-ml-project && cd my-ml-project
git init

# Initialize UWS with research project type
uws init research
# Or: /path/to/uws/scripts/init_workflow.sh research
```

### 2. Research Workflow (7 phases)

```bash
# Start the research workflow
uws research start

# Phase 1: Hypothesis
uws agent researcher
uws research status
# Define your hypothesis, document in .workflow/handoff.md
uws checkpoint create "Hypothesis: transformer attention improves tabular data"

# Phase 2: Literature Review
uws research next
uws research status   # Now in literature_review
# Review related work, collect references
uws checkpoint create "Literature review complete - 23 papers reviewed"

# Phase 3: Experiment Design
uws research next
uws agent experimenter
# Design experiments, define metrics
uws checkpoint create "Experiment design: 3 baselines, 2 architectures, 5 datasets"

# Phase 4: Data Collection
uws research next
# Prepare datasets, preprocessing pipelines
uws checkpoint create "Data collection complete - 5 datasets preprocessed"

# Phase 5: Analysis
uws research next
uws agent researcher
# Run experiments, analyze results
uws checkpoint create "Analysis complete - transformer outperforms baselines on 4/5 datasets"

# Phase 6: Peer Review
uws research next
# Internal review, address feedback
uws checkpoint create "Peer review feedback incorporated"

# Phase 7: Publication
uws research next
uws agent documenter
# Write paper, prepare submission
uws checkpoint create "Paper submitted to ICML"
```

### 3. Check status at any point

```bash
uws status              # Full workflow status
uws research status     # Research phase status
uws checkpoint list     # All checkpoints
```

### 4. Session continuity

```bash
# End of session
# Edit .workflow/handoff.md with notes

# Next session - context auto-recovers
uws recover             # Full context recovery
uws status              # See where you left off
```

## Automated Demo

Run `walkthrough.sh` to see a fully automated demo:

```bash
bash walkthrough.sh
```

## Key Concepts Demonstrated

- **Research workflow**: 7 phases from hypothesis to publication
- **Agent handoffs**: researcher -> experimenter -> researcher -> documenter
- **Checkpoints**: Preserving state at each milestone
- **Context recovery**: Resuming after session breaks
