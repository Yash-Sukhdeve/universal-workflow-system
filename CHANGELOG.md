# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Everything since 1.1.0. This includes:
- the Claude Code plugin;
- phase dispatch to real subagents;
- a goal-driven deliverable gate;
- a small, correct session-start context;
- a project knowledge base with meta-learning and a cross-project KB;
- an evidence-checked research team;
- a release-readiness pass over everything a new user meets.

The release number is the PI's decision. The breaking changes below call for a new
major version under SemVer. When it is cut, `VERSION` and
`plugins/uws/.claude-plugin/plugin.json` change together, because Claude Code updates an
installed plugin only when the manifest's version changes. The labels used on master since
February 2026 were never tagged releases: 1.2.0 for the plugin and 1.3.0 for the
per-project installer. They are now one number, read from `VERSION` (currently 1.2.0).

Design history, increment by increment, is in
[docs/design/knowledge-base.md](docs/design/knowledge-base.md) (sections 16-18) and
[docs/design/research-team.md](docs/design/research-team.md) (sections 11-11c).

### Upgrading from 1.1.0 (breaking changes)

- `uws agent`, `uws skill` and `uws company-os` are retired. `uws agent|skill` print a
  pointer and exit 2. Use `uws orchestrate dispatch "<task>"` (or `/uws:orchestrate`),
  Claude Code's `/agents` and native skills. Company OS (the FastAPI backend and React
  dashboard) moved to its own repository, `Yash-Sukhdeve/uws-company-os`.
- These scripts are deleted: `scripts/activate_agent.sh`, `scripts/enable_skill.sh` and
  `scripts/start_company_os.sh`. The per-project installer no longer writes `/uws-agent`
  and `/uws-skill`.
- `init` no longer creates any of these: `.workflow/skills/`,
  `.workflow/knowledge/patterns.yaml`, `.workflow/agents/{configs,memory}`, or the
  top-level `archive/`, `artifacts/`, `phases/` and `workspace/` directories.
  `scripts/migrate_state.sh --clean` removes the retired files from an existing project,
  backing each one up first.
- Once a goal is declared, `sdlc|research next` and `goto` are refused until every
  deliverable of the phase is ticked with `check <n>`. `--force` overrides.
- In a project with `research/ledger/`, `research next` runs the evidence gate and fails
  closed. `next --force` needs a reason, is logged, and is always refused at publication.
- The pre-commit hook that `init` installs no longer stages `.workflow/state.yaml` into
  every commit. Re-run `uws init` in a project to replace the old hook.
- Research projects: a `D-<n>` counts as a PI decision only when its record has a
  filled-in `PI DECISION:` line. Publication needs
  `PUBLICATION-APPROVAL: sha256:<manuscript hash> by <PI>` in `research/pi/decisions.md`.
  A `CR-...` approval counts only where `.uws/crs/` exists to check it.

### Added

- **Claude Code plugin** (`plugins/uws/`; the marketplace is in `.claude-plugin/`). Install
  it with `/plugin marketplace add Yash-Sukhdeve/universal-workflow-system` and
  `/plugin install uws@uws`. It provides:
  - ten `/uws:*` commands: init, status, recover, checkpoint, handoff, sdlc, research,
    research-check, kb, orchestrate;
  - SessionStart, PreCompact and SubagentStop hooks;
  - thirteen subagents (seven roles and six research roles);
  - the `uws-kb` and `uws-research-lead` skills;
  - the bundled `uws` CLI.
- **Phase dispatch.**
  - `uws orchestrate dispatch|collect|status` (`--methodology sdlc|research`,
    `--agent <role>`). It writes the subagent's brief to `workspace/<role>/TASK.md`,
    records the agent in `state.yaml` (`record_active_agent`), and stages the artifact as
    a change request for `uws review approve`.
  - `scripts/gen_subagents.sh` generates the subagents from `docs/personas/` with a model
    per role. Override it with `UWS_AGENT_MODEL_<ROLE>` or `UWS_AGENT_MODEL=inherit`.
- **Goal-driven gate**: `sdlc|research goal`, `deliverables` and `check <n>`. A phase
  change keeps `current_phase`, the `phases:` board, `last_updated` and the handoff in
  step.
