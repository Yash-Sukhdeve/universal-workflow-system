# UWS State Schema Documentation

## Overview

UWS currently has two state schemas produced by different initialization paths. Both are valid; scripts read whichever fields they need using `grep`/`sed` patterns.

## Schema v1.0 (init_workflow.sh)

Produced by: `scripts/init_workflow.sh`

```yaml
# Top-level fields
project_type: "software"          # research|ml|software|llm|optimization|deployment|hybrid
current_phase: "phase_1_planning" # phase_1_planning through phase_5_maintenance
current_checkpoint: "CP_1_001"    # CP_<phase>_<seq>
last_updated: "2026-02-17T10:00:00-05:00"

# Context bridge for session continuity
context_bridge:
  critical_info: []
  next_actions:
    - "Review project requirements"
    - "Set up development environment"
  dependencies: []

# Metadata
metadata:
  version: "1.0.0"
  workflow_version: "1.0.0"
  created: "2026-02-17T10:00:00-05:00"
```

### Scripts that read v1.0 fields

| Script | Fields read |
|--------|-------------|
| `status.sh` | `current_phase`, `current_checkpoint`, `project_type`, `last_updated` |
| `checkpoint.sh` | `current_checkpoint`, `last_updated` |
| `recover_context.sh` | `current_phase`, `current_checkpoint`, `project_type` |
| `sdlc.sh` | `current_phase`, reads from `sdlc` section if present |
| `research.sh` | `current_phase`, reads from `research` section if present |
| `orchestrate.sh` | `sdlc_phase`/`research_phase`, `goal`; writes `active_agent` on dispatch |

## Schema v2.0 (claude-code-integration/install.sh)

Produced by: `claude-code-integration/install.sh`

```yaml
# Current workflow position
current_phase: "phase_1_planning"
current_checkpoint: "CP_INIT"

# Project metadata (nested)
project:
  name: "my-project"
  type: "software"
  initialized: true
  init_date: "2026-02-17T10:00:00-05:00"

# Active agent tracking
active_agent:
  name: null
  activated_at: null
  status: "inactive"

# Phase progress tracking
phases:
  phase_1_planning:
    status: "active"
    progress: 0
    started_at: "2026-02-17T10:00:00-05:00"
  phase_2_implementation:
    status: "pending"
    progress: 0
  # ... through phase_5_maintenance

# System health
health:
  status: "healthy"
  last_check: "2026-02-17T10:00:00-05:00"

# Schema metadata
metadata:
  schema_version: "2.0"
  last_updated: "2026-02-17T10:00:00-05:00"
  created_by: "claude-code-integration"
```

### Additional fields in v2.0

| Field | Purpose |
|-------|---------|
| `project.name` | Human-readable project name |
| `project.initialized` | Boolean flag |
| `active_agent.*` | Last agent dispatched by `orchestrate.sh` (see below) |
| `phases.*` | Per-phase status, progress percentage, timestamps |
| `health.*` | System health monitoring |
| `metadata.schema_version` | Schema version identifier |

## Active agent (`active_agent`)

Both schemas share this block. `orchestrate.sh dispatch` writes it through
`record_active_agent` (`scripts/lib/workflow_routing.sh`), replacing any earlier
block, and logs `<timestamp> | AGENT_DISPATCHED | <agent>` to `checkpoints.log`:

```yaml
active_agent:
  name: "researcher"
  status: "active"
  activated_at: "2026-09-24T10:00:00-0400"
```

Readers: the managed block of `handoff.md` ("Active agent"), `status.sh`,
`recover_context.sh`, `submit.sh` (which `workspace/<agent>/` to stage) and the
dashboard. Agents run as Claude Code subagents; nothing asks the main session to
adopt a persona.

Retired: `.workflow/agents/active.yaml` (persona blocks for the main session),
`.workflow/skills/enabled.yaml`, `.workflow/skills/catalog.yaml` and the
`enabled_skills` key belonged to the removed `activate_agent.sh` / `enable_skill.sh`.
Nothing reads them; `scripts/migrate_state.sh --clean` removes the files (after
backing them up), and a leftover `enabled_skills` key is harmless.

## Compatibility

All core scripts use `grep`-based field extraction (e.g., `grep "^current_phase:"`) which works with both schemas since they share the same top-level field names for `current_phase`, `current_checkpoint`, and `last_updated`.

The `project_type` field differs in location:
- v1.0: `project_type:` (top-level)
- v2.0: `project.type:` (nested under `project`)

Scripts handle this by checking both patterns.

## Schema Unification (Deferred)

Merging schemas v1.0 and v2.0 into a single canonical schema is deferred to a future release. This would touch 22+ files and requires migration tests. For now:

- **v1.0 is canonical** for `init_workflow.sh` (development use)
- **v2.0 adds Claude Code fields** for the plugin installer
- Both produce valid state files that all scripts can read
