# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Knowledge base (increment 2)

Increment 2 of `docs/design/knowledge-base.md` (section 18): the global KB, imports of the older
memory stores, knowledge leads in subagent briefs, and usage counts for rule R4. Only the PI
promotes items, global ones included; imports create candidates only and only read their
sources; the vector-memory servers, skills and SessionStart hook are unchanged.

#### Added
- Global KB at `<global memory dir>/kb` (`UWS_GLOBAL_MEMORY_DIR`, `global_memory_dir` in
  `~/.config/uws/config.yaml`, or `~/uws-global-knowledge`): `uws kb init --global` creates it
  and runs `git init`; every global write is refused (exit 2) unless it is its own git
  repository. `--global`, `--scope global` or a `global:K-...` ID (as an ID argument, or the
  value of `--supersedes`, `--contradicts` or `--by`) select it, also outside a UWS project;
  `add --global` prints the new ID as `global:K-...`. It keeps its own PI (`uws kb pi --set <email> --global`, `<global kb>/config.yaml`).
  Global claims may not name project or home paths (`add`/`import` refuse; `lint` I8)
- `uws kb search` ranks trusted project and global items together in the same 5-line,
  1000-byte budget; global lines read `global:K-...`; `--scope project|global` narrows it.
  Queries drop common function words, and `--min-terms N` asks for N matching whole words;
  `search -- <words>` takes words that start with a dash. `show` finds global IDs; `stats` lists
  the global KB and this machine's usage
- `uws kb import vector --db <path> [--scope project|global] [--dry-run]` and
  `uws kb import automemory --dir <path> [--include-index] [--dry-run]` (`scripts/kb_import.py`,
  Python standard library only): a read-only SQLite connection copied into memory with the backup
  API, or for a WAL database a byte copy opened in a temporary directory, so nothing is created
  next to the source (only `memory_metadata` is read), or read-only file reads (`MEMORY.md` is opened only with
  `--include-index`, which imports each top-level entry as `automemory#MEMORY.md:L<line>`; UWS
  never writes it). Rows become
  candidates with `evidence: inferred`, `source: [import:vector-local#<row>]` (or
  `vector-global`, `automemory#<file>`) and `captured_by: import`; the local
  `PHASE n | DOMAIN: d | CATEGORY: c |` prefix is dropped from the claim (a global row keeps its
  `TOOL:` prefix), long rows are cut to 240 bytes, duplicates collapse by R7, retired
  claims are not brought back, secrets and (globally) project paths are skipped, auto-memory
  preferences and feedback stay where they are, and rows that name concrete things (paths, file
  names, snake_case names, backticked terms), none of which the project contains, are flagged
  `suspected-fixture` for the PI (project imports only)
- `uws kb review --imported [--global]`: the import triage queue with the PI's steps (keep or
  correct with `add --supersedes`, refute with `add --contradicts` + `dispute` + `approve`, drop
  with `reject`). `approve` refuses an item whose source is an import. No rule retires an
  import before the PI has reviewed it (decision D6): `prune` skips imports in R2 and R5, and
  an import that `add --supersedes` restates (the restatement may repeat its claim) is retired
  only when the PI approves the restatement
- `uws kb dispute <ID> --by <ID> ["why"]`: mark an active item disputed with counter-evidence
  (verified, observed or reported; a trusted item only by a trusted one)
- `uws kb init` also creates the project KB
- `orchestrate.sh dispatch` appends "Knowledge base leads (to verify; not evidence)" to the
  subagent's `TASK.md`: at most 5 trusted items, 1000 bytes, sharing at least two words with
  the task; nothing when there is no KB or no match
- Usage log `<kb>/.cache/usage.tsv` (gitignored, per machine) for search, show and brief
  retrievals, by session (`UWS_KB_SESSION`, else `CLAUDE_CODE_SESSION_ID`, else the day). R4:
  `prune` lists trusted items (not decisions, older than 90 days) not retrieved in the last 20
  sessions, for the human to retire with `retire <ID> unused` (reason code `unused`); `learn`
  measures `r4-unused-share` and proposes halving a review window above 50% (n >= 5), then
  tracks the adopted change over the next 20 sessions like the other metrics
  (`UWS_KB_UNUSED_SESSIONS`, `UWS_KB_UNUSED_MIN_AGE_DAYS`, `UWS_KB_LEARN_UNUSED_SHARE`)
