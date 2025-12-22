# Universal Workflow System (UWS) v1.0.0

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](#)
[![Tests](https://img.shields.io/badge/tests-361%20passing-green.svg)](#testing)

**Context-preserving workflow system for AI-assisted development.** Maintains state across sessions, survives context resets, and works with any project type.

---

## Table of Contents

- [Quick Start](#quick-start)
- [What's Included](#whats-included)
- [Installation](#installation)
- [Core Components](#core-components)
  - [1. Workflow Scripts](#1-workflow-scripts)
  - [2. Company OS (Backend + Dashboard)](#2-company-os-backend--dashboard)
  - [3. Multi-Agent System](#3-multi-agent-system)
  - [4. SDLC & Research Workflows](#4-sdlc--research-workflows)
- [Usage Guide](#usage-guide)
- [Testing](#testing)
- [Architecture](#architecture)
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

### Option 2: Full Installation

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git
cd universal-workflow-system

# Initialize workflow in current project
./scripts/init_workflow.sh

# Check status
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
| **Test Suite** | 361+ BATS/Python/React tests | `tests/` |

---

## Installation

### Prerequisites

- **Bash 4.0+** (or 3.x for basic features)
- **Git** for version control
- **Node.js 18+** (for dashboard)
- **Python 3.9+** (for backend)

### Step 1: Clone Repository

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git
cd universal-workflow-system
```

### Step 2: Initialize Workflow

```bash
./scripts/init_workflow.sh
```

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

# Required variables:
SECRET_KEY=your-secret-key-here
DATABASE_URL=sqlite:///./company_os.db
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
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
hypothesis → experiment_design → data_collection → analysis → publication
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
./scripts/handoff.sh  # or manually edit .workflow/handoff.md
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
| Core Scripts | 361 | BATS |
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
SECRET_KEY=your-secret-key-change-in-production
DEBUG=true
LOG_LEVEL=INFO

# Database
DATABASE_URL=sqlite:///./company_os.db

# Authentication
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# WebSocket
WS_HEARTBEAT_INTERVAL=30

# CORS
CORS_ORIGINS=http://localhost:5173,http://localhost:4173
```

### MCP Configuration (.mcp.json)

For Claude Code MCP integration:

```json
{
  "servers": {
    "company-os": {
      "command": "python",
      "args": ["-m", "company_os.api.main"],
      "env": {
        "DATABASE_URL": "sqlite:///./company_os.db"
      }
    }
  }
}
```

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
