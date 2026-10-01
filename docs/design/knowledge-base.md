# UWS Knowledge Base and Meta-Learning: Design

- Status: increments 1, 2 and 3 implemented (sections 16, 18 and 17 say what was built and
  where it differs)
- Author role: uws-architect subagent, 2026-09-24
- Repo state read: `chore/cleanup`, started at `ad6ff7a`, rechecked at `8c2372f` (only Company OS
  removal in between; no cited file changed except `.gitignore` line numbers, updated here)
- Goal (PI): "the workflow should have meta learning ability, a knowledge base that acts as a
  brain to store useful information and timely remove incorrect or unnecessary information."

## 0. Scope, deliverables, constraints

- Scope: one knowledge base (KB) for UWS projects plus a cross-project KB, the item
  lifecycle, meta-learning, migration of today's three memory stores, interfaces, risks, and a
  first increment that can be tested.
- Deliverable: this document only. No code.
- Constraints: git-native plain files are the source of truth; any vector index is a cache
  that can be rebuilt; the session-start context stays inside the existing 1200-byte budget;
  Bash 3.2 and BSD tools (CLAUDE.md "Portability rules"); no automatic changes to rules
  without a human; every removal auditable in git and reversible.

Labels used below: **[verified]** = I opened the file or page in this session and checked
it; **[inference]** = my reasoning, not checked against a source.

## 1. Summary for a freshman

Think of the KB as a lab notebook with rules. Each page holds one claim, says where the
claim came from, and says how to re-check it. A claim starts as a *candidate*. It becomes
*trusted* only after a check passes or a second party reviews it. When the code or document it
depends on changes, the claim is marked *stale* until someone re-checks it. When it is shown
wrong, replaced, or left unused and unchecked, it is *retired*: moved to a `retired/` folder
in git, not deleted, so you can see what was removed and why, and bring it back.

Agents do not get the notebook pasted into every session. They get one line saying the
notebook exists and how many pages need attention. They search it when they need it.

"Meta-learning" here means something concrete: UWS logs what happened to its own work (which
gate failed, which change request was rejected, which trusted claim later turned out wrong),
counts it, and when a pattern repeats often enough it writes a *proposal* to change a
checklist, a route, or a model choice. A human approves or rejects each proposal.

Five main decisions:
1. One Markdown file per item with flat YAML front matter, under `docs/kb/`, tracked in
   git. The vector database stops being a store and becomes an optional cache (ADR-KB-1).
2. Nothing enters without provenance that a script can resolve. Confidence is computed from
   evidence and status; agents cannot set it themselves (ADR-KB-3).
3. Retrieval is pull, not push: at most one KB line at session start and at most 5 items
   (about 1000 bytes) per search or subagent brief (ADR-KB-2).
4. Removal is a rule table that a script can test (superseded, check failing, expired, unused,
   unpromoted), carried out as `git mv` to `retired/` with a reason (Section 5.6).
5. Meta-learning learns only from machine-recorded outcomes (exit codes, review decisions,
   retirements). It never learns from narrative, and it never edits rules itself (Section 6).

## 2. Current state inventory

### 2.1 What exists today [verified]

| Store | Where | Loaded when | Tracked in git? | Notes |
|---|---|---|---|---|
| Vector memory, local | `memory/vector_memory.db` (sqlite), server config in `.mcp.json` `vector_memory_local` | on MCP call; a second SessionStart hook tells the model to query it (`.claude/settings.json:18`) | No: `.gitignore:133` `memory/` | 31 rows |
| Vector memory, global | `~/uws-global-knowledge/memory/vector_memory.db`; path from `scripts/lib/uws_config.sh:140-153` | same | No | 11 rows |
| Protocol | `.claude/skills/vector-memory/SKILL.md`; `memory-gate`, `phase-distillation`, `memory-retrospective` skills | skill description always; body on invoke | Yes | 4 skills |
| Claude Code auto-memory | `~/.claude/projects/<project>/memory/MEMORY.md` + topic files | every session (limits in 2.3) | No (machine-local) | MEMORY.md is 93 lines, 17,871 bytes |
| CLAUDE.md | repo root, 126 lines, 6,566 bytes; `## Vector Memory Protocol` at line 105 | every session | Yes | human-written rules |
| `.workflow/knowledge/` | `patterns.yaml`, written by `scripts/init_workflow.sh:403-418` | read only by `scripts/status.sh:340-342` (counts) | No: `.gitignore:168` | empty template (`patterns: []`) |
| Decisions log | `.workflow/logs/decisions.log` | never | No: `.gitignore:91-92` | 49 entries, all "Created checkpoint" / "Activated agent" events |
| Event history | `.workflow/checkpoints.log` (`AGENT_ACTIVATED` at `scripts/activate_agent.sh:321`, `PHASE_TRANSITION` at `scripts/sdlc.sh:318`) | 3 lines in session hook | No: `*.log` at `.gitignore:91` | |
| Session hook | `scripts/lib/hook_context.sh:30` `UWS_HOOK_MAX_BYTES` default 1200 | SessionStart | Yes | hook must be read-only (`hook_context.sh:12`) |

### 2.2 Defects found in the current memory (evidence for this redesign) [verified]

1. **Duplicates.** Local rows 1-6 and 7-12 are the same six memories stored twice. After
   removing the `CATEGORY: x |` prefix the texts are byte-identical. So 6 of 31 rows (19%) are
   redundant.
2. **Stale facts with no way to notice.** Local row 4 says "All 608 BATS tests passing". The
   handoff (`CP_2_014`/`CP_2_015` in `checkpoints.log`) records 741. Nothing marks row 4 old.
3. **A wrong claim promoted to cross-project memory.** Global row 6 begins "git stash pop
   silently drops changes when merge conflicts occur". The git manual says the opposite:
   "Applying the state can fail with conflicts; in this case, it is not removed from the stash
   list" (https://git-scm.com/docs/git-stash). The row even contradicts itself in its next
   sentence. It passed the `memory-gate` questions (`memory-gate/SKILL.md:16-21`) because
   those questions ask whether a lesson is *general*, not whether it is *true*.
4. **A wrong file name in both memory and protocol.** Global row 8 and
   `vector-memory/SKILL.md:148,159` say the DB file is `memories.db`. The server uses
   `vector_memory.db` (`~/.uws/tools/vector-memory/src/models.py:161`). `memories.db` is a
   leftover file from February.
5. **Test data in the real store.** Local row 13 mixes "configured Docker", a CI change and a
   "batch_size" in a training config. None of these exist in UWS. [inference] It looks like a
   fixture from the Phase 1 atomicity test that was written into the live DB.
6. **No provenance field.** No row records a file, commit, URL, or command. The protocol only
   asks for a phase prefix (`vector-memory/SKILL.md:18`).
7. **Removal cannot happen.** The MCP tool refuses `days_old < 1` (`main.py:260`) and
   `max_to_keep < 100` (`src/security.py:204-208`). "Removal" means adding another row
   (`memory-gate/SKILL.md:38-42`), so wrong rows stay searchable. `delete_memory` exists in
   `src/memory_store.py:474` but is not exposed as a tool.
8. **Contradictory protocol.** `memory-retrospective/SKILL.md:29` suggests
   `clear_old_memories(days_old=0, max_to_keep=0)`. `vector-memory/SKILL.md:150` and the code
   say both values are rejected.
9. **Context outside the budget.** The second SessionStart hook (`settings.json:18`) adds
   278 bytes of context that the 1200-byte cap does not count. It also tells the model to run
   memory searches at every resume. Auto-memory adds 17,871 bytes every session, about 15
   times the UWS budget.
10. **Lost meta-learning signal.** `sdlc.sh fail "<reason>"` prints the reason and regresses
    the phase but does not save the reason anywhere (`scripts/sdlc.sh:548`; same for
    `research.sh reject` at `scripts/research.sh:497`). The
    events it does record go to gitignored logs.

### 2.3 Native Claude Code memory vs what UWS adds [verified from docs, fetched 2026-09-24]

Source: https://code.claude.com/docs/en/memory unless marked otherwise.

- Auto-memory is written by Claude and holds "Your preferences, corrections you give Claude,
  project context Claude can't derive from the code".
- "The first 200 lines of `MEMORY.md`, or the first 25KB, whichever comes first, are loaded
  at the start of every conversation."
