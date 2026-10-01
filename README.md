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
- [Knowledge Base](#knowledge-base)
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
(`uws:uws-researcher`, `uws:uws-architect`, `uws:uws-implementer`, …) and a research
team (see [Research team](#research-team)).

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
| **Multi-Agent System** | 7 role subagents, dispatched per phase | `.claude/agents/`, `scripts/orchestrate.sh` |
| **SDLC Workflow** | Software development lifecycle | `scripts/sdlc.sh` |
| **Research Workflow** | Scientific method workflow | `scripts/research.sh` |
| **Claude Code Plugin** | Slash commands, hooks & subagents | `plugins/uws/` |
| **Gemini Integration** | Antigravity workflows | `antigravity-integration/` |
| **Vector Memory** | Semantic search across sessions | `scripts/lib/vector_memory_setup.sh` |
| **Dashboard** | Local review/PM page (change requests, board, active agent) | `dashboard/`, `uws dashboard` |
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
uws sdlc [cmd]               # SDLC workflow (status|start|next|fail|reset)
uws research [cmd]           # Research workflow (status|start|next|reject|reset)
uws orchestrate dispatch "<task>"   # Hand the current phase to its subagent
uws kb search <words>        # Project knowledge base (see Knowledge Base below)
uws dashboard                # Serve the review/PM dashboard on http://localhost:8080
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

# Hand the current phase to its subagent (writes the brief, records the agent)
./scripts/orchestrate.sh dispatch "Write the requirements"
```

**Script Reference:**

| Script | Purpose | Usage |
|--------|---------|-------|
| `init_workflow.sh` | Initialize UWS in project | `./scripts/init_workflow.sh` |
| `status.sh` | Show workflow status | `./scripts/status.sh` |
| `checkpoint.sh` | Manage checkpoints | `./scripts/checkpoint.sh create\|list\|restore` |
| `recover_context.sh` | Recover after breaks | `./scripts/recover_context.sh` |
| `orchestrate.sh` | Route a phase to its subagent | `./scripts/orchestrate.sh dispatch\|collect\|status` |
| `start_dashboard.sh` | Serve the review/PM dashboard | `./scripts/start_dashboard.sh` |
| `sdlc.sh` | SDLC workflow | `./scripts/sdlc.sh status\|start\|next` |
| `research.sh` | Research workflow | `./scripts/research.sh status\|start\|next` |

---

### 2. Multi-Agent System

Seven role agents, each a real Claude Code subagent (`.claude/agents/uws-<role>.md`,
generated from `docs/personas/` by `scripts/gen_subagents.sh` and shipped by the plugin).
They run in their own context; the main session does not role-play them.

| Agent | Icon | Used for |
|-------|------|----------|
| **Researcher** | 🔬 | Requirements, literature review, gap analysis |
| **Architect** | 🏗️ | System and API design |
| **Implementer** | 💻 | Code and tests |
| **Experimenter** | 🧪 | Verification, benchmarks |
| **Optimizer** | ⚡ | Performance work |
| **Deployer** | 🚀 | CI/CD, deployment |
| **Documenter** | 📝 | Documentation |

**Usage:**

```bash
# Hand the current SDLC/research phase to the agent that owns it: writes
# workspace/<role>/TASK.md, records the agent in state.yaml, prints a DISPATCH line
./scripts/orchestrate.sh dispatch "Write the requirements"

# After the subagent has written its artifact, stage it for human review
./scripts/orchestrate.sh collect "researcher: requirements"

# Which agent owns the current phase?
./scripts/orchestrate.sh status
```

In Claude Code, `/uws-orchestrate` runs this loop; `/agents` lists the subagents. The
earlier `activate_agent.sh` / `enable_skill.sh` (persona role-play and an enabled-skills
list) were retired; `uws agent` and `uws skill` now print a pointer here.

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

#### Research team

For work that has to hold up to review, UWS provides a research team led by the
`uws-research-lead` skill in your session. The team follows the Apocalypt persona
(`docs/personas/apocalypt.md`) and has six subagents: `uws-rt-scout` (finds sources and
proposes claims), `uws-rt-verifier` (checks each claim against its source, independently),
`uws-rt-methodologist` (pre-registers experiments and defines every metric),
`uws-rt-engineer` (data manifest, recorded runs, reproduction), `uws-rt-writer` (drafts text
only from verified ledger rows) and `uws-rt-redteam` (adversarial review). Their work is
recorded in plain-text ledgers under `research/`, and a deterministic checker (Python 3
standard library) checks those ledgers at every phase gate:

```bash
uws research check init              # scaffold research/ and bib_sources/ (no .workflow needed;
                                     # `uws init research` adds it for start/next)
uws research bib fetch doi:10.1371/journal.pcbi.1003285 --key sandve2013
uws research bib build               # references.bib only from bib_sources/
uws research check retraction --online      # cache Crossref retraction notices
uws research check plan new EXP-LEAK        # write the plan, then freeze and commit it
uws research check plan freeze EXP-LEAK     #   before any data or run exists
uws research check data add research/data/raw/x.csv --source ... --version 1 \
    --split '{"column": "split", "group_key": "scenario_id"}' \
    --origin measured                       # register every input (sha256, size)
uws research check run --exp EXP-LEAK --input research/data/raw/x.csv \
    --code analysis.py --output 'results_*.json' \
    -- python3 analysis.py                  # recorded in research/runs/
uws research check numbers add '{"macro": "\\AucCv", "output": "results_<stamp>.json",
    "pointer": "/auc", "rounding": "round:3", ...}'  # also: claims add '<json>'
uws research check repro all         # re-run in a scratch copy, compare each number
uws research check gate literature_review   # file:line findings; exit 1 blocks
uws research next                    # runs the gate; --force "<reason>" is logged,
                                     # and refused at publication
```

The checks enforce that no claim is verified by its own author, that ledgers are
append-only, that BibTeX is downloaded (never hand-written), that quotes appear verbatim in
the cached source, that every number in the paper comes from a generated macro traced to
an output file and its hash, and a set of "slop" rules (unsupported novelty, vague
attribution, placeholders, overclaimed causality, undisclosed simulated data, generator
labels called ground truth). They also check that each experiment's plan was frozen and
committed before its results, including any result a run's input was computed from (a
later change needs a PI decision), that every input is in
the data manifest with its hash and, when generated, its seed, that derived metrics match
their declared formula (for example FP / (FP + TN)), that cross-validation values are not
presented as held-out results, that every number reproduces from its recorded run, that the
red team reviewed the current manuscript, and that no verified claim rests on a source
Crossref lists as retracted (an unchecked source is a warning, never a pass). Ledger rows
are appended with `numbers add` / `claims add`, which validate them and never edit an
existing line; a hand-typed number is tied to its row through the row's `where`, and a split
declared as JSON is checked for one unit on both sides (leakage). The plugin command is
`/uws:research-check`. Design: `docs/design/research-team.md` (section 11b: what the first
field test, an audit of the PROMISE 2026 paper, changed).

---

## Knowledge Base

`uws kb` keeps what a project has learned in `docs/kb/`, tracked in git: one Markdown file
per claim, each with its source and, where possible, a command that re-checks it. Design:
[`docs/design/knowledge-base.md`](docs/design/knowledge-base.md).

```bash
uws kb pi --set you@example.com          # once, in your own terminal: who may promote
uws kb add --type fact --claim "The hook caps context at 1200 bytes" \
  --evidence verified --source file:scripts/lib/hook_context.sh:31 \
  --check "grep -q 'UWS_HOOK_MAX_BYTES:-1200' scripts/lib/hook_context.sh"
uws kb verify <ID>                       # run the check (the item stays a candidate)
uws kb approve <ID>                      # PI only: candidate -> trusted
uws kb search hook budget                # at most 5 lines: ID [type|status|evidence|date] claim (source)
uws kb verify --changed                  # re-check items whose watched files changed
uws kb prune                             # dry run of the removal rules; --apply to act
```

- New items are `candidate`s. Only the PI promotes them to `trusted`: `approve` checks that
  your `git config user.email` equals `kb.pi` in `.workflow/config.yaml` and refuses to run
  inside an AI agent (Claude Code's `CLAUDECODE` environment). Agents can `add`, `verify` and
  `recommend`; `uws kb review` lists what is waiting.
- `add` refuses items without a resolvable source (exit 2), duplicates (3), undeclared
  overlaps with trusted items (4) and anything that looks like a credential.
- Items become `stale` or `disputed` when their watched files change or their check fails,
  and `prune --apply` moves superseded, disproven, expired and never-promoted items to
  `docs/kb/retired/` with `git mv` (`uws kb restore <ID>` undoes it); imported items are
  excepted, since they wait for the PI's triage (decision D6). Every change is a line
  in `docs/kb/events.tsv`; nothing is committed for you.
- Session start adds one line (`KB: 12 trusted, 1 stale, ...`) inside the 1.2 KB context
  budget. In Claude Code, the `uws-kb` skill and `/uws:kb` command wrap the CLI.
  `/uws:kb search …` runs without a prompt. When Claude consults the knowledge base on its
  own, Claude Code asks once before running the plugin's `uws kb` command; approve it (or add
  it to your permission allow list). In non-interactive `claude -p` runs that request is
  denied, so allow it with `--allowedTools`.
- The approval gate is a process safeguard, not a security boundary: it keys on environment
  variables and your git e-mail, and every promotion is recorded in `events.tsv`, where
  `uws kb lint` flags a trusted item without a PI approval event.

### Meta-learning

Once `docs/kb/` exists, UWS's own scripts append one row per process outcome to
`docs/kb/outcomes.tsv`: `sdlc fail` / `research reject` (with the reason, which used to be
lost), `next` (deliverables done/total), `review approve|reject` (with the reason),
`orchestrate dispatch|collect` (role and the subagent's model), escaped bugs
(`uws kb add --type lesson --escaped-from <phase>`) and KB retirements. `uws kb learn` counts
them: the gate-escape rate per phase (proposes at > 20% of the last 10 passes), the first-pass
change-request rejection rate per role and model (> 40%), the disproven rate per evidence level
and capture channel (> 25%), and gate-failure reasons that repeat (3 or more). Only rows the
scripts wrote count, never candidate or inferred items, and each metric needs n >= 5. When one
crosses its threshold, `learn` writes a `proposal` candidate: the metric, n, the value, the
target file, the exact change as a diff, small-n and confounding caveats, and a falsifier.
`uws kb proposals` lists them, and the session-start line says when some are waiting.
Nothing changes without the PI: `uws kb approve <ID>` records acceptance but never applies the
change (that goes through a normal change request), and after approval `learn` watches the
same metric for 10 events and proposes a revert if it did not improve. `uws kb learn --dry-run`
shows what it would propose.

### Global knowledge base, imports and subagent briefs

A second, cross-project KB lives at `~/uws-global-knowledge/kb` (the directory is
`UWS_GLOBAL_MEMORY_DIR` or `global_memory_dir` in `~/.config/uws/config.yaml` when set). It must
be its own git repository, so every change stays reviewable and reversible; UWS refuses to
write to it otherwise.

```bash
uws kb init --global                     # create it and run git init (never commits)
uws kb pi --set you@example.com --global # its own PI, in your own terminal
uws kb add --global --type lesson --claim "macOS ships bash 3.2" --evidence reported \
  --source url:https://... --quote "..."  # prints global:K-20260930-1a2b3c
uws kb search bash                       # project and global items, one 5-line budget
uws kb approve global:K-20260930-1a2b3c  # global:ID reaches the global KB from any project
```

Global claims may not name project or home paths (`add` refuses, `lint` reports I8), and only
the global KB's PI promotes its items.

`uws kb import` turns the older memory stores into candidates for the PI to triage. It only
reads its sources (a vector-memory database is copied into memory through a read-only
connection; auto-memory files are read, and `MEMORY.md` is opened only with `--include-index`,
never written) and never makes anything trusted:

```bash
uws kb import vector --db memory/vector_memory.db --dry-run      # what it would add
uws kb import vector --db ~/uws-global-knowledge/memory/vector_memory.db --scope global
uws kb import automemory --dir ~/.claude/projects/<project>/memory
uws kb import automemory --dir ~/.claude/projects/<project>/memory --include-index --dry-run
                                         # also each entry of MEMORY.md (read only)
uws kb review --imported                 # the triage queue, with the steps to keep, correct,
                                         # refute (uws kb dispute) or drop each item
```

Duplicates collapse into one item, rows that look like secrets are skipped, preferences and
corrections stay in auto-memory, and rows that name concrete things (paths, file names,
snake_case names, backticked terms), none of which the project contains, are flagged
`suspected-fixture` (project imports only). `approve` refuses an import as it stands: the PI
restates it with a resolvable source (`uws kb add ... --supersedes <ID>`, repeating the claim
to keep it as it is), and approving the restatement retires the import. No rule retires an
import before the PI has reviewed it: `prune` skips imports, and a restatement or a dispute
takes effect only when the PI approves it (decision D6). The vector-memory servers and skills
keep running unchanged.

`uws orchestrate dispatch` adds up to 5 trusted items (1000 bytes) that share at least two
whole words with the task to the subagent's `TASK.md`, under a heading that calls them leads to
verify, not evidence. Searches, `show` and these briefs are logged per machine in
`docs/kb/.cache/usage.tsv` (gitignored). From that log, `uws kb prune` lists trusted items not
retrieved on this machine in the last 20 sessions (older than 90 days, decisions excepted) for
you to retire with `uws kb retire <ID> unused`, and `uws kb learn` measures the unused share and
proposes a shorter review window when it passes 50%.

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

# 4. Hand the current phase to its subagent
./scripts/orchestrate.sh dispatch "Implement user authentication"

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
| `/uws-orchestrate` | Dispatch the current phase to its subagent |
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
| Core Scripts | 701 | BATS |

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
│   ├── agents/                 # Agent registry
│   └── checkpoints/            # Checkpoint snapshots
├── scripts/                    # Core workflow scripts
│   ├── lib/                    # Utility libraries
│   │   └── vector_memory_setup.sh  # Vector memory installer
│   ├── init_workflow.sh        # Initialize workflow
│   ├── status.sh               # Show status
│   ├── checkpoint.sh           # Manage checkpoints
│   ├── sdlc.sh                 # SDLC workflow
│   ├── research.sh             # Research workflow
│   └── orchestrate.sh          # Phase -> subagent dispatch
├── dashboard/                  # Static review/PM dashboard (uws dashboard)
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

$ uws sdlc start
  ✓ SDLC started at: requirements

$ uws orchestrate dispatch "Write the requirements"
  ✓ Prepared dispatch for researcher (sdlc:requirements)
  DISPATCH: agent=researcher subagent=.claude/agents/uws-researcher.md ...

$ uws sdlc next
  ✓ Advanced to: design

$ uws checkpoint create "Architecture designed"
  ✓ Checkpoint created: CP_1_002 - Architecture designed

$ uws status
  Phase: phase_1_planning
  Agent: researcher
  Checkpoint: CP_1_002
  SDLC: design

$ uws sdlc next && uws orchestrate dispatch "Build the parser"
  ✓ Advanced to: implementation
  ✓ Prepared dispatch for implementer (sdlc:implementation)
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