- Test isolation: `tests/helpers/test_helper.bash` exports `UWS_KB_GUARD_ROOT` and a
  non-existent `UWS_GLOBAL_MEMORY_DIR`; while it is set, no KB write (items, outcomes, usage,
  caches) lands in the UWS checkout unless a test sets `UWS_KB_ALLOW_GUARDED_WRITE=1`
- Tests: `tests/integration/test_kb_global.bats` (15), `test_kb_import.bats` (19) and
  `test_kb_usage.bats` (19), on synthetic SQLite fixtures built with the vector-memory schema
  (`tests/fixtures/kb/make_vector_db.py`, which can also write custom rows and WAL databases);
  `tests/helpers/stdlib_only.py` checks that the importer and the fixture builder import only
  the Python standard library

#### Changed
- Approving an item retires every active item it contradicts as `disproven-by`, not only
  trusted ones, and every active item it supersedes (the imports R1 leaves for the PI)
- `uws kb learn` reports `r4-unused-share` instead of "not measured"

#### Fixed
- The front-matter list parser kept the space before each later quoted element, so an item with
  two or more sources could not be approved
- `uws kb search` (and with it `links` and lint I6) exited 141 with no output once the ranked
  matches passed about 64 KiB: the output budget stopped reading while `sort` and `cut` were
  still writing, and `pipefail` turned their SIGPIPE into the script's exit status. The budget
  now drains its input

### Meta-learning

Increment 3 of `docs/design/knowledge-base.md` (section 6), built before the global KB and
imports at the PI's priority: UWS records what happens to its own process and proposes rule
changes from those counts; only the PI accepts them and nothing is applied automatically.

#### Added
- `docs/kb/outcomes.tsv` (tracked, append-only, `merge=union`): one TSV row per outcome,
  columns `ts event phase role model subject result ref`, written only by scripts through
  `kb_outcome` (`scripts/lib/kb_utils.sh`). Fields are TSV-escaped (tab, newline, CR,
  backslash) and capped at 500 bytes. Recording is best effort: a no-op when `docs/kb` does
  not exist, and a failure prints one line on stderr without changing the caller's exit code
