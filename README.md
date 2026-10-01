# Universal Workflow System (UWS)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Release](https://img.shields.io/github/v/release/Yash-Sukhdeve/universal-workflow-system)](https://github.com/Yash-Sukhdeve/universal-workflow-system/releases)
[![CI](https://github.com/Yash-Sukhdeve/universal-workflow-system/actions/workflows/ci.yml/badge.svg)](https://github.com/Yash-Sukhdeve/universal-workflow-system/actions)

UWS keeps the state of a project's work in the project's own git repository, in a
`.workflow/` directory: the goal, the current SDLC or research phase and its
deliverables, checkpoints, and handoff notes for the next session. Claude Code reads that
state at the start of every session and checkpoints it before every context compaction,
so work survives session breaks. Each phase can be handed to a role subagent, and an
optional research team checks claims, citations and numbers against a ledger before a
phase gate lets the work move on.

What a session looks like with the `uws` CLI (real output, shortened):

```text
$ uws init software
  ...
  2. Declare the goal: uws sdlc goal "<what you are building>" (optional; turns on deliverable gating)
  3. Run: uws sdlc start to begin SDLC
$ uws sdlc goal "A CLI calculator with tests"
✓ Goal declared: A CLI calculator with tests
$ uws sdlc start
Starting SDLC: Requirements Phase
$ uws sdlc next
✗ Blocked: 3 unmet deliverable(s) in 'requirements'.
   [1] Requirements document with user stories and acceptance criteria
   [2] Non-functional requirements defined
   [3] Failure modes documented for each feature
Override with: uws sdlc next --force
$ uws orchestrate dispatch "Write the requirements"
✓ Prepared dispatch for researcher (sdlc:requirements)
DISPATCH: agent=researcher subagent=.claude/agents/uws-researcher.md phase=sdlc:requirements ...
$ uws sdlc check 1
✓ Marked [1]: Requirements document with user stories and acceptance criteria
$ uws checkpoint create "Requirements drafted"
✓ Checkpoint created: CP_1_002
```

`examples/nodejs-webapp/walkthrough.sh` (SDLC) and `examples/python-ml-project/walkthrough.sh`
(research) run complete cycles.

## Contents

- [Install](#install)
- [Your first session](#your-first-session)
- [Commands](#commands)
- [Workflows and gates](#workflows-and-gates)
- [Subagents](#subagents)
- [Research team](#research-team)
- [Knowledge base](#knowledge-base)
- [What `uws init` changes in your project](#what-uws-init-changes-in-your-project)
- [Optional: vector memory, dashboard, Antigravity](#optional-vector-memory-dashboard-antigravity)
- [Development](#development)

## Install

Three ways in. They share the `.workflow/` format, but they do not provide the same
features:

| | Option 1: plugin | Option 2: per-project installer | Option 3: `uws` CLI |
|---|---|---|---|
| Slash commands | `/uws:status`, `/uws:sdlc`, ... | `/uws-status`, `/uws-sdlc`, ... | none |
| Session-start context, checkpoint before compaction | yes | yes | no |
| Role subagents and research team | yes | no | only with the plugin, or agent files copied in ([Subagents](#subagents)) |
| `uws` in your own terminal | via the plugin's path (below) | no | yes |
| Goal and deliverable gate | yes | no | yes |
| `orchestrate`, knowledge base, research checks, dashboard | yes | no | yes |
| Lives in | Claude Code's plugin cache | `.uws/` and `.claude/` committed to the repo | a clone of this repository |

The plugin and the CLI run the same code. The per-project installer writes a smaller,
self-contained subset into the repository so that collaborators get it without installing
anything.

**Prerequisites.** Bash 3.2 or newer (the macOS default works) and git 2. `python3` (3.7+,
standard library only) for the research checks, the BibTeX tools, the dashboard and
`uws kb import`; `curl` for `uws research bib fetch`; `jq` for the per-project installer
to merge into an existing `.claude/settings.json`. Vector memory (optional) needs Python
3.9+ and about 1.5 GB.

### Option 1: Claude Code plugin (recommended)

Inside Claude Code:

```
/plugin marketplace add Yash-Sukhdeve/universal-workflow-system
/plugin install uws@uws
```

Then, in a project: `/uws:init`. The plugin's commands are listed under
[Commands](#commands).

The plugin puts no `uws` on your shell's PATH. Steps that only the PI may run in their
own terminal (approving knowledge-base items, `uws kb pi --set`) use the plugin's CLI,
`~/.claude/plugins/cache/uws/uws/<version>/bin/uws` (under `$CLAUDE_CONFIG_DIR` if you set
it). When Claude is refused such a step it prints the full command. To have a short name,
link it, and run this again after a plugin update:

```bash
ln -sf "$(ls -d ~/.claude/plugins/cache/uws/uws/*/ | tail -1)bin/uws" ~/.local/bin/uws
```

### Option 2: per-project installer

```bash
# in your project directory (add "-s -- --yes" after bash for unattended installs)
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash
git add .uws/ .claude/ .workflow/ CLAUDE.md .gitignore && git commit -m "Add UWS workflow"
```

It adds `/uws`, `/uws-status`, `/uws-checkpoint`, `/uws-recover`, `/uws-handoff`,
`/uws-sdlc` and `/uws-research`, the two hooks, and these permissions to
`.claude/settings.json`: `Bash(./.uws/scripts/*:*)`, `Bash(cat .workflow/*:*)`,
`Bash(grep:*)`, `Bash(tail:*)`, `Bash(head:*)`, `Bash(git status:*)`, `Bash(git branch:*)`,
`Bash(git rev-parse:*)`. Its scripts have no goal or deliverable gate. To remove it, run
`claude-code-integration/uninstall.sh` from a clone of this repository inside the project
(`--dry-run` lists what it would remove). Details:
[claude-code-integration/README.md](claude-code-integration/README.md).

### Option 3: command line

```bash
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git ~/uws
~/uws/install.sh          # links ~/.local/bin/uws to ~/uws/bin/uws
cd your-project
uws init
```

Without `install.sh`, call `~/uws/bin/uws` instead of `uws`. Running
`~/uws/scripts/init_workflow.sh` directly also works and writes a `./uws` wrapper into
the project. In Claude Code, the CLI alone gives no slash commands, hooks or subagents;
install the plugin as well, or see [Subagents](#subagents).

## Your first session

```bash
uws init                                  # or /uws:init; detects the project type
uws sdlc goal "A CLI calculator with tests"   # optional: turns on the deliverable gate
uws sdlc start                            # or: uws research start
uws sdlc deliverables                     # what this phase must produce
uws orchestrate dispatch "Write the requirements"   # brief for the phase's subagent
#   ... the subagent writes workspace/researcher/...; you review it ...
uws sdlc check 1                          # tick a deliverable (by its number)
uws sdlc next                             # refused while deliverables are open
uws checkpoint create "Requirements done"
```

Before you stop, update `.workflow/handoff.md` (in Claude Code: `/uws:handoff`). The
next session starts with a short summary of the state, the open Next Actions and
blockers from the handoff, and the latest checkpoints; `uws recover` (`/uws:recover`)
prints the full report. Commit `.workflow/` so the state travels with the repository.

## Commands

| What | CLI | Plugin | Per-project installer |
|---|---|---|---|
| Set up `.workflow/` | `uws init [type]` | `/uws:init` | (the installer) |
| Status | `uws status [-v\|-c]` | `/uws:status` | `/uws-status` |
| Recover context | `uws recover` | `/uws:recover` | `/uws-recover` |
| Update the handoff | edit `.workflow/handoff.md` | `/uws:handoff` | `/uws-handoff` |
| Checkpoint | `uws checkpoint create "msg"` (also `list`, `restore <ID>`, `verify`, `status`) | `/uws:checkpoint "msg"` | `/uws-checkpoint "msg"` |
| SDLC | `uws sdlc <action>` | `/uws:sdlc <action>` | `/uws-sdlc <action>` (no goal/check) |
| Research | `uws research <action>` | `/uws:research <action>` | `/uws-research <action>` (no goal/check) |
| Research checks | `uws research check <name>` | `/uws:research-check <name>` | - |
| Phase dispatch | `uws orchestrate dispatch\|collect\|status` | `/uws:orchestrate` | - |
| Knowledge base | `uws kb <verb>` | `/uws:kb <verb>` | - |
| Review a change request | `uws review list\|approve <CR>\|reject <CR>` | - | - |
| Dashboard | `uws dashboard` | - | - |
| Help | `uws help`, `uws <command> help` | - | `/uws` |

`<action>` for sdlc: `status`, `start`, `next`, `goto <phase>`, `fail "<reason>"`,
`reset`, `goal "<objective>"`, `deliverables [phase]`, `check <n>`. Research has `reject
"<reason>"` instead of `fail` and `goto`. The plugin also exposes its two skills as
`/uws:uws-kb` and `/uws:uws-research-lead`.

## Workflows and gates

```
SDLC:     requirements → design → implementation → verification → deployment → maintenance
Research: hypothesis → literature_review → experiment_design → data_collection
          → analysis → peer_review → publication
```

- **Goal and deliverables.** Each phase has a numbered list of deliverables
  (`uws sdlc deliverables`). Without a goal, `next` and `goto` move freely. Once a goal is
  declared (`uws sdlc goal "..."` or `uws research goal "..."`), they are refused until
  every deliverable of the current phase is ticked with `check <n>`; `--force` overrides.
- **Failure.** `uws sdlc fail "<reason>"` moves verification back to implementation,
  deployment back to verification and maintenance back to deployment. `uws research
  reject "<reason>"` moves back for refinement (for example analysis to
  experiment_design).
- **Evidence gate.** In a project with `research/ledger/`, `uws research next` also runs
  the research team's gate for the phase (below). `--force "<reason>"` overrides it, is
  logged in `.workflow/logs/decisions.log`, and is always refused at publication.
- Methodology phases map onto five coarse UWS phases (`phase_1_planning` ...
  `phase_5_maintenance`) that number the checkpoints (`CP_<phase>_<seq>`).

## Subagents

Seven roles do the phase work: researcher, architect, implementer, experimenter,
optimizer, deployer and documenter. Each is a Claude Code subagent generated from
`docs/personas/` by `scripts/gen_subagents.sh`, and runs in its own context.
`uws orchestrate dispatch "<task>"` writes the brief to `workspace/<role>/TASK.md`,
records the role in `state.yaml` and prints a `DISPATCH:` line; the subagent writes its
artifact under `workspace/<role>/`; `uws orchestrate collect "<summary>"` stages it as a
change request, and a person approves it with `uws review approve <CR-ID>`.

The plugin ships the subagents (named `uws:uws-<role>`) and runs this loop as
`/uws:orchestrate`. With the CLI only, the subagent files are not in your project, and
`dispatch` warns you. Copy them in to use them without the plugin:

```bash
mkdir -p .claude/agents && cp ~/uws/.claude/agents/uws-*.md .claude/agents/
```

## Research team

For work that has to survive review, the `uws-research-lead` skill acts as lead
scientist and dispatches six research subagents: scout (finds sources, proposes claims),
verifier (checks each claim against its source, never its own), methodologist
(pre-registers experiments), engineer (data manifest, recorded runs, reproduction),
writer (text only from verified ledger rows) and red team (adversarial review). Their
work is recorded in append-only ledgers under `research/`, and a checker (Python standard
library) runs at every research phase gate. The design, with every rule, is
[docs/design/research-team.md](docs/design/research-team.md).

A minimal path from nothing to a passing publication gate:

```bash
uws research check init                  # research/, bib_sources/, decisions.md template
uws research bib fetch doi:10.1371/journal.pcbi.1003285 --key sandve2013
uws research bib build                   # references.bib (in paper/ if it exists), only from bib_sources/
uws research check plan new EXP-LEAK     # fill every section, then freeze and commit it
uws research check plan freeze EXP-LEAK  #   before any data or run exists
git add research && git commit -m "freeze EXP-LEAK"
uws research check data add research/data/raw/x.csv --source "survey export" --version 1 \
    --split '{"column": "split", "group_key": "scenario_id"}' --origin measured
uws research check run --exp EXP-LEAK --input research/data/raw/x.csv \
    --output 'out/results_*.json' -- python3 analysis.py
uws research check numbers add '{"macro": "\\TestAuc", "output": "out/results_20261001.json",
    "pointer": "/test_auc", "rounding": "round:3", "metric": "held-out ROC-AUC",
    "data_origin": "measured", "evaluation": "held-out", "exp": "EXP-LEAK", "run": "RUN-0001"}'
uws research check macros                # writes paper/generated/numbers.tex
uws research check repro all             # re-runs the recorded command, compares each number
uws research check gate analysis         # file:line findings; exit 1 blocks
```

- The manuscript loads the macros with `\input{generated/numbers}` (from `paper/`) and
  prints `\TestAuc{}`, never a typed number. `check numbers --help` and `check claims
  --help` list every field of a row; `claims add` takes rows such as
  `{"text": "...", "category": "own_observation", "numbers": ["N-0001"], "author": "writer", "status": "unverified"}`.
- A hand-typed number is reported where results are reported, and anywhere its sentence
  names a ledger metric or it equals a ledger value. `% uws:literal <reason>` on the line
  accepts it, except a number close to a ledger value or one in a sentence about a ledger
  metric: those need a PI decision, `% uws:literal D-<n> <reason>`.
- A sentence that prints a simulated or synthetic number must say so (simulated,
  synthetic, generated, modelled, artificial); if only its paragraph, heading or the title
  says so, it is a warning. A cross-validation value must be called one; presenting it as
  held-out blocks from peer_review on.
- Decisions live in `research/pi/decisions.md` as records that start with
  `D-001 | raised <date> by <role> | phase <phase>` and count only once their
  `PI DECISION:` line is filled in. A plan changed after results needs one
  (`plan freeze ... --reason "..." --pi-decision D-<n>`), and the manuscript must name the
  deviation's DEV-ID.
- peer_review needs a red-team review, `research/reviews/REV-001.md`, that names the
  manuscript it covers (`Manuscript: sha256:<hash>` from
  `uws research check manuscript-hash`) and has a findings table
  (`| F-001 | blocking/major/minor | open/fixed | finding | evidence | settling check |`).
  Any manuscript edit re-opens review.
- publication needs the PI's line in `research/pi/decisions.md`:
  `PUBLICATION-APPROVAL: sha256:<manuscript hash> by <PI>`.
- BibTeX is only ever downloaded (arXiv, DOI, DBLP, ACL Anthology). arXiv entries carry
  the year of the latest arXiv version. When an endpoint blocks scripts (DBLP may return
  a bot check), the PI supplies the file: `bib fetch <id> --from-file <file> --pi-decision
  D-<n>`. `check retraction --online` caches Crossref retraction notices; a source without
  a DOI stays a "retraction status unknown" warning.
- Settings such as `numbers_tex`, `references`, `prose_dirs` and `tex_main` go in
  `research/checks.json`.

## Knowledge base

`uws kb` keeps what a project has learned in `docs/kb/`, tracked in git: one Markdown file
per claim, each with its source and, where possible, a command that re-checks it.

```bash
uws kb pi --set you@example.com          # once, in your own terminal: who may promote items
uws kb add --type fact --claim "The API timeout is 30 seconds" --evidence verified \
  --source file:src/config.py:12 --check "grep -q 'TIMEOUT = 30' src/config.py"
uws kb verify <ID>                       # run the check (the item stays a candidate)
uws kb approve <ID>                      # PI only, own terminal: candidate -> trusted
uws kb search timeout                    # trusted items only; --all for every status
uws kb verify --changed                  # re-check items whose watched files changed
uws kb prune                             # dry run of the removal rules; --apply to act
```

- New items are candidates. `search` shows trusted items unless you pass `--all` or
  `--status <status>`, and says on stderr when only other items match. Exit codes: 1 no
  match, 2 invalid or without a resolvable source, 3 duplicate, 4 undeclared conflict with
  a trusted item, 5 a check failed, 6 refused.
- Only the PI promotes: `approve` requires your `git config user.email` to equal `kb.pi`
  in `.workflow/config.yaml`, and refuses to run inside an AI agent. Agents may `add`,
  `verify` and `recommend`; `uws kb review` lists what waits. This is a process safeguard,
  not a security boundary: every promotion is logged in `docs/kb/events.tsv`, where
  `uws kb lint` flags one without a PI approval.
- Items become stale or disputed when their watched files change or their check fails;
  `prune --apply` moves retired items to `docs/kb/retired/` with `git mv`
  (`uws kb restore <ID>` undoes it). Nothing is committed for you.
- Session start adds one line (`KB: 12 trusted, 1 stale, ...`). In Claude Code,
  `/uws:kb search ...` runs without a prompt; Claude Code asks before it invokes the
  `uws-kb` skill on its own. In `claude -p`, allow the skill with
  `--allowedTools "Skill(uws:uws-kb)"`.
- Also in [docs/design/knowledge-base.md](docs/design/knowledge-base.md): meta-learning
  (`uws kb learn` turns recorded process outcomes into proposals that only the PI
  approves), a cross-project knowledge base (`uws kb init --global`, `--global`,
  `global:K-...` IDs) and read-only imports of older memory stores (`uws kb import`).

## What `uws init` changes in your project

- `.workflow/`: `state.yaml`, `config.yaml`, `handoff.md`, `checkpoints.log`,
  `agents/registry.yaml`. Checkpoint snapshots go to `.workflow/checkpoints/snapshots/`.
- `.gitignore`: lines for workflow temp files, `.workflow/checkpoints/snapshots/` and
  `workspace/*`.
- `.git/hooks/pre-commit`, unless the project already has one. It acts only on a commit
  that stages `.workflow/state.yaml`: it refreshes `last_updated` there. Delete it to opt
  out. Re-running `uws init` replaces the hook of older UWS versions, which staged
  `state.yaml` into every commit.
- `./uws`, a wrapper for the CLI, only when you run `scripts/init_workflow.sh` directly.
- `workspace/<role>/` appears on the first `orchestrate dispatch`, `docs/kb/` on the first
  `uws kb add`, `.mcp.json` only if you set up vector memory (below).

Re-running `uws init` in an initialised project leaves `.workflow/` alone: in a terminal
it asks first, and a non-interactive run backs it up and starts over only with
`UWS_FORCE_REINIT=true`.

## Optional: vector memory, dashboard, Antigravity

**Vector memory** (semantic search over stored memories through two MCP servers) is
never set up unless you ask: answer `y` when `uws init` asks, or run
`UWS_VECTOR_MEMORY=true uws init` (non-interactive runs skip it; `UWS_SKIP_VECTOR_MEMORY=true`
always skips it). Installing the server is a ~1.5 GB download into `~/.uws/tools/`;
`install.sh` offers it too, and also honours `UWS_VECTOR_MEMORY=true`. Setting it up for a
project writes `.mcp.json` with this machine's paths and adds `memory/` to `.gitignore`
(and `.mcp.json` itself when UWS created it). See
[docs/uws-vector-memory-integration-plan.md](docs/uws-vector-memory-integration-plan.md).

**Dashboard.** `uws dashboard` serves a local page with the change-request inbox, the
issue board and the active agent at http://localhost:8080 (`UWS_DASHBOARD_PORT`; live
updates use the next port, or `UWS_DASHBOARD_WS_PORT`, when the Python `websockets`
package is installed). It runs in the foreground; stop it with Ctrl+C. It listens on
127.0.0.1 only, sends no CORS headers, and accepts a POST (approve, reject, move) only from
its own page, which carries a per-run token.

**Gemini Antigravity.** From your project, run `~/uws/antigravity-integration/install.sh`.
It installs the `uws-*` workflows into `.agent/workflows/`
([docs/tutorials/antigravity_guide.md](docs/tutorials/antigravity_guide.md)).

## Development

```bash
./tests/run_all_tests.sh </dev/null      # all BATS tests (close stdin: some tests run init)
./tests/run_all_tests.sh -c unit         # or integration, system
./tests/run_all_tests.sh -l              # with ShellCheck
bats tests/unit/test_checkpoint.bats     # one file
```

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) also rejects GNU-only and
bash-4-only constructs and bats assertions that cannot fail under bash 3.2, checks that
the Python tools use only the standard library, validates the plugin with
`claude plugin validate`, and runs the tests on Ubuntu and macOS. Contributor rules are
in [CONTRIBUTING.md](CONTRIBUTING.md) and [CLAUDE.md](CLAUDE.md); changes are listed in
[CHANGELOG.md](CHANGELOG.md).

Issues: https://github.com/Yash-Sukhdeve/universal-workflow-system/issues. License: MIT
([LICENSE](LICENSE)).