- **Session context.**
  - `recover_context.sh --hook` writes the SessionStart context as plain text capped at
    1.2 KB. It holds the goal, the phases, the latest checkpoints, the open next actions
    and blockers, the git state, and one KB line. It is read-only, and silent outside UWS
    projects.
  - `handoff.md` has a UWS-managed summary block rendered from `state.yaml`: phase,
    checkpoint, goal, active agent, the remaining deliverables, and the next bootstrap
    step while the goal or the methodology is still missing. Everything outside the
    block is never rewritten.
- **Knowledge base** (`uws kb`, `docs/kb/`).
  - Items carry a source and a re-runnable check, and only the PI promotes them to
    trusted.
  - Verbs: add, search, links, show, verify, recommend, review, approve, reject, dispute,
    pi, prune, retire, restore, lint, stats, init.
  - Meta-learning: `docs/kb/outcomes.tsv`, `uws kb learn` and `proposals`. Proposals are
    candidates that only the PI approves, and nothing is applied automatically.
  - A cross-project KB (`uws kb init --global`, `--global`, `global:K-...` IDs).
  - Read-only imports of the vector-memory and auto-memory stores (`uws kb import`).
  - Knowledge leads in subagent briefs, and a per-machine usage log for rule R4.
- **Research team.**
  - `scripts/research_check.py` (Python standard library) provides: ledger, bib, quotes,
    numbers [add], claims [add], slop, plan, data, run, repro, retraction,
    manuscript-hash, macros, gate, init.
  - `scripts/research_bib.sh fetch|build` (`uws research bib`).
  - Six `uws-rt-*` subagents, the `uws-research-lead` skill, `/uws:research-check`, and a
    SubagentStop hook that sends a research agent back (at most twice) when it breaks a
    rule.
  - The checks cover claims verified by their own author, append-only ledgers, BibTeX
    that was downloaded, verbatim quotes, numbers traced to output files and runs, and
    pre-registered plans frozen before results. They also cover the data manifest and
    leakage between splits, reproduction of every number, CV values presented as
    held-out, retracted sources, red-team review of the current manuscript, and "slop"
    rules.
  - `check numbers --help` and `check claims --help` list every field of a ledger row.
- **Dashboard**: `uws dashboard` serves the change-request inbox, the issue board and the
  active agent of the current project.
- `VERSION`, the single release number. A test and CI check that `plugin.json`, the
  installers, `uws version`, the status footer and new `state.yaml` files agree.
- `claude-code-integration/install.sh --yes` (or `UWS_YES=true`) for unattended installs.
- Tests: 1019 BATS tests (unit 413, integration 537, system 69), plus 11 benchmark tests
  that CI runs on manual dispatch. New suites test the installed artifacts
  (`test_installability.bats`), the dashboard (`test_dashboard.bats`) and the research
  checks against probes of the gates (`test_research_team_probe.bats`).

### Changed

- **Commands the user can run.** Every next-step hint is now spelled the way the user
  reaches UWS (`scripts/lib/uws_ui.sh`):
  - `/uws:<command>` from the plugin;
  - `uws ...` from the CLI, or the install's `bin/uws` by path when an older `uws` comes
    first on PATH;
  - `./uws ...` from the per-project wrapper.

  Hints never use `./scripts/...`, an internal cache path, or a bare `uws` inside the
  plugin. Knowledge-base steps that only the PI may take name the CLI to run in their
  own terminal.
- **Plain output for agents.** Scripts print no ANSI colour codes when stdout is not a
  terminal (or when `NO_COLOR` or `TERM=dumb` is set). The "yq not found" notice appears
  only on a terminal.
- **`init`** writes only `.workflow/` (plus `.gitignore` lines and the pre-commit hook)
  and ignores checkpoint snapshots. For research projects it suggests the research
  commands. It seeds no Next Actions: the managed block shows the bootstrap steps until
  they are done.
- The vector-memory server is wired into a project (`.mcp.json`, `.gitignore`) only on
  opt-in, also when it is already installed. A `.mcp.json` that UWS creates is
  gitignored.
- `install.sh` requires Bash 3.2 (the macOS default), not 4. It honours
  `UWS_VECTOR_MEMORY=true`, and without a terminal it says that vector memory was
  skipped.
- The per-project installer's session context names the SDLC phase, the research phase
  and the goal. `state.yaml` starts at `CP_1_001`, which matches the log. The bundled
  scripts explain that `goal`/`check` belong to the plugin and the CLI.