- "Claude Code doesn't load topic files such as `user_role.md` ... at startup. Claude reads
  them on demand using its standard file tools".
- "Auto memory is machine-local. All worktrees and subdirectories within the same git
  repository share one auto memory directory. Files are not shared across machines".
- Toggle: `autoMemoryEnabled` in settings, or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`.
- CLAUDE.md: "target under 200 lines per CLAUDE.md file. Longer files consume more context and
  reduce adherence." `.claude/rules/` files with `paths` front matter "only load into context
  when Claude works with matching files".
- Subagents (https://code.claude.com/docs/en/sub-agents): "the main conversation's auto memory
  isn't loaded" into a non-fork subagent. An optional `memory` field (`user` | `project` |
  `local`) gives a subagent its own directory, and the first 200 lines or 25KB of its
  `MEMORY.md` go into its system prompt. No UWS agent sets `memory` today (checked
  `.claude/agents/*.md`).
- Skills (https://code.claude.com/docs/en/skills): "skill descriptions are loaded into
  context ... but full skill content only loads when invoked"; the `description` plus
  `when_to_use` text is "truncated at 1,536 characters". `` !`cmd` `` "runs shell commands
  before the skill content is sent to Claude".
- Hooks (https://code.claude.com/docs/en/hooks): "On `SessionStart`, the hook's
  `additionalContext` is added to the system prompt"; `UserPromptSubmit` also supports
  `additionalContext`. I found no documented size limit, so UWS keeps its own.

**What native memory lacks, and so UWS must add** [inference from the quotes above]:
provenance, evidence levels, checks that can be re-run, staleness tied to source changes,
contradiction links, removal rules, an audit trail in git shared with collaborators (native
auto-memory is machine-local), and a scoped retrieval budget. Native memory stays for what
it is designed for: the user's personal preferences and corrections (Section 7).

## 3. Prior work used (only sources opened in this session)

| Source | What it says (quoted or summarised from the opened page) | How this design uses it |
|---|---|---|
| Park et al., *Generative Agents*, arXiv:2304.03442 (PDF v2, Sec. 4.1-4.2) | Retrieval score = α_recency·recency + α_importance·importance + α_relevance·relevance, each min-max scaled to [0,1], "all αs are set to 1"; recency decays by 0.995 per game hour since last retrieval; importance is a 1-10 score from the LLM; reflections run when summed importance passes 150 | Ranking formula shape (5.3). **Changed**: the LLM-rated "importance" is replaced by a *trust* term from evidence level, because a model's own rating is not grounded evidence [inference] |
| Packer et al., *MemGPT*, arXiv:2310.08560 (abstract) | "virtual context management ... drawing inspiration from hierarchical memory systems in traditional operating systems"; "manages different memory tiers" | Three tiers: session line, search results, files (5.3) |
| Shinn et al., *Reflexion*, arXiv:2303.11366 (abstract) | agents "verbally reflect on task feedback signals, then maintain their own reflective text in an episodic memory buffer"; feedback may be "external or internally simulated" | Lessons come from feedback signals. UWS **allows only external signals** for rule-changing proposals (Section 6) |
| Wang et al., *Voyager*, arXiv:2305.16291 (abstract) | "an ever-growing skill library of executable code"; "self-verification for program improvement" | Best knowledge is executable: a `check` command, and in the end a real test or lint rule (5.2, "graduation") |
| Liu et al., *Lost in the Middle*, arXiv:2307.03172 (abstract) | performance "significantly degrades when models must access relevant information in the middle of long contexts" | Supports a small, ranked injection over a large dump (ADR-KB-2) |
| Nygard, *Documenting Architecture Decisions*, cognitect.com blog, 2011-11-15 | ADR sections Title/Context/Decision/Status/Consequences; status proposed/accepted/deprecated/superseded; "keep the old one around, but mark it as superseded"; ADRs live in the repository | `decision` item body and the retire-not-delete rule |

Not cited because not opened this session: A-MEM, MemoryBank, Mem0, and any study of LLM
confidence calibration. The claim that agent-stated confidence is unreliable is therefore
marked [inference] wherever it appears.

## 4. Data model

### 4.1 Item file

One item per file: `docs/kb/items/<id>.md`. The front matter is flat `key: value`. Lists
are one-line `[a, b]` so `grep`/`awk` can parse them without yq (yq is optional per
CLAUDE.md). The body holds detail, quotes, and for decisions the Nygard sections.

```markdown
---
id: K-20260924-3f9c1a
type: fact
scope: project
status: trusted
claim: "UWS caps SessionStart context at UWS_HOOK_MAX_BYTES, default 1200 bytes."
evidence: verified
source: [file:scripts/lib/hook_context.sh:30@ad6ff7a]
check: "grep -q 'UWS_HOOK_MAX_BYTES:-1200' scripts/lib/hook_context.sh"
watch: [scripts/lib/hook_context.sh]
watch_blob: [eb77b3572c0baf05efa5c57a48f249589960443f]
author: uws-architect
reviewer: human
captured_by: cli
created: 2026-09-24
verified_at: 2026-09-24
review_by: 2027-03-23
supersedes: []
superseded_by:
contradicts: []
supports: []
tags: [hooks, context-budget]
---
Why it matters: the KB session line must fit inside this cap.
```

### 4.2 Fields

| Field | Required | Values / rule |
|---|---|---|
| `id` | yes | `K-<yyyymmdd>-<6 hex of sha1(claim)>`. Content-derived, so two branches do not both mint `K-0005` [inference: sequential IDs collide on merge] |
| `type` | yes | `fact`, `decision` (ADR), `lesson`, `anti-pattern`, `question`, `hypothesis`, `proposal` (meta-learning output, Section 6) |
| `scope` | yes | `project` (this repo) or `global` (cross-project KB) |
| `status` | yes | `candidate`, `trusted`, `stale`, `disputed`, `retired` (state machine 5.1) |
| `claim` | yes | one sentence, at most 240 bytes, no project paths if `scope: global` |
| `evidence` | yes, except `question` | see 4.3 |
| `source` | yes, except `question` | one or more of `file:<path>:<line>@<commit>`, `commit:<sha>`, `url:<url>` (body must hold a verbatim quote), `cmd:<command>#<output-file>@<commit>`, `item:<id>` (for inferred) |
| `check` | required when `evidence: verified` | a shell command, exit 0 means the claim still holds; run with a time limit (default 10 s) |
| `watch`, `watch_blob` | optional | paths whose git blob hash at verify time is recorded; a later change makes the item stale |
| `falsifier` | required for `hypothesis` | the observation that would refute it (apocalypt.md principle 2) |
| `author` | yes | agent role (`uws-implementer`), `human`, or a script name |
| `reviewer` | for trusted non-`verified` items | must differ from `author` |
| `captured_by` | yes | `cli`, `hook:<name>`, `skill:<name>`, `import:<store>#<row>` |
| `created`, `verified_at` | yes | ISO dates |
| `review_by` | yes | date by which it must be re-verified; default per type (4.4) |
| `supersedes`, `superseded_by`, `contradicts`, `supports` | optional | item IDs |
| `retired_at`, `retired_reason` | when retired | reason code from 5.6 |

### 4.3 Evidence levels and computed confidence

The levels follow apocalypt.md line 39: "Separate established facts, reported findings, your
own observations, inferences, hypotheses, estimates, and open questions". Hypotheses and open
questions are *types*, not evidence levels. Estimates are recorded as `inferred`.

| Evidence | Meaning | Provenance required | Can become trusted by | Confidence shown |
|---|---|---|---|---|
| `verified` | a re-runnable `check` passes now | `check` plus a source | `uws kb verify` passing (no human needed for `project`) | high |
| `observed` | seen in this project's real output | `cmd:`/`file:`/`commit:` that resolves | reviewer ≠ author | medium |
| `reported` | stated by an external source | `url:` plus a verbatim quote in the body | reviewer ≠ author, who opened the URL | medium |
| `inferred` | reasoned from other items | `item:` links only | reviewer; never above its weakest input | low |

Confidence is **computed**, not typed in: `confidence = f(evidence, status)`, and it drops one
level once `verified_at` is older than half the `review_by` window. [inference] A model's own
statement of confidence is not evidence, so the design gives it no field.

### 4.4 Default review windows (configurable, Section 9)

`fact` 180 days; `lesson`/`anti-pattern` 365; `decision` no expiry (it changes only by being
superseded, as in Nygard); `question` 30; `hypothesis` 90; `proposal` 30. Items with a
`check` or `watch` are also re-checked whenever their sources change (5.4).

### 4.5 Layout

```
docs/kb/
  items/<id>.md        active items (candidate, trusted, stale, disputed)
  retired/<id>.md      retired items (kept, restorable)
  events.tsv           append-only audit: ts, id, from_status, to_status, reason, actor
  outcomes.tsv         append-only process outcomes (Section 6)
  .cache/              gitignored: search index, usage counts, optional vectors
```

`events.tsv` uses the `.tsv` extension on purpose: `.gitignore:91` ignores `*.log`. The
global KB uses the same layout at `$(uws_global_memory_dir)/kb/` (`uws_config.sh:140-153`),
which must be its own git repository (`uws kb init --global` runs `git init`).

## 5. Lifecycle

### 5.1 State machine

```
candidate --verify ok / review ok--> trusted
candidate --TTL 30d, rejected-----> retired
trusted  --watch blob changed-----> stale   --re-verify ok--> trusted
trusted  --check fails / contradicted-by-trusted--> disputed
stale    --grace 30d passes-------> retired (expired)
disputed --resolved true----------> trusted
disputed --resolved false / 14d---> retired (disproven)
any      --superseded-------------> retired (superseded)
retired  --uws kb restore---------> candidate
```

Only `trusted` items are returned by default. `stale` items appear with `--include-stale`
and a warning marker. `candidate` and `disputed` items appear only in `uws kb review`.

### 5.2 Capture: when, who, how

| Trigger | Who | Item type | Mechanism |
|---|---|---|---|
| Bug fixed with a regression test | implementer | `lesson` (evidence `verified`, `check` = the test) | `uws kb add` at the end of the fix; the skill prompts for it |
| `sdlc.sh fail <reason>` / `research.sh reject <reason>` | script | outcome row (6.1), plus a `question` item "why did <phase> fail" | new line in the `fail)`/`reject)` branch |
| Design decision accepted | architect/human | `decision` with the Nygard body | `uws kb add --type decision` |
| Experiment result | experimenter | `fact`, `cmd:` source pointing to the saved output file | `uws kb add` |
| External doc or paper read | researcher | `fact`, evidence `reported`, with URL and verbatim quote | `uws kb add` |
| Phase end | orchestrator | review queue, not new items | `uws kb review` replaces `phase-distillation` |

There is no automatic capture from free conversation. [inference] Hooks cannot tell a true
lesson from a plausible one; automatic capture would repeat defects 2.2-3 and 2.2-5.

**Graduation** (from Voyager's executable skill library): when a `lesson` or `anti-pattern`
can be written as a BATS test, ShellCheck rule, or lint, the item is retired with reason
`graduated:<test path>`. The rule then lives in CI, where it is always enforced, and not in
context, where it is only advice. For example, CLAUDE.md's `grep -c ... || echo 0` rule is a
candidate for a lint.

### 5.3 Retrieval under a budget

Three tiers (MemGPT's tiering idea):

1. **Session line (tier 0).** `hook_context.sh` adds one fixed line to its tail, at most 120
   bytes: `KB: 23 trusted, 2 stale, 1 disputed, 4 to review. Search: uws kb search <words>`.
   It is computed from `.cache/stats` (rebuilt by write commands), so the hook reads one file
   and stays read-only. Remove the separate vector-memory SessionStart hook
   (`settings.json:18`).
2. **On-demand search (tier 1).** `uws kb search <words> [--type T] [--limit N]` prints at
   most 5 lines, each at most 200 bytes: `K-… [lesson|verified|2026-09-01] <claim> (<first
   source>)`. The total is at most 1000 bytes (`UWS_KB_BRIEF_BYTES`). `uws kb show <id>` prints
   one full item.
3. **Files (tier 2).** Agents may read `items/*.md` directly.

Ranking (Generative Agents' sum with all α = 1, terms changed as noted):
`score = relevance + trust + recency`, each in [0,1]. `relevance` = share of query terms found
in claim, tags, and body in increment 1; cosine similarity from the optional vector cache
later. `trust` = verified 1.0, reported 0.75, observed 0.6, inferred 0.3 (these starting
constants are not from any source; meta-learning may propose changes, Section 6). `recency`
= 0.995^(days since `verified_at`). The 0.995 comes from the paper, which applied it per
*game hour since last retrieval*; applying it per day since verification is my change
[inference].

**Subagents**: `scripts/orchestrate.sh` writes `workspace/<role>/TASK.md` at line 94. Add a
section "Relevant knowledge (trusted, top 5)" filled by `uws kb search "<task text>"`, capped
at 1000 bytes. Subagents do not get the native `memory` field (Section 7).

### 5.4 Revalidation

`uws kb verify [--changed | --all | <id>]`:
- `--changed` (run by `checkpoint.sh create` and by `sdlc/research next`): for each trusted
  item, compare each `watch` path's current `git hash-object` to `watch_blob`. If it changed
  and the item has a `check`, run the check: pass → refresh `verified_at` and `watch_blob`;
  fail → `disputed`. If it changed and there is no `check` → `stale`.
- A `file:` source whose path no longer exists at HEAD → `stale`.
- `url:` sources are never fetched automatically, which avoids network access in hooks;
  expiry from `review_by` covers them.
- Checks run with a time limit (default 10 s each, 60 s total) using a portable timer, since
  GNU `timeout` is not in macOS base [inference]. A timeout counts as "unknown", which marks
  the item stale, not disputed.

### 5.5 Contradictions

- On `add`, the CLI searches for trusted items with overlapping `watch`/tags/terms and prints
  them. The author must pass `--supersedes <id>`, `--contradicts <id>`, or `--no-conflict`.
- `contradicts` a trusted item → the new item stays `candidate` and the old one gets a
  "disputed by" marker in search output. Resolution happens by running both checks or by a
  reviewer; the loser is retired with reason `disproven-by:<id>`.
- Invariant (lint): no two `trusted` items are linked by `contradicts`.

### 5.6 Removal rules (every rule testable)

| Rule | Condition | Action | Automatic? |
|---|---|---|---|
| R1 superseded | a newer item lists it in `supersedes` | retire, `superseded-by:<id>` | yes, on `add` |
| R2 disproven | status `disputed` for 14 days, or a reviewer rules it false | retire, `disproven` | `prune --apply` |
| R3 expired | `review_by` passed → `stale`; stale for 30 more days | retire, `expired` | `prune --apply` |
| R4 unused | not returned by any search in 20 sessions and older than 90 days; `decision` excluded | *propose* retirement | human confirms |
| R5 unpromoted | `candidate` for 30 days | retire, `unpromoted` | `prune --apply` |
| R6 graduated | a test or lint now enforces it | retire, `graduated:<path>` | on `add --graduate` |
| R7 duplicate | same normalised claim hash as an active item | refuse `add` (exit 3) | yes |
| R8 unprovenanced | missing or unresolvable source | refuse `add` (exit 2) | yes |

`uws kb prune` is a dry run by default. It prints the planned moves and changes nothing.
`--apply` does `git mv items/<id>.md retired/<id>.md`, sets `status: retired`,
`retired_at`, and `retired_reason`, and appends to `events.tsv`. It never commits; the human
or orchestrator commits. That keeps the audit in git history, and `uws kb restore <id>`
reverses it. Hard delete exists only as `uws kb purge <id> --secret` for leaked secrets. It
prints a warning that git history still holds the file and must be rewritten by hand.

Usage counts for R4 live in `.cache/usage.tsv` (gitignored), so a search never dirties the
tree. The side effect: R4 is per machine. That is why R4 only proposes.

## 6. Meta-learning

### 6.1 Operational definition

Meta-learning = (a) record outcomes of UWS's own process as machine-written rows, (b) compute
fixed metrics, (c) when a metric crosses a threshold with enough samples, create a `proposal`
item that names a concrete change, (d) a human accepts or rejects it, and (e) after
adoption, measure the same metric again and propose a revert if it did not improve.

### 6.2 What is measured (`docs/kb/outcomes.tsv`, tracked)

Columns: `ts, event, phase, role, model, subject, result, ref`. `ref` is a commit, CR ID, or
item ID. Rows are written only by scripts:

| Event | Written by | Result |
|---|---|---|
| `gate_fail` | `sdlc.sh fail` / `research.sh reject` (the reason is saved; today it is lost, 2.2-10) | reason text, target phase |
| `gate_pass` | `sdlc/research next` | deliverables done/total from `methodology_progress` |
| `cr_decision` | `review.sh approve/reject` | approved / rejected + reason |
| `dispatch` | `orchestrate.sh dispatch/collect` | role, model (from agent front matter `model:`), deliverable path, first-pass CR result |
| `escape` | `uws kb add --type lesson --escaped-from <phase>` | a bug found after the named phase's gate passed |
| `kb_retire` | `prune`/`add` | reason code + the retired item's `evidence` and `captured_by` |

### 6.3 Metrics and proposal thresholds (starting values; each needs n ≥ 5)

| Metric | Proposal triggered | Example change proposed |
|---|---|---|
| Gate-escape rate per phase = escapes / gate_passes | > 20% over the last 10 passes | add the escaped check to that phase's deliverable checklist |
| First-pass CR rejection rate per (role, model) | > 40% | route that role to another model, or add a checklist item from the top rejection reasons |
| Disproven rate per `evidence` level and per `captured_by` | a level or source is disproven > 25% | raise that level's bar (e.g. `observed` needs 2 sources) or lower its `trust` weight |
| Repeated `gate_fail` reason (same normalised text) | ≥ 3 times | a lesson item plus a checklist or test proposal |
| R4-unused share of trusted items | > 50% | shorter review windows or fewer capture triggers |

A proposal item carries: the metric, n, values before and after, the target file (e.g.
`docs/personas/architect.md`, `scripts/orchestrate.sh` routing, a TASK.md template), the
exact diff as text in the body, and `falsifier` ("revert if the metric does not improve over
the next 10 events").

### 6.4 Guards

- **Only external signals.** Metrics read only `outcomes.tsv` rows written by scripts from
  exit codes and review decisions. Reflexion allows "internally simulated" feedback; UWS does
  not use it for rule changes.
- **Only trusted knowledge.** `candidate` and `inferred` items never feed a metric or a
  proposal.
- **Human in the loop.** `uws kb approve <proposal-id>` records the decision. It does not
  apply the diff. A human (or the implementer on explicit instruction) applies it through the
  normal CR flow. Nothing edits CLAUDE.md, personas, settings, or routing by itself.
- **Honest statistics.** Proposals report counts, not causes. Small n and confounding
  (different tasks per model) are stated in every proposal, following apocalypt.md principle
  4 ("Distinguish ... association, and causal evidence").

## 7. Migration: one source of truth

| Current store | Decision | How |
|---|---|---|
| Vector local DB (31 rows) | **import, then retire as a store** | `uws kb import vector --db memory/vector_memory.db` (uses Python's `sqlite3` module; python3 is already a dependency) writes `candidate` items: `evidence: inferred`, `source: [import:vector-local#<row>]`, `captured_by: import`. The 6 duplicate pairs collapse via R7. Row 13 is flagged "suspected fixture" for review. Unpromoted imports retire after 30 days (R5) |
| Vector global DB (11 rows) | import into the global KB as candidates, same way | row 6 goes straight to `disputed` with the git-stash quote as counter-evidence; row 8 is corrected (file name) |
| Vector MCP servers | stop writing; keep the binary available as an optional *cache* backend | remove the SessionStart hook at `settings.json:18`; replace the `vector-memory`, `memory-gate`, `phase-distillation`, `memory-retrospective` skills with one `uws-kb` skill; shrink CLAUDE.md section at line 105 to 3 lines. `.mcp.json` entries: PI decision (D3) |
| Claude Code auto-memory | **keep, narrowed** to what the docs say it is for: user preferences and corrections | UWS never writes to it. Offer `uws kb import automemory` to turn project facts into candidates. The PI then trims `MEMORY.md` to a short index (D2). That is the user's private file, so UWS does not edit it |
| CLAUDE.md / `.claude/rules/` | keep for human-written rules | the KB never writes them; accepted proposals change them through CRs |
| Subagent `memory` field | **do not enable** | it would create 7 more stores without provenance; subagents get KB items through TASK.md |
| `.workflow/knowledge/patterns.yaml` | **retire** | `init_workflow.sh:403-418` stops creating it; `migrate_state.sh` deletes it only if it equals the empty template; `status.sh:340-342` reads `uws kb stats` |
| `.workflow/logs/decisions.log` | leave as is, not imported | its 49 entries are event noise, not decisions |

## 8. Interfaces

### 8.1 CLI (`bin/uws kb …`, implemented in `scripts/kb.sh` + `scripts/lib/kb_utils.sh`)

| Verb | Purpose | Exit codes |
|---|---|---|
| `add --type T --claim "…" --evidence E --source S… [--check C] [--watch P…] [--supersedes ID] [--contradicts ID] [--no-conflict] [--scope global]` | create a candidate (runs R7/R8 and secret scan) | 0 ok, 2 invalid/unprovenanced, 3 duplicate, 4 conflict not declared |
| `search <words> [--type] [--limit ≤5] [--include-stale] [--all]` | ranked, budgeted lines | 0, 1 no match |
| `show <id>` | full item | 0, 1 not found |
| `verify [<id>\|--changed\|--all]` | run checks and watch comparison; promote verified candidates | 0, 5 some disputed |
| `review` / `approve <id>` / `reject <id> "<why>"` | reviewer queue (reviewer ≠ author enforced) | 0, 6 self-review refused |
| `prune [--apply]` | apply R1-R6; dry run by default | 0 |
| `retire <id> "<reason>"` / `restore <id>` | manual retire and undo | 0, 1 |
| `lint` | invariants I1-I6 (8.4) | 0, 1 violation |
| `stats` | counts by status/type/evidence; rebuilds `.cache/stats` | 0 |
| `learn` | compute 6.3 metrics; write proposal candidates | 0 |
| `import vector\|automemory` | migration (7) | 0 |

### 8.2 Claude Code surface

- Skill `uws-kb` (model-invocable; the description says to use it before stating a fact about
  earlier work and after fixing a bug). Its body is short and uses `` !`uws kb stats` `` for
  live counts. Ship it in both `.claude/skills/` and the plugin (`plugins/uws/`, which today
  has commands but no skills directory).
- Command `/uws:kb <verb>` in `plugins/uws/commands/kb.md`, calling
  `${CLAUDE_PLUGIN_ROOT}/bin/uws` (per CLAUDE.md "never a bare `uws`").
- Hooks: tier-0 line inside `hook_context.sh`; `verify --changed` inside `checkpoint.sh
  create`, which the PreCompact hook already calls. No new hook events are needed.

### 8.3 Research team: claim ledger

A paper project uses `type: fact|hypothesis` items tagged `paper:<name>`. Every sentence with
a number or citation in the manuscript maps to an item ID. `uws kb ledger <paper-tag>` prints
the table: claim, evidence, source, status. `lint --paper <tag>` fails if a cited item is not
`trusted`, if a `reported` item lacks a quote, or if a `cmd:` output file is missing. This
enforces apocalypt.md principle 6 ("Keep reported numbers traceable to generated outputs")
and the user's rule R6 (BibTeX from `bib_sources/`): a `url:` source for a paper must point
to the saved `bib_sources/<citekey>.bib`.

### 8.4 Invariants checked by `lint`

I1 every item parses and has the required fields; I2 every trusted item's sources resolve;
I3 no two trusted items contradict; I4 every `supersedes` target is retired; I5 deleting
`.cache/` and rebuilding gives identical `search` output; I6 search and hook output stay
within their byte budgets.

## 9. Configuration (environment variables; all optional)

| Variable | Default | Meaning |
|---|---|---|
| `UWS_KB_DIR` | `docs/kb` | project KB root |
| `UWS_GLOBAL_MEMORY_DIR` | `~/uws-global-knowledge` (existing, `uws_config.sh:140`) | global KB is `<dir>/kb` |
| `UWS_KB_SEARCH_LIMIT` | 5 | max items per search/brief |
| `UWS_KB_ITEM_BYTES` / `UWS_KB_BRIEF_BYTES` | 200 / 1000 | per-line and total caps |
| `UWS_KB_CHECK_TIMEOUT` / `UWS_KB_VERIFY_BUDGET` | 10 / 60 s | check time limits |
| `UWS_KB_CANDIDATE_TTL_DAYS`, `UWS_KB_STALE_GRACE_DAYS`, `UWS_KB_DISPUTE_DAYS` | 30, 30, 14 | R5, R3, R2 |
| `UWS_KB_UNUSED_SESSIONS`, `UWS_KB_UNUSED_MIN_AGE_DAYS` | 20, 90 | R4 |
| `UWS_KB_NOW` | unset | fake clock for tests |

## 10. Risks and failure modes

| # | Failure | Detection | Mitigation |
|---|---|---|---|
| 1 | Agents fill the KB with plausible but untrue items (slop) | disproven-rate metric; lint I2 | R8 provenance gate; reviewer ≠ author; `inferred` is capped at low confidence; auto-retire after 30 days if unpromoted (R5) |
| 2 | Context bloat creeps back | I6 in CI; the hook test measures bytes | fixed tier-0 line; hard caps on search; no full-item injection |
| 3 | Too many stale flags (every edit to a watched file) so people ignore them | stale count in `stats` | prefer `check` over bare `watch`; a changed file with a passing check is refreshed silently |
| 4 | A `check` command is harmful or slow (it is code from an agent) | review at promotion; time limit | checks run only on `verify`, never in the SessionStart hook; commands showing up in `events.tsv` are reviewed like code in the CR diff; refuse checks with `rm`, `git push`, `curl … \|` patterns [inference: a denylist is incomplete, so review is the real control] |
| 5 | Secrets or personal data stored in an item and committed | secret scan on `add` (key patterns, `BEGIN … PRIVATE KEY`) | refuse on match; `purge --secret` with a history-rewrite warning |
| 6 | Prompt injection through retrieved text | n/a at runtime | search output is framed as "evidence to assess", following apocalypt.md principle 10; imperative text in `claim` is flagged by lint |
| 7 | Merge conflicts across branches | git conflict | content-hash IDs; one file per item; `events.tsv`/`outcomes.tsv` append-only, and a `.gitattributes merge=union` line for both |
| 8 | Two agents write at once | lint I1 | `atomic_write`/`atomic_append` from `scripts/lib/atomic_utils.sh:202,311` |
| 9 | The meta-learning loop overfits on small n or learns a confounded "cause" | n shown in each proposal | n ≥ 5, human approval, falsifier with automatic revert proposal |
| 10 | Checkpoint restore rolls back state but not the KB (or the reverse) | lint after restore | the KB is tracked files, so `git checkout` restores both together; `.cache/` is rebuilt |
| 11 | The PI decides to untrack `.workflow/` (pending, handoff Next Actions) | — | `UWS_KB_DIR` can move the KB to a tracked path (D1) |
| 12 | The stale `uws` on PATH (`~/.local/bin/uws` points to a different checkout, `~/Documents/AI_Professor/...`) runs old code without `kb` | `uws kb` says "unknown command" | tests call `bin/uws`; plugin commands use `${CLAUDE_PLUGIN_ROOT}` |
| 13 | The global KB is not a git repo (for example a copied directory) | `kb init --global` check | refuse global writes unless `git rev-parse` succeeds there |

## 11. ADRs (short)

- **ADR-KB-1 Plain files as the source, vector DB as cache.** Status: proposed. Context:
  2.2-1..8 show a DB that cannot delete, has no provenance, and is not in git. Decision: we will
  store items as Markdown in git. Consequences: + review, diff, restore, audit; + no server
  needed; − keyword search is weaker than embeddings. At 42 rows total that is acceptable
  [inference]. An embedding cache in `.cache/` can come later without changing the format.
- **ADR-KB-2 Pull, not push.** Decision: we will inject one line at session start and at most
  5 items on demand. Consequences: + bounded context (supported by Lost in the Middle); −
  agents must remember to search, so the skill description and TASK.md brief do the
  reminding.
- **ADR-KB-3 Computed confidence and a reviewer who is not the author.** Consequences: + no
  self-certified items; − slower promotion for `observed`/`reported` items.
- **ADR-KB-4 Retire, never delete.** Follows Nygard's "keep the old one around, but mark it as
  superseded". Consequences: + reversible, auditable; − `retired/` grows. It is not loaded, so
  it costs disk only.

## 12. Minimal first increment (project scope only)

**In:** item format; `add` (R7, R8, secret scan), `search`, `show`, `verify` (check +
watch), `prune` (R1, R2, R3, R5), `retire`, `restore`, `lint` (I1-I4, I6), `stats`; tier-0
line in `hook_context.sh`; `events.tsv`; removal of `.gitignore:168` and the
`patterns.yaml` scaffold; the `uws-kb` skill and `/uws:kb` command.
**Out (increment 2+):** global scope, imports, `learn`/`outcomes.tsv`, R4, vector cache,
claim ledger, TASK.md injection.
**Why this slice:** it stops new unprovenanced memory, gives a working remove path, and
proves the context budget. Each later piece builds on this format.

### Acceptance tests (BATS, run on the existing Ubuntu + macOS CI matrix)

Each test runs in `setup_test_environment` with a git repo and `UWS_KB_NOW` fixed.

1. `uws kb add --type fact --claim X --evidence observed` with no `--source` → exit 2, and
   `items/` is still empty.
2. `add … --source file:scripts/lib/hook_context.sh:30` → exit 0; one file in `items/`;
   `status: candidate`; the source has `@<HEAD sha>` appended; `events.tsv` gains one line.
3. `--source file:does/not/exist:1` → exit 2.
4. Adding the same claim twice → second call exits 3 and prints the first ID.
5. `--evidence verified --check 'grep -q 1200 f'` then `verify <id>` → `trusted`,
   `verified_at` = fake today. Edit `f` so the grep fails, then `verify --changed` →
   `disputed`; `search` no longer returns it.
6. Item with `--watch g` and no check, trusted by `approve` from a different `--as` reviewer;
   edit `g` → `verify --changed` → `stale`. `approve` by the same actor as the author → exit 6.
7. `add B --supersedes A` → A is in `retired/` with `retired_reason: superseded-by:B`;
   `restore A` → A is back in `items/` as `candidate`; `git log --follow` shows both moves.
8. With `review_by` in the past: `prune` (dry run) leaves `git status --porcelain` unchanged;
   `prune --apply` → `stale`; move the clock 31 days ahead, `prune --apply` → retired
   `expired`.
9. Seed 50 trusted items → `search test` prints ≤ 5 lines, each ≤ 200 bytes, total ≤ 1000
   bytes, and no retired/disputed/stale items.
10. With those 50 items, `recover_context.sh --hook` JSON `additionalContext` ≤ 1200 bytes
    and contains `KB: 50 trusted`; `git status --porcelain` is unchanged by the hook.
11. Two trusted items linked by `contradicts` → `lint` exits 1 and names both.
12. `add --claim "key AKIA…"` (AWS key shape) → exit 2.
13. `rm -rf docs/kb/.cache && uws kb stats && uws kb search test` gives the same output
    as before the delete (I5).
14. ShellCheck is clean; no GNU-only flags (existing `-l` run).
15. End to end with real Claude Code (per CLAUDE.md): in a scratch project with an isolated
    `CLAUDE_CONFIG_DIR`, `claude -p "what does the KB say about the hook budget?"` produces a
    transcript where the `uws-kb` skill or `uws kb search` was called and the answer cites the
    item ID.

## 13. Later increments

2: global KB + imports (7) + TASK.md injection + R4 usage counts. 3: `outcomes.tsv`, `learn`,
proposals, `sdlc fail` reason capture. 4: claim ledger + paper lint. 5: optional embedding
cache for `relevance` (rebuild-only; I5 still holds).

Note (2026-09-30): increment 3 (meta-learning) was implemented before increment 2 (global KB
and imports) because the PI gave it priority. Section 17 records what was built.

Note (2026-09-30, later): increment 2 is implemented: the global KB, both imports, TASK.md
leads, the usage log with R4 and the R4-unused-share metric. Section 18 records what was built.
Increments 4 (claim ledger) and 5 (vector cache) are not started.

## 14. Decisions needed from the PI

- **D1 Where the project KB lives.** `.workflow/kb/` (tracked; the original recommendation) conflicted with the
  open question in handoff.md about untracking `.workflow/`. The alternative is a top-level
  `kb/` directory.
- **D2 Auto-memory.** OK to trim your `MEMORY.md` (17.9 KB, loaded every session) to a short
  index of preferences and move project facts into the KB? UWS will not touch it without
  your OK.
- **D3 Vector memory servers.** Remove `vector_memory_local/global` from `.mcp.json` after
  import, or keep them installed but unused as a possible future cache?
- **D4 Who may promote.** May an agent reviewer (different role from the author) promote
  `observed`/`reported` project items, or must a human approve every promotion? Global items
  are human-only in this design.
- **D5 Thresholds.** Accept the starting values (30/30/14 days, n ≥ 5, 20 sessions), or set
  your own.
- **D6 Imported legacy items.** Triage the ~36 imported rows by hand, or let R5 retire
  anything not re-verified within 30 days?

### PI decisions (recorded 2026-09-26)

Decided by the PI:
- **D1:** the project KB lives in **`docs/kb/`**, tracked in git (not `.workflow/kb/`); the rest of this document uses `docs/kb/` throughout.
- **D4:** **the PI approves every promotion** (project and global). Agents may capture and
  check sources, and a reviewer agent may recommend promotion, but only the PI promotes.

Defaults adopted until the PI says otherwise:
- **D2:** `MEMORY.md` is not touched without the PI's explicit OK (still open).
- **D3:** keep the vector-memory servers installed as an optional, rebuildable search cache;
  they are never the source of truth.
- **D5:** accept the starting thresholds; they are configurable (Section 9).
- **D6:** imported legacy rows are triaged by hand (consistent with D4); nothing is
  retired automatically until the PI has reviewed the import.

## 15. Assumptions made

- The first increment is Bash + awk to match the codebase; only the importer uses python3.
- `git hash-object` is enough to detect a change; line-level anchoring is not needed at first.
- No network access in hooks or `verify`, so URL sources expire by date only.

## 16. Increment 1 as built (2026-09-26)

Code: `scripts/kb.sh`, `scripts/lib/kb_utils.sh`; tests: `tests/integration/test_kb.bats`.
Where the build differs from the text above, this section wins.

**PI-only promotion (D4).** The only code path that writes `status: trusted` is
`uws kb approve`. It refuses with exit 6 unless all of these hold:
1. no AI-agent marker is in the environment (`CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`,
   `CLAUDE_CODE_CHILD_SESSION`, `AI_AGENT`, `UWS_AGENT`, `GEMINI_CLI`, `CODEX_SANDBOX`;
   Claude Code sets the first two in every tool call it runs);
2. a PI is configured: `kb: pi:` in `.workflow/config.yaml`, or `UWS_KB_PI` when the config
   has none (the config wins, so an exported variable cannot replace a configured PI);
3. `git config user.email` equals the PI (case-insensitive), and `--as`, if given, equals it too.

`reject` and `pi --set` use the same gate. Limits: on the PI's own machine an agent runs with
the PI's git identity, so check 3 alone would not stop it; check 1 does, but an agent with shell
access can unset variables or edit item files. The CLI therefore stops accidental and
well-behaved agent promotion; the real control is review of the `docs/kb/` diff before commit.
`lint` (I7) reports any trusted item whose `reviewer` is not the PI, which catches a
hand-edited `status: trusted`.

**verify and approve.** `verify` never promotes. On a candidate, stale or disputed item a
passing check sets `check_status: pass` (shown as `check-passed` in search) and the item keeps
its status. On a trusted item a passing check refreshes `verified_at` and `watch_blob`; a
failure makes it `disputed`, a timeout makes it `stale`. `approve` re-resolves the sources and,
if the item has a check, runs it and refuses with exit 5 unless it passes. So `stale -> trusted`
and `disputed -> trusted` also need the PI. `recommend <ID>` (open to agents) records who thinks
an item is ready; `review` lists the queue.

**Other decisions.**
- `watch` defaults to the paths of `file:` sources, so `verify --changed` notices edits to cited
  files without an explicit `--watch`.
- `status_since` (new field) dates the last status change; R2, R3 and R5 count from it, so a
  restored item gets a fresh 30 days.
- Approving an item that `contradicts` a trusted item retires the latter as
  `disproven-by:<id>` (5.5: the PI settles the dispute).
- `restore` also removes the item from the `supersedes` list that retired it, so R1 does not
  retire it again.
- The session line and `search` read the item files directly; `.cache/stats` is written by
  write commands and `stats` but is never read back, so I5 holds by construction.
- IDs use `git hash-object` of the normalised claim (git is present on every platform; `sha1sum`
  is not on macOS).
- Events are appended with a single `printf >>` per row, not `atomic_append` (which rewrites the
  whole file); item files are replaced by temp file plus `mv`.

**Not built in increment 1** (as planned in section 12): global scope, imports, `learn` and
`outcomes.tsv`, R4, R6, `purge --secret`, vector cache, claim ledger, TASK.md injection,
`verify --changed` inside `checkpoint.sh create`, and removal of the vector-memory SessionStart
hook (kept per D3).

## 17. Increment 3 as built: meta-learning (2026-09-30)

Code: `kb_outcome` and the recording helpers in `scripts/lib/kb_utils.sh`; `learn`,
`proposals` and the proposal handling of `approve` in `scripts/kb.sh`; one call each in
`sdlc.sh`, `research.sh`, `review.sh` and `orchestrate.sh`. Tests:
`tests/integration/test_kb_learn.bats`. Where the build differs from section 6, this section
wins.

**outcomes.tsv.** No header; 8 tab-separated columns as in 6.2. Every field is TSV-escaped
(`\\`, `\t`, `\n`, `\r`; other control characters become spaces), capped at 500 bytes, and `-`
when empty. Recording is best effort: a no-op when the KB directory does not exist, and a
failed append prints one line on stderr and never changes the caller's exit code. Columns per
event (`<m>` is `sdlc` or `research`; `ref` is the HEAD commit unless stated):

| event | phase | role | model | subject | result | ref |
|---|---|---|---|---|---|---|
| `gate_fail` | `<m>:<failed phase>` | - | - | `<m>:<regression target>` or - | the reason | HEAD |
| `gate_pass` | `<m>:<phase left>` | - | - | `<m>:<phase entered>` | `done/total`, plus ` forced` or ` ungated` (no goal) | HEAD |
| `cr_decision` | current phase | CR agent | model recorded at collect | CR summary | `approved`, `rejected[: reason]` | CR ID |
| `dispatch` | `<m>:<phase>` | agent | `model:` of `uws-<agent>.md` | target artifact | `dispatched` / `collected` | HEAD / CR ID |
| `escape` | `<m>:<phase>` | item author | - | lesson ID | the lesson's claim | HEAD |
| `kb_retire` | - | item author | - | retired ID | `<code> evidence=E captured_by=C from=S type=T` | related item or - |

`gate_pass` is written by `next` only (not `goto`). Reason codes: `superseded-by`,
`disproven-by`, `disproven`, `expired`, `unpromoted`, `rejected`, `graduated`, `manual`.
`review.sh reject <CR-ID> ["reason"]` gained the optional reason.

**Metrics as built** (each over the last `UWS_KB_LEARN_WINDOW` = 10 samples, proposing only
with n >= `UWS_KB_LEARN_MIN_N` = 5; thresholds from 6.3, configurable):

| Metric (key) | Sample | Proposes when | Proposed change (as a unified diff when the target is found) |
|---|---|---|---|
| `gate-escape-rate` (`phase=<m>:<p>`) | a `gate_pass` of the phase; k = approved escapes after the earliest pass in the window | k/n > 0.20 | a deliverable line naming the latest escaped lesson in `get_phase_deliverables` of `scripts/<m>.sh` |
| `cr-first-pass-rejection` (`role=R,model=M`) | the first `cr_decision` of R after a `dispatched` row of R (model from that row) | k/n > 0.40 | a Quality Gate item from the most frequent rejection reason in `docs/personas/<R>.md`; with no reasons, `model:` of `uws-<R>.md` set to the next tier (via `UWS_AGENT_MODEL_<R>`) |
| `disproven-rate` (`evidence=E`, `captured_by=C`) | a retirement of a formerly trusted (trusted, stale, disputed) fact, decision, lesson or anti-pattern with evidence verified, observed or reported | k/n > 0.25 | E: `trust["E"]` in `scripts/kb.sh` times (1 - rate); C: a "give two sources" line in the `uws-kb` skill |
| `repeated-gate-fail` (`reason=<normalised>`) | a `gate_fail` row (any phase); normalised = lower case, spacing collapsed, trailing punctuation dropped | the same reason >= 3 times | a deliverable line in the phase the failures sent work back to |

Targets are looked up in the project first, then in the UWS installation; when a file or
anchor is missing, the proposal states the change in words instead of a diff.

**Guards, as enforced.**
- External signals only: `learn` reads `outcomes.tsv` plus the status of the items its rows
  name; nothing else feeds a number.
- Only trusted knowledge: an `escape` row counts only when its lesson is trusted or stale now
  (or was retired later as superseded or graduated after a PI review) and its evidence is not
  `inferred`; `kb_retire` rows of candidates, inferred items, hypotheses, questions and
  proposals are skipped, and `learn` reports how many were skipped.
- Human in the loop: proposals are written as `candidate` items (`author: kb-learn`,
  `captured_by: script:kb-learn`, source `file:docs/kb/outcomes.tsv@<HEAD>`). Only the PI gate
  of section 16 makes them trusted. `approve` on a proposal records `approved_ts` and prints
  that nothing was changed; no code path applies a proposal's diff.
- Honest statistics: every proposal body reports k of n, the window, the rows behind the count
  (CR IDs, item IDs or phases), a small-n caveat (one event moves the rate by 1/n) and a
  metric-specific confounding caveat, and says it reports counts, not causes.

**Idempotence and tracking.** Samples count only after the latest decision point of any
proposal on the same key (its `followup_ts`, else `approved_ts`, else `created_ts`), so a
proposal the PI turned down is not repeated from the same rows. A key with an open proposal
(a candidate, or an approved change still being measured) gets no second one; for CR proposals
the block and the window apply to the whole role, because the change is measured per role (a
new route changes the model). After approval, `learn` computes the same metric over the next
10 samples and records it as `metric_after` next to `metric_before`: below the value at
proposal time records `followup: improved ...`; otherwise it writes a revert proposal
(`proposal_kind: revert`, `reverts: <id>`, the original diff reversed) and records
`followup: revert-proposed:<id>`. A revert proposal is not itself tracked.

**Surface.** `uws kb proposals` lists waiting and measured proposals. The SessionStart context
and `uws kb stats --short` add `KB: N meta-learning proposal(s) await the PI (uws kb
proposals).` while any wait; the hook stays inside its 1200-byte budget (tested).

**Differences from section 6.**
- The R4-unused-share metric was not built in this increment: R4 usage counts did not exist
  yet, and they live in the machine-local `.cache/`, not in `outcomes.tsv`. Increment 2 built
  both (section 18).
- A repeated `gate_fail` reason produces one proposal (the checklist line); no separate lesson
  item is written, so that `learn` creates only proposals.
- `learn` needs the KB inside the project (proposals cite `outcomes.tsv` by a project path).
- The alternative model (haiku -> sonnet -> opus, opus -> sonnet) and the trust-weight factor
  are heuristics; the proposals say so.

## 18. Increment 2 as built: global KB, imports, TASK.md leads, R4 (2026-09-30)

Code: `scripts/kb.sh` (scope, `init`, `import`, `dispute`, R4 in `prune` and `learn`),
`scripts/lib/kb_utils.sh` (`kb_global_*`, `kb_guarded`, `kb_session_id`, `kb_usage_record`),
`scripts/kb_import.py` (read-only readers, Python standard library only), `scripts/orchestrate.sh`
(`kb_brief_section`), `bin/uws` (global verbs outside a project), `tests/helpers/test_helper.bash`
(guard). Tests: `tests/integration/test_kb_global.bats`, `test_kb_import.bats`,
`test_kb_usage.bats`; fixture builder `tests/fixtures/kb/make_vector_db.py`. Where the build
differs from the sections above, this section wins.

PI constraints for this increment: only the PI promotes (global items too) and imports create
only candidates; UWS never edits `MEMORY.md`; the vector-memory databases, MCP servers, the four
memory skills and the vector-memory SessionStart hook are neither changed nor removed (D2, D3);
imports only read their sources; no import was run on the real stores.

**Global KB.**
- Root `<global memory dir>/kb`, the directory from `UWS_GLOBAL_MEMORY_DIR`, else
  `global_memory_dir` in `~/.config/uws/config.yaml`, else `~/uws-global-knowledge` (the chain of
  `uws_resolve_global_memory_dir`). `uws kb init --global` creates it and runs `git init`. Every
  global write (items, events, caches, `pi --set`) is refused with exit 2 unless the directory is
  the top level of its own git repository (risk 13). Nothing commits.
- A verb runs on it with `--global`, `--scope global`, or an ID written `global:K-...` in an ID
  position (the first positional argument, or the value of `--supersedes`, `--contradicts` or
  `--by`; other values, such as a `--quote` text, are never read as IDs); `uws kb <verb>
  --global ...` (or a `global:K-...` ID) works outside a UWS project. `add --global` prints the
  new ID as `global:K-...`, as `import --scope global` and `review --global` do. Sources resolve against the global repository, so
  `url:` and `item:` are the practical kinds. `learn` and `proposals` are project-only.
- PI: `<global kb>/config.yaml` holds its own `kb.pi` (`uws kb pi --set <email> --global`); the
  gate of section 16 applies unchanged, with the global repository's `git config user.email`.
- 4.2 "no project paths": `add` and `import` refuse, and `lint` reports as I8, a global claim
  naming `~/...`, `$HOME...` or `${HOME}...`, an absolute path under /home, /Users, /root, `$HOME`
  or the project (a `file://` URL included), the project or home directory written anywhere in
  the claim (so a path with spaces or non-ASCII bytes is caught), or a relative path with a slash
  that exists in the project the command runs in. A path in the KB's source notation counts as
  the path: a `file:`, `cmd:` or `commit:` prefix, an `@<ref>` suffix and a `:<line>[-<line>]`
  suffix are removed first. Other URLs are not paths. Only claims are checked, as 4.2 says.
- Global retirements write no `outcomes.tsv` row (outcomes describe one project's process), and
  `--escaped-from` is project-only.
- `search` ranks trusted project and global items together (same score, one budget: 5 lines,
  1000 bytes); global lines read `global:K-...`; `--scope project|global` restricts it. `show`
  falls back to the global KB for an ID the project lacks. `stats` adds a global line.

**Imports** (section 7). `uws kb import vector --db <path> [--scope project|global] [--dry-run]`;
`uws kb import automemory --dir <path> [--include-index] [--dry-run]` (project only).
- Read-only: `kb_import.py` opens a rollback-journal database through a `mode=ro` URI connection
  and copies it into memory with SQLite's backup API. A WAL database (header bytes 18-19), or one
  with a `-wal` or `-journal` file beside it, is byte-copied with that file into a temporary
  directory and the copy is opened, because even a read-only connection to a WAL database
  creates `-wal` and `-shm` files next to it; the same copy is the fallback when the read-only
  open fails. It reads only `memory_metadata`, so the `vec0` extension is not needed. Auto-memory
  files are only read, and `MEMORY.md` is not opened unless `--include-index` asks for it. The
  tests make the fixtures read-only and compare hashes and directory listings before and after,
  and import a WAL fixture from a writable directory.
- `--include-index`: on a machine like this one most project facts sit in `MEMORY.md` itself
  (2.1: 93 lines, 17.9 KB) rather than in topic files, so importing topic files alone would
  leave them out of the triage that D2 needs. With the flag, each top-level list item or
  paragraph of `MEMORY.md` becomes a candidate with source `import:automemory#MEMORY.md:L<first
  line>`, tags `import, automemory, index, <section heading>` and the entry quoted in the body.
  Nested items join their parent (with "; "), fenced code stays inside its entry, list and quote
  markers and paired bold markers outside code spans (`**text**`, `__text__`) are dropped from
  the claim (so `__init__.py` in a code span and `2 ** 10` stay as written), and lines that only link a topic file, or
  entries under 12 characters, are skipped with the reason printed. The file is still only
  read; trimming it remains the PI's own edit (D2). A line number moves when the file is
  edited, so a rerun after an edit adds the new reference to the existing candidate (R7) instead
  of a second item.
- Each row becomes a candidate: `evidence: inferred`, `source: [import:vector-local#<row id>]`
  (`vector-global` for `--scope global`, `automemory#<file>`), `captured_by: import`, `author:
  kb-import`. The claim is the row without its `PHASE n | DOMAIN: d | CATEGORY: c |` prefix, cut
  to 240 bytes at a sentence end or word boundary; the body quotes the full text and names the
  file's blob hash and row. The type is guessed from the category (decision-adr -> decision;
  bug-resolution, bug-fix, tool-usage ... -> lesson; phase-summary, learning, other -> fact); the
  PI fixes it when restating.
- R7: a row whose normalised claim equals an active item's is collapsed into it (its source is
  added when that item is itself an import candidate); one equal to a retired item's is not
  brought back, and the report names the retirement. Removing the prefix is what collapses the
  duplicate pairs of 2.2-1. A rerun changes nothing.
- Skipped, with the reason printed: text that looks like a secret; global claims naming a
  project or home path; auto-memory `user` and `feedback` memories (they stay in auto-memory,
  section 7), files without front matter, and `MEMORY.md` (unless `--include-index`).
- Suspected fixture (2.2-5 as a rule, project imports only): `flags: [suspected-fixture]` plus
  `flag_detail` when a row names at least one concrete thing (a path, a file name with an
  extension, a snake_case identifier, a backticked term) and none of them occurs in the
  project: not as a tracked path, directory or file name, and not in tracked file contents
  outside prose (Markdown, text, TeX) and test fixtures, which can quote a stray memory (this
  document quotes row 13's `batch_size`). The flag informs triage and retires nothing.
  [inference] It misses a fixture that names one real file and flags a true fact whose names
  occur only in prose; it has not been run on the real stores.
- Decision D6 (no rule retires an import before the PI has reviewed it): `prune` skips imported
  candidates and disputed imports in R5 and R2 and says how many wait, and R1 retires an import
  only for a trusted (PI-approved) superseding item. `add --supersedes <import>` leaves the
  import active (an events row `restated-by:<new ID>`, and `review --imported` shows the
  restatement); the PI's `approve` of the new item retires it as `superseded-by`. Lint I4
  accepts an import whose restatement is not yet trusted. A restatement the PI rejects leaves
  the import in the queue. `approve` refuses an item with an `import:` source (exit 2): an
  import is a lead, not evidence, so the PI restates it with a resolvable source first (R8 at
  promotion).
- PI triage, `uws kb review --imported [--global]`, instead of row-numbered special cases:
  - keep or correct: `uws kb add ... --source <resolvable> --supersedes <ID>`, then `approve`
    the new item, which retires the import as `superseded-by`. To keep a claim as it is, the new
    item repeats it: R7 does not count the item it supersedes as a duplicate (on the same day the
    new ID gets 8 hex digits, as for any ID collision). Global row 8 (wrong file name) goes this
    way, quoting `DB_NAME = "vector_memory.db"` from the server's source.
  - refute: `uws kb add ... --evidence reported --source url:... --quote "..." --contradicts
    <ID>`, then `uws kb dispute <ID> --by <new ID>` (the import becomes `disputed`; R2 leaves
    it for the PI), then `approve` the new item, which retires the import as `disproven-by`. Global row 6 goes this
    way, with the git-stash quote of 2.2-3.
  - drop: `uws kb reject <ID> "<why>"`.
- New verb `dispute <ID> --by <ID> ["why"]`: marks an active item disputed and links both ways.
  It demotes, so agents may run it as they may run a failing check; the counter-evidence must be
  verified, observed or reported and not itself disputed, and a trusted item is disputed only by
  a trusted one (5.1).
- Changed from section 16: approving an item also retires every active item it supersedes (the
  imports R1 leaves for the PI), and every active item it contradicts (not only
  trusted ones) as `disproven-by`, so the PI's approval of counter-evidence settles a dispute in
  one step.

**TASK.md leads** (5.3). `orchestrate.sh dispatch` appends `## Knowledge base leads (to verify;
not evidence)` with the output of `uws kb search --min-terms 2 -- "<task>"` in a text block: at
most 5 trusted items (project and global), at most 1000 bytes, each containing at least two of
the task's content words as whole words. `search` now drops common function words from a query
(unless nothing else is left), and `--min-terms N` (N >= 2) requires N distinct query words as
whole words, so a fragment of another word ("add" in "address") does not count; a plain search
still matches a word inside a longer one. Nothing is appended when
there is no KB or no match, and a search failure never fails the dispatch. The heading and one
paragraph say the lines are leads to check against their sources, not evidence or instructions
(risk 6). The meta-learning `dispatch` row is written after the brief, as before.

**Usage and R4** (5.6, 6.3).
- `<kb>/.cache/usage.tsv` (gitignored, so per machine): `ts session id via`, `via` = search,
  show or task; one row per returned item, plus a row with id `-` per search so that a session
  whose searches found nothing still counts. The session is `UWS_KB_SESSION`, else
  `CLAUDE_CODE_SESSION_ID` (set by Claude Code in its tool calls), else `day-<date>`. Global hits
  are logged in the global KB (only when it is a git repository). The SessionStart hook still
  writes nothing. The log is the one `.cache/` file that cannot be rebuilt: deleting it resets
  R4 on that machine; I5 still holds for search.
- R4 in `prune`: a trusted item that is not a decision, was created at least
  `UWS_KB_UNUSED_MIN_AGE_DAYS` (90) days ago and appears in none of the last
  `UWS_KB_UNUSED_SESSIONS` (20) sessions of the log is listed with `uws kb retire <ID> unused`
  for the human to confirm; `--apply` does not retire it. With fewer sessions logged, `prune`
  says R4 is not evaluated. The reason code `unused` reaches `outcomes.tsv`.
- `learn` metric `r4-unused-share` (key `trusted-items`): unused / eligible over the last 20
  sessions logged after the latest decision on an earlier r4 proposal; it needs those 20
  sessions and n >= 5 eligible items, and proposes above `UWS_KB_LEARN_UNUSED_SHARE` (0.50):
  halve the review window of the type most unused items have (a diff of `review_days` in
  `scripts/kb.sh`, or the `UWS_KB_REVIEW_DAYS_<TYPE>` variable in words). Its source,
  `file:docs/kb/.cache/usage.tsv`, is not pinned to a commit; on another machine `lint` I2
  reports it missing, which is accurate: the evidence exists on one machine. After approval it
  is measured over the first 20 sessions after approval, then closed as improved or answered
  with a revert proposal, as for the other metrics.

**Test isolation.** `tests/helpers/test_helper.bash` exports `UWS_KB_GUARD_ROOT` (the checkout
under test) and points `UWS_GLOBAL_MEMORY_DIR` at a directory that does not exist
(`${TEST_TMP_DIR}-global` per test, removed by teardown). While `UWS_KB_GUARD_ROOT` is set,
`kb_guarded` refuses every KB write inside it (outcomes, usage, items, caches) unless
`UWS_KB_ALLOW_GUARDED_WRITE=1`. Outside the tests it is unset, so UWS may still keep a KB in its
own repository.

**Fixed in increment-1 code.** The list parser kept the space before each later quoted element
(`["a", "b"]` read ` b`), so an item with two sources could not be approved. Regression test in
`test_kb_usage.bats`.

**Retiring the old memory stores (not done; needs a PI decision).** It would mean: running the
triage above on the real stores first; removing the second SessionStart hook in
`.claude/settings.json` (the "VECTOR MEMORY ACTIVE" context); replacing the `vector-memory`,
`memory-gate`, `phase-distillation` and `memory-retrospective` skills with pointers to `uws-kb`;
shrinking the CLAUDE.md "Vector Memory Protocol" section and the README's vector-memory
section; deciding D3 for the `.mcp.json` servers, the opt-in server install in `install.sh`,
`scripts/lib/vector_memory_setup.sh` (called by `init_workflow.sh`) and the `.mcp.json` cleanup
in `scripts/uninstall.sh`; and updating `tests/integration/test_vector_memory.bats` and
`tests/unit/test_vector_memory_setup.bats`. The databases themselves need no change: they stay
readable for a later import. Until then both systems run side by side.
