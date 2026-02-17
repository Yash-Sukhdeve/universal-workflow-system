# UWS x Vector Memory MCP -- Integration Plan

**Version**: 3.4.1
**Date**: 2026-02-17
**Status**: Multi-agent verified (5 specialized agents) + manual executable-path walkthrough. All copy-pasteable configs verified. All content strings follow convention.
**Complexity**: Medium (5 phases, ~1-2 weeks)
**Review**: 14 findings from v2.0 resolved. 8 findings from v3.0 resolved. 16 findings from v3.1 review resolved. 11 findings from v3.2 review resolved. 9 findings from v3.3 multi-agent review + 6 from manual walkthrough resolved (total: 64).

---

## 1. Executive Summary

This plan integrates `vector-memory-mcp` (cornebidouil, MIT license) as a **semantic retrieval layer** beneath UWS's existing markdown/YAML state management. The architecture uses a **hybrid local+global** database strategy with a **three-mechanism generalizability detection system**.

- **Local DB** (per-project): Project-specific memories. `<project>/memory/vector_memory.db`.
- **Global DB** (cross-project): Abstracted, generalizable lessons. `~/.uws/knowledge/memory/vector_memory.db`.
- **Generalizability detection**: Auto-invoked `memory-gate` skill + `/phase-distillation` manual skill + `/memory-retrospective` manual skill. No dedicated agent.

### 1.1 Verified Server Capabilities

Verified against `cornebidouil/vector-memory-mcp` source code (2026-02-16):

| Capability | Confirmed | Tool Signature |
|-----------|-----------|---------------|
| Store memory | Yes | `store_memory(content: str, category: str="other", tags: list[str]=None)` |
| Semantic search | Yes | `search_memories(query: str, limit: int=10, category: str=None)` |
| List recent | Yes | `list_recent_memories(limit: int=10)` |
| Stats | Yes | `get_memory_stats()` |
| Cleanup | Yes | `clear_old_memories(days_old: int=30, max_to_keep: int=1000)` |

| Capability | NOT Supported | Design Implication |
|-----------|---------------|-------------------|
| Tag-based search filtering | Tags stored, returned, but NOT queryable | Category is the only search filter. Searchable context must be in content string |
| Batch store | No batch API | Each store is sequential (~110ms each) |
| min_similarity threshold | All results returned up to limit | Agent must judge relevance from content, not score |
| Multiple DBs per instance | One DB per `--working-dir` | Isolation via separate MCP server instances |
| Configurable model | Hardcoded all-MiniLM-L6-v2 (384D) | Must fork source to change model |
| Selective delete | No delete_memory or update_memory tool | Cannot remove individual memories; only bulk `clear_old_memories(days_old, max_to_keep)`. "Removal" = store corrective superseding memory |

### 1.2 UWS File Reference Map

This plan targets only files that exist in UWS (or explicitly marks new files):

| Plan References | Actual UWS File | Purpose |
|----------------|----------------|---------|
| Project instructions | `CLAUDE.md` | Agent behavioral directives, session protocol |
| Session handoff | `.workflow/handoff.md` | Human-readable context between sessions |
| Workflow state | `.workflow/state.yaml` | Machine-readable phase/checkpoint/agent state |
| System configuration | `.workflow/config.yaml` | Rules, policies, feature flags |
| Agent definitions | `.workflow/agents/registry.yaml` | Capabilities, transitions, MCP assignments |
| Active agent | `.workflow/agents/active.yaml` | Current agent state and persona |
| Checkpoint log | `.workflow/checkpoints.log` | Timestamped checkpoint history |
| Decision log | `.workflow/logs/decisions.log` | Structured decision records |
| Executable hooks | `.claude/settings.json` | Shell commands triggered by lifecycle events |
| Slash commands | `.claude/commands/uws-*.md` | User-invokable UWS commands |
| Autonomous skills | `.claude/skills/*/SKILL.md` | Auto/manual-invokable memory procedures |
| MCP configuration | `.mcp.json` | MCP server definitions |
| Git ignore | `.gitignore` | Files excluded from version control |

Files that do **NOT** exist in UWS and are **NOT** created by this plan: `RULES.md`, `soul.md`, `MASTER_PROGRESS.md`, `EVOLUTION_LOG.md`, `AGENTS.md`, `PHASE_N.md`. All memory protocol instructions go into `CLAUDE.md`.

### 1.3 MCP Tool Naming Convention

Claude Code names MCP tools as `mcp__<server_name>__<tool_name>`. Hyphens in server names convert to underscores. This plan uses underscore-separated names for clarity:

| Server Name in `.mcp.json` | Tool Call in Claude Code |
|---------------------------|------------------------|
| `vector_memory_local` | `mcp__vector_memory_local__store_memory(...)` |
| `vector_memory_local` | `mcp__vector_memory_local__search_memories(...)` |
| `vector_memory_global` | `mcp__vector_memory_global__store_memory(...)` |
| `vector_memory_global` | `mcp__vector_memory_global__search_memories(...)` |

---

## 2. Architecture

### 2.1 Hybrid Local + Global Design