- `uws kb search` says on stderr when only candidate, stale or disputed items match.
- `uws research --help`, `research check help` and a bare `research check` work outside
  a UWS project.
- `sdlc.sh`, `research.sh` and `uws help` list goal, deliverables, check and goto, and
  explain the gate.
- Research checks:
  - The field test on the PROMISE 2026 paper (design section 11b) brought these changes:
    - `PLAN-ORDER` follows result provenance.
    - Sentences are split with LaTeX in mind.
    - `NUM-LITERAL` covers numbers with units and more sections.
    - A number row's `where` links hand-typed values to their row.
    - Splits can be declared as structured data, with a leakage check.
    - New rule `BIB-UNDEFINED`.
    - Run records hold the interpreter and the environment lock.
    - `REPRO` accepts only the repro job's re-run.
  - The release-readiness probe (design section 11c) brought these changes:
    - `uws:literal` no longer hides a number close to a ledger value, or one in a
      sentence about a ledger metric. Such a number needs a PI decision.
    - Findings, analysis, performance and outcomes headings are results sections, and a
      ledger-metric number is checked anywhere.
    - CV keys such as `cv5_`, `cv10`, `cvacc` and `kfold` are recognised.
    - A CV value presented as held-out blocks from peer_review on.
    - Append-only checks cover the ledger's whole history.
    - Plan deviations must be reported in the manuscript.
    - C3 accepts a disclosure in the paragraph, heading or title as a warning.
    - `bib build` writes `paper/references.bib` when `paper/` exists.
- `CLAUDE.md` went from 16 KB to about 9 KB and matches the tree. The vector-memory
  protocol moved into the on-demand `vector-memory` skill.
- Subagents return unresolved choices under "Open questions for the orchestrator"
  instead of asking the user.
- Phase transitions and dispatches log one line to `checkpoints.log`, instead of
  appending sections that made `handoff.md` grow without bound.

### Removed

- Company OS and its files, which moved to `Yash-Sukhdeve/uws-company-os`:
  - `company_os/`, `code_review/`, `migrations/`, `docs/implementation/`;
  - `Dockerfile`, `docker-compose.yml`, `.env.example`, `pyproject.toml`, `setup.py`,
    `requirements.txt` and `tests/conftest.py`;
  - `uws company-os`.
- The role-play agent and skill commands:
  - `scripts/activate_agent.sh`, `scripts/enable_skill.sh`, and
    `.claude/commands/uws-agent.md` and `uws-skill.md`;
  - the Antigravity `uws-agent`/`uws-skill` workflows;
  - the SessionStart hook that told the model to adopt a persona;
  - the unused `validate_skill`, `require_skill_available` and `log_agent` functions.
- The `.workflow/knowledge/patterns.yaml` scaffold, which nothing wrote to.

### Fixed

- **Installing UWS**:
  - The per-project installer wrote commands without `.md` and hooks as a flat list, and
    Claude Code loaded neither. Commands are now `.md` files, and hooks use the nested
    format; upgrades migrate the old files.
  - `curl | bash` no longer consumes the script as input.
  - The installer no longer gitignores `.uws/` and `.claude/`.
  - `! cmd` lines in the installer's commands did not run; they now use `` !`cmd` ``.
  - `bin/uws` ran scripts from the user's project, so every command after `init` failed.
  - `uws status` failed without `TERM`.
  - A non-interactive `init` re-run moved `.workflow/` aside; it now leaves it in place.
  - `init` overwrote an existing pre-commit hook; it now leaves it alone.
  - `claude plugin validate` failed on both manifests.
- **macOS**: BSD `sed -i`, bash 3.2 empty arrays and `${var,,}`, and BSD `date +%N` broke
  every state write. `scripts/lib/portable.sh` and CI checks replace these constructs.
  Every bats `[[ ]]` assertion now fails under bash 3.2: 733 lines were no-ops on the
  macOS CI job. A run of the whole suite on bash 3.2.57 found one more failure, which is
  now fixed.
- **Checkpoints and recovery**:
  - `uws checkpoint restore <ID>` refused every checkpoint, because it looked for
    `|CP_x|` while the log writes ` | CP_x | `.
  - `checkpoint list` counted every log line as a checkpoint.
  - Recovery and completeness read an obsolete nested schema. As a result, every project
    showed "61% PARTIAL" and "Project Type: null".
  - `checkpoint create` left the flat `last_updated` stale.
  - "Recent checkpoints" listed comments and events.
  - The auto-checkpoint script called `./scripts/checkpoint.sh`.
