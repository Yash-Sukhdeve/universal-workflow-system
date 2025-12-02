# Universal Workflow System (UWS)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](#)

**Context-preserving workflow system for AI-assisted development.** Maintains state across sessions, survives context resets, and works with any project type.

---

## Quick Start with Claude Code

```bash
# In your project directory:
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash

# Start Claude Code
claude

# Your context loads automatically. Use these commands:
/uws:status              # Check current state
/uws:checkpoint "msg"    # Save progress
/uws:recover             # Full context recovery
/uws:handoff             # Prepare for session end
```

**[Full Getting Started Guide →](claude-code-integration/GETTING_STARTED.md)**

---

## What UWS Does

| Problem | UWS Solution |
|---------|--------------|
| Context lost after session break | **Auto-loads context** on session start |
| Forgot where you left off | **Handoff document** preserves priorities |
| Context window fills up | **Auto-checkpoints** before compaction |
| Manual state tracking | **Structured state** in git-native YAML |

## Features

- **Context Persistence** - State survives any context window reset
- **Auto-Checkpointing** - Saves before context compaction
- **Multi-Agent System** - 7 specialized agents for different tasks
- **Skill Library** - 26 reusable skills across 6 categories
- **Git Native** - Everything tracked in version control
- **Zero Dependencies** - Pure Bash, works anywhere

---

## Installation Options

### Option 1: Claude Code Integration (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash
```

### Option 2: Standalone Scripts

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git
cd your-project
/path/to/universal-workflow-system/scripts/init_workflow.sh
```

---

## Repository Structure

```
universal-workflow-system/
├── claude-code-integration/   # Claude Code plug-and-play installer
│   ├── install.sh             # One-liner installer
│   └── GETTING_STARTED.md     # Detailed guide
├── scripts/                   # Core workflow scripts
│   ├── init_workflow.sh       # Initialize workflow
│   ├── checkpoint.sh          # Create/restore checkpoints
│   ├── recover_context.sh     # Recover after breaks
│   ├── status.sh              # Show current state
│   └── activate_agent.sh      # Switch agents
├── .workflow/                 # Workflow state (template)
│   ├── state.yaml             # Current phase/checkpoint
│   ├── handoff.md             # Human-readable context
│   ├── agents/                # Agent definitions
│   └── skills/                # Skill catalog
├── tests/                     # BATS test suite
└── research/                  # Academic research (PROMISE 2026)
```

---

## Agents & Skills

### 7 Specialized Agents

| Agent | Purpose |
|-------|---------|
| 🔬 **Researcher** | Literature review, experiments, statistics |
| 🏗️ **Architect** | System design, APIs, schemas |
| 💻 **Implementer** | Code development, testing |
| 🧪 **Experimenter** | Benchmarks, ablations, A/B tests |
| ⚡ **Optimizer** | Quantization, pruning, performance |
| 🚀 **Deployer** | Containers, CI/CD, monitoring |
| 📚 **Documenter** | Papers, docs, presentations |

### 26 Skills in 6 Categories

- **Research**: literature_review, experimental_design, statistical_validation
- **Development**: code_generation, debugging, testing, refactoring
- **ML/AI**: model_development, fine_tuning, quantization, pruning
- **Optimization**: profiling, benchmarking, hyperparameter_tuning
- **Deployment**: containerization, ci_cd, monitoring, scaling
- **Documentation**: technical_writing, paper_writing, visualization

---

## Core Commands

```bash
# Initialize workflow
./scripts/init_workflow.sh

# Check status
./scripts/status.sh

# Recover context after break
./scripts/recover_context.sh

# Create checkpoint
./scripts/checkpoint.sh "Completed feature X"

# Activate agent
./scripts/activate_agent.sh implementer

# Enable skills
./scripts/enable_skill.sh testing debugging
```

---

## Workflow Phases

UWS tracks your project through 5 phases:

1. **Planning** - Requirements, design decisions
2. **Implementation** - Building and coding
3. **Validation** - Testing, benchmarking
4. **Delivery** - Deployment, release
5. **Maintenance** - Support, iteration

---

## Running Tests

```bash
# Run all tests (requires BATS)
./tests/run_all_tests.sh

# Run specific category
./tests/run_all_tests.sh -c unit
./tests/run_all_tests.sh -c integration
```

---

## Research

The `research/` directory contains academic work validating UWS design decisions:

- **PROMISE 2026 Paper**: Predictive models for workflow recovery
- **Component Study**: 840 experiments testing design variants
- **Replication Package**: Docker environment for reproducibility

See [research/README.md](research/README.md) for details.

---

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License - see [LICENSE](LICENSE).

---

**Remember**: UWS adapts to you, not the other way around. Start simple, evolve as needed.