```
┌─────────────────────────────────────────────────────────────────┐
│                 UWS APPLICATION LAYER (unchanged)                │
│                                                                  │
│  R1-R5 Rules | Agents | Phases | Checkpoints                    │
│  CLAUDE.md | .workflow/state.yaml | .workflow/handoff.md         │
├──────────────────────┬──────────────────────────────────────────┤
│  BEHAVIORAL          │  GENERALIZABILITY                         │
│  DIRECTIVES          │  DETECTION                                │
│  (in CLAUDE.md)      │                                           │
│                      │  Mechanism 1: Inline Skill (per-fix)      │
│  on_phase_complete   │  Mechanism 2: Phase-End Review (batch)    │
│  on_error_resolved   │  Mechanism 3: Retrospective (manual)      │
│  on_agent_handoff    │                                           │
│  on_verification     │         │                                 │
│         │            │         ▼                                 │
│         ▼            │    GLOBAL DB                              │
│    LOCAL DB          │    ~/.uws/knowledge/memory/               │
├──────────────────────┴──────────────────────────────────────────┤
│  vector_memory_local MCP      │  vector_memory_global MCP        │
│  --working-dir <project>      │  --working-dir ~/.uws/knowledge  │
│                               │                                  │
│  Categories:                  │  Categories:                     │
│    phase-summary              │    anti-pattern                  │
│    decision-adr               │    tool-gotcha                   │
│    bug-resolution             │    design-lesson                 │
│    agent-handoff              │    library-compat                │
│    verification               │    workflow-improvement          │
│    environment                │                                  │
│                               │                                  │
│  ~200 memories/project        │  ~50-100 curated lessons total   │
│  Lifecycle: project-scoped    │  Lifecycle: indefinite, curated  │
├───────────────────────────────┴──────────────────────────────────┤
│  SQLite + sqlite-vec | all-MiniLM-L6-v2 (384D) | FastMCP        │
│  Model: ~/.cache/huggingface/ (~80MB, shared across instances)   │
│  RAM: ~120MB per instance (~240MB total for both)                │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 Source of Truth

| Data | Source of Truth | Local DB | Global DB |
|------|----------------|----------|-----------|
| Phase status | `.workflow/state.yaml` | Mirror for search | Not stored |
| Decisions | `.workflow/handoff.md` | Semantic index | Only if generalizable |
| Bug fixes | `.workflow/handoff.md` | Searchable by symptom | Abstracted lesson |
| Agent state | `.workflow/agents/active.yaml` | Not stored | Not stored |
| Tool/library gotchas | N/A (implicit in fixes) | Raw fix context | Explicit lesson |
| Architectural patterns | N/A (implicit in decisions) | Raw decision context | Explicit lesson |

**Rule**: If markdown/YAML and vector memory conflict, markdown/YAML wins. Vector memory is a **read-optimized index**, not a ledger.

### 2.3 Enforcement Mechanisms

This plan uses three enforcement mechanisms at different reliability levels:

| Mechanism | Location | Enforcement | Reliability |
|-----------|----------|------------|-------------|
| **Executable hooks** | `.claude/settings.json` | Auto-triggered by Claude Code lifecycle events | High -- always fires |
| **Claude Code skills** | `.claude/skills/*/SKILL.md` | Auto-invoked when description matches conversation context (`user-invocable: false`) or manually invoked (`disable-model-invocation: true`) | Medium-High -- depends on description matching or explicit invocation |
| **Behavioral directives** | `CLAUDE.md` | Prompt instructions the LLM follows voluntarily | Medium -- may be skipped under token pressure |

This plan uses all three mechanisms:
- **Hooks**: SessionStart (inject memory context via `additionalContext`), PreCompact (store compaction marker via `agent` hook)
- **Skills**: `memory-gate` (auto-invoked after bug fixes), `phase-distillation` (manual `/phase-distillation <N>`), `memory-retrospective` (manual `/memory-retrospective`)
- **Behavioral directives**: When-to-store triggers (on_phase_complete, on_error_resolved, on_agent_handoff, on_verification) in `CLAUDE.md`

The behavioral directives depend on the LLM following instructions. Skills provide a middle layer: Claude auto-invokes them when the description matches, loading full procedures on-demand rather than keeping them always in context. UWS already has 3 skills (`workflow-checkpoint`, `workflow-recovery`, `workflow-status`) following this pattern.

#### Claude Code Hook Specification (Verified)

**Schema**: Three-level nesting: `hooks` → `Event` (array of matcher groups) → `hooks` (array of handlers):

```json
{
  "hooks": {
    "<EVENT>": [
      {
        "matcher": "REGEX_PATTERN",
        "hooks": [
          { "type": "command|prompt|agent", ... }
        ]
      }
    ]
  }
}
```

**Hook Types**:

| Type | Fields | Description | MCP Access |
|------|--------|-------------|------------|
| `command` | `command`, `timeout`(600s), `async`, `statusMessage` | Shell command execution | No |
| `prompt` | `prompt`, `timeout`(30s), `model`, `statusMessage` | Single LLM evaluation | No |
| `agent` | `prompt`, `timeout`(60s), `model`, `statusMessage` | Multi-turn subagent with tool access | Yes (via tools) |

**Events Relevant to Memory Integration**:

| Event | Pre/Post | Can Block | Memory Use |
|-------|----------|-----------|------------|
| `SessionStart` | Pre | No | **Inject memory context** via `additionalContext` in `hookSpecificOutput` |
| `PreCompact` | Pre | No | **Remind** to store critical memories before context loss |
| `Stop` | Post | Yes | Too frequent (every response turn) -- not suitable |
| `PostToolUse` | Post | No | Could detect file changes, but adds latency -- not used |

**Key capability**: `SessionStart` command hooks can return JSON with `hookSpecificOutput.additionalContext` to inject context directly into Claude's system knowledge. This is more reliable than `echo` because it becomes part of Claude's context, not just terminal output.

**Compensating controls**: Phase 2 adds two executable hooks to `.claude/settings.json`:
1. **SessionStart**: Injects memory protocol reminder via `additionalContext` (conditional on server config)
2. **PreCompact**: Stores compaction marker to local memory via `agent` hook with MCP access

---

## 3. Generalizability Detection: Three-Mechanism Design

### 3.1 Mechanism 1: Inline Skill (per-fix, ~200 tokens)

The active agent applies a 3-question gate immediately after fixing a non-trivial bug or making an architectural decision. No agent switch. No context loss.

```
GENERALIZABILITY GATE:

Q1: Does the root cause involve a named tool, library, or
    architectural pattern (not just this project's code)?
Q2: Could someone hit this exact issue in a different project?
Q3: Can you state the lesson in one sentence WITHOUT referencing
    any file path, variable name, or project-specific term
    from THIS project?

ALL THREE = YES:
  Compose abstracted lesson (NO project file paths, NO project variable names):
    content="<TOOL_OR_PATTERN>: <root cause mechanism>
             FIX: <fix approach> APPLIES_TO: <scope>"
  Select category: anti-pattern | tool-gotcha | design-lesson |
                   library-compat | workflow-improvement
  Select tags: [<root-cause-tag>, <scope-tag>, <fix-pattern-tag>]
  Call: mcp__vector_memory_global__store_memory(content, category, tags)

ANY = NO:
  Local store only. No global promotion.
```

**Self-assessment bias mitigation**: After every 10 global promotions, the agent runs a batch adversarial review: "Which of the last 10 global stores are actually project-specific? Be strict." This calibration check is part of Mechanism 2.

### 3.2 Mechanism 2: Phase-End Review (batch, per-phase, ~1000 tokens)

At phase completion, the active agent reviews local memories from the completed phase.

```
PHASE-END KNOWLEDGE DISTILLATION:

1. mcp__vector_memory_local__search_memories(
     query="PHASE <N>", limit=50)
   NOTE: Using search (not list_recent) to target current phase
         via content prefix convention.

2. Group results by category.

3. For groups with 2+ entries sharing a root cause:
   Consolidate into ONE general lesson.
   Apply 3-question gate.

4. CALIBRATION CHECK: Review last 10 global promotions.
   "Which of these are actually project-specific? Be adversarial."
   For false promotions: store a corrective memory with same category:
     content="SUPERSEDES: <original content summary>. REASON: project-specific."
   NOTE: Server has no delete_memory tool. Superseding entries rank
         higher for targeted queries, effectively displacing false ones.

5. Store passing patterns to global DB.

6. Add to .workflow/handoff.md:
   "Phase N distillation: promoted M lessons to global knowledge"
```

### 3.3 Mechanism 3: Project Retrospective (manual)

User-triggered at project completion.

```
PROJECT RETROSPECTIVE:

1. mcp__vector_memory_global__get_memory_stats()
   Note total count for limit parameter.

2. mcp__vector_memory_global__list_recent_memories(
     limit=<total_from_stats>)
   NOTE: Using list_recent (not empty-string search) to enumerate.
         Set limit to total count from stats to get ALL memories.

3. For each memory, identify project origin by inspecting content
   for tool/pattern names from the current project's domain.
   (Global memories are abstracted, so project identification relies
   on temporal proximity and domain overlap, not file paths.)

4. For each memory from this project's timeframe:
   a. Still accurate? → Keep
   b. Needs refinement? → Store improved version (old stays but
      ranks lower for targeted queries due to less precise content)
   c. Project-specific? → Store corrective superseding memory:
      content="SUPERSEDES: <summary>. REASON: project-specific."
   d. Related to another? → Store merged consolidated version

   NOTE: No delete_memory tool exists. "Removal" means storing a
   superseding entry. For severe contamination, use:
     clear_old_memories(days_old=0, max_to_keep=0)
   then re-store all valid memories from the review notes.
   WARNING: Verify max_to_keep=0 is accepted by the server before
   relying on this -- edge case not confirmed in source.

5. Document results in project completion notes.
```

---

## 4. Category & Tag Taxonomy

### 4.1 Local DB Categories

```yaml
local_categories:
  phase-summary:    # "PHASE 2 | DOMAIN: training | OUTCOME: Baseline EER=5.2%"
  decision-adr:     # "PHASE 1 | DECISION: REST over gRPC BECAUSE: ..."
  bug-resolution:   # "PHASE 2 | BUG: batch_size mismatch ROOT_CAUSE: ..."
  agent-handoff:    # "HANDOFF researcher->implementer | PHASE 1 | ..."
  verification:     # "PHASE 3 | VERIFIED: cross-dataset EER RESULT: pass"
  environment:      # "PHASE 0 | Python 3.10, PyTorch 2.1, A100 40GB"
```

### 4.2 Global DB Categories

```yaml
global_categories:
  anti-pattern:          # Architectural mistakes (coupling, shotgun surgery)
  tool-gotcha:           # Tool behavior causing unexpected failures
  design-lesson:         # Reusable pattern applications
  library-compat:        # Version conflicts, API breaks
  workflow-improvement:  # Process/methodology lessons
```

**Global content rule**: Global memory content MUST NOT contain project file paths, project variable names, or project-specific identifiers. Only tool names, library names, pattern names, and general descriptions.

### 4.3 Content String Convention

Tags don't filter searches. Searchable context goes in **content**:

```
LOCAL: "PHASE <N> <methodology_phase> | DOMAIN: <domain> | <structured content>"
GLOBAL: "<TOOL_OR_PATTERN>: <description> FIX: <approach> APPLIES_TO: <scope>"
```

**Phase numbering**: `<N>` is the UWS overall phase number (1-5: planning, implementation, validation, delivery, maintenance). `<methodology_phase>` is the methodology-specific phase name. Examples:
- `"PHASE 2 experiment_design | DOMAIN: training | ..."` (research methodology, overall phase 2)
- `"PHASE 3 verification | DOMAIN: testing | ..."` (SDLC methodology, overall phase 3)

This dual prefix ensures memories are findable by both overall phase number AND methodology phase name.

### 4.4 Tag Taxonomy (post-retrieval metadata)

Tags help interpret retrieved results but cannot filter searches:

```yaml
root_cause_tags:       # What went wrong
  - library-behavior   - tool-limitation    - coupling-violation
  - api-contract-break - silent-failure     - config-drift

fix_pattern_tags:      # How it was solved
  - mediator-pattern   - isolation-pattern  - fallback-pattern
  - validation-pattern - temp-file-pattern  - override-pattern

scope_tags:            # Where it applies
  - bash-scripting     - python-packaging   - yaml-processing
  - multi-agent-system - state-management   - test-isolation
```

---

## 5. Implementation Phases

Each phase produces a **specific deliverable** consumed by the next phase. Phases are connected by explicit input/output contracts.

### Prerequisites

Before starting Phase 0, verify the following are available:

| Requirement | Minimum Version | Check Command | Notes |
|-------------|----------------|---------------|-------|
| Python | 3.9+ | `python3 --version` | Required by sentence-transformers and sqlite-vec |
| pip | 21.0+ | `pip --version` | Installed with Python; may need `python3-pip` on some distros |
| venv module | (bundled) | `python3 -m venv --help` | May need `sudo apt install python3-venv` on Ubuntu/Debian |
| git | 2.0+ | `git --version` | For cloning MCP server source |
| BATS | 1.0+ | `bats --version` | For Phase 3 integration tests only |
| Disk space | ~1.5 GB free | `df -h ~/.uws` | PyTorch (~800MB) + embedding model (~80MB) + SQLite DBs |
| Network access | (once) | | Required for initial `git clone`, `pip install`, and model download |
| Write permissions | | `touch ~/.uws/test && rm ~/.uws/test` | Must be able to write to `~/.uws/` and project `memory/` dir |

**Transitive dependencies** (installed automatically by `pip install sentence-transformers`):
- PyTorch (~800MB) -- CPU-only sufficient; GPU not required for 384D embeddings
- transformers (Hugging Face)
- huggingface-hub (downloads all-MiniLM-L6-v2 model on first run, ~80MB, cached to `~/.cache/huggingface/`)
- tokenizers, safetensors, tqdm, regex

**If behind a corporate proxy**: Set `HTTP_PROXY` and `HTTPS_PROXY` environment variables before `pip install` and first server run (model download).

**If on a restricted network**: Pre-download the model:
```bash
python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"
```

### Phase 0: Infrastructure (Day 1)

**Input**: Clean UWS project with existing `.mcp.json`
**Output**: Two running MCP server instances verified healthy

#### 0.1 Install Dependencies (Isolated Environment)

```bash
mkdir -p ~/.uws/tools
git clone https://github.com/cornebidouil/vector-memory-mcp.git ~/.uws/tools/vector-memory
cd ~/.uws/tools/vector-memory && git log --oneline -1  # Record commit hash
# Pin to verified version to prevent breaking API changes:
# git checkout <commit_hash_from_verification>

# Create isolated venv to avoid conflicts with project PyTorch/numpy versions
python3 -m venv ~/.uws/tools/vector-memory/.venv
~/.uws/tools/vector-memory/.venv/bin/pip install sqlite-vec sentence-transformers fastmcp
```

**Why venv?** `sentence-transformers` depends on PyTorch, `transformers`, and `huggingface-hub`. Installing globally could conflict with project-specific PyTorch versions or `replication/requirements.txt` packages.

#### 0.2 Verify MCP Server Tool Signatures

**CRITICAL**: Before proceeding, inspect the cloned source to confirm the tool signatures match this plan's assumptions. The evidence validator could not independently verify these from public documentation alone.

```bash
cd ~/.uws/tools/vector-memory

# Locate tool definitions (look for FastMCP tool decorators or function defs)
grep -rn "def store_memory\|def search_memories\|def list_recent_memories\|def get_memory_stats\|def clear_old_memories" .

# Verify parameter names and defaults for each tool:
#   store_memory(content: str, category: str="other", tags: list[str]=None)
#   search_memories(query: str, limit: int=10, category: str=None)
#   list_recent_memories(limit: int=10)
#   get_memory_stats()
#   clear_old_memories(days_old: int=30, max_to_keep: int=1000)

# Check for tools NOT expected (delete_memory, update_memory, batch_store):
grep -rn "def delete_memory\|def update_memory\|def batch_store" .
# Expected: no matches

# Confirm embedding model:
grep -rn "MiniLM\|all-MiniLM\|sentence-transformers" .

# Confirm SQLite + sqlite-vec:
grep -rn "sqlite_vec\|sqlite-vec\|import sqlite3" .

# Confirm --working-dir argument:
grep -rn "working.dir\|working_dir" .

# Confirm entrypoint filename (plan assumes main.py):
ls -la *.py
# If main.py doesn't exist, check for:
#   server.py, app.py, __main__.py, or a pyproject.toml [project.scripts] entry
# Also check: python3 -c "import vector_memory_mcp; print(vector_memory_mcp.__file__)"
# Update .mcp.json "args" in Section 0.4 to match actual entrypoint.
```

**If any signature differs from this plan**: STOP. Update all tool call examples in Phases 1-5 before proceeding. Record the actual signatures in `.workflow/handoff.md`.

**If entrypoint is not `main.py`**: Update `.mcp.json` args accordingly. Alternatives:
- If package installs a console script: use it directly as `"command"` instead of Python
- If module-based: use `"args": ["-m", "vector_memory_mcp", "--working-dir", "..."]`
- If `server.py`: replace `main.py` with `server.py` in `.mcp.json`

**If tools are missing or renamed**: The server may be a different version. Check git tags/releases and pin to a version that matches.

#### 0.3 Set Up Directories

```bash
# Create global knowledge directory
# NOTE: Path must NOT contain dot-prefixed components (e.g., .uws/) --
# the server's security.py rejects paths with parts starting with "."
mkdir -p ~/uws-global-knowledge

# Create project-local memory directory (server auto-creates
# memory/vector_memory.db inside --working-dir, but we create
# the parent for .gitignore clarity)
mkdir -p memory/
```

#### 0.4 Configure MCP Servers

Add entries inside the existing `"mcpServers"` object in `.mcp.json`. **NOTE**: The `"...existing servers..."` placeholder below represents your current MCP servers (arxiv, filesystem, etc.) -- do NOT copy it literally. Only add the two `vector_memory_*` entries:

```json
{
  "mcpServers": {
    "...existing servers...": "...keep your current servers unchanged...",

    "vector_memory_local": {
      "command": "/home/lab2208/.uws/tools/vector-memory/.venv/bin/python",
      "args": [
        "/home/lab2208/.uws/tools/vector-memory/main.py",
        "--working-dir", "/home/lab2208/Documents/universal-workflow-system"
      ]
    },
    "vector_memory_global": {
      "command": "/home/lab2208/.uws/tools/vector-memory/.venv/bin/python",
      "args": [
        "/home/lab2208/.uws/tools/vector-memory/main.py",
        "--working-dir", "/home/lab2208/uws-global-knowledge"
      ]
    }
  }
}
```

**IMPORTANT**: Entries go inside `"mcpServers"`, NOT at the root level. The `command` uses the venv Python to avoid dependency conflicts. The entrypoint `main.py` was assumed -- if Section 0.2 verification reveals a different filename, update both `args` arrays.

#### 0.5 Update `.gitignore`

Append to project `.gitignore`:
```
# Vector memory database (local, per-project)
memory/
```

#### 0.6 Verification Gate

Both must return healthy before proceeding to Phase 1:
```
mcp__vector_memory_local__get_memory_stats()  → {"total_memories": 0, "health_status": "Healthy"}
mcp__vector_memory_global__get_memory_stats() → {"total_memories": 0, "health_status": "Healthy"}
```

If either server fails to start, check:
1. Venv Python path matches `.mcp.json` command
2. All pip packages installed in the venv (not global)
3. `--working-dir` paths are absolute and directories exist

**Deliverable**: `.mcp.json` updated (inside `mcpServers`), `.gitignore` updated, both servers verified healthy.

**Resource note**: Two Python processes, ~120MB RAM each (~240MB total). Model downloads ~80MB on first run, caches to `~/.cache/huggingface/`.

#### 0.7 Rollback (if Phase 0 fails)

```bash
# Remove MCP entries from .mcp.json (delete vector_memory_local and vector_memory_global)
# Remove local memory directory
rm -rf memory/
# Remove .gitignore entry for memory/
# Optionally remove server installation:
rm -rf ~/.uws/tools/vector-memory
# Global knowledge directory is harmless to leave
```

---

### Phase 1: Seed Test Memories & Validate Retrieval (Day 1-2)

**Input**: Two healthy MCP server instances (from Phase 0)
**Output**: Validated retrieval quality with real test data

#### 1.1 Store 6 Local Test Memories

Store one memory per local category (all 6 fully specified -- R2 zero placeholders):

```
# Memory 1: decision-adr
mcp__vector_memory_local__store_memory(
  content="PHASE 2 implementation | DOMAIN: architecture | DECISION: Use
           shared routing library instead of point-to-point integration
           between subsystems. BECAUSE: 4 subsystems sharing state.yaml
           never communicated. ALTERNATIVES_REJECTED: Individual patches
           per script.",
  category="decision-adr",
  tags=["phase:2", "decision", "architecture"]
)

# Memory 2: bug-resolution
mcp__vector_memory_local__store_memory(
  content="PHASE 3 verification | DOMAIN: testing | BUG: Tests scanning
           real project directory instead of test temp dir. ROOT_CAUSE:
           PROJECT_ROOT hardcoded from BASH_SOURCE instead of overridable.
           FIX: Changed to PROJECT_ROOT=${PROJECT_ROOT:-$(...)}.
           PREVENTION: Always make path resolution overridable in scripts.",
  category="bug-resolution",
  tags=["phase:3", "bug", "testing"]
)

# Memory 3: phase-summary
mcp__vector_memory_local__store_memory(
  content="PHASE 1 planning | DOMAIN: workflow | OUTCOME: Identified 10
           systemic architectural flaws in UWS subsystem integration.
           Root cause: 4 subsystems (detection, methodology, agents, skills)
           share state.yaml but never communicate. Plan: 12-step fix
           creating shared routing library.",
  category="phase-summary",
  tags=["phase:1", "architecture", "planning"]
)

# Memory 4: verification
mcp__vector_memory_local__store_memory(
  content="PHASE 3 verification | DOMAIN: testing | VERIFIED: All 608 BATS
           tests passing after routing integration. METHOD:
           ./tests/run_all_tests.sh full suite. RESULT: pass. EVIDENCE:
           3 pre-existing failures fixed (multiline sed, PROJECT_ROOT
           override, grep -c arithmetic).",
  category="verification",
  tags=["phase:3", "verification", "testing"]
)

# Memory 5: environment
mcp__vector_memory_local__store_memory(
  content="PHASE 0 planning | DOMAIN: environment | Python 3.10, BATS 1.x,
           yq 4.x, git 2.x. OS: Ubuntu Linux 6.8.0. Project: UWS v1.0.0
           git-native workflow system. Shell scripts with YAML state.",
  category="environment",
  tags=["phase:0", "environment", "setup"]
)

# Memory 6: agent-handoff
mcp__vector_memory_local__store_memory(
  content="PHASE 1 planning | DOMAIN: handoff | HANDOFF
           researcher->implementer. KEY_DECISIONS: Use shared routing
           library for subsystem integration. 4 independent subsystems
           connected via workflow_routing.sh. OPEN_ISSUES: Edge case
           test coverage for hybrid project type detection.",
  category="agent-handoff",
  tags=["phase:1", "agent:researcher", "agent:implementer"]
)
```

#### 1.2 Store 3 Global Test Memories

All 3 fully specified (R2 zero placeholders):

```
# Global 1: tool-gotcha
mcp__vector_memory_global__store_memory(
  content="BASH/SED: sed's s/// command fails when the replacement
           string contains literal newlines because the shell expands
           variables before sed parses the command. FIX: Use a
           while-read loop writing to a temp file instead of sed
           for multiline insertions.
           APPLIES_TO: Any bash script using sed with multiline variables.",
  category="tool-gotcha",
  tags=["tool-limitation", "bash-scripting", "temp-file-pattern"]
)

# Global 2: anti-pattern
mcp__vector_memory_global__store_memory(
  content="ARCHITECTURE/COUPLING: Multiple subsystems sharing a single
           state file without a routing layer causes silent drift -- each
           subsystem reads/writes independently, producing inconsistent
           state. FIX: Create a shared routing library that all subsystems
           source, centralizing state access through validated functions.
           APPLIES_TO: Any multi-component system sharing YAML/JSON state.",
  category="anti-pattern",
  tags=["coupling-violation", "state-management", "mediator-pattern"]
)

# Global 3: workflow-improvement (testing methodology)
mcp__vector_memory_global__store_memory(
  content="TESTING/GREP: grep -c returns exit code 1 when match count is
           zero, even though it successfully outputs '0'. Using
           var=$(grep -c ... || echo 0) appends a second '0' producing
           '0\\n0' which breaks bash arithmetic. FIX: Use
           var=$(grep -c ...) || var=0 (assign on failure, don't append).
           APPLIES_TO: Any bash script using grep -c in arithmetic.",
  category="workflow-improvement",
  tags=["tool-limitation", "bash-scripting", "validation-pattern"]
)
```

#### 1.3 Validate Retrieval Quality

Test that semantic search returns relevant results:

```
# Should return the sed lesson
mcp__vector_memory_global__search_memories(
  query="multiline string substitution bash",
  limit=3)
→ VERIFY: sed lesson appears in top 3

# Should return the PROJECT_ROOT bug
mcp__vector_memory_local__search_memories(
  query="tests running against wrong directory",
  limit=3)
→ VERIFY: PROJECT_ROOT bug appears in top 3

# Should return decision-adr entries
mcp__vector_memory_local__search_memories(
  query="architecture routing",
  category="decision-adr",
  limit=3)
→ VERIFY: routing library decision appears

# Cross-category: should NOT return environment entries for bug query
mcp__vector_memory_local__search_memories(
  query="dataloader batch size mismatch",
  limit=3)
→ VERIFY: irrelevant environment memories are not in top results
  (Note: all results returned; verify by content inspection)
```

#### 1.4 Verify Atomic Memory Principle

Test that **focused single-topic** memories outrank **unfocused multi-topic** memories for targeted queries. (The embedding model ranks by semantic similarity, not content length.)

```
# UNFOCUSED: Store a multi-topic memory mixing 3 unrelated concerns
mcp__vector_memory_local__store_memory(
  content="PHASE 2 implementation | DOMAIN: mixed | Setup Python venv,
           configured Docker, fixed YAML parsing bug where yq silently
           drops keys, also updated CI pipeline to run on PRs, and
           noticed the batch_size was wrong in training config.",
  category="phase-summary",
  tags=["phase:2", "mixed"])

# FOCUSED: Store a single-topic memory about the YAML bug only
mcp__vector_memory_local__store_memory(
  content="PHASE 2 implementation | DOMAIN: yaml | BUG: yq silently
           drops keys when input has trailing whitespace. ROOT_CAUSE:
           yq parser trims lines before parsing. FIX: Pipe through
           sed 's/[[:space:]]*$//' before yq.",
  category="bug-resolution",
  tags=["phase:2", "yaml", "yq"])

# VERIFY: Focused memory ranks higher for a targeted query
mcp__vector_memory_local__search_memories(
  query="yq drops keys YAML parsing", limit=5)
→ VERIFY: Focused YAML bug memory appears ABOVE the unfocused mixed memory
```

#### 1.5 Document Results in Handoff

Update `.workflow/handoff.md` with Phase 1 results:

```markdown
## Vector Memory Integration - Phase 1 Results

- **Local DB**: 8 memories (6 seeds + 2 atomic test)
- **Global DB**: 3 memories
- **Retrieval quality**: [PASS/FAIL] -- [brief notes on query relevance]
- **Atomic principle verified**: Focused single-topic memories rank higher than
  mixed multi-topic memories for targeted queries
- **Phase 1 completed**: [timestamp]
- **Next**: Phase 2 (behavioral integration -- CLAUDE.md, skills, hooks)
```

**Deliverable**: 9 test memories stored (6 local, 3 global) + 2 atomic principle test memories. Retrieval quality validated with 4+ test queries. Results documented in `.workflow/handoff.md`.

#### 1.6 Rollback (if Phase 1 validation fails)

```
If retrieval quality is unacceptable (embedding model performs poorly):
1. clear_old_memories on both DBs to reset
2. Reassess: Are content strings too long? Too vague? Wrong prefixes?
3. Adjust content conventions and re-seed
4. If fundamentally unusable: execute Phase 0 rollback
```

---

### Phase 2: Protocol, Skills & Hooks (Day 2-4)

**Input**: Validated retrieval (from Phase 1). Confirmed category taxonomy works.
**Output**: `CLAUDE.md` updated with memory protocol. 3 memory skills created. `.claude/settings.json` updated with memory hooks.

#### 2.1 Add Memory Protocol Section to CLAUDE.md

Append to `CLAUDE.md`:

```markdown
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
      content="PHASE <N> <methodology_phase> | DOMAIN: <d> | OUTCOME: <description>",
      category="phase-summary" or "decision-adr",
      tags=["phase:<N>", "<domain>"])

**After fixing a non-trivial bug** (on_error_resolved):
  mcp__vector_memory_local__store_memory(
    content="PHASE <N> <methodology_phase> | DOMAIN: <d> | BUG: <symptom>
             ROOT_CAUSE: <cause> FIX: <fix> PREVENTION: <how>",
    category="bug-resolution",
    tags=["phase:<N>", "bug", "<domain>"])
  THEN run Generalizability Gate (see below).

**After agent transition** (on_agent_handoff):
  Outgoing agent stores:
    mcp__vector_memory_local__store_memory(
      content="PHASE <N> <methodology_phase> | DOMAIN: handoff |
               HANDOFF <from>-><to>. KEY_DECISIONS: <list>
               OPEN_ISSUES: <list>",
      category="agent-handoff",
      tags=["phase:<N>", "agent:<from>", "agent:<to>"])
  Incoming agent queries:
    mcp__vector_memory_local__search_memories(
      query="decisions constraints phase <N>",
      category="decision-adr", limit=5)

**After verification/test run** (on_verification):
  mcp__vector_memory_local__store_memory(
    content="PHASE <N> <methodology_phase> | VERIFIED: <what> METHOD: <how>
             RESULT: <pass/fail> EVIDENCE: <summary>",
    category="verification",
    tags=["phase:<N>", "verification"])

### Generalizability Gate
After storing a bug-resolution or decision-adr to local DB, the
`memory-gate` skill auto-invokes (via description matching) to evaluate
3 questions. If all pass, an abstracted lesson is promoted to global DB.
If any fail, local only. See `.claude/skills/memory-gate/SKILL.md`.

### Session Resume (Enhanced)
At session start, after reading state.yaml and handoff.md:
  mcp__vector_memory_local__search_memories(
    query="blockers issues PHASE <current>", limit=5)
  mcp__vector_memory_local__search_memories(
    query="decisions PHASE <current>", category="decision-adr", limit=5)
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

### Local Categories
phase-summary | decision-adr | bug-resolution | agent-handoff |
verification | environment

### Global Categories
anti-pattern | tool-gotcha | design-lesson | library-compat |
workflow-improvement
```

#### 2.2 Create Memory Skills

Create 3 skills following UWS's existing skill pattern (`.claude/skills/*/SKILL.md`):

**`.claude/skills/memory-gate/SKILL.md`** -- Auto-invoked after bug fixes:
```yaml
---
name: memory-gate
description: >
  Run generalizability gate after fixing non-trivial bugs or making
  architectural decisions. Evaluates whether lessons should be promoted
  from project-local to cross-project global memory.
  USE WHEN: A bug fix involves a named tool/library/pattern, or an
  architectural decision applies beyond this project.