- Writers: `sdlc.sh fail` / `research.sh reject` (`gate_fail`: the reason is now kept),
  `sdlc/research next` (`gate_pass`: deliverables done/total, `forced`, `ungated`),
  `review.sh approve|reject` (`cr_decision`; `reject <CR-ID> "<reason>"` now takes a reason),
  `orchestrate.sh dispatch|collect` (`dispatch`: role, the subagent's `model:`, target, CR ID),
  `uws kb add --type lesson --escaped-from <phase>` (`escape`), and every KB retirement
  (`kb_retire`: reason code, the item's evidence, captured_by, prior status and type)
- `uws kb learn [--dry-run]`: gate-escape rate per phase (> 20% of the last 10 passes),
  first-pass CR rejection rate per role and model (> 40%), disproven rate per evidence level and
  per captured_by (> 25%), and repeated gate-failure reasons (>= 3), each over the last 10
  samples and only with n >= 5 (all configurable, `UWS_KB_LEARN_*`). Escapes count only once the
  PI has approved the lesson; retirements of candidates, inferred items, hypotheses, questions
  and proposals are not counted. A crossing writes a `proposal` candidate with the metric, n,
  the value, the target file, the exact change as a unified diff (a checklist line in
  `scripts/<m>.sh`, a persona Quality Gate item, a model route, a trust weight, or a line in
  the `uws-kb` skill), a falsifier and small-n/confounding caveats. Idempotent: a key (for CR
  proposals, the role) with an open or tracked proposal gets no second one, and only samples
  after the latest proposal count
- `uws kb approve` on a proposal records `approved_ts` and says that nothing was changed; it
  never applies the diff. `learn` then measures the same metric over the next 10 events and
  either records `followup: improved ...` or writes a revert proposal (the diff reversed)
- `uws kb proposals` lists proposals waiting for the PI and adopted ones being measured; the
  SessionStart context, `uws kb stats --short` and `uws status -v` add one line while
  proposals wait. `restore` of a proposal drops its old approval, so it waits for a new decision
- `tests/integration/test_kb_learn.bats` (23 tests: each writer, the no-KB and failure
  guards, every threshold, n < 5, idempotence and dry run, the candidate/inferred guard,
  approve leaving the target file untouched, restore, revert and improvement tracking, the
  session line)

#### Not built
- The R4-unused-share metric: it needs R4 usage counts, which are not built, and would not
  come from `outcomes.tsv`; `learn` says it is not measured (built in increment 2, above)

#### Fixed
- `review.sh reject` no longer stops under `set -e` when `NOTIFICATIONS.md` is missing
- `review.sh list` reads the agent with `grep -F` (the pattern was a regex by accident)

### Knowledge base

Increment 1 of `docs/design/knowledge-base.md`: a project knowledge base in `docs/kb/`,
tracked in git, where every item has a source and only the PI promotes items to trusted.

#### Added
- `uws kb` (`scripts/kb.sh`, `scripts/lib/kb_utils.sh`): `add`, `search`, `links`, `show`,
  `verify`, `recommend`, `review`, `approve`, `reject`, `pi`, `prune`, `retire`, `restore`,
  `lint`, `stats`. One Markdown file per item with flat front matter (awk-parsed; yq not
  needed), content-hash IDs (`K-<yyyymmdd>-<hex>`), and an append-only `docs/kb/events.tsv`
- `add` is non-interactive and prints the new ID on stdout. It refuses unprovenanced or
  unresolvable sources (exit 2; `file:` sources are pinned to `@<HEAD>`), claims over 240
  bytes, duplicates (exit 3, prints the existing ID), undeclared overlaps with trusted items
  (exit 4), destructive-looking checks and text that looks like a credential
- PI-only promotion: `approve` and `reject` require `git config user.email` to equal `kb.pi`
  in `.workflow/config.yaml` (or `UWS_KB_PI` when the config has none) and refuse (exit 6)
  when run inside an AI agent (`CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `UWS_AGENT`, ...).
  `verify` records `check-passed` but never promotes; agents use `recommend`. `lint` flags
  trusted items whose reviewer is not the PI (I7)
- `search` prints at most 5 lines of at most 200 bytes (1000 bytes total) with status and
  evidence per line; `--status disputed` and `links --type contradicts <ID|words>` list
  disputes
- `verify --changed` re-runs checks of trusted items whose watched files changed (failure ->
  `disputed`, timeout -> `stale`; no check -> `stale`); `prune` applies R1 superseded, R2
  disproven, R3 expired and R5 unpromoted as a dry run, `--apply` moves items to
  `docs/kb/retired/` with `git mv`
- One tier-0 line (`KB: N trusted, N stale, N disputed, N to review. ...`) in the
  SessionStart context, inside the existing 1.2 KB budget; `uws status -v` shows it too
- `uws-kb` skill (`.claude/skills/` and the plugin's new `skills/` directory) and the
  `/uws:kb` plugin command, both calling `${CLAUDE_PLUGIN_ROOT}/bin/uws kb` in the plugin
- `tests/integration/test_kb.bats` (32 tests: the design's acceptance tests 1-14, the PI gate,
  and the research-team interface)

#### Removed
- The `.workflow/knowledge/patterns.yaml` scaffold (nothing wrote to it): `init` no longer
  creates it, `migrate_state.sh --clean` deletes it when it is still the empty template, and
  the stale `.workflow/knowledge/` line is gone from `.gitignore`

### Research team (increment 2)

Increment 2 of `docs/design/research-team.md`: the methodologist, engineer and writer, plan
freeze, data manifests, run records and the repro job, the red-team manuscript hash,
retraction checks and metric formulas. Each failure found in the PROMISE 2026 audit is now
caught by a check (tests in `tests/integration/test_research_team_inc2.bats`, 46 tests).

#### Added
- Subagents `uws-rt-methodologist` (opus), `uws-rt-engineer` and `uws-rt-writer` (sonnet),
  generated from `docs/personas/research-{methodologist,engineer,writer}.md` with
  `apocalypt.md` included once. The engineer and methodologist have Edit; the writer has no
  web tools. `orchestrate.sh` routes experiment_design and analysis to the methodologist,
  data_collection to the engineer and publication to the writer when `research/ledger/`
  exists; the `uws-research-lead` skill (both copies) dispatches all six roles.
- Plan freeze: `research_check.py plan new|freeze <EXP-ID>` writes
  `research/experiments/EXP-*/plan.md` (hypothesis, unit, baseline, metric, controls, split
  and grouping, sample size, decision rule, stopping condition) and records its SHA-256 in
  the append-only `research/ledger/plans.jsonl`. `plan` fails when a plan is incomplete or
  unfrozen (`PLAN-FIELDS`, `PLAN-FREEZE`), changed since its freeze (`PLAN-DRIFT`), when a
  result (a number row or run record naming the experiment) was committed before or with the
  freeze, or the freeze row was edited later (`PLAN-ORDER`, from git history), when a re-freeze
  after results lacks a reason, a recorded PI decision and a `deviations.md` row
  (`PLAN-DEVIATION`), and when a non-literature number names no experiment and is not
  labelled `exploratory` (`PLAN-LINK`). `plan freeze` refuses a first freeze once results
  exist, and a change after results without `--pi-decision D-<n>`.
- Data manifest `research/data/manifest.jsonl` (`data add <path> --source --version --split
  --origin [--generator --seed --labels]`, raw files made read-only). `data` fails on hash
  or size drift (`DATA-HASH`), registered files that are gone (`DATA-MISSING`), raw files and
  number inputs that are not registered (`DATA-UNMANIFESTED`), numbers that name no inputs
  (`DATA-NOINPUT`), runs that used an older version of an input (`DATA-RUNHASH`), generated
  data without a recorded seed, a generator that draws random values without seeding, or
  builds an RNG without a seed (`DATA-SEED`), replaced raw data without a PI decision
  (`DATA-REPLACE`), and incomplete run records (`RUN-SCHEMA`).
- Run records: `run [--exp] [--input]... [--output]... [--seed] [--env] -- <command>` writes
  `research/runs/RUN-*/run.json` (command, commit, dirty flag, inputs and outputs with
  hashes, seeds, environment, exit code, stdout/stderr) and keeps failed runs.
- Repro job: `repro <N-ID ...|all>` re-runs each run at its recorded commit in a scratch copy
  (`git archive`; recorded inputs copied in at their recorded hash; outputs deleted first),
  compares every number within its `tolerance` (default exact, or
  `UWS_RESEARCH_TOLERANCE_DEFAULT`), refuses runs recorded on a dirty tree, reports a re-run
  that changes files of the original project, and writes `research/repro/report-*.json`.
  The analysis, peer_review and publication gates need a passing report for every number's
  current ledger row and run record (`REPRO`); `UWS_RESEARCH_REPRO_MAX_AGE_DAYS` adds an
  age limit.
- Red-team manuscript hash: `manuscript-hash` hashes the manuscript files (prose, number
  macros, references.bib). The peer_review and publication gates need a review whose
  `Manuscript: sha256:...` line matches (`GATE-REVIEW-HASH`), so edits after review re-open it.
- Retraction check: `retraction --online` asks Crossref for each `bib_sources/` DOI
  (`updated-by` on the work, and notices whose `update-to` names it) and appends the answer
  to `research/sources/retractions.jsonl`; exit 2 when Crossref is unreachable, and an
  unreachable attempt never hides an earlier answer. Offline, `retraction` (and every gate
  from literature_review) blocks a verified claim resting on a retracted source and a
  `\cite` of it in a sentence that does not say "retracted"; unchecked, unreachable,
  non-Crossref or DOI-less sources are warnings, never passes.
- Numbers: a row may declare a `formula` over other N-IDs; the check recomputes it and
  compares it with `raw` and with `printed` under the row's rounding (`NUM-FORMULA`: the
  PROMISE false-positive rate, 5.8% for 37/88 = 42.0%, now fails). Non-literature numbers
  declare `evaluation` (`held-out` | `validation` | `cross-validation` | `training` | `n/a`);
  a cross-validation, training or validation macro used in a sentence or caption that does
  not say so fails, and one next to held-out wording warns (`NUM-SPLIT`). A number's `run`
  must list its output at the same hash.
- Slop rule C6: "ground truth", "annotated" or "gold standard" wording on a sentence traced to
  generated data, or to an input whose manifest `labels` is `generator-rule`, fails unless
  the sentence says the labels come from the generator.
- `macros` writes the generated macro file from the number ledger; `init` also scaffolds
  `research/experiments`, `research/data/raw`, `research/runs`, `research/repro`,
  `plans.jsonl` and `manifest.jsonl`.

#### Changed
- The gates no longer print "not checked yet" for these checks. From analysis on they list
  the rules that are still unimplemented (S3, S5, S7, C2, C4 and the INVENTORY report).
- The research-team fixture gained a seeded generator, a frozen plan (EXP-LEAK), a manifest
  row, a real Crossref answer for its one source, and a `Manuscript:` line in REV-001; the
  tests commit the freeze before the results.

### Research team

Increment 1 of the research team (`docs/design/research-team.md` section 11): research
claims, citations and numbers are checked by a program, not by trust.

#### Added
- `scripts/research_check.py` (Python 3.8+ standard library only): `ledger`, `bib`, `quotes`,
  `numbers`, `slop` (rules S1, S2, S4, S6, C1, C3, C5) and `gate <phase>`, plus `init`.
  Findings print as `file:line RULE-ID message` (or `--json`); exit 0 pass, 1 findings,
  2 could not run. The claim ledger rejects a claim verified by its own author, and the
  ledgers are append-only against `HEAD` and `HEAD~1`.
- `scripts/research_bib.sh fetch|build` (`uws research bib …`): downloads BibTeX from
  arXiv, DOI content negotiation, DBLP or the ACL Anthology into `bib_sources/` with a
  `.meta.json` (source URL, HTTP status, SHA-256). It refuses HTML and bot-check pages and
  anything that is not exactly one entry, and writes nothing in that case.
  `references.bib` is built only from `bib_sources/`; keys are renamed through `KEYMAP.tsv`.
- Research subagents `uws-rt-scout` (sonnet), `uws-rt-verifier` and `uws-rt-redteam` (opus),
  generated from `docs/personas/research-*.md` with `apocalypt.md` included verbatim and a
  research output contract (C-IDs instead of REQ-IDs). Model overrides use
  `UWS_AGENT_MODEL_RT_SCOUT` and so on.
- `uws-research-lead` skill (also shipped in the plugin under `skills/`) and the
  `/uws:research-check` plugin command.
- Plugin `SubagentStop` hook for `uws-rt-*` agents (plain and plugin-scoped names): it
  sends an agent back when a claim is verified by its own author, raw data was modified,
  or the report has no "Open questions for the orchestrator" section. It retries at most
  `UWS_RESEARCH_HOOK_RETRIES` times (default 2) and then records a blocker.
- `orchestrate.sh --methodology sdlc|research` and `--agent <role>`.

#### Changed
- `research.sh next` runs the evidence gate when `research/ledger/` exists and fails
  closed. `--force` now needs a reason, is logged to `decisions.log` with category
  `research-gate-force`, and is always refused at publication. `research.sh check <name>`
  runs a check, while `check <n>` still ticks a deliverable.
- `orchestrate.sh`: when both an SDLC and a research phase are active, research work can
  now be dispatched with `--methodology research`. Before, SDLC always won.

### Context hygiene

What UWS injects into Claude's context at session start is small,
correct, plain text and current.

#### Added
- `recover_context.sh --hook` (also `uws recover --hook`): one line of SessionStart
  hook JSON with a plain-text summary capped at 1.2 KB (goal, phases, checkpoint, the
  last three real checkpoints, open next actions and blockers from `handoff.md`, git
  branch and counts). Read-only, silent outside UWS projects. The plugin's
  SessionStart hook and this repository's `.claude/settings.json` both use it
- `handoff.md` now has a UWS-managed summary block between
  `<!-- uws:managed:start -->` / `<!-- uws:managed:end -->`, rendered from
  `state.yaml` and refreshed on every checkpoint, phase change and goal change;
  everything outside the block is never rewritten. Older handoffs are migrated on the
  first refresh (their "Last Session Summary" section becomes the block)
- The managed block now also shows the active agent (linked to its
  `docs/personas/<agent>.md`) and the current phase's remaining deliverables
  (`- **Deliverables (sdlc: design)** - 1/4 done, 3 remaining:` plus the not-yet-checked
  items), sourced from `state.yaml`'s `active_agent` and `methodology_progress` ledger
- `tests/integration/test_context_hygiene.bats` (26 tests)

#### Changed
- Agent activation (`activate_agent.sh`) and SDLC phase transitions (`sdlc.sh next`/
  `goto`) no longer append a "## Agent Activated" / "## Phase Transition" section to
  `handoff.md` on every call — that appending is what made the file grow without bound.
  Both now log a one-line event to `checkpoints.log` instead (`AGENT_ACTIVATED`,
  `PHASE_TRANSITION`), already excluded from recovered context by the `| CP_` filter
  above; the managed block picks up the new agent/phase/deliverables immediately
- Subagents are generated with a per-role `model:` (architect and researcher: `opus`;
  implementer, experimenter, optimizer, deployer, documenter: `sonnet`); override with
  `UWS_AGENT_MODEL_<ROLE>` or `UWS_AGENT_MODEL=inherit` when running
  `scripts/gen_subagents.sh`. Unknown aliases are rejected before any file is written
- Subagents no longer try to ask the user (they have no channel to them): unresolved
  material choices are returned under "Open questions for the orchestrator"
- `CLAUDE.md` is accurate and 58% smaller (16,114 -> 6,821 bytes); the vector-memory
  protocol moved verbatim into the on-demand `vector-memory` skill
- The SessionStart injection for this repository's own state dropped from 5,815 bytes
  (86 lines, 69 ANSI escapes, emoji, box drawing) to 1,172 bytes of JSON
- Human-mode `recover_context.sh` prints no ANSI colour when stdout is not a terminal
  or `NO_COLOR` is set, and its suggestions use `uws ...` commands
- `init` writes a handoff that states facts (project type, init date) instead of
  "Ready to begin planning phase", and resumes with `uws recover` / `/uws:recover`
  instead of `./scripts/recover_context.sh`, which user projects do not have

#### Fixed
- `enable_skill.sh execute` recorded fabricated outcomes ("Found 25 relevant papers",
  "Model size reduced by 75%") and `SKILL_EXECUTED` entries for work that never ran; it
  now refuses and explains that skills run through Claude Code agents
- `/uws:research` advertised a `goto` action that `research.sh` does not have
- Recovery read `project.type` and `metadata.last_updated`, but `state.yaml` uses flat
  keys, so it showed "Project Type: null" and "Last Updated: null"
- Completeness scored an obsolete nested schema (`project.name`, `session.*`,
  `health.*`, ...), so every current project showed "61% PARTIAL"; a freshly
  initialized project now scores 100% (legacy nested keys are still accepted)
- `checkpoint create` wrote `metadata.last_updated`, leaving the flat `last_updated`
  stale; it now updates whichever key the state file uses
- "Recent Checkpoints" listed the `# Format:` comment, `INIT`/`AUTO` markers and
  `AGENT_*`/`SKILL_*` events; only `| CP_` entries are shown (also in the installer's
  SessionStart hook, which additionally read the project type from the flat key)
- A pre-existing handoff containing old "## Agent Activated" / "## Phase Transition"
  sections is cleaned up the next time its managed block refreshes: those sections are
  removed (everything else, including any human-written section, is kept byte-for-byte)
  and a `handoff.md.bak-<timestamp>` backup of the file is written first; a no-op, no
  backup, once nothing is left to remove
- `activate_agent.sh` set `active_agent.name`/`status`/`activated_at` in `state.yaml`
  via `yaml_set`, but without `yq` that function's nested-key fallback only replaces a
  `parent:\n  child:` pair that already exists — it never creates the `active_agent:`
  section, so a freshly initialized project silently never got these fields on its
  first agent activation. The first activation now seeds the section directly; every
  activation after that uses the existing `yaml_set` path as before

### Installability

Every documented install path now produces a working setup, and CI
checks the artifacts a user's project receives rather than only this repository.

#### Added
- Claude Code plugin at `plugins/uws/`, installable with
  `/plugin marketplace add Yash-Sukhdeve/universal-workflow-system` and
  `/plugin install uws@uws`: seven `/uws:*` commands, SessionStart/PreCompact hooks,
  the seven `uws-*` subagents, and a bundled `uws` CLI
- `claude-code-integration/install.sh --yes` (or `UWS_YES=true`) for unattended installs
- `tests/integration/test_installability.bats` (20 tests) covering the installer, the
  global CLI and the plugin; CI now lints user-facing entry points at warning level
  and runs `claude plugin validate`

#### Fixed
- Installer wrote slash commands without the `.md` extension, so Claude Code never
  loaded them; it now writes `uws*.md` and removes the extensionless files on upgrade
- Installer wrote hooks as a flat `[{"event": ...}]` list, which Claude Code ignores;
  hooks now use the nested format with `$CLAUDE_PROJECT_DIR` paths, and upgrades
  migrate the old list while keeping unrelated settings
- Installer prompts read from `/dev/tty`, so `curl | bash` no longer consumes the
  script as input; with no terminal the default answer is used and printed
- Installer no longer adds `.uws/` and `.claude/` to `.gitignore` (clones got hooks
  pointing at missing scripts) and drops the broad `Bash(git:*)`/`Bash(sed:*)`
  permissions it used to grant; generated commands and hooks use portable
  `sed -i.bak` and `date -u`
- Installer's `/uws-status`, `/uws-recover` and `/uws-handoff` used `! cmd` lines,
  which Claude Code does not execute; they now use `` !`cmd` ``
- `bin/uws` ran scripts from the user's project instead of the UWS installation, so
  every command after `uws init` failed with "No such file or directory"
- `uws status` exited 1 without a terminal (`clear` with no `TERM`)
- `init_workflow.sh` no longer moves an existing `.workflow/` aside when run without
  a terminal (set `UWS_FORCE_REINIT=true` to do so), no longer overwrites an existing
  git `pre-commit` hook, and skips the per-project `./uws` wrapper when a global `uws`
  is in use
- The ~1.5GB vector-memory install is opt-in: prompts default to No, and
  non-interactive runs skip it unless `UWS_VECTOR_MEMORY=true`
- macOS: CI had failed there since February. BSD `sed` rejects `sed -i 's/..' file`,
  so every in-place state write failed; bash 3.2 (macOS `/bin/bash`) treats an empty
  `"${arr[@]}"` as unbound and has no `${var,,}`; BSD `date +%s%3N` prints a literal
  `3N`, which crashed `recover_context.sh`. Added `scripts/lib/portable.sh`
  (`sed_inplace`, `append_after_match`, `now_ms`) and a CI step rejecting these
  constructs. First fully green CI run: Ubuntu 741/741, macOS 671/671
- `grep -c … || echo 0` printed `0` twice when nothing matched (e.g. "Modified: 0
  0 files" in recovery and status output)
- CI summary treated skipped jobs as passing; it now requires success
- `.claude-plugin/marketplace.json` and the plugin manifest failed
  `claude plugin validate` (spaces in the name, no `owner`/`plugins`, hooks declared as
  prose)

### Cleanup

Company OS (the FastAPI backend + React dashboard) was a separate product built
inside this repository; it is now extracted to its own private repository so UWS
and Company OS can be versioned and installed independently.

#### Removed
- `company_os/` (FastAPI backend, React dashboard), `code_review/` (its December
  2025 code review), `migrations/`, `docs/implementation/`, and the Company-OS-only
  files under `docs/brainstorm/`, `tests/unit/`, and `tests/integration/`, plus
  `Dockerfile`, `docker-compose.yml`, `.env.example`, `pyproject.toml`, `setup.py`,
  `requirements.txt`, `tests/conftest.py`, and `scripts/start_company_os.sh` — all
  moved to `Yash-Sukhdeve/uws-company-os` with no UWS-side functionality lost (no
  UWS script ever imported from `company_os/`)
- The `uws company-os [start|dashboard]` subcommand and its help text
- The role-play agent and skill commands, which predate Claude Code subagents and
  skills: `scripts/activate_agent.sh` (made the main session adopt a persona by
  writing `.workflow/agents/active.yaml`, which a SessionStart hook told the model to
  read), `scripts/enable_skill.sh` (kept an enabled-skills list that nothing used),
  `.claude/commands/uws-agent.md`, `.claude/commands/uws-skill.md`, the Antigravity
  `uws-agent`/`uws-skill` workflows (`uws-skill` only appended a comment to
  `state.yaml`), the "ACTIVE AGENT ... Read .workflow/agents/active.yaml" SessionStart
  hook in `.claude/settings.json`, and their tests (`tests/unit/test_activate_agent.bats`,
  `tests/unit/test_enable_skill.bats`, `tests/integration/test_agent_transitions.bats`).
  `uws agent` / `uws skill` (and `./uws agent|skill`) now print a one-line pointer to
  `uws orchestrate dispatch` / `/agents` / native skills and exit 2
- `init` no longer creates `.workflow/skills/` (catalog, definitions, chains) or
  `.workflow/agents/{configs,memory}`, and `config.yaml` no longer carries the unused
  `agents.auto_activate` and `skills:` keys; the installer's `state.yaml` has no
  `enabled_skills`. Checkpoints no longer snapshot or restore `agents/active.yaml` /
  `skills/enabled.yaml`. The now-unused `validate_skill`, `require_skill_available`
  and `log_agent` library functions are gone
- `sdlc.sh next` / `research.sh next` no longer "auto-switch" agents (a path that ran
  `activate_agent.sh` only when an `auto_select` key nothing wrote was set); they print
  the subagent that owns the new phase instead

#### Added
- `record_active_agent` / `get_active_agent` (`scripts/lib/workflow_routing.sh`): the
  one job of `activate_agent.sh` that still mattered. `orchestrate.sh dispatch` calls
  it to write `active_agent: {name, status, activated_at}` to `state.yaml` (replacing
  any earlier or legacy block; plain awk, same with or without `yq`) and to log
  `<ts> | AGENT_DISPATCHED | <agent>` to `checkpoints.log`. The handoff managed block,
  `status.sh`, `recover_context.sh`, `submit.sh` and the dashboard read it
- `uws orchestrate <dispatch|collect|status>` and `uws dashboard` CLI commands (also
  in the generated per-project `./uws`)
- `migrate_state.sh --clean` removes the retired `agents/active.yaml`,
  `skills/enabled.yaml` and `skills/catalog.yaml`, backing each up first (it used to
  prune unknown skills from `enabled.yaml`)

#### Changed
- README no longer documents Company OS installation/usage; it points to the new
  repository in one line
- `.gitignore` no longer carries the two `company_os/dashboard/` entries
- The review/PM dashboard (`dashboard/`, `scripts/dashboard_server.py`,
  `scripts/start_dashboard.sh`) is reachable again as `uws dashboard` and is titled
  "UWS Dashboard" ("Company OS" is now the separate product). It shows the project it
  is started from (`UWS_PROJECT_ROOT`, set by `start_dashboard.sh`) instead of the UWS
  installation, runs `review.sh`/`pm.sh` from the installation with that project's
  `WORKFLOW_DIR`, reads the active agent from `state.yaml`, listens on 127.0.0.1 only
  (its POST endpoints approve change requests without authentication), and takes
  `UWS_DASHBOARD_PORT` (default 8080). The plugin ships `dashboard/` so
  `uws dashboard` works from it too
- `status.sh` / `recover_context.sh` show the dispatched agent from `state.yaml` and
  no "Enabled skills" section; `/uws-recover` no longer tells the model to adopt the
  active agent's persona. `submit.sh` stages `workspace/<active_agent.name>/`
- `detect_and_configure.sh` recommendations, README, CONTRIBUTING, `docs/index.html`,
  `docs/state-schema.md` and both `examples/*` (README and `walkthrough.sh`) use
  `uws orchestrate dispatch` instead of the retired commands
- `tests/benchmarks` "agent activation" now times `record_active_agent`; its JSON
  gains an `"operation"` field saying so

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
