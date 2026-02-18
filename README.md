# Universal Workflow System (UWS) v1.1.0

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](#)
[![Tests](https://img.shields.io/badge/tests-662%20passing-green.svg)](#testing)
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

### Option 1: Claude Code Integration (Recommended)

```bash
# In your project directory:
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash

# Start Claude Code
claude

# Your context loads automatically. Use these commands:
/uws-status              # Check current state
/uws-checkpoint "msg"    # Save progress
/uws-recover             # Full context recovery
/uws-handoff             # Prepare for session end
```

### Option 2: CLI Installation

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git
cd universal-workflow-system
./install.sh    # Symlinks 'uws' to ~/.local/bin

# In your project directory:
uws init        # Initialize workflow
uws status      # Check status
```

### Option 3: Manual (no install)

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git
cd universal-workflow-system
./scripts/init_workflow.sh
./scripts/status.sh
```

---

## What's Included

| Component | Description | Location |
|-----------|-------------|----------|
| **Workflow Scripts** | Core Bash scripts for state management | `scripts/` |
| **Company OS Backend** | FastAPI with event sourcing | `company_os/api/` |
| **React Dashboard** | Real-time monitoring UI | `company_os/dashboard/` |
| **Multi-Agent System** | 7 specialized AI agents | `.workflow/agents/` |
| **SDLC Workflow** | Software development lifecycle | `scripts/sdlc.sh` |
| **Research Workflow** | Scientific method workflow | `scripts/research.sh` |
| **Claude Code Plugin** | Slash commands & hooks | `.claude/` |
| **Gemini Integration** | Antigravity workflows | `antigravity-integration/` |
| **Vector Memory** | Semantic search across sessions | `scripts/lib/vector_memory_setup.sh` |
| **Test Suite** | 662+ BATS tests | `tests/` |

---

## Installation

### Prerequisites

- **Bash 4.0+** (or 3.x for basic features)
- **Git** for version control
- **Node.js 18+** (optional — only for Company OS dashboard)
- **Python 3.9+** (optional — for vector memory and Company OS backend)

### Step 1: Clone Repository

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git
cd universal-workflow-system
```

### Step 2: Initialize Workflow

```bash
./scripts/init_workflow.sh
```

During initialization, UWS will offer to install the vector memory server for semantic search across sessions. This requires Python 3.9+ and ~1.5GB of disk space. You can skip it with `UWS_SKIP_VECTOR_MEMORY=true` or install it later by running `./scripts/lib/vector_memory_setup.sh`.

### Step 3: (Optional) Start Company OS

```bash
# Install Python dependencies
pip install -r requirements.txt

# Start backend
./scripts/start_company_os.sh

# In another terminal, start dashboard
cd company_os/dashboard
npm install
npm run dev
```

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
uws company-os start         # Start Company OS backend
uws company-os dashboard     # Start React dashboard
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

### 2. Company OS (Backend + Dashboard)

Full-stack application for task management, agent monitoring, and memory storage.

#### Backend (FastAPI)

```bash
# Install dependencies
pip install -r requirements.txt

# Start server
uvicorn company_os.api.main:app --reload --port 8000

# Or use the convenience script
./scripts/start_company_os.sh
```

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/health` | GET | Health check |
| `/api/v1/auth/login` | POST | User authentication |
| `/api/v1/auth/register` | POST | User registration |
| `/api/v1/tasks` | GET/POST | Task management |
| `/api/v1/agents` | GET | List agents |
| `/api/v1/agents/{name}/activate` | POST | Activate agent |
| `/api/v1/memory` | GET/POST | Memory storage |
| `/ws` | WebSocket | Real-time updates |

**Environment Configuration (.env):**

```bash
# Copy example and configure
cp .env.example .env

# Key variables:
JWT_SECRET_KEY=your-super-secret-key-change-in-production
DATABASE_URL=postgresql://company_os:dev_password@localhost:5432/company_os
ACCESS_TOKEN_EXPIRE_MINUTES=15
```

#### Dashboard (React + Vite)

```bash
cd company_os/dashboard

# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Run tests
npm run test
```

**Dashboard Features:**

- **Dashboard Page** - Overview with statistics and quick actions
- **Tasks Page** - Create, manage, complete tasks with filtering
- **Agents Page** - Activate/deactivate agents, view status
- **Memory Page** - Store and search organizational memory
- **Settings Page** - Configure preferences

**Access:** Open http://localhost:5173 (dev) or http://localhost:4173 (preview)

---

### 3. Multi-Agent System

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

### 4. SDLC & Research Workflows

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

### Dashboard Tests

```bash
cd company_os/dashboard

# Run unit tests (Vitest)
npm run test

# Run E2E tests (Playwright)
npm run test:e2e

# Run with coverage
npm run test -- --coverage
```

### Backend Tests

```bash
# Run Python tests
pytest tests/unit/company_os/ -v

# Run integration tests
pytest tests/integration/company_os/ -v
```

**Test Coverage:**

| Component | Tests | Framework |
|-----------|-------|-----------|
| Core Scripts | 662+ | BATS |
| Dashboard Unit | 123 | Vitest |
| Dashboard E2E | 64 | Playwright |
| Backend Unit | 50+ | Pytest |

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
├── company_os/                 # Company OS application
│   ├── api/                    # FastAPI backend
│   │   ├── main.py             # Application entry
│   │   ├── routes/             # API endpoints
│   │   └── security.py         # Auth & security
│   ├── core/                   # Business logic
│   │   ├── auth/               # Authentication
│   │   ├── events/             # Event sourcing
│   │   └── memory/             # Memory service
│   └── dashboard/              # React frontend
│       ├── src/
│       │   ├── components/     # React components
│       │   ├── contexts/       # Auth & WebSocket contexts
│       │   ├── hooks/          # Custom hooks
│       │   ├── pages/          # Page components
│       │   └── services/       # API services
│       └── e2e/                # E2E tests
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
├── docs/                       # Documentation
└── migrations/                 # Database migrations
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

### Event Sourcing

Company OS uses event sourcing for state management:

```
Event → Store → Projection → Read Model
```

All state changes are recorded as immutable events, enabling:
- Full audit trail
- Time-travel debugging
- Event replay for recovery

---

## Environment Configuration

### .env.example

```bash
# Application
APP_NAME=Company OS
DEBUG=true
ENVIRONMENT=development

# Database
DATABASE_URL=postgresql://company_os:dev_password@localhost:5432/company_os
DATABASE_POOL_SIZE=10

# Authentication
JWT_SECRET_KEY=your-super-secret-key-change-in-production
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=7

# Server
HOST=0.0.0.0
PORT=8000

# CORS
CORS_ORIGINS=["http://localhost:3000","http://localhost:8080"]
```

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