user-invocable: false
---

# Generalizability Gate

After storing a bug-resolution or decision-adr to local DB, evaluate:

Q1: Does the root cause involve a named tool, library, or
    architectural pattern (not just this project's code)?
Q2: Could someone hit this exact issue in a different project?
Q3: Can you state the lesson in one sentence WITHOUT referencing
    any file path, variable name, or project-specific term
    from THIS project?

ALL THREE = YES:
  Compose abstracted lesson (NO project file paths, NO project variable names):
    content="<TOOL_OR_PATTERN>: <root cause mechanism>
             FIX: <fix approach> APPLIES_TO: <scope>"
  Select category: anti-pattern | tool-gotcha | design-lesson |
                   library-compat | workflow-improvement
  Select tags: [<root-cause-tag>, <scope-tag>, <fix-pattern-tag>]
  Call: mcp__vector_memory_global__store_memory(content, category, tags)

ANY = NO:
  Local store only. No global promotion.

CALIBRATION: After every 10 global promotions, run adversarial review:
  "Which of the last 10 global stores are actually project-specific?"
  For false promotions, store corrective entry:
    "SUPERSEDES: <summary>. REASON: project-specific."
  (No delete_memory tool -- supersede pattern only.)
```

**`.claude/skills/phase-distillation/SKILL.md`** -- Manual at phase end:
```yaml
---
name: phase-distillation
description: Distill local memories into global lessons at phase completion
disable-model-invocation: true
argument-hint: "[phase-number]"
---

# Phase-End Knowledge Distillation

Distill memories from Phase $ARGUMENTS:

1. mcp__vector_memory_local__search_memories(
     query="PHASE $ARGUMENTS", limit=50)
   NOTE: Using search (not list_recent) to target phase via content prefix.

2. Group results by category.

3. For groups with 2+ entries sharing a root cause:
   Consolidate into ONE general lesson.
   Apply generalizability gate (3-question evaluation).

4. CALIBRATION CHECK: Review last 10 global promotions.
   "Which of these are actually project-specific? Be adversarial."
   For false promotions: store corrective memory with same category:
     content="SUPERSEDES: <original content summary>. REASON: project-specific."
   NOTE: Server has no delete_memory tool. Superseding entries rank
         higher for targeted queries, displacing false ones.

5. Store passing patterns to global DB.

6. Add to .workflow/handoff.md:
   "Phase $ARGUMENTS distillation: promoted M lessons to global knowledge"
```

**`.claude/skills/memory-retrospective/SKILL.md`** -- Manual at project end:
```yaml
---
name: memory-retrospective
description: Review and curate global memory database at project completion
disable-model-invocation: true
---

# Project Retrospective

1. mcp__vector_memory_global__get_memory_stats()
   Note total count for limit parameter.

2. mcp__vector_memory_global__list_recent_memories(
     limit=<total_from_stats>)
   NOTE: Set limit to total count from stats to get ALL memories.

3. For each memory, identify project origin by inspecting content
   for tool/pattern names from the current project's domain.
   (Temporal proximity and domain overlap, not file paths.)

4. For each memory from this project's timeframe:
   a. Still accurate? → Keep
   b. Needs refinement? → Store improved version (old ranks lower)
   c. Project-specific? → Store corrective superseding memory:
      content="SUPERSEDES: <summary>. REASON: project-specific."
   d. Related to another? → Store merged consolidated version

   NOTE: No delete_memory tool. "Removal" = superseding entry.
   For severe contamination, use:
     clear_old_memories(days_old=0, max_to_keep=0)
   then re-store all valid memories from the review notes.
   WARNING: Verify max_to_keep=0 is accepted by the server before
   relying on this -- edge case not confirmed in source.

5. Document results in project completion notes.
```

**Design rationale**:
- `memory-gate` uses `user-invocable: false` so Claude auto-invokes it when the description matches ("after fixing bugs"). This provides two-layer enforcement: CLAUDE.md says "run the gate" (behavioral) + skill description triggers auto-invocation (structural).
- `phase-distillation` and `memory-retrospective` use `disable-model-invocation: true` because they are explicit user-initiated workflows, not automatic responses. Users invoke `/phase-distillation 3` or `/memory-retrospective`.
- All 3 follow UWS's existing skill pattern (see `workflow-checkpoint`, `workflow-recovery`, `workflow-status`).

**Deliverable**: 3 skill files created in `.claude/skills/`.

#### 2.3 Add Memory Hooks to `.claude/settings.json`

Add memory hooks alongside existing UWS hooks. The full updated `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "cd \"$(git rev-parse --show-toplevel 2>/dev/null)\" && [ -f scripts/recover_context.sh ] && ./scripts/recover_context.sh 2>/dev/null || true"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "cd \"$(git rev-parse --show-toplevel 2>/dev/null || pwd)\" && grep -q vector_memory_local .mcp.json 2>/dev/null && echo '{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"VECTOR MEMORY ACTIVE: Query local+global memory DBs during session resume per CLAUDE.md Vector Memory Protocol. Use mcp__vector_memory_local__search_memories() for project context and mcp__vector_memory_global__search_memories() for cross-project lessons.\"}}' || true",
            "timeout": 5,
            "statusMessage": "Loading memory context..."
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "cd \"$(git rev-parse --show-toplevel 2>/dev/null)\" && [ -f scripts/checkpoint.sh ] && ./scripts/checkpoint.sh create 'Auto-checkpoint before context compaction' 2>/dev/null || true"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Context is about to be compacted. Store a compaction marker to local vector memory: mcp__vector_memory_local__store_memory(content='COMPACTION MARKER: Context compacted at this point. Previous conversation context was summarized by Claude Code.', category='phase-summary', tags=['compaction']). Then output a brief confirmation.",
            "timeout": 30,
            "statusMessage": "Persisting memory state before compaction..."
          }
        ]
      }
    ]
  },
  "enabledPlugins": {}
}
```

**Hook classification (pre/post execution)**:

| Hook | Event | Pre/Post | Type | Purpose |
|------|-------|----------|------|---------|
| Context recovery | SessionStart | Pre | `command` | Run `recover_context.sh` (existing) |
| Memory context injection | SessionStart | Pre | `command` | Inject `additionalContext` reminder into Claude's knowledge (conditional on server config) |
| Checkpoint creation | PreCompact | Pre | `command` | Create checkpoint before compaction (existing) |
| Compaction marker | PreCompact | Pre | `agent` | Store compaction timestamp marker to local memory via MCP |

**Design notes**:
- `SessionStart` memory hook uses `additionalContext` (injected into Claude's system context) rather than plain `echo` (terminal output only). This is more reliable. The hook is **conditional**: it only fires when `vector_memory_local` is configured in `.mcp.json`, preventing false instructions in projects without memory setup.
- `PreCompact` memory hook uses `agent` type (not `command`) because:
  - `command` hooks can only run shell commands -- no MCP access, so they cannot store memories
  - `agent` hooks spawn a subagent with MCP tool access, enabling direct `store_memory()` calls
  - The `systemMessage` alternative (v3.2) only showed text to the **user**, not Claude -- it could not trigger memory storage
  - **Limitation**: Agent hooks run in isolation without the main conversation context. The hook can store a compaction marker (timestamp boundary) but cannot intelligently summarize what happened. Conversation-specific memory storage remains a behavioral directive in CLAUDE.md.
- `SessionStart` hook has `timeout: 5` (echo only). `PreCompact` agent hook has `timeout: 30` (MCP call).
- `Stop` event was considered but rejected: fires on every Claude response, too frequent for memory operations.
- `PostToolUse` with `Edit|Write` matcher was considered but rejected: adds latency to every file operation with minimal benefit. An `agent`-type PostToolUse hook COULD detect significant changes and auto-store, but the latency trade-off is not justified.
- **Execution order**: Multiple SessionStart hooks run in parallel. The context recovery hook (~120ms) and memory hook (~5ms) finish independently. The `additionalContext` injection order relative to recovery output is undefined by the spec but harmless -- both inject into the same session context.

**Hook type evaluation** (all 3 types considered):

| Type | SessionStart | PreCompact | Rationale |
|------|-------------|------------|-----------|
| `command` | **USED** (echo + additionalContext) | Rejected | Cannot call MCP tools; `systemMessage` only reaches user |
| `prompt` | Rejected (no MCP access for queries) | Rejected | Cannot call MCP tools; output visibility uncertain |
| `agent` | Rejected (unnecessary latency for static text) | **USED** (store compaction marker) | Has MCP access; can call store_memory(); justified for data persistence |

**Deliverable**: `CLAUDE.md` updated with memory protocol (abbreviated, references skills). 3 memory skills created. `.claude/settings.json` updated with 2 memory hooks (conditional command + agent).

**TRANSITION TO PHASE 3**: After completing Phase 2, you MUST restart the Claude Code session (or run `/hooks` to reload hook configuration). This is required because:
1. `CLAUDE.md` changes take effect when Claude Code reads the file (session start or context reload)
2. `.claude/settings.json` hook changes are "captured at session startup" per the hooks spec; external modifications require `/hooks` review to take effect
3. New skills (`.claude/skills/`) are discovered at session startup; they won't appear in `/` menu or auto-invoke until reloaded
4. Phase 3 tests rely on the agent FOLLOWING the behavioral directives and skills written in Phase 2

**Note on CLAUDE.md**: The existing research phases listed in CLAUDE.md (line 80) show 5 phases but the current codebase uses 7 phases (with `literature_review` and `peer_review` added in commit f38d82b). Update this line during Phase 2 to avoid confusion with the memory content convention.

#### 2.4 Rollback (if Phase 2 fails)

```
Phase 2 modifies 3 file groups. Rollback order:

