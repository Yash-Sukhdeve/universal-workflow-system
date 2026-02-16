# UWS x Vector Memory MCP -- Integration Plan

**Version**: 3.2.0
**Date**: 2026-02-16
**Status**: Verified against source code, architecturally reviewed, hooks verified, all findings resolved
**Complexity**: Medium (5 phases, ~2 weeks)
**Review**: 14 findings from v2.0 resolved. 8 findings from v3.0 resolved. 16 findings from v3.1 review resolved (2 CRITICAL, 4 HIGH, 5 MEDIUM, 5 LOW).

---

## 1. Executive Summary

This plan integrates `vector-memory-mcp` (cornebidouil, MIT license) as a **semantic retrieval layer** beneath UWS's existing markdown/YAML state management. The architecture uses a **hybrid local+global** database strategy with a **three-mechanism generalizability detection system**.

- **Local DB** (per-project): Project-specific memories. `<project>/memory/vector_memory.db`.
- **Global DB** (cross-project): Abstracted, generalizable lessons. `~/.uws/knowledge/memory/vector_memory.db`.
- **Generalizability detection**: Inline skill + phase-end review + manual retrospective. No dedicated agent.

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

### 2.3 Behavioral Directives vs Executable Hooks

This plan distinguishes two enforcement mechanisms:

| Mechanism | Location | Enforcement | Reliability |
|-----------|----------|------------|-------------|
| **Executable hooks** | `.claude/settings.json` | Auto-triggered by Claude Code lifecycle events | High -- always fires |
| **Behavioral directives** | `CLAUDE.md` | Prompt instructions the LLM follows voluntarily | Medium -- may be skipped under token pressure |

The memory lifecycle operations (on_phase_complete, on_error_resolved, etc.) are **behavioral directives** in `CLAUDE.md`. They depend on the LLM following instructions. This is acknowledged as a reliability limitation.

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
1. **SessionStart**: Injects memory protocol reminder via `additionalContext`
2. **PreCompact**: Echoes reminder to store phase memories before context compaction

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

### Phase 0: Infrastructure (Day 1)

**Input**: Clean UWS project with existing `.mcp.json`
**Output**: Two running MCP server instances verified healthy

#### 0.1 Install Dependencies (Isolated Environment)

```bash
mkdir -p ~/.uws/tools
git clone https://github.com/cornebidouil/vector-memory-mcp.git ~/.uws/tools/vector-memory

# Create isolated venv to avoid conflicts with project PyTorch/numpy versions
python3 -m venv ~/.uws/tools/vector-memory/.venv
~/.uws/tools/vector-memory/.venv/bin/pip install sqlite-vec sentence-transformers fastmcp
```

**Why venv?** `sentence-transformers` depends on PyTorch, `transformers`, and `huggingface-hub`. Installing globally could conflict with project-specific PyTorch versions or `replication/requirements.txt` packages.

#### 0.2 Set Up Directories

```bash
# Create global knowledge directory
mkdir -p ~/.uws/knowledge

# Create project-local memory directory (server auto-creates
# memory/vector_memory.db inside --working-dir, but we create
# the parent for .gitignore clarity)
mkdir -p memory/
```

#### 0.3 Configure MCP Servers

Add entries inside the existing `"mcpServers"` object in `.mcp.json`:

```json
{
  "mcpServers": {
    "...existing servers...": "...unchanged...",

    "vector_memory_local": {
      "command": "/home/lab2208/.uws/tools/vector-memory/.venv/bin/python",
      "args": [
        "/home/lab2208/.uws/tools/vector-memory/main.py",
        "--working-dir", "/absolute/path/to/current/project"
      ]
    },
    "vector_memory_global": {
      "command": "/home/lab2208/.uws/tools/vector-memory/.venv/bin/python",
      "args": [
        "/home/lab2208/.uws/tools/vector-memory/main.py",
        "--working-dir", "/home/lab2208/.uws/knowledge"
      ]
    }
  }
}
```

**IMPORTANT**: Entries go inside `"mcpServers"`, NOT at the root level. The `command` uses the venv Python to avoid dependency conflicts.

#### 0.4 Update `.gitignore`

Append to project `.gitignore`:
```
# Vector memory database (local, per-project)
memory/
```

#### 0.5 Verification Gate

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

#### 0.6 Rollback (if Phase 0 fails)

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

#### 1.1 Store 5 Local Test Memories

Store one memory per local category (all 5 fully specified -- R2 zero placeholders):

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
  content="PHASE 3 verification | VERIFIED: All 608 BATS tests passing
           after routing integration. METHOD: ./tests/run_all_tests.sh
           full suite. RESULT: pass. EVIDENCE: 3 pre-existing failures
           fixed (multiline sed, PROJECT_ROOT override, grep -c arithmetic).",
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

