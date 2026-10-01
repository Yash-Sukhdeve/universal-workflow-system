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
./scripts/research.sh check <name>      # evidence checks (init|ledger|numbers|gate <phase>|...)
./scripts/research.sh bib fetch|build   # BibTeX into bib_sources/, references.bib from it
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
- `agents/registry.yaml` - descriptions and capabilities of the seven roles (no transition
  rules: `validate_agent_transition` allows any transition when none are defined)
- `active_agent:` in `state.yaml` - last agent `orchestrate.sh` dispatched (`record_active_agent`)
- `checkpoints/snapshots/<CP_ID>/` - state snapshots (gitignored)
- Knowledge base: `docs/kb/` (tracked; `scripts/kb.sh` + `lib/kb_utils.sh`, `uws kb`); only the PI (`kb.pi` in `config.yaml`) promotes items to trusted
- Meta-learning: scripts append outcomes to `docs/kb/outcomes.tsv` via `kb_outcome` (best effort, no-op without `docs/kb`); `uws kb learn` turns them into `proposal` candidates that only the PI approves and nothing applies automatically
- Global KB `<global memory dir>/kb` (its own git repo, `uws kb init --global`; `--global`/`global:K-...`), read-only imports (`uws kb import`, `scripts/kb_import.py`), TASK.md leads and the per-machine usage log `docs/kb/.cache/usage.tsv` (R4): design section 18. Tests: `test_helper.bash` sets `UWS_KB_GUARD_ROOT`, so no KB write lands in this checkout unless a test sets `UWS_KB_ALLOW_GUARDED_WRITE=1`

### Agents
Seven roles (`researcher`, `architect`, `implementer`, `experimenter`, `optimizer`,
`deployer`, `documenter`). Personas are in `docs/personas/`; `scripts/gen_subagents.sh`
turns them into Claude Code subagents in `.claude/agents/uws-<role>.md`. The research
group follows `docs/personas/apocalypt.md`.
Research team (`docs/design/research-team.md`): six `uws-rt-*` agents, the `uws-research-lead` skill, and `scripts/research_check.py` (stdlib-only gate that `research.sh next` runs when `research/ledger/` exists; `run`/`repro` are its only commands that execute code, `retraction --online` its only network use).

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

User-facing hints ("run ... next") go through `uws_hint` in `scripts/lib/uws_ui.sh`: the
plugin prints `/uws:<command>`, the CLI `uws ...` (or its path when `uws` on PATH is another
install). Never print `./scripts/...`, `$0` or a bare `uws` from a script. The release
number is in `VERSION` (with `plugin.json` and the installers' literals; a test checks them).

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
- no `source <(...)` (it reads nothing on bash 3.2): write a temp file and source that
- in bats, a line that is only `[[ ... ]]` never fails under bash 3.2: write `[[ ... ]] || false`
- colour codes only when stdout is a terminal (the colour blocks reset them otherwise)
- `scripts/research_check.py`, `scripts/kb_import.py` and `tests/fixtures/kb/make_vector_db.py`:
  Python standard library only

## Test Infrastructure

BATS tests in `tests/{unit,integration,system}` share `tests/helpers/test_helper.bash`
(`setup_test_environment`, `create_full_test_environment`, `assert_*`, `measure_time`).
A bare `! cmd` line never fails a bats test - use `run` and check `$status`.
`tests/integration/test_installability.bats` checks what a user's project actually receives.

## Session Workflow

1. The SessionStart hook runs context recovery; read `.workflow/handoff.md` for next actions.
2. Checkpoint at milestones: `./scripts/checkpoint.sh create "description"`.
3. Update `handoff.md` before ending a session.

A checkout where `init` was run has a UWS pre-commit hook. Older versions of it staged
`.workflow/state.yaml` into every commit (re-running init replaces it); use
`git commit --no-verify` for code-only commits.

## Vector Memory Protocol

Optional: when the vector-memory MCP servers (`mcp__vector_memory_local`,
`mcp__vector_memory_global`) are configured (set up by `UWS_VECTOR_MEMORY=true` init; the
tracked `.mcp.json` points at the maintainer's install), follow the `vector-memory` skill
(`.claude/skills/vector-memory/SKILL.md`): what to store and when, categories, tag format,
maintenance, recovery. Markdown/YAML files remain the source of truth.

## Key Conventions

- Checkpoint before and after major changes
- State YAML uses `yq` when available and falls back to grep/sed
- Never record work that did not happen (no simulated results in logs or state)

## graphify

Only when `graphify-out/` exists (it is gitignored and built locally with `graphify`): it holds
a knowledge graph with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