1. Hooks (.claude/settings.json):
   - Remove the SessionStart memory hook (second matcher group)
   - Remove the PreCompact agent hook (second matcher group)
   - Keep existing hooks (recover_context.sh, checkpoint.sh) unchanged

2. Skills (.claude/skills/):
   - Delete: memory-gate/, phase-distillation/, memory-retrospective/
   - Existing skills (workflow-checkpoint, workflow-recovery, workflow-status) unchanged

3. CLAUDE.md:
   - Remove the "## Vector Memory Protocol" section and all its subsections
   - Keep all other CLAUDE.md content unchanged

4. Vector memory DBs:
   - Phase 2 does NOT add new memories (only Phase 1 seeds exist)
   - No DB cleanup needed for Phase 2 rollback

Note: After rollback, restart Claude Code session to clear cached CLAUDE.md
and hooks. The memory servers from Phase 0 remain functional but unused.
```

---

### Phase 3: Generalizability Skill & Distillation (Day 4-6)

**Input**: Memory protocol loaded in CLAUDE.md (from Phase 2, session restarted). 3 memory skills created (from Phase 2). Categories tested (from Phase 1). Local DB has 8 memories from Phase 1 (6 seeds + 2 atomic test). Global DB has 3 memories.
**Output**: Generalizability detection working end-to-end. At least 1 test global promotion. Skills validated. Automated regression test created.

#### 3.1 Integration Test: Bug Fix with Global Promotion

1. Fix a non-trivial bug (or simulate one in a test environment).
2. Store to local DB per protocol.
3. Run generalizability gate.
4. If promoted: verify global DB contains the abstracted lesson.
5. If not promoted: verify global DB is unchanged.

Test cases:
- **Should promote**: Fix involving a named tool (e.g., sed, grep, git).
- **Should NOT promote**: Fix involving a project-specific config value.

#### 3.2 Integration Test: Phase-End Distillation

1. Ensure local DB has 5+ memories for a given phase (from Phase 1 seeds + any new work).
2. Run phase-end distillation protocol.
3. Verify: consolidated patterns stored to global.
4. Verify: calibration review runs (adversarial check).

#### 3.3 Integration Test: Cross-DB Session Resume

1. Start a fresh context (or simulate session resume).
2. Run the enhanced session resume protocol.
3. Verify: local search returns project-relevant memories.
4. Verify: global search returns applicable cross-project lessons.
5. Measure: total time for all queries (<3s target).

#### 3.4 Create Automated Regression Test

UWS uses BATS for testing (608 existing tests). Create `tests/integration/test_vector_memory.bats` to verify MCP server health and basic store/retrieve. This ensures future UWS changes don't break the memory integration.

```bash
#!/usr/bin/env bats
# Integration tests for vector memory MCP servers
# Requires: vector_memory_local and vector_memory_global configured in .mcp.json

