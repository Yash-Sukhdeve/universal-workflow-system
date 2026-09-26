# CLAUDE.md

Guidance for Claude Code when working on this repository.

## Project Overview

Universal Workflow System (UWS) is a git-native workflow system for AI-assisted
development: phase-gated SDLC and research workflows, checkpoints, and context
recovery that survive session breaks and context compaction. State lives in a
project's `.workflow/` directory. Users install it as a Claude Code plugin
(`plugins/uws/`), with the per-project installer (`claude-code-integration/`), or as
the `uws` CLI (`bin/uws`).

The PROMISE 2026 paper, benchmarks and replication package live in their own repository,
https://github.com/Yash-Sukhdeve/uws-promise-2026 (split out with history).

## Common Commands

### Testing
```bash
./tests/run_all_tests.sh </dev/null        # all BATS tests (close stdin: some tests run init)
./tests/run_all_tests.sh -c unit           # or: integration | system
./tests/run_all_tests.sh -l                # with ShellCheck
bats tests/unit/test_checkpoint.bats       # one file
```

### Workflow Operations
```bash
./scripts/recover_context.sh            # recover context after a session break
./scripts/status.sh                     # current workflow status
./scripts/checkpoint.sh create "msg"    # also: list, restore, status
./scripts/sdlc.sh status|start|next|goto|fail|goal|check|deliverables|reset
./scripts/research.sh status|start|next|reject|goal|check|deliverables|reset
./scripts/orchestrate.sh dispatch|collect|status   # route a phase to its subagent
./scripts/gen_subagents.sh              # regenerate .claude/agents/uws-*.md from docs/personas/
```

SDLC phases: `requirements → design → implementation → verification → deployment → maintenance`.
Research phases: `hypothesis → literature_review → experiment_design → data_collection →
analysis → peer_review → publication`. Once a goal is declared (`sdlc.sh goal "..."`),
`next` is blocked until the phase's deliverables are checked off (`--force` overrides).

## Architecture

### State Files (`.workflow/`)
- `state.yaml` - flat top-level keys `project_type`, `goal`, `current_phase`,
  `current_checkpoint`, `last_updated`, `sdlc_phase`/`research_phase`, plus `phases:` and
  the `methodology_progress:` deliverable ledger
- `checkpoints.log` - `TIMESTAMP | CP_ID | DESC`
- `handoff.md` - human-readable handoff for the next session
- `agents/registry.yaml` - agent definitions and transition rules
- `active_agent:` in `state.yaml` - last agent `orchestrate.sh` dispatched (`record_active_agent`)
- `checkpoints/snapshots/<CP_ID>/` - state snapshots (gitignored)

### Agents
Seven roles (`researcher`, `architect`, `implementer`, `experimenter`, `optimizer`,
`deployer`, `documenter`). Personas are in `docs/personas/`; `scripts/gen_subagents.sh`
turns them into Claude Code subagents in `.claude/agents/uws-<role>.md`. The research
group follows `docs/personas/apocalypt.md`.

### Phases and Checkpoints
UWS phases: `phase_1_planning → phase_2_implementation → phase_3_validation →
phase_4_delivery → phase_5_maintenance`; SDLC/research phases map onto them
(`uws_phase_for_methodology` in `scripts/lib/workflow_routing.sh`). Checkpoint IDs are
`CP_<phase>_<seq>`.

### Claude Code integration (three delivery paths)
- `plugins/uws/` - the marketplace plugin (`.claude-plugin/marketplace.json` at the repo
  root lists it). `scripts/` and `agents/` there are symlinks that the plugin cache
  materializes; commands call `${CLAUDE_PLUGIN_ROOT}/bin/uws`, never a bare `uws`
  (an older `uws` on the user's PATH would win).
- `claude-code-integration/install.sh` - writes `.uws/`, `.claude/commands/uws*.md` and
  hooks into a user's project.
- `.claude/` in this repo - commands, skills, agents and hooks for developing UWS itself.

Verify integration changes against real Claude Code, not only BATS: install into a scratch
project with an isolated `CLAUDE_CONFIG_DIR` and run `claude -p ... --output-format
stream-json --verbose`; `claude plugin validate .` checks the manifests.

## Portability rules (CI enforces these)

Scripts must run on macOS (`/bin/bash` 3.2, BSD sed/date) as well as Linux:
- no `sed -i 's/..' file` - use `sed_inplace` / `append_after_match` from `scripts/lib/portable.sh`
- no `date +%N`/`%3N` - use `now_ms`; no `head -c -N`
- no `${var,,}`/`${var^^}`, `declare -A`, `mapfile`, namerefs
- empty arrays under `set -u`: `${arr[@]+"${arr[@]}"}`
- `grep -c pat || echo 0` prints `0` twice on no match - use `|| true`
- yq is optional: code and tests must accept both quoted (sed) and unquoted (yq) scalars

## Test Infrastructure

BATS tests in `tests/{unit,integration,system}` share `tests/helpers/test_helper.bash`
(`setup_test_environment`, `create_full_test_environment`, `assert_*`, `measure_time`).
A bare `! cmd` line never fails a bats test - use `run` and check `$status`.
`tests/integration/test_installability.bats` checks what a user's project actually receives.

## Session Workflow

1. The SessionStart hook runs context recovery; read `.workflow/handoff.md` for next actions.
2. Checkpoint at milestones: `./scripts/checkpoint.sh create "description"`.
3. Update `handoff.md` before ending a session.

This repository's own `.git/hooks/pre-commit` stages `.workflow/state.yaml` into every
commit; use `git commit --no-verify` for code-only commits.

## Vector Memory Protocol

This repository uses two vector-memory MCP servers (`mcp__vector_memory_local`,
`mcp__vector_memory_global`). The full protocol (what to store and when, categories, tag
format, maintenance, recovery) is in the `vector-memory` skill
(`.claude/skills/vector-memory/SKILL.md`). Markdown/YAML files remain the source of truth.

## Key Conventions

- Checkpoint before and after major changes
- State YAML uses `yq` when available and falls back to grep/sed
- Never record work that did not happen (no simulated results in logs or state)

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
