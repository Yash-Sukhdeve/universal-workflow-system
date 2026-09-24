# Universal Workflow System (UWS) v1.1.0

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](#)
[![CI](https://github.com/Yash-Sukhdeve/universal-workflow-system/actions/workflows/ci.yml/badge.svg)](https://github.com/Yash-Sukhdeve/universal-workflow-system/actions)

**Context-preserving workflow system for AI-assisted development.** Maintains state across sessions, survives context resets, and works with any project type.

---

## Table of Contents

- [Quick Start](#quick-start)
- [What's Included](#whats-included)
- [Installation](#installation)
- [CLI](#cli)
- [Core Components](#core-components)
- [Usage Guide](#usage-guide)
- [Testing](#testing)
- [Architecture](#architecture)
- [Vector Memory](#vector-memory)
- [CI/CD](#cicd)
- [Contributing](#contributing)

---

## Quick Start

Pick one. All three keep state in your project's `.workflow/` directory; none needs
anything beyond Bash, git and (for the Claude Code paths) Claude Code.

### Option 1: Claude Code plugin (recommended)

Inside Claude Code:

```
/plugin marketplace add Yash-Sukhdeve/universal-workflow-system
/plugin install uws@uws
```

Then, in any project:

```
/uws:init                # set up .workflow/ (auto-detects the project type)
/uws:status              # phase, checkpoint, recent activity
/uws:checkpoint "msg"    # save progress
/uws:recover             # full context recovery after a break
/uws:handoff             # update handoff notes before ending a session
/uws:sdlc start          # or /uws:research start
```

Workflow context is injected automatically at session start, and a checkpoint is taken
before every context compaction. The plugin also adds seven role subagents
(`uws:uws-researcher`, `uws:uws-architect`, `uws:uws-implementer`, …).

### Option 2: Per-project installer (commit UWS into the repo)

Use this when collaborators should get the commands and hooks from the repository
itself, without installing a plugin:

```bash
# In your project directory (add "-s -- --yes" after bash for unattended installs):
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash
git add .uws/ .claude/ .workflow/ CLAUDE.md .gitignore && git commit -m "Add UWS workflow"
```

This adds `/uws`, `/uws-status`, `/uws-checkpoint`, `/uws-recover`, `/uws-handoff`,
`/uws-sdlc` and `/uws-research`. See [claude-code-integration/](claude-code-integration/README.md).

### Option 3: Command-line only

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git ~/uws
~/uws/install.sh        # links `uws` into ~/.local/bin

cd your-project
uws init                # initialize workflow
uws status              # check status
uws sdlc start          # begin the SDLC workflow
```

Without installing, run the scripts from your project directory instead:
`~/uws/scripts/init_workflow.sh`, then `~/uws/scripts/status.sh`.

The optional vector-memory server (~1.5GB) is never installed unless you ask for it:
answer `y` at the prompt, or set `UWS_VECTOR_MEMORY=true` for non-interactive runs.

---

## What's Included

| Component | Description | Location |
|-----------|-------------|----------|
| **Workflow Scripts** | Core Bash scripts for state management | `scripts/` |
| **Multi-Agent System** | 7 specialized AI agents | `.workflow/agents/` |
| **SDLC Workflow** | Software development lifecycle | `scripts/sdlc.sh` |
| **Research Workflow** | Scientific method workflow | `scripts/research.sh` |
| **Claude Code Plugin** | Slash commands, hooks & subagents | `plugins/uws/` |
| **Gemini Integration** | Antigravity workflows | `antigravity-integration/` |
| **Vector Memory** | Semantic search across sessions | `scripts/lib/vector_memory_setup.sh` |
| **Test Suite** | BATS unit, integration and system tests | `tests/` |

> Company OS (the FastAPI backend + React dashboard formerly built in this repo) has
> moved to its own private repository, [Yash-Sukhdeve/uws-company-os](https://github.com/Yash-Sukhdeve/uws-company-os).

---

## Installation

### Prerequisites

- **Bash 4.0+** (or 3.x for basic features)
- **Git** for version control
- **Python 3.9+** (optional — for vector memory)

### Step 1: Clone Repository

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git
cd universal-workflow-system
```

### Step 2: Initialize Workflow in Your Project

Run the initializer from **your project's** directory (not from the UWS clone):

```bash
cd /path/to/your-project
/path/to/universal-workflow-system/scripts/init_workflow.sh
```

During initialization, UWS asks whether to install the optional vector memory server for semantic search across sessions (default: no). It requires Python 3.9+ and ~1.5GB of disk space. Non-interactive runs skip it unless `UWS_VECTOR_MEMORY=true` is set; `UWS_SKIP_VECTOR_MEMORY=true` always skips it.

---

## CLI

The `uws` command wraps all scripts into a single interface:

```bash
uws init [type]              # Initialize UWS (software|research|ml|llm|...)
uws status [-v|-c]           # Show workflow status
uws checkpoint create "msg"  # Create checkpoint
uws recover                  # Recover context after break
uws agent <name>             # Activate agent (researcher|architect|implementer|...)
uws skill <name>             # Enable/disable skills
uws sdlc [cmd]               # SDLC workflow (status|start|next|fail|reset)
uws research [cmd]           # Research workflow (status|start|next|reject|reset)
uws help                     # Show all commands
```

Install: `./install.sh` (creates symlink to `~/.local/bin/uws`)

---

## Core Components

### 1. Workflow Scripts

Core scripts for managing workflow state.

```bash
# Initialize workflow system
./scripts/init_workflow.sh

# Check current status
./scripts/status.sh

# Create checkpoint
./scripts/checkpoint.sh create "Completed feature X"

# List checkpoints
./scripts/checkpoint.sh list

# Restore checkpoint
./scripts/checkpoint.sh restore CP_1_003

# Recover context after session break
./scripts/recover_context.sh

# Activate an agent
./scripts/activate_agent.sh researcher

# Enable skills
./scripts/enable_skill.sh testing debugging
```

**Script Reference:**

| Script | Purpose | Usage |
|--------|---------|-------|
| `init_workflow.sh` | Initialize UWS in project | `./scripts/init_workflow.sh` |
| `status.sh` | Show workflow status | `./scripts/status.sh` |
| `checkpoint.sh` | Manage checkpoints | `./scripts/checkpoint.sh create\|list\|restore` |
| `recover_context.sh` | Recover after breaks | `./scripts/recover_context.sh` |
| `activate_agent.sh` | Switch active agent | `./scripts/activate_agent.sh <agent>` |
| `enable_skill.sh` | Enable agent skills | `./scripts/enable_skill.sh <skill>...` |
| `sdlc.sh` | SDLC workflow | `./scripts/sdlc.sh status\|start\|next` |
| `research.sh` | Research workflow | `./scripts/research.sh status\|start\|next` |

---

### 2. Multi-Agent System

Seven specialized agents for different development tasks.

| Agent | Icon | Capabilities | Primary Skills |
|-------|------|--------------|----------------|
| **Researcher** | 🔬 | Literature review, experiments | `literature_review`, `statistical_validation` |
| **Architect** | 🏗️ | System design, APIs | `system_design`, `api_design` |
| **Implementer** | 💻 | Code development | `code_generation`, `testing` |
| **Experimenter** | 🧪 | Benchmarks, A/B tests | `experimental_design`, `benchmarking` |
| **Optimizer** | ⚡ | Performance tuning | `profiling`, `quantization` |
| **Deployer** | 🚀 | CI/CD, containers | `containerization`, `ci_cd` |
| **Documenter** | 📝 | Documentation, papers | `technical_writing`, `paper_writing` |

**Usage:**

```bash
# Activate an agent
./scripts/activate_agent.sh researcher

# Check current agent
./scripts/activate_agent.sh status

# Deactivate agent
./scripts/activate_agent.sh deactivate

# View agent capabilities
cat .workflow/agents/registry.yaml
```

---

### 3. SDLC & Research Workflows

#### Software Development Lifecycle (SDLC)

```bash
# Check SDLC status
./scripts/sdlc.sh status

# Start new SDLC cycle
./scripts/sdlc.sh start

# Advance to next phase
./scripts/sdlc.sh next

# Report failure (triggers regression)
./scripts/sdlc.sh fail "Build error in module X"

# Reset SDLC
./scripts/sdlc.sh reset
```

**SDLC Phases:**
```
requirements → design → implementation → verification → deployment → maintenance
```

#### Research Workflow (Scientific Method)

```bash
# Check research status
./scripts/research.sh status

# Start research project
./scripts/research.sh start

# Advance to next phase
./scripts/research.sh next

# Reject hypothesis (triggers refinement)
./scripts/research.sh reject "Results not significant"

# Reset research
./scripts/research.sh reset
```

**Research Phases:**
```
hypothesis → literature_review → experiment_design → data_collection → analysis → peer_review → publication
```

---

## Usage Guide

### Daily Workflow

```bash
# 1. Start your session - context auto-recovers
./scripts/recover_context.sh

# 2. Check where you left off
./scripts/status.sh

# 3. Read handoff notes
cat .workflow/handoff.md

# 4. Activate appropriate agent
./scripts/activate_agent.sh implementer

# 5. Work on your tasks...

# 6. Create checkpoint at milestones
./scripts/checkpoint.sh create "Completed user authentication"

# 7. Before ending session, update handoff
# Edit .workflow/handoff.md with session notes
```

### Claude Code Commands

When using with Claude Code, these slash commands are available:

| Command | Description |
|---------|-------------|
| `/uws-status` | Show workflow status |
| `/uws-checkpoint <msg>` | Create checkpoint |
| `/uws-recover` | Recover context |
| `/uws-agent <name>` | Activate agent |
| `/uws-skill <name>` | Enable/disable skill |
| `/uws-sdlc <cmd>` | SDLC workflow |
| `/uws-research <cmd>` | Research workflow |
| `/uws-handoff` | Prepare session handoff |

### Gemini Antigravity Commands

```bash
# Install Antigravity integration
./antigravity-integration/install.sh

# Available workflows in Gemini:
uws-status       # Check status
uws-checkpoint   # Create checkpoint
uws-sdlc         # SDLC management
uws-research     # Research workflow
```

---

## Testing

### Run All Tests

```bash
# Run complete test suite
./tests/run_all_tests.sh

# Run with ShellCheck linting
./tests/run_all_tests.sh -l

# Run specific category
./tests/run_all_tests.sh -c unit
./tests/run_all_tests.sh -c integration
./tests/run_all_tests.sh -c system
```

**Test Coverage:**

| Component | Tests | Framework |
|-----------|-------|-----------|
| Core Scripts | 773 | BATS |

---

## Architecture

### Directory Structure

```
universal-workflow-system/
├── .claude/                    # Claude Code plugin
│   ├── commands/               # Slash commands
│   ├── skills/                 # Autonomous skills
│   └── settings.json           # Hook configuration
├── .workflow/                  # Workflow state (per-project)
│   ├── state.yaml              # Current phase/checkpoint
│   ├── handoff.md              # Session handoff notes
│   ├── agents/                 # Agent registry & state
│   ├── skills/                 # Skill definitions
│   └── checkpoints/            # Checkpoint snapshots
├── scripts/                    # Core workflow scripts
│   ├── lib/                    # Utility libraries
│   │   └── vector_memory_setup.sh  # Vector memory installer
│   ├── init_workflow.sh        # Initialize workflow
│   ├── status.sh               # Show status
│   ├── checkpoint.sh           # Manage checkpoints
│   ├── sdlc.sh                 # SDLC workflow
│   └── research.sh             # Research workflow
├── antigravity-integration/    # Gemini Antigravity
├── tests/                      # Test suites
│   ├── unit/                   # Unit tests
│   ├── integration/            # Integration tests
│   └── system/                 # System tests
└── docs/                       # Documentation
```

### State Management

UWS stores state in `.workflow/` directory:

```yaml
# .workflow/state.yaml
current_phase: phase_3_validation
current_checkpoint: CP_3_004
project_type: hybrid
metadata:
  name: universal-workflow-system
  initialized: "2024-01-15T10:30:00Z"
  last_updated: "2024-12-22T10:54:21Z"
```

---

## Environment Configuration

### MCP Configuration (.mcp.json)

UWS uses MCP servers for vector memory (semantic retrieval across sessions):

```json
{
  "mcpServers": {
    "vector_memory_local": {
      "command": "/path/to/vector-memory/.venv/bin/python",
      "args": ["/path/to/vector-memory/main.py", "--working-dir", "/your/project/root"]
    },
    "vector_memory_global": {
      "command": "/path/to/vector-memory/.venv/bin/python",
      "args": ["/path/to/vector-memory/main.py", "--working-dir", "/your/global-knowledge-dir"]
    }
  }
}
```

See [Vector Memory Integration Plan](docs/uws-vector-memory-integration-plan.md) for setup details.

---

## Vector Memory

UWS integrates semantic vector memory for cross-session knowledge retrieval:

- **Local DB**: Project-specific memories (decisions, bug fixes, phase summaries)
- **Global DB**: Cross-project generalizable lessons (tool gotchas, design patterns)

Memories are stored atomically (one idea per entry, max 200 words) and retrieved via semantic similarity search. The system includes a generalizability gate that evaluates whether local lessons should be promoted to the global knowledge base.

### Setup

Vector memory is automatically offered during `init_workflow.sh` and `install.sh`. You can also set it up manually:

```bash
# Standalone setup (from UWS repo root)
./scripts/lib/vector_memory_setup.sh

# Skip vector memory during init
UWS_SKIP_VECTOR_MEMORY=true ./scripts/init_workflow.sh
```

**Requirements**: Python 3.9+, ~1.5GB disk space (packages + sentence-transformers model).

The setup library (`scripts/lib/vector_memory_setup.sh`) handles:
- Cloning the [vector-memory-mcp](https://github.com/cornebidouil/vector-memory-mcp) server
- Creating a Python venv with dependencies (`sqlite-vec`, `sentence-transformers`, `fastmcp`)
- Configuring `.mcp.json` with local and global server entries
- Adding `memory/` to `.gitignore`

See [Vector Memory Integration Plan](docs/uws-vector-memory-integration-plan.md) for full documentation.

---

## CI/CD

Continuous integration runs on every push and PR via GitHub Actions:

```bash
# Local equivalent of CI pipeline
./tests/run_all_tests.sh -l   # Run all tests with ShellCheck linting
```

See [`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the workflow definition.

---

<details>
<summary><strong>Demo: UWS in action</strong></summary>

```bash
$ uws init software
  Initializing UWS workflow...
  ✓ Directory structure created
  ✓ State file initialized
  ✓ Checkpoint system ready

$ uws agent architect
  ✓ Activated agent: architect

$ uws sdlc start
  ✓ SDLC started at: requirements

$ uws sdlc next
  ✓ Advanced to: design

$ uws checkpoint create "Architecture designed"
  ✓ Checkpoint created: CP_1_002 - Architecture designed

$ uws status
  Phase: phase_1_planning
  Agent: architect
  Checkpoint: CP_1_002
  SDLC: design

$ uws sdlc next && uws agent implementer
  ✓ Advanced to: implementation
  ✓ Activated agent: implementer
```

Run the full automated walkthroughs:
```bash
bash examples/python-ml-project/walkthrough.sh   # Research workflow (7 phases)
bash examples/nodejs-webapp/walkthrough.sh        # SDLC workflow (6 phases)
```

</details>

---

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`./tests/run_all_tests.sh`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Support

- **Issues**: [GitHub Issues](https://github.com/Yash-Sukhdeve/universal-workflow-system/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Yash-Sukhdeve/universal-workflow-system/discussions)

---

**Remember**: UWS adapts to you, not the other way around. Start simple, evolve as needed.