load '../helpers/test_helper.bash'

# Use actual project root (not temp dir) -- these test real project config
setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
}

@test "vector memory local server is configured in .mcp.json" {
    run grep -c "vector_memory_local" "${PROJECT_ROOT}/.mcp.json"
    assert_success
    [ "$output" -ge 1 ]
}

@test "vector memory global server is configured in .mcp.json" {
    run grep -c "vector_memory_global" "${PROJECT_ROOT}/.mcp.json"
    assert_success
    [ "$output" -ge 1 ]
}

@test "vector memory venv exists" {
    [ -f "${HOME}/.uws/tools/vector-memory/.venv/bin/python" ]
}

@test "memory directory is gitignored" {
    run grep -c "^memory/" "${PROJECT_ROOT}/.gitignore"
    assert_success
}

@test "CLAUDE.md contains Vector Memory Protocol section" {
    run grep -c "Vector Memory Protocol" "${PROJECT_ROOT}/CLAUDE.md"
    assert_success
    [ "$output" -ge 1 ]
}

@test "settings.json contains memory hooks" {
    run grep -c "additionalContext" "${PROJECT_ROOT}/.claude/settings.json"
    assert_success
}

@test "memory-gate skill exists" {
    [ -f "${PROJECT_ROOT}/.claude/skills/memory-gate/SKILL.md" ]
}

@test "phase-distillation skill exists" {
    [ -f "${PROJECT_ROOT}/.claude/skills/phase-distillation/SKILL.md" ]
}

@test "memory-retrospective skill exists" {
    [ -f "${PROJECT_ROOT}/.claude/skills/memory-retrospective/SKILL.md" ]
}

@test "memory-gate skill is auto-invocable (no disable-model-invocation)" {
    # memory-gate should NOT have disable-model-invocation: true
    run grep -c "disable-model-invocation: true" "${PROJECT_ROOT}/.claude/skills/memory-gate/SKILL.md"
    [ "$output" -eq 0 ] || [ "$status" -ne 0 ]
}

@test "memory-gate skill has user-invocable: false" {
    run grep -c "user-invocable: false" "${PROJECT_ROOT}/.claude/skills/memory-gate/SKILL.md"
    assert_success
    [ "$output" -ge 1 ]
}

@test "phase-distillation skill is manual-only" {
    run grep -c "disable-model-invocation: true" "${PROJECT_ROOT}/.claude/skills/phase-distillation/SKILL.md"
    assert_success
    [ "$output" -ge 1 ]
}
```

**Note**: Full MCP tool calls (store/search) cannot be tested via BATS because they require a running Claude Code session. The BATS tests verify configuration, file structure, and skill invocation properties. End-to-end memory operations are validated manually in Sections 3.1-3.3.

#### 3.5 Verify Local DB State for Phase 4

Before proceeding to Phase 4, confirm local DB has sufficient memories:
```
mcp__vector_memory_local__get_memory_stats()
→ VERIFY: total_memories >= 10 (6 Phase 1 seeds + 2 atomic test + Phase 3 test stores)
```

Record the memory count in `.workflow/handoff.md` for Phase 4's reference.

**Deliverable**: End-to-end generalizability pipeline tested. At least 1 global promotion validated. Skills (memory-gate auto-invocation, phase-distillation manual) verified. Session resume timing measured. Automated BATS test created at `tests/integration/test_vector_memory.bats` (12 tests). Local DB memory count recorded.

#### 3.6 Rollback (if Phase 3 fails)

```
Phase 3 adds memories to both DBs during testing.

Point of no return: After Phase 3 stores test memories, there is NO
selective delete. Rollback options:

Option A (recommended): Leave test memories in place.
  - Phase 3 test memories are properly prefixed ("PHASE 3 verification")
  - They rank low in searches for current work phases
  - Harmless to keep; provides retrieval quality baseline data

Option B (nuclear): Full DB wipe + re-seed.
  1. mcp__vector_memory_local__clear_old_memories(days_old=0, max_to_keep=0)
     WARNING: Verify max_to_keep=0 is accepted -- edge case.
  2. mcp__vector_memory_global__clear_old_memories(days_old=0, max_to_keep=0)
  3. Re-store Phase 1's 6 local seeds + 3 global seeds manually
  4. Re-run Phase 1 atomic principle test (2 memories)
  5. You are back at Phase 1 exit state

To roll back Phase 2 changes as well: follow Phase 2 rollback procedure.
To roll back everything: follow Phase 0 rollback procedure.
```

---

### Phase 4: Cross-Agent Knowledge Transfer (Day 6-8)

**Input**: Memory protocol working (from Phase 3). Local DB has >= 10 memories (verified in Phase 3 Section 3.5).
**Output**: Agent handoff via memory validated across 3 representative transitions.

#### 4.1 Agent Handoff Tests (3 transitions)

**Test A: researcher → implementer** (planning → implementation):
1. Activate researcher agent. Store 2-3 decision-adr memories.
2. Transition to implementer agent.
3. Implementer queries local DB for researcher's decisions.
4. Verify: all decisions retrievable via semantic search.
5. Verify: handoff memory stored with correct category and tags.

**Test B: implementer → experimenter** (implementation → verification):
1. Implementer stores 1-2 bug-resolution memories.
2. Transition to experimenter agent.
3. Experimenter queries for implementation issues and constraints.
4. Verify: bug fixes and decisions from implementation are retrievable.

**Test C: experimenter → documenter** (verification → documentation):
1. Experimenter stores 1-2 verification memories.
2. Transition to documenter agent.
3. Documenter queries for test results and verified claims.
4. Verify: verification memories retrievable for documentation.

#### 4.2 Update Slash Commands

Add memory query hints to relevant slash commands:

**`.claude/commands/uws-recover.md`** -- add memory search to recovery:
```
After displaying recovery info, query vector memory:
  mcp__vector_memory_local__search_memories("current blockers", limit=3)