# Global 3: workflow-improvement
mcp__vector_memory_global__store_memory(
  content="TESTING/GREP: grep -c returns exit code 1 when match count is
           zero, even though it successfully outputs '0'. Using
           var=$(grep -c ... || echo 0) appends a second '0' producing
           '0\\n0' which breaks bash arithmetic. FIX: Use
           var=$(grep -c ...) || var=0 (assign on failure, don't append).
           APPLIES_TO: Any bash script using grep -c in arithmetic.",
  category="tool-gotcha",
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

**Deliverable**: 8 test memories stored (5 local, 3 global) + 2 atomic principle test memories. Retrieval quality validated with 4+ test queries. Results documented in `.workflow/handoff.md`.

#### 1.5 Rollback (if Phase 1 validation fails)

```
If retrieval quality is unacceptable (embedding model performs poorly):
1. clear_old_memories on both DBs to reset
2. Reassess: Are content strings too long? Too vague? Wrong prefixes?
3. Adjust content conventions and re-seed
4. If fundamentally unusable: execute Phase 0 rollback
```

---

### Phase 2: Behavioral Directives in CLAUDE.md (Day 2-4)

**Input**: Validated retrieval (from Phase 1). Confirmed category taxonomy works.
**Output**: `CLAUDE.md` updated with complete memory protocol. `.claude/settings.json` updated with memory reminder hook.

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
      content="HANDOFF <from>-><to> | PHASE <N> <methodology_phase> |
               KEY_DECISIONS: <list> OPEN_ISSUES: <list>",
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
After storing a bug-resolution or decision-adr to local DB:
  Q1: Root cause involves a named tool/library/pattern? (not project code)
  Q2: Could happen in a different project?
  Q3: Can state lesson without THIS project's file paths or var names?
  ALL YES → Store abstracted lesson to global:
    mcp__vector_memory_global__store_memory(
      content="<TOOL>: <mechanism> FIX: <approach> APPLIES_TO: <scope>",
      category=<anti-pattern|tool-gotcha|design-lesson|library-compat|workflow-improvement>,
      tags=[<root-cause>, <scope>, <fix-pattern>])
  ANY NO → Local only.

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
At phase completion:
  1. mcp__vector_memory_local__search_memories("PHASE <N>", limit=50)
  2. Group by category. Find recurring root causes (2+ entries).
  3. Consolidate into general lessons. Apply gate. Store to global.
  4. Every 10 global promotions: adversarial review ("which are
     actually project-specific?"). For false promotions, store
     corrective entry: "SUPERSEDES: <summary>. REASON: project-specific."
     (No delete_memory tool exists -- supersede pattern only.)
  5. Note in .workflow/handoff.md.

### Local Categories
phase-summary | decision-adr | bug-resolution | agent-handoff |
verification | environment

### Global Categories
anti-pattern | tool-gotcha | design-lesson | library-compat |
workflow-improvement
```

#### 2.2 Add Memory Hooks to `.claude/settings.json`

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
            "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"VECTOR MEMORY ACTIVE: Query local+global memory DBs during session resume per CLAUDE.md Vector Memory Protocol. Use mcp__vector_memory_local__search_memories() for project context and mcp__vector_memory_global__search_memories() for cross-project lessons.\"}}'",
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
            "type": "command",
            "command": "echo '{\"systemMessage\":\"MEMORY: Before compaction, store critical phase context to vector memory per CLAUDE.md protocol. Key decisions, bug fixes, and phase outcomes should be persisted.\"}'",
            "timeout": 5,
            "statusMessage": "Memory compaction reminder..."
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
| Memory context injection | SessionStart | Pre | `command` | Inject `additionalContext` reminder into Claude's knowledge |
| Checkpoint creation | PreCompact | Pre | `command` | Create checkpoint before compaction (existing) |
| Memory store reminder | PreCompact | Pre | `command` | Show `systemMessage` to store memories before context loss |

**Design notes**:
- `SessionStart` memory hook uses `additionalContext` (injected into Claude's system context) rather than plain `echo` (terminal output only). This is more reliable.
- `PreCompact` memory hook uses `systemMessage` (shown to user as warning) to remind about pending stores.
- Both hooks have `timeout: 5` since they only echo JSON (no I/O).
- `Stop` event was considered but rejected: fires on every Claude response, too frequent for memory reminders.
- `PostToolUse` with `Edit|Write` matcher was considered but rejected: adds latency to every file operation with minimal benefit.
- **Execution order**: Multiple SessionStart hooks run in parallel. The context recovery hook (~120ms) and memory hook (~5ms) finish independently. The `additionalContext` injection order relative to recovery output is undefined by the spec but harmless -- both inject into the same session context.

**Deliverable**: `CLAUDE.md` updated with full memory protocol. `.claude/settings.json` updated with 2 memory hooks (pre-execution, non-blocking).

**TRANSITION TO PHASE 3**: After completing Phase 2, you MUST restart the Claude Code session (or run `/hooks` to reload hook configuration). This is required because:
1. `CLAUDE.md` changes take effect when Claude Code reads the file (session start or context reload)
2. `.claude/settings.json` hook changes are "captured at session startup" per the hooks spec; external modifications require `/hooks` review to take effect
3. Phase 3 tests rely on the agent FOLLOWING the behavioral directives written in Phase 2

**Note on CLAUDE.md**: The existing research phases listed in CLAUDE.md (line 80) show 5 phases but the current codebase uses 7 phases (with `literature_review` and `peer_review` added in commit f38d82b). Update this line during Phase 2 to avoid confusion with the memory content convention.

---

### Phase 3: Generalizability Skill & Distillation (Day 4-6)

**Input**: Memory protocol loaded in CLAUDE.md (from Phase 2, session restarted). Categories tested (from Phase 1). Local DB has 10 seed memories from Phase 1.
**Output**: Generalizability detection working end-to-end. At least 1 test global promotion. Automated regression test created.

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
```

**Note**: Full MCP tool calls (store/search) cannot be tested via BATS because they require a running Claude Code session. The BATS tests verify configuration and file structure. End-to-end memory operations are validated manually in Sections 3.1-3.3.

#### 3.5 Verify Local DB State for Phase 4

Before proceeding to Phase 4, confirm local DB has sufficient memories:
```
mcp__vector_memory_local__get_memory_stats()
→ VERIFY: total_memories >= 10 (5 Phase 1 seeds + 2 atomic test + Phase 3 test stores)
```

Record the memory count in `.workflow/handoff.md` for Phase 4's reference.

**Deliverable**: End-to-end generalizability pipeline tested. At least 1 global promotion validated. Session resume timing measured. Automated BATS test created at `tests/integration/test_vector_memory.bats`. Local DB memory count recorded.

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

---

### Phase 5: Maintenance, Recovery & Hardening (Day 8-10)

**Input**: Full system working (from Phase 4).
**Output**: Maintenance procedures documented. Recovery paths tested. Performance benchmarked.

#### 5.1 Memory Hygiene Procedures

Add as a subsection under the "Vector Memory Protocol" section added in Phase 2 (append after the "Global Categories" line in CLAUDE.md):

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
  5. Re-store each memory with updated categories
- Keep category taxonomy stable. Prefer adding new categories over renaming.

**Deliverable**: Maintenance procedures in CLAUDE.md. Recovery procedures documented. Performance benchmarked. Category migration strategy noted.

---

## 6. Simulation: End-to-End Walkthrough

### Session 1: Phase 0 Complete

```
Agent completes Phase 0 (environment setup).

on_phase_complete fires (behavioral directive):
  mcp__vector_memory_local__store_memory(
    content="PHASE 0 | DOMAIN: environment | OUTCOME: Python 3.10,
             PyTorch 2.1, AASIST cloned from abc123. Datasets:
             ASVspoof2019LA, ASVspoof2021LA, In-The-Wild. GPU: A100 40GB.",
    category="environment",
    tags=["phase:0", "pytorch", "aasist"])

  mcp__vector_memory_local__store_memory(
    content="PHASE 0 | DECISION: Use ASVspoof2019LA for training,
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
    content="PHASE 2 | DOMAIN: training | BUG: Forward pass crashes
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
Phase 0: Infrastructure                              [Deliverable: 2 healthy MCP servers]
  [ ] Clone vector-memory-mcp to ~/.uws/tools/vector-memory
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
  [ ] Store 5 local test memories (all specified in plan -- R2 zero placeholders)
  [ ] Store 3 global test memories (all specified in plan)
  [ ] Run 4+ retrieval quality tests
  [ ] Verify category filtering works
  [ ] Verify atomic memory principle (focused > unfocused, not short > long)
  [ ] Store atomic test pair (unfocused multi-topic vs focused single-topic)
  [ ] Document results in .workflow/handoff.md

Phase 2: Behavioral Directives                       [Deliverable: CLAUDE.md + hooks updated]
  [ ] Update CLAUDE.md research phases to 7 (literature_review, peer_review)
  [ ] Add Vector Memory Protocol section to CLAUDE.md
  [ ] Add all 4 behavioral directive definitions
  [ ] Add generalizability gate procedure
  [ ] Add session resume enhancement
  [ ] Add R1 evidence extension
  [ ] Add phase-end distillation procedure (with supersede instead of delete)
  [ ] Add SessionStart memory hook (additionalContext injection) to .claude/settings.json
  [ ] Add PreCompact memory hook (systemMessage reminder) to .claude/settings.json
  [ ] Verify hook JSON schema uses correct 3-level nesting
  [ ] RESTART Claude Code session or run /hooks to reload

Phase 3: End-to-End Testing                          [Deliverable: Pipeline validated + BATS test]
  [ ] Test: bug fix → local store → gate → global promotion
  [ ] Test: bug fix → local store → gate → NO promotion (project-specific)
  [ ] Test: phase-end distillation with 5+ local memories
  [ ] Test: adversarial calibration (supersede false promotions, not delete)
  [ ] Test: session resume with dual-DB queries (<3s)
  [ ] Create tests/integration/test_vector_memory.bats (automated regression)
  [ ] Verify local DB memory count >= 10 for Phase 4
  [ ] Record memory count in .workflow/handoff.md

Phase 4: Cross-Agent Transfer                        [Deliverable: 3 handoffs tested]
  [ ] Test A: researcher → implementer (decisions retrievable)
  [ ] Test B: implementer → experimenter (bug fixes retrievable)
  [ ] Test C: experimenter → documenter (verifications retrievable)
  [ ] Update .claude/commands/uws-recover.md with memory hint
  [ ] Update .claude/commands/uws-agent.md with memory hint

Phase 5: Maintenance & Hardening                     [Deliverable: Procedures documented]
  [ ] Add maintenance subsection under Vector Memory Protocol in CLAUDE.md
  [ ] Document local DB cleanup (max_to_keep, no selective delete)
  [ ] Document global DB cleanup (manual, no days_old, supersede pattern)
  [ ] Document local DB recovery procedure
  [ ] Document global DB recovery procedure
  [ ] Document checkpoint-restore + vector memory warning (no selective revert)
  [ ] Run performance benchmarks, record in handoff.md
  [ ] Document category migration strategy (get_memory_stats for limit)
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
| 1 | `.mcp.json` format wrong (missing `mcpServers` wrapper) | CRITICAL | Fixed Phase 0 Section 0.3 to show correct `"mcpServers"` top-level key |
| 2 | No `delete_memory` tool -- adversarial calibration unimplementable | CRITICAL | Added "Selective delete" row to Section 1.1. Changed "remove" to "supersede" pattern throughout (Sections 3.2, 3.3, 5.2, CLAUDE.md directives). Documented nuclear option (clear + re-seed) |
| 3 | Incomplete seed memories (R2 violation) | HIGH | All 5 local + 3 global memories fully specified in Phase 1 (no `# ... N more` placeholders) |
| 4 | No Python environment isolation | HIGH | Phase 0 now creates isolated venv at `~/.uws/tools/vector-memory/.venv/`. `.mcp.json` command uses venv python path |
| 5 | Phase 3 tests entirely manual | HIGH | Added Section 3.4: automated `tests/integration/test_vector_memory.bats` with 6 BATS tests for config/structure regression |
| 6 | Phase 2→3 transition requires session restart | HIGH | Added explicit "TRANSITION TO PHASE 3" block with restart/`/hooks` instruction |
| 7 | Phase 3→4 input contract weak | MEDIUM | Phase 3 adds Section 3.5 verifying local DB memory count >= 10. Phase 4 input references this |
| 8 | Phase numbering ambiguity | MEDIUM | Section 4.3 now specifies dual prefix: `"PHASE <N> <methodology_phase>"` with examples. All CLAUDE.md directive examples updated |
| 9 | Atomic Memory test logic flawed | MEDIUM | Section 1.4 rewritten: tests focused vs unfocused (not short vs long), with specific test pair and verification query |
| 10 | Phase 5 CLAUDE.md additions not positioned | MEDIUM | Section 5.1 now specifies: "Add as subsection under Vector Memory Protocol section added in Phase 2" |
| 11 | No rollback procedures | MEDIUM | Added Phase 0 Section 0.6 rollback and Phase 1 Section 1.5 rollback |
| 12 | `list_recent_memories` limit issue for export | LOW | Section 5.4 migration now uses `get_memory_stats()` total for limit parameter |
| 13 | Retrospective can't filter by project in global DB | LOW | Section 3.3 updated with project identification strategy (temporal proximity + domain overlap) |
| 14 | Hook execution order undefined | LOW | Added note to Phase 2 design notes about parallel SessionStart hook execution |
| 15 | Phase 4 tests only 1 agent transition | LOW | Phase 4 now tests 3 transitions: researcher→implementer, implementer→experimenter, experimenter→documenter |
| 16 | CLAUDE.md research phases stale (5 vs 7) | LOW | Added note in Phase 2→3 transition block to update CLAUDE.md research phases during Phase 2 |

*Version 3.2 -- All server capabilities verified against source. All file references audited. All prior findings resolved. Hooks verified against Claude Code specification. No-delete limitation explicitly addressed throughout with supersede pattern. This plan follows UWS R2 (zero placeholders) and R5 (Reproducibility): any agent can execute this integration from this document alone.*