- **Hints and help**:
  - `sdlc bogus` printed a literal `\033` escape.
  - `/uws:research` advertised `goto`.
  - Two hints pointed at the maintainer's `~/Documents/...` path.
- **Dashboard**:
  - POST `/api/sessions` wrote into the UWS installation instead of the project,
    because `session_manager.sh` took the install as the project.
  - A restart stopped other projects' dashboards; it now stops only the one on the same
    port.
- **Knowledge base**:
  - An item with two or more sources could not be approved, because the list parser kept
    the spaces.
  - `search` exited 141 with no output beyond about 64 KiB of matches.
  - `review.sh reject` stopped when `NOTIFICATIONS.md` was missing.
- **Research checks**: the field test's integrity gaps, misses and false positives are
  fixed, and listed in design section 11b. Examples:
  - a value reformatted after the plan freeze passed `PLAN-ORDER`;
  - `BIB-UNDEFINED` missed multi-line and biblatex citations;
  - a hand-appended manifest row could switch off `DATA-LEAK`;
  - checks left a stray `.workflow/` in projects without one.

### Security

- Dashboard:
  - It listens on 127.0.0.1 only.
  - It sends no CORS headers and refuses a request whose Host is not its own (DNS
    rebinding).
  - It accepts a POST only from its own page. The POST must come from the dashboard's
    origin, carry the per-run token that the page holds, and be `application/json`.
  - Before this, any web page open in the browser could approve or reject change
    requests and read the API.
- The per-project installer no longer grants `Bash(git:*)`, `Bash(sed:*)` or
  `Bash(date:*)`, and removes them when it upgrades a project.
- `uws kb add` refuses text that looks like a credential. `approve` and `pi --set` refuse
  to run inside an AI agent; this is a process safeguard, not a security boundary.

### Known limitations

- A number measured under generated conditions has no `data_origin` of its own.
- The BibTeX metadata cross-check is not built.
- Repro reports are not signed.
- `PLAN-ORDER` traces provenance only through recorded runs.

The design (section 11b) lists these and the other open items.

## [1.1.0] - 2026-02-17

### Added
- CLI wrapper (`bin/uws`) for unified command interface covering all 15 scripts
- Root-level installer (`install.sh`) with symlink to `~/.local/bin`
- 26 BATS tests for the CLI wrapper (646 total tests)
- Examples for ML research project and Node.js webapp workflows
- GitHub Pages landing site (`docs/index.html`)
- CONTRIBUTORS.md
- CHANGELOG.md
- State schema documentation (`docs/state-schema.md`)
- Vector Memory section in README
- CI/CD section in README
- GitHub repository topics for discoverability

### Fixed
- 22 documentation errors across README, CONTRIBUTING, and plugin files
- Research phases updated from 5 to 7 in README (added literature_review, peer_review)
- Test count badges updated from 361 to 620+
- Plugin/marketplace URLs corrected from `lab2208` to `Yash-Sukhdeve`
- Install script URLs corrected from `YOUR_REPO/main` to `Yash-Sukhdeve/.../master`
- `.env.example` in README updated to match actual file (JWT_SECRET_KEY, postgresql, 15 min)
- MCP config section updated for vector memory servers
- Removed reference to nonexistent `handoff.sh` script

## [1.0.0] - 2026-02-17

### Added
- Initial release with full workflow system
- 7 specialized agents (researcher, architect, implementer, experimenter, optimizer, deployer, documenter)
- Research workflow (7 phases: hypothesis through publication)
- SDLC workflow (6 phases: requirements through maintenance)
- Checkpoint system with snapshot/restore and integrity verification
- Context recovery system with automatic session injection
- Vector memory integration (local + global databases)
- 620 BATS tests across unit, integration, and system categories
- Claude Code plugin with slash commands, hooks, and autonomous skills
- Company OS backend (FastAPI) and React dashboard
- PROMISE 2026 research paper and replication package

[Unreleased]: https://github.com/Yash-Sukhdeve/universal-workflow-system/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Yash-Sukhdeve/universal-workflow-system/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Yash-Sukhdeve/universal-workflow-system/releases/tag/v1.0.0