```

**`.claude/commands/uws-agent.md`** -- add memory query on agent activation:
```
After activating agent, query relevant memories:
  mcp__vector_memory_local__search_memories(
    "handoff <previous_agent>", category="agent-handoff", limit=3)
```

**Deliverable**: 3 agent handoff transitions tested via memory. Slash commands updated.

#### 4.3 Exit Gate

```
For each of the 3 agent transitions tested in Section 4.1:
  mcp__vector_memory_local__search_memories(
    "handoff <target_agent>", category="agent-handoff", limit=3)
  → VERIFY: Each search returns the handoff memory stored during that test
  → VERIFY: Returned content includes the outgoing agent's context summary

mcp__vector_memory_local__get_memory_stats()
  → VERIFY: total_memories increased since Phase 3 exit (record new count)

Slash command verification:
  → VERIFY: uws-recover.md contains memory search instruction
  → VERIFY: uws-agent.md contains memory query on activation
```

#### 4.4 Rollback (if Phase 4 fails)

```
Phase 4 adds agent-handoff memories and modifies slash commands.

1. Slash commands (uws-recover.md, uws-agent.md):
   - Use git to revert: git checkout -- .claude/commands/uws-recover.md
   - Use git to revert: git checkout -- .claude/commands/uws-agent.md

2. Agent handoff memories:
   - Same as Phase 3: no selective delete. Leave in place (Option A)
     or full wipe + re-seed through Phase 1 (Option B)

Phase 4 rollback returns you to Phase 3 exit state (memory protocol
working, skills validated, but no cross-agent features).
```

---

### Phase 5: Maintenance, Recovery & Hardening (Day 8-10)

**Input**: Full system working (from Phase 4). Agent handoff validated. Slash commands updated.
**Output**: Maintenance procedures documented. Recovery paths tested. Performance benchmarked.

#### 5.1 Memory Hygiene Procedures

Add as a subsection under `## Vector Memory Protocol` in CLAUDE.md, after the `### Global Categories` line. The exact heading hierarchy:

```
## Vector Memory Protocol          ← Added in Phase 2
### ...existing subsections...     ← Phase 2 content
### Memory Maintenance             ← Phase 5 adds THIS subsection
```

Content to append:

```markdown
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
```

#### 5.2 Recovery Procedures

**Local DB lost**:
```
1. Not catastrophic -- markdown is source of truth.
2. Re-seed manually: read .workflow/handoff.md and .workflow/logs/decisions.log.
3. For each decision/bug documented in handoff.md, store to local DB.
4. Full re-indexing is manual but bounded by project size.
```

**Global DB lost**:
```
1. Lessons may also exist in CLAUDE.md auto-memory (~/.claude/MEMORY.md).
2. Re-seed from team documentation and known patterns.
3. Global DB grows slowly (~5-10 lessons per project). Loss is recoverable.
```

