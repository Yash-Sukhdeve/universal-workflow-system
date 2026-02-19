# Workflow Handoff

**Last Updated**: 2026-02-19T16:00:00-05:00
**Phase**: phase_4_delivery
**Checkpoint**: CP_4_003
**Active Work**: Auto-discovery config + post-launch maintenance

---

## Recent Changes

### Auto-Discovery for Global Vector Memory Config [COMPLETE]
- **Commit**: `18f0e32` — pushed to `origin/master`
- **Checkpoint**: CP_4_003
- Created `scripts/lib/uws_config.sh` — XDG-compliant config library
  - Config location: `~/.config/uws/config.yaml`
  - Resolution chain per setting: env var → config file → default convention
  - Path validation (catches security.py dot-prefix violations early)
- Modified `scripts/lib/vector_memory_setup.sh` — uses resolved paths instead of hardcoded constants
- Modified `scripts/init_workflow.sh` — `./uws` wrapper resolves install dir at runtime from config
- Created `tests/unit/test_uws_config.bats` — 28 new tests
- **Test suite**: 690/690 pass (28 new + 662 existing, zero regressions)

### Prior: Cross-Project Friction Fix
- **Commit**: `d3534e4` — WORKFLOW_DIR defaults to CWD

### Prior: Vector Memory Setup Integration
- **Commit**: `8d10642` — vector memory setup into default UWS initialization

### Prior: Community Launch v1.1.0
- **Commit**: `535a12a` — full launch with 6 audit findings resolved

---

## Vector Memory Integration — ALL 5 PHASES COMPLETE

All 5 phases executed and verified (see `docs/uws-vector-memory-integration-plan.md` v3.4.1):
- Phase 0: Infrastructure setup
- Phase 1: Seed memories + retrieval validation (14 local + 5 global)
- Phase 2: Protocol, skills, hooks (3 skills, 2 hooks)
- Phase 3: Generalizability testing + distillation (12 BATS tests)
- Phase 4: Cross-agent knowledge transfer (3 handoff transitions)
- Phase 5: Maintenance, recovery, hardening (5/5 benchmarks pass)

---

## Priority Actions (Next Session)

1. Resume other project work (Company OS dashboard, PROMISE paper, etc.)
2. Consider committing remaining untracked/modified files (company_os dashboard changes, checkpoint snapshots)
3. Run periodic vector memory maintenance if DB grows (local >500 → clear_old_memories)

---

## Critical Context

- **Config file**: `~/.config/uws/config.yaml` — auto-generated on first init, editable
  - `global_memory_dir`, `uws_install_dir`, `vector_memory_server`
  - Env overrides: `UWS_GLOBAL_MEMORY_DIR`, `UWS_INSTALL_DIR`, `UWS_VECTOR_SERVER_DIR`
- **Vector memory MCP server**: `~/.uws/tools/vector-memory/` (cornebidouil/vector-memory-mcp)
- **Local DB working dir**: `/home/lab2208/Documents/universal-workflow-system`
- **Global DB working dir**: `/home/lab2208/uws-global-knowledge`
- **Server security constraint**: rejects dot-prefixed path components in working-dir
- **Embedding model**: all-MiniLM-L6-v2 (384D), stored in `~/.cache/huggingface/`
- **No selective delete**: only clear_old_memories (min days_old=1, min max_to_keep=100); delete DB file for full reset
- **Server categories**: code-solution, bug-fix, architecture, learning, tool-usage, debugging, performance, security, other
- **Tag format**: Use hyphens not colons (e.g., `phase-2` not `phase:2`)
- **Test suite**: 690/690 (662 original + 28 uws_config)
- **Local DB**: 26 memories, 1.58 MB
- **Global DB**: 7 memories, 1.56 MB