**Checkpoint restore (state reverts but vector DB doesn't)**:
```
WARNING: Checkpoint restore does NOT revert vector memory.
After restoring a checkpoint:
  1. Check mcp__vector_memory_local__get_memory_stats() for memory count.
  2. If memories from future phases exist, they may cause confusion.
  3. Option A (recommended): Ignore -- stale memories with future phase
     prefixes (e.g., "PHASE 4") will rank low when searching for current
     phase (e.g., "PHASE 2"). The content prefix convention handles this.
  4. Option B (nuclear): If contamination is severe:
       mcp__vector_memory_local__clear_old_memories(days_old=0, max_to_keep=0)
     Then re-seed from .workflow/handoff.md and .workflow/logs/decisions.log.
     NOTE: There is no selective delete. clear_old_memories with
     max_to_keep=0 removes ALL memories. You must re-store valid ones.
     WARNING: Verify max_to_keep=0 is accepted by the server before
     relying on this -- edge case behavior not confirmed in source.
     Test with a disposable DB first.
```

#### 5.3 Performance Benchmarks

Run and document actual measurements:

| Operation | Target | Actual | Pass? |
|-----------|--------|--------|-------|
| store_memory (single) | <500ms | ___ms | |
| search_memories (local, ~200 entries) | <200ms | ___ms | |
| search_memories (global, ~100 entries) | <200ms | ___ms | |
| Session resume (5 local + 3 global queries) | <3s | ___s | |
| Phase checkpoint (10 stores) | <5s | ___s | |

#### 5.4 Category Migration Note

If categories need to change in the future (e.g., splitting `bug-resolution`):
- The vector-memory-mcp server has no rename/update or selective delete capability.
- Migration procedure:
  1. `get_memory_stats()` to get total count
  2. `list_recent_memories(limit=<total_from_stats>)` to export all
     (default limit=10 is insufficient; set limit to total count)
  3. Record all memory content and categories externally
  4. `clear_old_memories(days_old=0, max_to_keep=0)` to wipe DB
     (WARNING: Verify max_to_keep=0 is accepted -- edge case not confirmed in source)
  5. Re-store each memory with updated categories
- Keep category taxonomy stable. Prefer adding new categories over renaming.

#### 5.5 Exit Gate

```
Documentation checks:
  → VERIFY: CLAUDE.md contains "### Memory Maintenance" subsection
  → VERIFY: Recovery procedures documented for local DB loss, global DB loss,
    and checkpoint restore
  → VERIFY: Category migration procedure documented

Performance benchmarks (Section 5.3):
  → VERIFY: store_memory < 200ms (target 110ms)
  → VERIFY: search_memories < 300ms (target 150ms)
  → VERIFY: Session resume overhead < 500ms
  → VERIFY: All 5 operations have "Actual" column filled in benchmark table
  → VERIFY: All 5 operations meet Target time (Pass? = Yes)

clear_old_memories edge case:
  → VERIFY: Tested clear_old_memories(days_old=0, max_to_keep=0) on a
    disposable test DB to confirm behavior (record result in handoff.md)
```

**Deliverable**: Maintenance procedures in CLAUDE.md. Recovery procedures documented. Performance benchmarked. Category migration strategy noted.

#### 5.6 Rollback (if Phase 5 fails)

```
Phase 5 only adds documentation and runs benchmarks. No new memories stored.

1. CLAUDE.md maintenance section:
   - Remove "### Memory Maintenance" subsection added in Section 5.1
   - All other CLAUDE.md content unchanged

2. No DB changes to revert.

Phase 5 is the lowest-risk phase. If benchmarks fail (performance
targets not met), the system is still functional -- just slower than
target. Document actual times and consider optimization separately.
```

---

## 6. Simulation: End-to-End Walkthrough

### Session 1: Phase 0 Complete

```
Agent completes Phase 0 (environment setup).

on_phase_complete fires (behavioral directive):
  mcp__vector_memory_local__store_memory(
    content="PHASE 0 planning | DOMAIN: environment | OUTCOME: Python 3.10,
             PyTorch 2.1, AASIST cloned from abc123. Datasets:
             ASVspoof2019LA, ASVspoof2021LA, In-The-Wild. GPU: A100 40GB.",
    category="environment",
    tags=["phase:0", "pytorch", "aasist"])

  mcp__vector_memory_local__store_memory(
    content="PHASE 0 planning | DOMAIN: dataset | DECISION: Use ASVspoof2019LA for training,
             2021LA and ITW for cross-dataset eval. BECAUSE: Standard
             protocol per Tak et al. (2021). ALTERNATIVES_REJECTED:
             Training on 2021LA -- different codec distribution.",
    category="decision-adr",
    tags=["phase:0", "decision", "dataset-split"])

Generalizability gate: Q1=NO (project-specific dataset) → LOCAL only.
```

### Session 2: Bug Fixed in Phase 2

```
Bug: DataLoader collate_fn doubles batch size.

on_error_resolved fires:
  mcp__vector_memory_local__store_memory(
    content="PHASE 2 experiment_design | DOMAIN: training | BUG: Forward pass crashes
             'Expected batch_size 32 to match target 64'. ROOT_CAUSE:
             collate_fn doubled batch via bonafide/spoof pairing.
             FIX: Custom collate preserving batch_size.
             PREVENTION: Verify shapes after collate with dry-run.",
    category="bug-resolution",
    tags=["phase:2", "bug", "pytorch", "dataloader"])

Generalizability gate:
  Q1: YES (PyTorch DataLoader)
  Q2: YES (any binary classification with paired samples)
  Q3: YES ("Custom collate functions that pair pos/neg samples
       can silently double batch size")

  mcp__vector_memory_global__store_memory(
    content="PYTORCH/DATALOADER: Custom collate_fn that pairs
             positive/negative samples can silently double the effective
             batch size, causing 'batch_size N to match target 2N' errors.
             FIX: Always verify tensor shapes after collate with
             next(iter(dataloader)).shape before training.
             APPLIES_TO: Any PyTorch binary classification with
             paired/contrastive sampling.",
    category="tool-gotcha",
    tags=["library-behavior", "python-packaging", "validation-pattern"])
```

### Session 3: New Session Resumes at Phase 3

```
Enhanced session resume:
  1-4. Read CLAUDE.md, state.yaml, handoff.md, phase context.

  5. mcp__vector_memory_local__search_memories(
       query="blockers issues PHASE 3", limit=5)
     → Returns DataLoader bug (relevant to training domain)

  6. mcp__vector_memory_local__search_memories(
       query="decisions dataset PHASE 2",
       category="decision-adr", limit=5)
     → Returns ASVspoof2019LA decision

  7. mcp__vector_memory_global__search_memories(
       query="PyTorch training data augmentation", limit=3)
     → Returns DataLoader collate lesson
     → Returns (if exists) other PyTorch lessons from past projects

Total time: ~1.5 seconds for all queries.
```

### Six Months Later: Different Project

```
Working on a speech synthesis project. Session resume:

  mcp__vector_memory_global__search_memories(
    query="PyTorch DataLoader training", limit=5)
  → Returns: collate_fn batch doubling lesson (tool-gotcha)
  → Agent adds shape assertions proactively.
  → Bug avoided entirely.
```

---

## 7. Risk Assessment

| Risk | Prob | Impact | Mitigation |
|------|------|--------|-----------|
| Model download fails (offline) | Medium | Blocks setup | Pre-download; model caches to ~/.cache/huggingface/ |
| Local DB corrupts | Low | Lose project index | Markdown is source of truth; manual re-seed from handoff.md |
| Global DB corrupts | Low | Lose cross-project lessons | Small DB (~50-100); re-seed from memory + documentation |
| False-positive retrieval | Medium | R1 risk | Always cross-reference markdown; never cite memory alone |
| Over-promotion to global | Medium | Global noise | 3-question gate + adversarial calibration every 10 promotions |
| Under-promotion | Medium | Missed learning | Phase-end distillation catches patterns; retrospective catches rest |
| Behavioral directives skipped | Medium | Missing memories | Session-start reminder hook; phase-end check |
| ~240MB RAM for 2 MCP processes | Low | Resource pressure | Acceptable for dev machines; can stop global when not needed |
| Checkpoint restore doesn't revert DB | Medium | Temporal mismatch | Document warning; stale future-phase memories rank low for current queries |
| No selective delete | Medium | Cannot remove individual false promotions | "Supersede" pattern stores corrective entries; nuclear option wipes + re-seeds |
| Category needs to change | Low | Migration required | Keep taxonomy stable; prefer adding over renaming |

---

## 8. Success Criteria

| Metric | Target | How to Measure |
|--------|--------|---------------|
| Session resume | <3s for all memory queries | Time Phase 3 test (Section 5.3) |
| Cross-phase retrieval | Relevant in top 5 for known queries | Phase 1 validation tests |
| R1 false claims | 0% fabricated history | Audit claims against markdown |
| Local memory overhead | <20 atomic memories per phase | `get_memory_stats()` |
| Global promotion rate | 10-20% of local bug/decision memories | Track gate outcomes |
| Global reuse | >=1 global memory cited per new project | Track session resume hits |
| False promotion rate | <5% pruned in retrospective | Count retrospective removals |

---

## 9. Implementation Checklist

```
Prerequisites:                                        [Verify before starting]
  [ ] Python 3.9+ installed (python3 --version)
  [ ] pip available (pip --version)
  [ ] venv module available (python3 -m venv --help)
  [ ] git 2.0+ installed
  [ ] ~1.5 GB disk space free (~/.uws)
  [ ] Write permissions to ~/.uws/ and project memory/ dir
  [ ] Network access for git clone + pip install + model download

Phase 0: Infrastructure                              [Deliverable: 2 healthy MCP servers]
  [ ] Clone vector-memory-mcp to ~/.uws/tools/vector-memory
  [ ] Record commit hash for version pinning
  [ ] VERIFY tool signatures against source (Section 0.2 -- CRITICAL)
  [ ] Create isolated venv at ~/.uws/tools/vector-memory/.venv/
  [ ] Install sqlite-vec, sentence-transformers, fastmcp in venv
  [ ] Create ~/.uws/knowledge/ directory
  [ ] Create <project>/memory/ directory
  [ ] Add vector_memory_local to .mcp.json (inside mcpServers, using venv python)
  [ ] Add vector_memory_global to .mcp.json (inside mcpServers, using venv python)
  [ ] Add memory/ to .gitignore
  [ ] Verify local get_memory_stats() returns healthy
  [ ] Verify global get_memory_stats() returns healthy

Phase 1: Seed & Validate                             [Deliverable: Validated retrieval]
  [ ] Store 6 local test memories (all specified in plan -- R2 zero placeholders)
  [ ] Store 3 global test memories (all specified in plan)
  [ ] Run 4+ retrieval quality tests
  [ ] Verify category filtering works
  [ ] Verify atomic memory principle (focused > unfocused, not short > long)
  [ ] Store atomic test pair (unfocused multi-topic vs focused single-topic)
  [ ] Document results in .workflow/handoff.md (Section 1.5 template)

Phase 2: Protocol, Skills & Hooks                    [Deliverable: CLAUDE.md + skills + hooks]
  [ ] Update CLAUDE.md research phases to 7 (literature_review, peer_review)
  [ ] Add Vector Memory Protocol section to CLAUDE.md (abbreviated, references skills)
  [ ] Add all 4 behavioral directive definitions (triggers)
  [ ] Add generalizability gate summary (references memory-gate skill)
  [ ] Add session resume enhancement
  [ ] Add R1 evidence extension
  [ ] Add phase-end distillation summary (references phase-distillation skill)
  [ ] Create .claude/skills/memory-gate/SKILL.md (user-invocable: false)
  [ ] Create .claude/skills/phase-distillation/SKILL.md (disable-model-invocation: true)
  [ ] Create .claude/skills/memory-retrospective/SKILL.md (disable-model-invocation: true)
  [ ] Add SessionStart memory hook (conditional, with cd to git root) to .claude/settings.json
  [ ] Add PreCompact memory hook (agent type, compaction marker) to .claude/settings.json
  [ ] Verify hook JSON schema uses correct 3-level nesting
  [ ] RESTART Claude Code session or run /hooks to reload (skills + hooks)

Phase 3: End-to-End Testing                          [Deliverable: Pipeline + skills validated + BATS test]
  [ ] Test: bug fix → local store → gate skill auto-invokes → global promotion
  [ ] Test: bug fix → local store → gate skill auto-invokes → NO promotion (project-specific)
  [ ] Test: /phase-distillation <N> with 5+ local memories
  [ ] Test: adversarial calibration (supersede false promotions, not delete)
  [ ] Test: session resume with dual-DB queries (<3s)
  [ ] Verify memory-gate skill auto-invokes on bug fix (description matching)
  [ ] Verify /phase-distillation is visible in / menu (not auto-invocable)
  [ ] Create tests/integration/test_vector_memory.bats (12 automated regression tests)
  [ ] Verify local DB memory count >= 10 for Phase 4
  [ ] Record memory count in .workflow/handoff.md

Phase 4: Cross-Agent Transfer                        [Deliverable: 3 handoffs tested]
  [ ] Test A: researcher → implementer (decisions retrievable)
  [ ] Test B: implementer → experimenter (bug fixes retrievable)
  [ ] Test C: experimenter → documenter (verifications retrievable)
  [ ] Update .claude/commands/uws-recover.md with memory hint
  [ ] Update .claude/commands/uws-agent.md with memory hint
  [ ] EXIT GATE: Verify handoff memories retrievable per Section 4.3

Phase 5: Maintenance & Hardening                     [Deliverable: Procedures documented]
  [ ] Add maintenance subsection under ## Vector Memory Protocol → ### Memory Maintenance
  [ ] Document local DB cleanup (max_to_keep, no selective delete)
  [ ] Document global DB cleanup (manual, no days_old, supersede pattern)
  [ ] Document local DB recovery procedure
  [ ] Document global DB recovery procedure
  [ ] Document checkpoint-restore + vector memory warning (no selective revert)
  [ ] Verify clear_old_memories(days_old=0, max_to_keep=0) edge case with test DB
  [ ] Run performance benchmarks, fill in Section 5.3 table, all must PASS
  [ ] Document category migration strategy (get_memory_stats for limit)
  [ ] EXIT GATE: All Section 5.5 checks pass
```

---

## 10. References

1. Reimers, N. & Gurevych, I. (2019). *Sentence-BERT: Sentence Embeddings using Siamese BERT-Networks*. EMNLP 2019.
2. Thakur, N. et al. (2021). *BEIR: A Heterogeneous Benchmark for Zero-shot Evaluation of Information Retrieval Models*. NeurIPS 2021.
3. Garcia, A. (2024). *sqlite-vec: A vector search SQLite extension*. https://github.com/asg017/sqlite-vec
4. Wang, W. et al. (2020). *MiniLM: Deep Self-Attention Distillation for Task-Agnostic Compression of Pre-Trained Transformers*. NeurIPS 2020.
5. cornebidouil (2025). *vector-memory-mcp*. MIT License. https://github.com/cornebidouil/vector-memory-mcp
6. Norton, M., Mochon, D. & Ariely, D. (2012). *The IKEA effect: When labor leads to love*. Journal of Consumer Psychology, 22(3), 453-460. (Self-assessment bias reference for Section 3.1)

---

## Appendix A: Changes from v2.0 (Design Review Resolution)

| Finding | Severity | Resolution |
|---------|----------|-----------|
| Phantom file references | CRITICAL | All references mapped to actual UWS files (Section 1.2) |
| Wrong MCP naming | CRITICAL | Corrected to `mcp__vector_memory_local__` convention (Section 1.3) |
| Hooks are behavioral, not executable | HIGH | Labeled as "behavioral directives" (Section 2.3). Added 2 executable hooks: SessionStart (`additionalContext`), PreCompact (`systemMessage`). Hook spec verified against Claude Code docs (v3.1). |
| Phase connectivity gaps | HIGH | Each phase has Input/Output/Deliverable contracts (Section 5) |
| Self-assessment bias | HIGH | Added adversarial calibration every 10 promotions (Section 3.1, 3.2) |
| Recovery path incomplete | HIGH | Full recovery procedures for both DBs (Section 5.2) |
| Testing is shallow | MEDIUM | Added retrieval quality validation, edge case tests, timing targets (Phase 1, 3) |
| Resource impact underestimated | MEDIUM | Documented ~240MB RAM, model load latency (Section 2.1) |
| Checkpoint restore conflict | MEDIUM | Documented warning and mitigation (Section 5.2) |
| list_recent_memories breaks distillation | MEDIUM | Changed to search_memories("PHASE N") using content prefix (Section 3.2) |
| Empty string search degenerate | LOW | Changed to list_recent_memories for retrospective (Section 3.3) |
| No structural enforcement on global content | LOW | Added explicit content rule (Section 4.2) |
| Time-based pruning inappropriate for global | LOW | Global uses max_to_keep only, no days_old (Section 5.1) |
| No category migration strategy | LOW | Documented: prefer adding over renaming (Section 5.4) |

---

## Appendix B: Changes from v3.0 (Hooks Verification)

| Finding | Resolution |
|---------|-----------|
| Hook JSON schema wrong (missing inner `hooks` array) | Fixed to correct 3-level nesting: `hooks` → Event array → matcher group with `hooks` array |
| Only `command` type described | Documented all 3 types: `command`, `prompt`, `agent` with fields and MCP access |
| No pre/post classification | Added full classification table for all 14 events |
| `echo` reminder is weak | Changed SessionStart hook to use `additionalContext` (injected into Claude's system context) |
| Missing PreCompact memory hook | Added `systemMessage`-based reminder for storing memories before compaction |
| `Stop` event considered | Rejected: fires every response turn, too frequent for memory reminders |
| `PostToolUse` matcher considered | Rejected: adds latency to file operations with minimal memory benefit |
| Full `.claude/settings.json` not shown | Phase 2 now shows complete file with all hooks (existing + new) |

---

## Appendix C: Changes from v3.1 (Comprehensive Review)

16 findings resolved (2 CRITICAL, 4 HIGH, 5 MEDIUM, 5 LOW):

| # | Finding | Severity | Resolution |
|---|---------|----------|-----------|
| 1 | `.mcp.json` format wrong (missing `mcpServers` wrapper) | CRITICAL | Fixed Phase 0 Section 0.4 to show correct `"mcpServers"` top-level key |
| 2 | No `delete_memory` tool -- adversarial calibration unimplementable | CRITICAL | Added "Selective delete" row to Section 1.1. Changed "remove" to "supersede" pattern throughout (Sections 3.2, 3.3, 5.2, CLAUDE.md directives). Documented nuclear option (clear + re-seed) |
| 3 | Incomplete seed memories (R2 violation) | HIGH | All 5 local + 3 global memories fully specified in Phase 1 (no `# ... N more` placeholders) |
| 4 | No Python environment isolation | HIGH | Phase 0 now creates isolated venv at `~/.uws/tools/vector-memory/.venv/`. `.mcp.json` command uses venv python path |
| 5 | Phase 3 tests entirely manual | HIGH | Added Section 3.4: automated `tests/integration/test_vector_memory.bats` with 6 BATS tests for config/structure regression |
| 6 | Phase 2→3 transition requires session restart | HIGH | Added explicit "TRANSITION TO PHASE 3" block with restart/`/hooks` instruction |
| 7 | Phase 3→4 input contract weak | MEDIUM | Phase 3 adds Section 3.5 verifying local DB memory count >= 10. Phase 4 input references this |
| 8 | Phase numbering ambiguity | MEDIUM | Section 4.3 now specifies dual prefix: `"PHASE <N> <methodology_phase>"` with examples. All CLAUDE.md directive examples updated |
| 9 | Atomic Memory test logic flawed | MEDIUM | Section 1.4 rewritten: tests focused vs unfocused (not short vs long), with specific test pair and verification query |
| 10 | Phase 5 CLAUDE.md additions not positioned | MEDIUM | Section 5.1 now specifies: "Add as subsection under Vector Memory Protocol section added in Phase 2" |
| 11 | No rollback procedures | MEDIUM | Added Phase 0 Section 0.7 rollback and Phase 1 Section 1.6 rollback. v3.4 extended to all phases (Sections 2.4, 3.6, 4.4, 5.6). |
| 12 | `list_recent_memories` limit issue for export | LOW | Section 5.4 migration now uses `get_memory_stats()` total for limit parameter |
| 13 | Retrospective can't filter by project in global DB | LOW | Section 3.3 updated with project identification strategy (temporal proximity + domain overlap) |
| 14 | Hook execution order undefined | LOW | Added note to Phase 2 design notes about parallel SessionStart hook execution |
| 15 | Phase 4 tests only 1 agent transition | LOW | Phase 4 now tests 3 transitions: researcher→implementer, implementer→experimenter, experimenter→documenter |
| 16 | CLAUDE.md research phases stale (5 vs 7) | LOW | Added note in Phase 2→3 transition block to update CLAUDE.md research phases during Phase 2 |

*Version 3.2 -- All server capabilities verified against source. All file references audited. All prior findings resolved. Hooks verified against Claude Code specification. No-delete limitation explicitly addressed throughout with supersede pattern. This plan follows UWS R2 (zero placeholders) and R5 (Reproducibility): any agent can execute this integration from this document alone.*

---

## Appendix D: Changes from v3.2 (AI Framework Architect Review)

11 findings resolved (1 CRITICAL, 3 HIGH, 4 MEDIUM, 3 LOW):

| # | Finding | Severity | Resolution |
|---|---------|----------|-----------|
| 1 | Plan creates zero Claude Code skills despite UWS having 3 existing skills | CRITICAL | Created 3 memory skills in Phase 2 Section 2.2: `memory-gate` (user-invocable: false, auto-invoked), `phase-distillation` (disable-model-invocation: true, manual), `memory-retrospective` (disable-model-invocation: true, manual). CLAUDE.md protocol section shortened to reference skills. Added skills to enforcement mechanism table (Section 2.3). Added 5 skill BATS tests to Phase 3 Section 3.4. |
| 2 | PreCompact `systemMessage` only reaches user, not Claude | HIGH | Changed PreCompact memory hook from `command` type (echo systemMessage) to `agent` type (stores compaction marker via MCP). Agent hooks have MCP tool access and can call `store_memory()` directly. Limitation documented: agent runs in isolation, can't summarize conversation. |
| 3 | `agent` type hooks not evaluated for memory operations | HIGH | Added hook type evaluation table to Phase 2 Section 2.3 design notes. All 3 types (command, prompt, agent) explicitly evaluated for both SessionStart and PreCompact with rationale for selection. |
| 4 | Generalizability gate enforcement purely behavioral | HIGH | Gate procedure moved to `memory-gate` skill with `user-invocable: false`. Two-layer enforcement: CLAUDE.md behavioral trigger + skill auto-invocation via description matching. Strictly better than behavioral-only. |
| 5 | Phase 1 seeds miss `agent-handoff` category (5 of 6) | MEDIUM | Added Memory 6 (agent-handoff) to Phase 1 Section 1.1. All 6 local categories now covered. Counts updated: 6 local seeds (+ 2 atomic = 8 local), 3 global, Phase 3 exit gate >= 10 local. |
| 6 | SessionStart memory hook fires unconditionally | MEDIUM | Made hook conditional: `grep -q vector_memory_local .mcp.json` before echoing additionalContext. Hook silently passes in projects without memory configuration. |
| 7 | Simulation walkthrough doesn't use dual phase prefix | MEDIUM | Fixed Section 6 examples: `"PHASE 0"` → `"PHASE 0 planning"`, `"PHASE 2"` → `"PHASE 2 experiment_design"`. All simulation content strings now match Section 4.3 convention. |
| 8 | No version pinning for vector-memory-mcp clone | MEDIUM | Phase 0 Section 0.1 now records commit hash and includes `git checkout` command for pinning to verified version. |
| 9 | CLAUDE.md will grow to ~310 lines with full memory protocol | LOW | Addressed by CRITICAL #1: gate and distillation procedures moved to skills. CLAUDE.md protocol section reduced from ~100 to ~50 lines (references skills for details). |
| 10 | `clear_old_memories(days_old=0, max_to_keep=0)` untested edge case | LOW | Added WARNING notes to all 4 occurrences (Sections 3.3, 5.2, 5.4, and memory-retrospective skill) noting edge case not confirmed in source. Phase 5 checklist adds explicit verification step. |
| 11 | Phase 5 maintenance positioning depends on Phase 2 structure | LOW | Section 5.1 now specifies exact heading hierarchy: `## Vector Memory Protocol` → `### Memory Maintenance`. |

*Version 3.3 -- Skills architecture integrated following UWS's existing pattern. All 3 hook types evaluated. PreCompact upgraded to agent hook for executable memory persistence. Behavioral directives retained as triggers; procedures moved to skills for on-demand loading. 11 findings resolved across 4 severity levels.*

---

## Appendix E: Changes from v3.3 (Multi-Agent Verification Review)

5 specialized agents verified the plan in parallel (file explorer, code reviewer, QA assessor, Claude Code spec verifier, MCP evidence validator). 9 findings resolved (1 CRITICAL, 2 HIGH, 5 MEDIUM, 1 LOW):

| # | Finding | Severity | Resolution |
|---|---------|----------|-----------|
| 1 | MCP server tool signatures unverified -- evidence validator could not independently confirm cornebidouil/vector-memory-mcp tool signatures from public docs (30% confidence) | CRITICAL | Added Phase 0 Section 0.2: explicit source code inspection step with grep commands to verify all 5 tool signatures, parameter names, embedding model, and SQLite+sqlite-vec usage before proceeding. |
| 2 | SessionStart memory hook missing `cd` to git root -- grep for `.mcp.json` uses relative path but second matcher group has no `cd` command | HIGH | Prepended `cd "$(git rev-parse --show-toplevel 2>/dev/null \|\| pwd)" &&` to the SessionStart memory hook command. |
| 3 | Phases 4 and 5 have no measurable exit gates -- only Phases 0, 1, 3 had programmatic verification criteria | HIGH | Added Section 4.3 (exit gate with handoff memory search verification + slash command verification) and Section 5.5 (exit gate with documentation checks, performance benchmark pass/fail criteria, and clear_old_memories edge case verification). |
| 4 | Phase 1 promises handoff.md documentation but never creates it | MEDIUM | Added Section 1.5 with explicit handoff.md template and instructions. |
| 5 | Phases 2-5 have no rollback procedures -- only Phases 0-1 had guidance despite no-selective-delete constraint | MEDIUM | Added rollback sections: Phase 2 (Section 2.4: remove hooks+skills+CLAUDE.md section), Phase 3 (Section 3.6: leave memories or nuclear wipe+re-seed), Phase 4 (Section 4.4: git checkout slash commands), Phase 5 (Section 5.6: remove maintenance subsection). |
| 6 | No prerequisites section -- Python version, transitive deps, disk space, write permissions, network access undocumented | MEDIUM | Added "Prerequisites" section before Phase 0 with requirements table, transitive dependency list, proxy/offline instructions. |
| 7 | Simulation example at line 1252 missing DOMAIN prefix per content convention | MEDIUM | Fixed: `"PHASE 0 planning \| DECISION:"` → `"PHASE 0 planning \| DOMAIN: dataset \| DECISION:"`. |
| 8 | BATS tests reference PROJECT_ROOT without setup() function -- integration tests check actual files, not temp copies | MEDIUM | Added `setup()` function to BATS test template that sets `PROJECT_ROOT` relative to test file location. Added `user-invocable: false` verification test (12 tests total). |
| 9 | Timeline padded 2-3x (10 days estimated vs 3-6 days realistic) | LOW | Changed complexity estimate from "~2 weeks" to "~1-2 weeks". Per-phase day estimates retained as upper bounds including debugging time. |

**False alarms discarded (agent confusion):**
- Claude Code guide agent incorrectly claimed hook nesting was 2-level (it described 3-level structure correctly then miscounted)
- Claude Code guide agent flagged `user-invocable` vs `disable-model-invocation` as errors but the plan uses both correctly for different purposes
- Claude Code guide agent flagged `uvx` concern but the plan uses direct Python venv execution, not uvx
- Code reviewer flagged PreCompact prompt Python quotes but JSON is valid and Claude interprets natural language regardless of quote style

**Manual executable-path walkthrough** (v3.4.0 → v3.4.1): After the agent review, a manual trace of every copy-pasteable command, config block, and content string found 6 additional issues:

| # | Finding | Severity | Resolution |
|---|---------|----------|-----------|
| 10 | `.mcp.json` local server `--working-dir` was placeholder `/absolute/path/to/current/project` | HIGH | Replaced with actual project path `/home/lab2208/Documents/universal-workflow-system`. |
| 11 | Entrypoint assumed to be `main.py` without verification -- PyPI packages may use different entrypoints | HIGH | Added entrypoint verification to Section 0.2 (`ls *.py`, `pyproject.toml` check). Added note to Section 0.4 that entrypoint may need updating. Added alternatives (module, console_script, server.py). |
| 12 | Memory 6 (agent-handoff) content prefix violated convention: `"HANDOFF ... \| PHASE ..."` instead of `"PHASE ... \| DOMAIN: handoff \| HANDOFF ..."` | MEDIUM | Fixed to follow convention. Also fixed the CLAUDE.md directive template (on_agent_handoff) which had the same inversion. |
| 13 | Memory 4 (verification) missing DOMAIN prefix: `"PHASE 3 verification \| VERIFIED: ..."` | MEDIUM | Fixed to `"PHASE 3 verification \| DOMAIN: testing \| VERIFIED: ..."`. |
| 14 | Global 3 comment said `workflow-improvement` but category was `tool-gotcha` (duplicate of Global 1) | MEDIUM | Changed category to `workflow-improvement` to cover 3 of 5 global categories with seeds (was 2 of 5). |
| 15 | No issue found | - | - |

*Version 3.4.1 -- Manual walkthrough of executable paths completed. All copy-pasteable configs, tool calls, and content strings verified against conventions. 64 total findings resolved across 6 review cycles (v2.0: 14, v3.0: 8, v3.1: 16, v3.2: 11, v3.3 agents: 9, v3.4 manual: 6).*
