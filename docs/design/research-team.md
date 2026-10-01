# Design: The UWS Research Team (Apocalypt)

- **Status**: increments 1 and 2 implemented (section 11 and section 11a), and the fixes
  from the first field test, an audit of the PROMISE 2026 paper (section 11b). Still not
  built: slop rules S3, S5, S7, C2 and C4, the INVENTORY report, the BibTeX metadata
  cross-check (6.3 step 6), `bib verify --online`, a check that the environment lock pins
  every package (runs record the lock's hash, nothing checks its content) and the Dockerfile
  check, and the KB promotion interface (section 9). Each gate names the checks among these
  that its phase would run (the BibTeX items from literature_review, the lock and Dockerfile
  checks from data_collection, the slop rules and INVENTORY from analysis); the KB promotion
  interface is not a gate check. Section 11b lists what the field test and the review of its
  fixes found, and what was consciously not fixed.
- **Date**: 2026-09-24
- **Author role**: principal system architect (UWS subagent)
- **Governing persona**: `docs/personas/apocalypt.md` (PI-supplied, verbatim). Every rule below cites the principle it enforces as P1-P11, which are the numbered principles in that file (P1 = line 21, P11 = line 101).
- **Related design**: `docs/design/knowledge-base.md` (written in parallel). Section 9 maps the research ledgers onto its item model and lists the interface this design needs from it.

## 0. Scope and how to read this

**Goal (from the PI):** make the UWS research workflow work like a strong team of agents
working for a Principal Investigator. The team removes AI slop, handles code, data and
documentation responsibly, and never invents facts in research.

**Deliverable:** this file only. It covers team roles, how the roles map to the 7 research
phases, the anti-hallucination machinery, how the team works with the PI, data and code
management, the interface to the knowledge base, a worked audit of the PROMISE 2026 paper,
a minimal first increment with acceptance tests, and risks.

**Constraints:** UWS is git-native Bash (CLAUDE.md). `yq` may be missing, so nested YAML is
edited with sed/awk. Subagents cannot talk to the PI. The PI's global rules require a
source for every claim, BibTeX that is downloaded and never hand-written (kept in
`bib_sources/<citekey>.bib`), and a checkpoint after each phase.

**Evidence labels used in this document:**
- **[obs]**: I observed it this session (a file:line, a command output, or a fetched page).
- **[src Sx]**: stated in source Sx (Section 16).
- **[inference]**: my reasoning. It is not verified.
- **[decision]**: a design choice I made. Section 14 gives the trade-offs.

---

## 1. The answer first

The team is **six specialist subagents plus a lead that runs in the main session**. What
makes them trustworthy is not the prompts. It is **three plain-text ledgers checked by a
deterministic program that can fail CI and block `research.sh next`**:

1. A **claim ledger**. Every claim is labelled as established fact, reported finding, own
   observation, inference, hypothesis, estimate or open question. Each claim points to its
   evidence. The claim's author can never mark it verified.
2. A **source registry**. Every BibTeX entry is downloaded from arXiv, a DOI resolver,
   DBLP or the ACL Anthology into `bib_sources/`. Every quoted supporting sentence must
   appear word for word in the cached source text.
3. A **number ledger**. Every number in the paper comes from a generated LaTeX macro,
   which traces to an output file and its hash, the run that produced it, the commit,
   environment, data manifest and seed.

Five decisions carry the design:

1. **Separation of duties is enforced by data, not by trust.** The checker rejects a claim
   whose `verified_by` role equals its `author` role. Verification runs in a new subagent
   whose context never saw the author's reasoning. This follows Chain-of-Verification,
   which answers verification questions "independently so the answers are not biased by
   other responses" [src S12].
2. **Gates check evidence, not checkboxes.** Today's gate counts boxes the operator ticks
   by hand [obs `scripts/research.sh:567-598`]. The new gate runs `research_check.py gate
   <phase>` offline against the committed ledgers. Every network fetch happens earlier, at
   verification time, so CI gives the same result on every run.
3. **Numbers are never typed by hand in results prose.** They are generated macros. This
   follows Sandve et al.'s rules "For Every Result, Keep Track of How It Was Produced" and
   "Connect Textual Statements to Underlying Results" [src S6].
4. **No agent writes BibTeX.** Edit deny rules block the built-in edit tools and recognised
   shell writes on `bib_sources/**` [src S5]. Only the fetch script writes there. This
   matters because frontier LLMs produced fully correct BibTeX for only 50.9% of entries
   when working from memory [src S11].
5. **The PI owns anything irreversible or outward-facing.** Changing a reported number,
   submitting, pushing to a public remote, deleting data, changing a pre-registered
   decision rule, and using `--force` at the publication gate all need a PI decision ID
   (P10, line 99).

---

## 2. What exists today (inventory)

| Item | What it does now | Gap for this goal |
|---|---|---|
| `scripts/research.sh:26` | 7 phases: hypothesis → literature_review → experiment_design → data_collection → analysis → peer_review → publication | Keep as is. |
| `scripts/research.sh:235-273` | Deliverables are prose lines such as "Key references catalogued with citations" | Nothing checks them. |
| `scripts/research.sh:279-305` | Gate blocks `next` while any deliverable is unchecked. Active only when a goal is set (`:283`). `--force` skips it (`:281`). | The operator ticks boxes with `check <n>` (`:567-598`). There is no evidence behind a tick, and `--force` leaves no record. |
| `scripts/research.sh:196-229` | `reject` moves back to a refinement phase | Good. Negative results need a place in the ledger (Section 6). |
| `scripts/lib/workflow_routing.sh:51-61` | research → researcher/experimenter/documenter | Roles are generic SDLC roles. |
| `scripts/orchestrate.sh:44-47` | Chooses `sdlc` whenever `sdlc_phase` is set, and only then `research` | A project with both set can never dispatch research work. **Bug for this design.** |
| `scripts/orchestrate.sh:94-110` | Writes `TASK.md`. `:108` says "Trace claims to REQ-IDs" | Research claims need claim IDs (C-IDs), not REQ-IDs. |
| `scripts/orchestrate.sh:123-144` | `collect` goes to `submit.sh`, then the human `review.sh approve` | Reuse as the PI approval channel. |
| `scripts/gen_subagents.sh:34,72-77` | 7 roles; architect and researcher on opus, the rest on sonnet; env overrides `:19-22` | Research roles must be added. The contract text `:146` says REQ-ID. |
| `.claude/skills/uws-orchestrate/SKILL.md:29-31` | "Do not approve on the user's behalf" | Keep. The lead follows the same rule. |
| `plugins/uws/hooks/hooks.json` | Only `SessionStart` and `PreCompact` hooks | No enforcement hook for research agents. |
| `plugins/uws/agents/uws-*.md` | The plugin ships the 7 agents | Plugin agents ignore the `hooks`, `mcpServers` and `permissionMode` fields [src S4]. Enforcement must therefore live in plugin `hooks/hooks.json`, not in agent frontmatter. |
| `scripts/lib/decision_utils.sh:91,155,243` | `log_decision`, `log_blocker`, `log_assumption` write to `.workflow/logs/decisions.log` | Reuse for PI decisions and `--force` records. |
| `scripts/lib/checksum_utils.sh:39,265,360` | SHA-256 and snapshot manifests | Reuse for data manifests. |
| `.workflow/handoff.md:31` | Next action: "Research team: Apocalypt agents with claim/source verification; audit promise-2026..." | This document. |

**Research agents and skills in the PI's environment, and whether UWS can reuse them [obs]:**

| Asset | Where | Reuse decision |
|---|---|---|
| `citation-verifier`, `claim-to-source`, `research-evidence-validator`, `senior-research-scientist`, `humanizer`, `model-deep-dive` | `~/.claude/agents/` (PI's personal agents, no license file) | **UWS cannot ship or depend on these.** Other UWS users will not have them. The PI's texts carry no license, so UWS re-expresses the useful rules in its own words. For example, `senior-research-scientist` requires writing `[VALUE NOT IN RETRIEVED SOURCE]` instead of guessing, and the ledger's `unverified` status does the same job. |
| `humanizer` | same | **Not used, on purpose.** Its goal is to make text "sound human". Ours is to remove unsupported content. Disguising AI involvement conflicts with P10 (line 99, no facilitating fraud). Section 7 covers AI-use disclosure. |
| `research-assistant` plugin 1.2.0-beta3 (22 skills, e.g. `ai-check`, `pre-registration`, `power-analysis`, `effect-size`, `prisma-diagram`) | `~/.claude/plugins/marketplaces/research-assistant-marketplace`, MIT, author Aaron Storey | **Optional complement, not a dependency.** It is third-party beta software. UWS only notes that it exists. |
| `voltagent-subagents` research category (e.g. `scientific-literature-researcher`) | `~/.claude/plugins/marketplaces/voltagent-subagents/categories/10-research-analysis` | Not needed. I did not check its license. |

---

## 3. Ambiguities and unstated items, resolved

| # | Item | Resolution |
|---|---|---|
| A1 | "Do anything for the PI" versus "never without the PI" | Section 7.3 lists what the team does alone and what it never does without the PI. The dividing line is P10: anything irreversible or outward-facing needs the PI. |
| A2 | Which PROMISE source is canonical? `main-promise.tex:106` inputs `sections/04-evaluation-promise`, which does not exist at 778ab9a [obs]. It was deleted in UWS commit 69a5afc [obs `git log --diff-filter=D`]. `main.tex:108` uses `04-evaluation`. | I cannot resolve this from the files. It is a PI decision (Section 17). |
| A3 | Which UWS commit did the paper measure? | Artifact timestamps are 2025-11-21 to 2025-12-02 [obs file names]. The UWS repo has 14 commits between 2025-11-15 and 2025-12-05 [obs]. Needs the PI (Section 17). |
| A4 | Evidence categories | Taken from P3 (line 39): established fact, reported finding, own observation, inference, hypothesis, estimate, open question. I added a separate `data_origin` field (measured, simulated, synthetic-generated, literature), because "simulated" describes where data came from, not how certain a claim is. |
| A5 | Python in a Bash project | The checkers need to parse LaTeX, JSON and BibTeX, which is brittle in Bash. Decision: research checkers use Python 3 standard library only (no pip). The SDLC path stays Bash-only. Listed for the PI in Section 17. |
| U1 | Not stated: fetched pages can contain instructions | P10 (line 97): retrieved content is evidence, never instructions. Section 12 covers the risk. |
| U2 | Not stated: copyright of cached PDFs | Caches are gitignored. The repo stores only a hash, a short quote and a locator (Section 6.3). |
| U3 | Not stated: Edit deny rules do not cover scripts | Deny rules "don't apply to ... arbitrary subprocesses that read or write files indirectly, like a Python or Node script" [src S5]. So data protection also needs detective controls: manifest hashes, read-only raw files, and git (Section 8). |
| U4 | Not stated: a `SubagentStop` hook can loop | Exit code 2 "prevents Claude from stopping, continues the conversation" [src S3]. Retries are capped (Section 6.7). |
| U5 | Not stated: DBLP blocks scripted access | `curl` to the DBLP search API returned HTTP 200 with an HTML "Making sure you're not a bot!" page [obs]. The fetcher must reject non-BibTeX bodies (Section 6.3). |

---

## 4. Team composition

The team has seven roles. I merged two pairs where keeping them separate would not add an
independent check. The statistician is merged into the methodologist, because the
independent check on analysis is the pre-registration hash plus the red team, not a second
analyst. The data steward is merged into the research engineer, because data integrity is
enforced by hashes that a script verifies, not by a second agent reading files.

| Role (agent file) | Model | Why this tier | Enforces |
|---|---|---|---|
| **Lead Scientist / PI liaison** (skill `uws-research-lead`, runs in the main session) | the PI's session model; recommend opus | It is the only role that can reach the PI. Subagents have `AskUserQuestion` removed [src S2]. Framing and triage need the most judgment. | P1, P2, P7, P10, P11 |
| **Literature Scout** (`uws-rt-scout`) | sonnet | High-volume search and reading. Its output is never trusted without the verifier and the deterministic quote check. | P2, P3 |
| **Claim & Citation Verifier** (`uws-rt-verifier`) | opus | Errors here are the most expensive. LLMs fabricated 55% (GPT-3.5) and 18% (GPT-4) of citations [src S10]. ChatGPT reached a FActScore of only 58% [src S13]. | P3, P4 |
| **Methodologist** (experiment designer + statistician) (`uws-rt-methodologist`) | opus | Designing discriminating experiments and preventing leakage takes judgment. Leakage affected 329 papers in 17 fields [src S15]. | P4, P5, P6, P7 |
| **Research Engineer & Data Steward** (`uws-rt-engineer`) | sonnet | Code and runs are checked by tests, run records and re-runs, not by the model's own judgment. | P6, P8 |
| **Red Team** (adversarial reviewer) (`uws-rt-redteam`) | opus | Must find what the others missed. An evaluation of an autonomous AI scientist found "hallucinated numerical results", "placeholder text" and 42% of experiments failing from coding errors [src S14]. | P4, the final checklist (lines 109-116), P11 |
| **Scientific Writer/Editor** (`uws-rt-writer`) | sonnet | Writes only from ledger entries. Slop and number checks back it up. | P9, P11 |

No role uses haiku. There is no research task where a mistake is cheap and also invisible
to the deterministic checks. [decision] The PI can override any tier with the existing
`UWS_AGENT_MODEL_<ROLE>` environment variables [obs `gen_subagents.sh:19-22`].

**How the agents are built [decision]:** `gen_subagents.sh` gains a `RESEARCH_ROLES` list.
Each research agent file is concatenated from `_universal_protocol.md`, then `apocalypt.md`
(verbatim), then `docs/personas/research/<role>.md`, then a **research output contract**.
The research contract replaces "Trace every requirement/claim to a REQ-ID" (`:146`) with
"every claim is a C-ID row in `research/ledger/claims.jsonl`". Tools: the scout and verifier
get Read, Grep, Glob, Bash, WebSearch, WebFetch and Write. The engineer adds Edit. The red
team gets read and search tools plus Bash, and **no Write outside `research/reviews/`**,
which is enforced by an Edit deny rule.

### Role cards (inputs → outputs)

- **Lead**. In: PI goal, `research/pi/decisions.md`, subagent reports. Out:
  `research/QUESTION.md` (question, success criteria, constraints, consequence of failure,
  per P1), `research/pi/BRIEF.md` at each gate, `research/pi/questions.md`. Dispatches every
  other role through `orchestrate.sh`. Never marks a claim verified.
- **Scout**. In: `QUESTION.md`. Out: `research/lit/search_log.md` (queries, databases, date,
  inclusion and exclusion counts), `research/lit/matrix.md` (paper × method × dataset ×
  metric × limitations), `bib_sources/*.bib` via the fetcher, and claim rows with
  `status=unverified` and a proposed quote and locator.
- **Verifier**. In: claim ID, claim text and citekey only. It does not receive the scout's
  quote. Out: an appended verification row with verdict (`supports`, `partial`,
  `does-not-support`, `contradicts`, `unverifiable-access`), its own quote and locator, and
  whether the comparison is valid (same dataset, protocol, metric and resources, per P3
  line 37).
- **Methodologist**. In: hypotheses and literature. Out:
  `research/experiments/EXP-*/plan.md` with hypothesis, independent unit of evaluation,
  baseline, metric, controls, decision rule, stopping condition and the decision the result
  would change (P5, P7). The plan is frozen by SHA-256 in the ledger before any data is
  seen. Also writes the analysis scripts that follow the plan, and effect sizes with
  uncertainty at the correct sampling level (P6 line 63).
- **Engineer**. In: frozen plans. Out: code, `research/data/MANIFEST.tsv`, run records
  `research/runs/RUN-*/run.json`, the environment lock, and repro reports.
- **Red Team**. In: all artifacts, but not the authors' summaries. Out:
  `research/reviews/REV-*.md`, one row per finding with severity
  `blocking|major|minor`, evidence, and the check that would settle it.
- **Writer**. In: verified ledger rows and generated macros. Out: manuscript sections in
  which every factual sentence carries `% C-0123`, plus the AI-use disclosure paragraph
  drafted for the PI.

---

## 5. Phases, owners and evidence gates

`research.sh next` calls `python3 scripts/research_check.py gate <phase>` whenever
`research/` exists. Exit 0 advances. Exit 1 blocks and prints the failing rows. Exit 2 is
an environment error and also blocks: the gate fails closed. `--force` still works, except
at publication, but it writes `log_decision` with the reason and appears in the next PI
brief. Box-ticking with `check <n>` stays for projects without `research/`, so existing
tests stay green.

| Phase | Owner (reviewer) | Hard evidence gate (all offline, deterministic) |
|---|---|---|
| hypothesis | Lead (Methodologist) | `QUESTION.md` has all five P1 fields. Each hypothesis row (category `hypothesis`) has `mechanism`, `distinguishing_prediction`, `strongest_alternative` and `undermining_observation` (P2 line 29). Novelty words are allowed only as "candidate contribution" (P2 line 31). |
| literature_review | Scout (Verifier) | Every C-row with category `established_fact` or `reported_finding` has status `verified` by the verifier role. Every citekey used in any `.tex`/`.md` has `bib_sources/<key>.bib` and `.meta.json`. `references.bib` equals the concatenation of `bib_sources` exactly. Every recorded quote appears in the cached text. The search log is present. |
| experiment_design | Methodologist (Red Team) | Every EXP plan has the P5 fields and a `frozen_sha256` that matches the file. The evaluation unit is named, and so is the grouping variable if samples repeat. There is a power analysis or a written reason for the sample size. The red team review has no open blocking rows. |
| data_collection | Engineer (Methodologist) | `MANIFEST.tsv` hashes match. Raw files are read-only. Every run record is complete (Section 8). Deviations from the plan are recorded as rows in `research/experiments/EXP-*/deviations.md`, and there may be zero. |
| analysis | Methodologist (Verifier) | Every number in the number ledger resolves to its output file and hash. Printed values equal rounded raw values. Every own-observation claim links N-IDs. Every non-measured origin is disclosed (rule C3). Negative results are ledger rows, never deleted. The repro job for cited numbers passes within tolerance. |
| peer_review | Red Team (Lead) | The red team ran on the frozen manuscript hash. Zero open `blocking` findings. Every `major` finding is fixed or has a PI decision ID. Every plan deviation (DEV row) is named in the manuscript. A CV value in a sentence that calls it held-out blocks. |
| publication | Writer (Lead, PI) | All checks pass on the final hash: ledger, bib, numbers, slop (no block-level hits), data. The PI's approval is recorded in `research/pi/decisions.md` as `PUBLICATION-APPROVAL: sha256:<manuscript hash> by <PI>` (or the CR ID of a change request approved with review.sh). Every `uws:literal` number is listed as a warning. **No `--force`.** Submission is done by the PI. |

---

## 6. Anti-hallucination machinery

### 6.1 Project layout (in the research project, not in the UWS repo)

```
bib_sources/<citekey>.bib          # downloaded BibTeX, never edited (PI rule R6)
bib_sources/<citekey>.meta.json    # {source_url, id_type, fetched_at, http_status, sha256}
research/QUESTION.md
research/ledger/claims.jsonl       # append-only claim ledger
research/ledger/numbers.jsonl      # append-only number ledger
research/sources/cache/            # full texts for quote checks (gitignored)
research/sources/index.jsonl       # {citekey, text_sha256, retrieved_at, url, access}
research/lit/{search_log.md,matrix.md}
research/experiments/EXP-*/{plan.md,config.yaml,deviations.md}
research/ledger/plans.jsonl       # append-only plan freezes (increment 2; see 11a)
research/runs/RUN-*/{run.json,stdout.txt,stderr.txt}
research/data/{raw/,derived/,manifest.jsonl}   # was MANIFEST.tsv; see 11a
research/sources/retractions.jsonl  # Crossref retraction lookups (increment 2)
research/env/{requirements.lock,Dockerfile}
research/repro/report-<date>.json
research/reviews/REV-*.md
research/pi/{BRIEF.md,questions.md,decisions.md}
research/INVENTORY.md              # generated, never hand-edited
paper/generated/numbers.tex        # generated macros
```

JSON Lines is used because each record is one line: `git diff` stays readable, the Python
standard library parses it, and `grep` works on it. [decision]

### 6.2 Claim ledger (`claims.jsonl`)

Each line is one record. Changes are **appended** as a new record carrying `supersedes`.
Nothing is edited in place and nothing is deleted.

```json
{"id":"C-0042","rev":2,"supersedes":"C-0042@1","text":"Gradient Boosting reaches a 5-fold CV mean ROC-AUC of 0.912 on the synthetic benchmark",
 "where":"paper/main.tex:69","category":"own_observation","strength":"empirical",
 "data_origin":"synthetic-generated","numbers":["N-0007"],"sources":[],"depends_on":[],
 "author":"writer","status":"verified","verified_by":"verifier","verified_at":"2026-09-30T10:00:00Z",
 "note":"CV mean on train split, not held-out test (test_auc=0.9199)"}
```

- `category`: established_fact | reported_finding | own_observation | inference |
  hypothesis | estimate | open_question (P3 line 39).
- `strength`: proof | empirical | association | causal | none (P4 line 47). Words like
  "proves" or "causes" in the claim text must match its strength (slop rule S6).
- `status`: unverified | verified | disputed | refuted | unverifiable-access | retracted.
- **Rules the checker enforces:**
  - `verified_by != author`.
  - `reported_finding` and `established_fact` need at least one source with a verified quote.
  - `own_observation` needs N-IDs or a run ID.
  - `inference` needs `depends_on`, and it is never stronger than its weakest dependency.
  - `hypothesis` can never be `verified`. It becomes `supported` or `refuted` only through
    an EXP.
  - Every line of `HEAD` and of every commit that touched the ledger is still present, so
    the ledger is append-only (acceptance test AT9; until section 11c only `HEAD` and `HEAD~1`).

### 6.3 Citation verification pipeline

1. **Fetch BibTeX (deterministic script `uws research bib fetch <id>`):**
   - arXiv: `https://arxiv.org/bibtex/<id>` [obs: returned a valid `@misc` for 2309.11495].
   - DOI: `curl -LH "Accept: application/x-bibtex" https://doi.org/<doi>` [src S17]. This
     returned a valid `@article` for 10.1371/journal.pcbi.1003285 [obs]. BibTeX is
     supported for Crossref, DataCite and mEDRA DOIs [src S17].
   - DBLP `rec/<key>.bib`, and the ACL Anthology `.bib`.

   The script refuses any response that does not parse as exactly one BibTeX entry. The
   DBLP HTML bot page is the observed failure (U5). It writes `.meta.json` with the source
   URL and a hash. There is **no fallback to a model-written entry**. A failure becomes an
   open question for the PI, who may supply the file.
2. **Build `references.bib`:** only by concatenating `bib_sources/*.bib`. Citekeys can be
   renamed only through a recorded map `bib_sources/KEYMAP.tsv`.
3. **Get the text:** the scout caches the full text (an open-access PDF or HTML) under
   `research/sources/cache/` and records `text_sha256`. Paywalled sources get
   `access=none`. They can never support a `verified` claim until the PI provides the text.
4. **Verify independently:** a new verifier subagent receives the claim and the citekey. It
   must find the passage itself, read the methods, evaluation conditions and limitations
   (P3 line 35), and record its quote, locator (page, section, table) and verdict.
5. **Deterministic quote check:** after normalising whitespace and hyphenation, each
   recorded quote must be a substring of the cached text. A made-up quote fails regardless
   of how confident the model sounds.
6. **Metadata cross-check:** title, authors, year and venue in the `.bib` must match the
   cached text's first page, allowing for accents and case. This catches the "wholesale
   entry substitution" failure [src S11].
7. **Retraction status (increment 2):** Crossref's REST API carries retractions, including
   those from the Retraction Watch database it acquired in 2023, in the `update-to` field
   of the notice, with `source` `publisher` or `retraction-watch` [src S20]; the retracted
   work lists them under `updated-by` [obs: `api.crossref.org/works/10.1016/S0140-6736(97)11096-0`,
   2026-09-30, a `retraction` from `retraction-watch`]. The Crossmark schema defines 12
   update types [src S21]. `research_check.py retraction --online` reads both the work's
   `updated-by` and `works?filter=updates:<doi>`, and caches the answer in
   `research/sources/retractions.jsonl`. Offline gates read the cache: a verified claim on a
   retracted source blocks; an unchecked or unreachable source is a warning and is never
   reported as clean. DataCite DOIs (for example arXiv's) are "not in Crossref" and stay
   unknown.

### 6.4 Number provenance (`numbers.jsonl`)

```json
{"id":"N-0007","macro":"\\GbAucCv","printed":"0.912","raw":0.9125,"rounding":"floor:3",
 "metric":"5-fold CV mean ROC-AUC, train split","output":"artifacts/predictive_models/model_results_20251122_072525.json",
 "pointer":"/classification/Gradient Boosting/cv_auc_mean","output_sha256":"<hex>","run":"RUN-0003",
 "tolerance":{"kind":"abs","value":0.005},"data_origin":"synthetic-generated"}
```

The chain is: paper macro → `numbers.jsonl` row → output file plus JSON pointer or CSV cell
→ `output_sha256` → `run.json` (command, git commit, dirty flag, env lock hash, data manifest
hash, seeds, hardware, exit code) → `MANIFEST.tsv` row. Checks:

- (a) Every macro used in the `.tex` has a row.
- (b) The value at the pointer equals `raw` and the file hash matches.
- (c) `printed` equals the rounding rule applied to `raw`. The rounding rule is explicit,
  because the PROMISE audit found values that match only under truncation (Section 10).
- (d) Hand-typed decimals in the abstract, results, conclusion and tables fail, unless the
  line carries `% uws:literal <reason>`. Years, section numbers and citations are excluded
  by pattern. Since the field test (section 11b) this also covers the introduction,
  evaluation, experiments and discussion, integers and decimals with a unit (`1.1ms`, `1.1\,ms`, `30\%`), and any
  hand-typed value at a place a row's `where` names, which is judged like a use of the row's
  macro (`NUM-SPLIT`, C3, C6), with or without `uws:literal`. Since section 11c,
  `uws:literal` does not accept a number within 10% of a ledger value (a typo or a stale
  copy) or one in a sentence that names a ledger metric, unless it cites a recorded PI
  decision (`% uws:literal D-<n> <reason>`); headings named findings, analysis, performance
  or outcomes are results sections; and outside the results sections a number is reported
  when its sentence names a ledger metric or it is a ledger value.
- (e) `run.json` exit code is 0 and the run's commit is an ancestor of HEAD.

### 6.5 What "AI slop" means, as checkable rules

"Slop" here means content that is not backed by evidence, or text and code that only look
finished. Wikipedia's guide itself warns its patterns are "only potential signs of a
problem" [src S19]. So vocabulary-style signs only warn, and rules tied to evidence block.

| ID | Rule (concrete) | Level |
|---|---|---|
| S1 | Novelty or superlative words (first, novel, state-of-the-art, breakthrough, best, unprecedented, outperforms) in a sentence with no C-ID, or whose C-row is a hypothesis or unverified (P2 line 31). "First" counts after an article ("the first") or before a contribution noun ("First predictive models"); four fixed idioms do not count: best practice(s), best effort, best case, at best (section 11b) | block |
| S2 | Vague attribution ("studies show", "it is well known", "researchers have found", "experts agree") with no `\cite` in the same sentence (src S19 category "Vague attributions") | block |
| S3 | Fabricated precision: printed decimals exceed what the ledger's uncertainty supports (more than one digit past the first significant digit of the CI half-width or SD). Also "100%" or "0%" claims without an N-ID. | block |
| S4 | Placeholders: TODO, TBD, FIXME, XXX, `??` from undefined refs in the LaTeX log, "lorem", "[citation needed]", empty table cells | block |
| S5 | Padding: density of words such as delve, pivotal, testament, landscape, seamless, leverage, underscores above a threshold. Also rule-of-three triplets and outline-style "challenges and future prospects" endings (src S19) | warn, sent to the red team |
| S6 | Strength drift: "proves", "demonstrates that X causes", "enables causal analysis" when the C-row strength is lower (P4 line 47) | block |
| S7 | "Significant" or "significantly" with no test, effect size and N-ID in the same sentence | block |
| C1 | Code placeholders: `TODO`, `pass` as a whole function body, `NotImplementedError`, bare `except: pass` in `research/` or `benchmarks/` code | block |
| C2 | Untested path: a script whose outputs feed an N-ID has no successful run record at the recorded commit | block |
| C3 | Undisclosed simulation: `random.`/`np.random` feeds an output used by an N-ID whose `data_origin` is `measured`, or a non-measured origin appears in a sentence or caption with no "simulated/synthetic/generated" disclosure | block |
| C4 | Fragile paths: `Path(__file__).parent.parent...` or absolute home paths in scripts listed in `run.json` | warn |
| C5 | Input chosen by modification time, e.g. `max(..., key=st_mtime)`, where the input should be pinned by hash | block |

The regular expressions are a floor, not a ceiling. The red team does the semantic pass,
using the final checklist in the Apocalypt persona (lines 109-116).

### 6.6 The checker

`scripts/research_check.py {ledger|bib|quotes|numbers|slop|data|repro|inventory|gate <phase>}`
uses the Python 3 standard library only.

- Exit codes: 0 pass, 1 findings, 2 environment error.
- Output: one line per finding, in the form `file:line RULE-ID message`, with `--json`
  available for CI.
- Everything except `repro` and `bib fetch` works offline.
- `bib verify --online` re-fetches and compares against the stored hashes. It is a separate
  job, so the gates never depend on the network.

The research project's CI runs `research_check.py gate <current phase>` on every push.

### 6.7 Enforcement layers

| Layer | Mechanism | What it stops |
|---|---|---|
| L1 | `research_check.py` inside `research.sh next`, `orchestrate.sh collect`, and CI | Anything wrong in the committed ledgers. This is the main control. |
| L2 | Plugin `hooks/hooks.json` `SubagentStop` with a matcher on the research agent types. It matches on agent type, including plugin-scoped names [src S3]. It runs `research_check.py role-exit --agent <type>`. | An agent stopping after it marked its own claim verified, touched `data/raw`, or left out the "Open questions" section. Exit 2 makes it continue [src S3]. A counter file in `.workflow/tmp/` allows 2 retries, then lets it stop and records a blocker, to avoid loops. |
| L3 | Permission deny rules in the project's `.claude/settings.json`: `Edit(/bib_sources/**)`, `Edit(/research/data/raw/**)`, `Edit(/research/ledger/numbers.jsonl)` for hand edits. Deny is evaluated first [src S5]. | Hand-written BibTeX and edits to raw data through built-in tools or recognised shell commands. It does **not** stop scripts [src S5]. L1 hashes cover that gap. |
| L4 | Human review: `submit.sh`/`review.sh approve`. The lead never approves (`SKILL.md:29-31`). | Everything outward-facing. |

---

## 7. How the PI works with the team

### 7.1 What the PI sees

- **`research/pi/BRIEF.md`**, rewritten at every gate. It stays under one page and is
  generated from the ledgers wherever possible. Sections:
  1. Current finding, stated first (P11 line 103).
  2. What changed since the last brief.
  3. Key numbers with their N-IDs.
  4. **What did not work**. This section is mandatory, and negative results are stated
     with the same precision as positive ones (P5 line 57).
  5. Untested or unverified items (P6 line 65, P8 line 79).
  6. Any `--force` use.
  7. Decisions needed.
- **Decision records** in `research/pi/decisions.md`, one per decision:
  ```
  D-007 | raised 2026-09-30 by redteam | phase analysis
  CONCERN: test split is not grouped by scenario_id
  EVIDENCE: 1,000 distinct feature vectors, each exactly 3 times (N-0101); split code train_predictive_models.py:157
  RISK: held-out metrics may be optimistic (src S15, S16)
  ALTERNATIVE: re-run with GroupKFold by scenario_id; report both
  RECOMMENDATION: ...   COST: ...   PI DECISION: (blank until the PI answers)
  ```
- Change requests go through `NOTIFICATIONS.md` (existing `submit.sh`). Every proposed edit
  to a manuscript is a CR. The PI approves with `review.sh approve`.

### 7.2 How subagent questions reach the PI

A subagent cannot ask the PI [src S2]. It ends its report with "Open questions for the
orchestrator", as required by `_universal_protocol.md`. The lead then:

1. Parses the questions.
2. Removes duplicates.
3. Gives each a Q-ID in `questions.md`, recording who raised it, whether it is blocking,
   the options, and the assumption the agent would otherwise make.
4. For a **blocking** question about a material choice (correctness, cost, safety,
   architecture; P1 line 23 and P10 line 95), asks the PI in the main session straight away.
5. Batches all other questions into the next BRIEF.

Work that depends on an open blocking question does not proceed. Other work continues.

### 7.3 Autonomy boundary

**The team does these alone:** search, fetch, read, cache sources, draft, write ledger rows,
run experiments inside the approved plan and budget, open CRs, raise findings, and re-run
the repro job.

**The team never does these without a recorded PI decision ID:**
- Change a number already reported to anyone.
- Submit, upload, or push to a public remote.
- Delete or overwrite raw data or any ledger row.
- Downgrade or omit a negative result.
- Change a frozen hypothesis, metric or decision rule after seeing data (P5 line 51).
- Spend compute or API budget beyond the plan.
- Contact third parties.
- Rewrite git history.
- Use `--force` on a gate.
- Add AI-use disclosure wording to a manuscript (the PI chooses the wording for the venue).

---

## 8. Data and code management

- **Manifest:** `research/data/MANIFEST.tsv` has the columns `path sha256 bytes origin
  source_url license version created_by_run immutable`. Raw files are made read-only after
  they are registered, following "Save the raw data" and making files read-only [src S7].
  The manifest records backups in two locations [src S7].
- **Experiments:** `plan.md` is frozen by hash. `config.yaml` holds every parameter. Seeds
  are listed explicitly (Sandve rule 6 [src S6]).
- **Run records:** `run.json` holds the command line, `git rev-parse HEAD`, dirty flag, env
  lock hash, manifest hash, seeds, hardware (CPU, GPU, OS), start and end time, exit code,
  and outputs with hashes. The engineer's `uws research run -- <cmd>` wrapper writes it. A
  run started outside the wrapper has no record, so its numbers cannot enter the number
  ledger.
- **Environment:** an exact lock (`pip freeze` output with `==` everywhere, plus the Python
  version) and a Dockerfile whose base image is pinned by digest.
- **Repro job:** `research_check.py repro [--numbers N-...|--all] [--sample k]`:
  1. Creates a clean `git worktree` at each run's recorded commit.
  2. Rebuilds the environment from the lock.
  3. Re-runs the command.
  4. Compares each cited number within its declared tolerance: exact for deterministic
     code, absolute or relative for stochastic code, and "same-hardware CI overlap" for
     timings, which are hardware-dependent.
  5. Writes `research/repro/report-<date>.json`.

  This makes Pineau et al.'s definition operational: "obtaining similar results as
  presented ... using the same code and data" [src S8]. For benchmark claims, the SIGSOFT
  standard requires "sufficient experiment repetitions" and a construct-validity discussion
  [src S9], so the methodologist's plan must state both.
- **Inventory:** `research/INVENTORY.md` is generated from the manifest, ledgers and run
  records. It lists and flags:
  - outputs no run produced,
  - scripts never run,
  - data never used,
  - numbers never cited,
  - sources never cited.

  Sandve rule 8 asks for hierarchical output that can be inspected layer by layer [src S6].

---

## 9. Interface to the knowledge base

This section is aligned with `docs/design/knowledge-base.md`, which appeared while I was
writing. I cite it by section as "KB §x". The KB is **an index, never evidence**. That
matches CLAUDE.md ("Never cite vector memory as sole evidence") and KB §4.3. The project
ledger stays the source of truth.

**How ledger rows map to KB items.** The lead promotes a row only after it is verified or
refuted.

| Ledger row | KB item | KB `source` |
|---|---|---|
| `established_fact` / `reported_finding`, verified | `type: fact`, `evidence: reported`, `reviewer` = verifier ≠ `author` (KB §4.2) | `url:` plus the verbatim quote in the body |
| `own_observation`, verified | `type: fact`, `evidence: verified`, `check: python3 scripts/research_check.py numbers --id N-…` | `cmd:<run command>#<output>@<commit>` |
| `inference` / `estimate` | `evidence: inferred` (KB §4.3 records estimates as inferred) | `item:` links |
| `hypothesis` | `type: hypothesis` with `falsifier` = the ledger's `undermining_observation` | none |
| `open_question` | `type: question` | none |
| refuted | the existing KB item goes to `disputed`, then `retired` (KB §5.1) | new ledger row |
| process lesson (e.g. "DBLP blocks scripted access") | `type: lesson` | `file:research/…:<line>@<commit>` |

Every promoted item also carries `source: file:research/ledger/claims.jsonl:<line>@<commit>`,
so the trail back to the ledger survives.

**What this design needs from the KB (gaps to confirm with the KB designer):**
1. `uws kb add` that can run non-interactively, with `--type --claim --evidence --source
   --check --author --reviewer --tags`, printing the new ID on stdout and exiting non-zero
   on validation failure.
2. A 240-byte `claim` cap (KB §4.2). Ledger text can be longer, so promotion stores a
   240-byte summary and the full text stays in the ledger.
3. A command that lists items linked by `contradicts`, or items in `disputed` state, for a
   set of search terms. The literature_review and analysis gates call it, and every hit
   becomes a Q-ID for the PI.
4. `uws kb search` output that includes `status` and `evidence`, so the lead can see that a
   hit is only a lead to follow.

**The rule from the KB back to the ledger:** a KB item used in new work enters the ledger as
`unverified`, and the verifier must check it again against the primary source. Its KB
confidence counts for nothing, because the KB computes it and does not treat it as evidence
(KB §4.3).

**If the KB is missing or fails:** the gates still pass, because the KB is advisory. The
BRIEF notes "KB unavailable", and nothing is promoted until it is back.

## 10. Worked example: auditing the PROMISE 2026 paper

**Inputs:** `github.com/Yash-Sukhdeve/uws-promise-2026` at commit `778ab9a`. I cloned it
into my scratchpad for this design [obs]. The audit works **read-only** on a pinned clone.
All proposed fixes are CRs against an `audit/2026-10` branch, and nothing in `paper/` is
changed before the PI decides.

**Facts already observed while designing (the audit re-verifies them all):**

| # | Observation [obs] | Why it matters |
|---|---|---|
| F1 | `benchmarks/framework_comparison_benchmark.py:403-409` draws LangGraph-, AutoGen- and CrewAI-style times with `random.uniform`. `:412` decides success with `random.random() <` a modelled rate. `:414` adds the draw to the measured elapsed time. | The comparison is simulated, not measured. |
| F2 | The table for that benchmark is only in `paper/tables/archive/`, which neither main file inputs. But `sections/06-conclusion.tex:53` says "Our framework comparison benchmark provides a starting point". | Rule C3: disclosure is needed wherever the comparison is mentioned. |
| F3 | `main-promise.tex:106` inputs a section file that does not exist (A2). | That paper version does not compile. |
| F4 | 10 benchmark scripts use `PROJECT_ROOT = Path(__file__).parent.parent.parent`. `replication/run_benchmarks.sh:31,38` calls `tests/benchmarks/...` paths from the old UWS layout. README `:28-33` admits this. | The replication package cannot run. |
| F5 | `replication/requirements.txt:12,19` leaves statsmodels and PyYAML unpinned (`>=`). `:3` says "Python 3.9+". | The environment is not reproducible. |
| F6 | `paper/references.bib` has 32 entries, 0 `doi =` fields, 7 `@misc`, and there is no `bib_sources/`. | Violates PI rule R6. Every entry must be re-fetched. |
| F7 | 3,000 rows = 1,000 scenarios × 3 trials (`04-evaluation.tex:32`). The raw data has 1,000 distinct model-feature vectors, **each exactly 3 times**. `train_predictive_models.py:157-159,242-244` splits per row with `train_test_split`, not grouped by scenario. | Hypothesis: held-out metrics are optimistic [src S15, S16]. [inference] With an 80/20 split, about 96% of test rows have an identical twin in train (1 − 0.2²). This is a back-of-envelope estimate, not measured. |
| F8 | Training reads the newest `processed/training_data_*.csv` by modification time (`:102,107`). No such CSV is in the repo. | Rule C5. The exact training input is not archived. |
| F9 | `model_results_20251122_072525.json`, Gradient Boosting: `cv_mae_mean` 1.098, `test_mae` 1.17, `r_squared` 0.756, `cv_auc_mean` 0.9125, `test_auc` 0.9199, `test_f1` 0.915. The abstract reports "MAE of 1.1ms", "AUC-ROC of 0.912" and "F1 of 0.911" (`01-introduction-promise.tex:25-26`). | The headline numbers appear to be CV means, not held-out test values. F1 0.911 does not appear in this file; it does appear in `paper/tables/model_comparison_full.tex:47`. Each number needs a `metric` definition and a traced source. [inference until the audit traces them] |
| F10 | Claims needing ledger rows: "first predictive models" (`01-introduction-promise.tex:35`), "enables *causal analysis*" (`:14`), "adequate statistical power" (`04-evaluation.tex:357`). | Rules S1 and S6. The synthetic generator defines the causal structure, so the causal claim may be circular [inference]. |
| F11 | `artifacts/paper_scientific_review.md` contains an earlier verification table (e.g. F1 0.911 against 0.9115). | Prior work to check independently, not to accept as true. |

**Procedure. The owner is shown in brackets. Each step ends in a ledger or report artifact.**

1. **Intake** (Lead). Pin the commit. Create `research/QUESTION.md`: "Is every claim and
   number in the canonical PROMISE manuscript supported, correctly labelled, and
   reproducible?" Record A2 and A3 as blocking Q-IDs for the PI.
2. **Build check** (Engineer). Compile both main files and record the LaTeX logs, undefined
   references and missing inputs. Covers F3.
3. **Claim extraction** (Writer, then Verifier). Every factual sentence in the canonical
   manuscript becomes a C-row with a category and `data_origin`. Novelty, causal and power
   claims get S1/S6 flags. Covers F10.
4. **Citation audit** (Scout, then Verifier).
   - Fetch authoritative BibTeX for all 32 entries.
   - Diff each against the existing `references.bib`.
   - Verify that every cited sentence is supported, with quote checks.
   - `@misc` software citations need a URL and version.
   - Covers F6.
5. **Number trace** (Methodologist). Every number in the abstract, text and tables becomes
   an N-row. Resolve CV versus test, the rounding rule, and the output file. Unresolvable
   numbers get status `unverified` and are reported. Covers F9 and F11.
6. **Simulation audit** (Red Team).
   - Classify each script's output as measured, simulated, or synthetic-generated.
   - Find every sentence, table or caption that uses it.
   - Run check C3.
   - Covers F1 and F2, plus `predictive_dataset_generator.py` and
     `repository_mining_study.py`, which the README (`:34-38`) says generate simulated
     scenarios.
7. **Methodology probes** (Methodologist). Pre-register EXP-LEAK:
   - Hypothesis: grouped-split metrics differ from per-row metrics by more than the CV SD.
   - Unit of evaluation: scenario.
   - Decision rule: stated before the run.
   - Run it and report both results.

   Covers F7 and F8. A decisive null result is reported as prominently as a positive one
   (P5 line 57).
8. **Reproduction** (Engineer).
   - Fix the paths in the audit branch only.
   - Pin the UWS commit (after the PI answers A3).
   - Lock the environment.
   - Run the repro job against `replication/expected_outputs/expected_values.json` within
     declared tolerances.

   Covers F4 and F5.
9. **Adversarial review** (Red Team). Covers the whole package plus the slop scan, with
   blocking, major and minor findings.
10. **PI report** (Lead). This is the stop point.

**Deliverables:**
- the ledgers (`claims.jsonl`, `numbers.jsonl`) and `bib_sources/`,
- `research/audit/REPORT.md`: findings ordered by severity, each with
  CONCERN/EVIDENCE/RISK/ALTERNATIVE,
- `repro/report-*.json`,
- the EXP-LEAK plan and result,
- a list of proposed manuscript changes, as unapplied diffs in CRs, one per finding,
- the INVENTORY.

**What the PI sees before any change to the paper:**
- the BRIEF, listing:
  - which numbers traced cleanly,
  - which did not,
  - which statements rest on simulated data without saying so,
  - the grouped-split result,
  - whether the package reproduces;
- decisions D-* for each proposed wording or number change;
- the open questions A2 and A3.

Nothing is merged or pushed until the PI approves each CR.

---

## 11. First increment (end-to-end, testable)

**Scope, increment 1:**
1. `scripts/research_check.py` with `ledger`, `bib`, `quotes`, `numbers`, `slop` (S1, S2,
   S4, S6, C1, C3, C5) and `gate`.
2. `scripts/research_bib.sh fetch|build` (arXiv, DOI, DBLP) with strict parsing.
3. `research.sh next` calls `gate` when `research/` exists. `--force` logs through
   `log_decision`.
4. `gen_subagents.sh` research roles for scout, verifier and red team, plus the
   `uws-research-lead` skill.
5. The `orchestrate.sh` fix: a `--methodology research` flag, overriding the preference at
   `:44-47`.
6. Plugin `SubagentStop` hook with bounded retries.
7. The PROMISE audit, steps 1-6 and 10, as the first real use.

The methodologist, engineer, writer, the repro job, retraction checks and data manifests
come in increment 2.

**Acceptance tests (BATS plus fixtures, except AT11 and AT12):**

| ID | Check | Expected |
|---|---|---|
| AT1 | Ledger row `verified_by == author` | `ledger` exits 1 and names the C-ID |
| AT2 | A `references.bib` entry is not byte-equal to any `bib_sources` file, or `.meta.json` is missing | `bib` exits 1 |
| AT3 | Fetcher is served the DBLP HTML bot page fixture | non-zero exit, no file written |
| AT4 | A quote is not a substring of the cached text | `quotes` exits 1 |
| AT5 | Hand-typed `0.913` in the abstract gives exit 1. The macro with raw 0.9125 and `floor:3` passes. Changing one byte in the output file gives a hash-mismatch exit 1. | as stated |
| AT6 | "the first predictive models" with no C-ID | `slop` S1 exits 1 |
| AT7 | A number whose `data_origin` is `simulated` is used in a sentence without a disclosure word | C3 exits 1 |
| AT8 | `research.sh next` in analysis with a failing check | blocked, exit 1. With `--force`: advances, and `decisions.log` has an entry |
| AT9 | A ledger ID deleted compared with `HEAD~` | exits 1 |
| AT10 | `research.sh next` at publication with `--force` | refused |
| AT11 | Headless `claude -p` in an isolated `CLAUDE_CONFIG_DIR` (as required by `handoff.md:23-24`): a research subagent tries to mark its own claim verified | the `SubagentStop` hook fires for the plugin-scoped agent name, and the agent continues or a blocker is recorded after 2 retries |
| AT12 | On the PROMISE clone: the audit ledger traces the 4 headline abstract numbers and records F7 (1,000 vectors × 3) as an own observation with an N-ID | `gate analysis` produces the expected pass/fail lines |

The existing 720 BATS tests must stay green. The gate stays inactive without `research/`.

---

## 11a. Second increment (implemented 2026-09-30)

**Scope delivered:** the methodologist, engineer and writer (section 4), plan freeze,
data manifests, run records and the repro job (section 8), the red-team manuscript hash
(section 5, peer_review), retraction checks (6.3 step 7), and metric formulas. Tests:
`tests/integration/test_research_team_inc2.bats`.

**What each gate now checks, in addition to increment 1:**

| Phase | New checks |
|---|---|
| literature_review and later | retraction cache (`RETRACTION`) |
| experiment_design and later | at least one plan; all nine plan fields; frozen hash matches; freeze committed before results; deviations need a PI decision (`PLAN-*`) |
| data_collection and later | data manifest, seeds, number inputs, run-record completeness (`DATA-*`, `RUN-SCHEMA`) |
| analysis and later | formulas and evaluation splits (`NUM-FORMULA`, `NUM-SPLIT`), rule C6, a passing current repro report for every non-literature number (`REPRO`) |
| peer_review, publication | a red-team review naming the current manuscript hash (`GATE-REVIEW-HASH`) |

**PROMISE audit failures and the check that now catches each:**

| Failure found in the audit (section 10) | Check |
|---|---|
| training input chosen by newest mtime and never archived (F8) | C5 on the code; `DATA-UNMANIFESTED` for the run's input; `DATA-MISSING` if the file is gone; the repro job cannot re-run an input it does not have |
| data generator unseeded | `DATA-SEED` (no recorded seed; draws without a seed call; RNG built without a seed) |
| generator-rule labels called ground truth | C6 |
| CV means reported as held-out (F9) | `NUM-SPLIT` (every number declares `evaluation`; the sentence or caption must say "cross-validation"/"CV"/"fold") |
| FPR misreported, 5.8% for 37/88 = 42.0% | `NUM-FORMULA` (the row declares `N-FP/(N-FP+N-TN)` and the check recomputes it) |

**Deviations from the earlier sections, and why [decision]:**
1. The data manifest is `research/data/manifest.jsonl`, not `MANIFEST.tsv` (section 8): JSON
   Lines matches the ledgers (ADR 1) and carries the generator, seed, label origin and split
   definition the PROMISE failures need. A new version of a file is a new row naming the
   hash it supersedes and a reason; replacing raw data needs a PI decision ID.
2. Freezes live in the append-only `research/ledger/plans.jsonl`, not in a `frozen_sha256`
   field of the plan, so the plan file never has to be edited to record its own hash.
   "Frozen before results" is checked from git history: the commit that first contains the
   freeze row (keyed on its hash) must be a strict ancestor of the first commit containing
   each result. A freeze committed together with its results fails. Without git the order
   cannot be shown, and the check fails.
3. The repro job extracts the run's recorded commit with `git archive` into a scratch
   directory instead of creating a `git worktree`, so it never touches the repository's
   worktree list, and it does not rebuild the environment from the lock: the re-run uses the
   current interpreter and packages, and the report records them. Environment rebuilds stay
   a PI decision (compute budget). Inputs that git does not track (large data) are copied in
   only when their hash equals the recorded one. Outputs are deleted before the re-run.
   A re-run can still write outside the scratch copy through an absolute path: that is
   detected (hashes of number outputs and manifest files before and after), not prevented.
4. "Recent" for the repro record means *current*: the report's hash of the number row and of
   its run record must equal today's. A time limit is optional
   (`UWS_RESEARCH_REPRO_MAX_AGE_DAYS`), so committed fixtures do not expire.
5. The plan has nine required sections (P5, P7 and the section-5 gate text): hypothesis,
   unit of evaluation, baseline, metric, controls, split and grouping, sample size, decision
   rule, stopping condition.
6. Every non-literature number names its experiment (`exp`) or is labelled `exploratory`,
   and names its inputs (`inputs` or a run). Otherwise pre-registration and the data
   manifest could be bypassed by leaving the link out.

**Configuration added:** `UWS_RESEARCH_TOLERANCE_DEFAULT` (exact | abs:x | rel:x),
`UWS_RESEARCH_REPRO_TIMEOUT` (seconds, default 3600), `UWS_RESEARCH_REPRO_MAX_AGE_DAYS`
(default off), `UWS_RESEARCH_RETRACTION_MAX_AGE_DAYS` (warning, default 180),
`UWS_RESEARCH_CURL` (curl binary for Crossref; tests use a stub), `UWS_RESEARCH_MAILTO`
(optional contact in the User-Agent), `UWS_RESEARCH_CROSSREF_API` (base URL).

## 11b. Field-test fixes (implemented 2026-09-30)

**Field test:** the first real use of the checks was the audit of the PROMISE 2026 paper
(section 10) at `778ab9a`: a local clone, branch `audit/research-ledger`, with 32 number
rows, 8 claim rows, two wrapper runs and the gate output committed under
`research/gate-output/`. Each fix below has at least one regression test in
`tests/integration/test_research_team_fieldtest.bats` that fails on the code before the fix
(commit `2b53533`, or the branch commit before it for the three re-run fixes); lines quoted
from the paper are verbatim copies in `tests/fixtures/research/promise/`. An adversarial
review of the fixes followed; its findings and their fixes are listed after the decisions.

**What the field test found, and the fix:**

| Finding [obs] | Fix | Rule |
|---|---|---|
| A result committed before its plan's freeze passed when its ledger row was added after a fresh freeze | the order is checked against when the result existed: the first commit of the output file, of its content under any name, of the run record, and the commit the run executed on | `PLAN-ORDER` |
| "ground truth" at `01-introduction-promise.tex:33` and `03-approach.tex:120` was missed; the sentence splitter broke at the dot in `recover\_context.sh` and dropped the start of the sentence | LaTeX-aware sentences (a stop ends a sentence only before whitespace; `\_x.sh`, `0.912`, `Fig.~3`, `et al.\ ` and common abbreviations do not); only ledger macro names count as number uses, never `\textit` or `\paragraph` | C6 |
| Hand-typed numbers escaped `NUM-SPLIT` and C3: only macro uses were judged | a row's `where` (`file:line; file:l1,l2; file#label`, text in parentheses is a note) links the hand-typed value on that line to the row; `NUM-LITERAL` names the row and its macro; a named place that does not show the value is a `NUM-WHERE` warning | `NUM-SPLIT`, `NUM-LITERAL`, C3, C6 |
| `1.1ms`, `1.1\,ms`, `30\%` and every number in the introduction passed | integers and decimals with a unit are numbers; besides the abstract, results, conclusion and tables, the introduction, evaluation, experiments and discussion (by file name or top-level section) are result regions | `NUM-LITERAL` |
| `printed 0.912` blocked against a stored, pre-rounded `0.9125` although the unrounded value 0.91245 prints as 0.912 | a row may name `unrounded` {run, output, pointer} of a wrapper run with the full precision, which must round to `raw` and then decides; without it a printed value that a stored-equivalent value could produce is a warning ("pre-rounded; cannot judge") | `NUM-ROUND` |
| One number-ledger schema error printed once per check in a gate | the gate drops repeated findings | `NUM-SCHEMA` |
| "version control best practices" was an unsupported superlative | a narrow idiom allowlist, matched as whole phrases: best practice(s), best effort, best case, at best ("to the best of our knowledge" is not on it) | S1 |
| A script given as a run input was "unmanifested data" | `run --code <file>`: code is versioned by the run's commit, never registered as data (code extensions given as `--input`, also in older records, count as code); code missing from the recorded commit is `RUN-CODE` | `DATA-UNMANIFESTED`, `RUN-CODE` |
| `\cite{autogen2023}` with no entry anywhere was reported like a missing download | a key that `references.bib` does not define and `bib_sources/` lacks cites nothing | `BIB-UNDEFINED` |
| Timestamped output names (`model_results_20251122_072525.json`) could not be recorded | `--output` takes a glob, resolved after the run to the files the command wrote; the repro job finds the re-run's file by the same pattern; a glob that matches nothing is an error | `run`, `repro` |
| A free-text split could not show the per-row split of 1,000 scenarios × 3 trials (F7) | the manifest `split` may be `{"train", "validation", "test", "group_key"}` (registered files) or `{"column", "group_key"}`; one group on both sides fails; a malformed declaration is `DATA-SPLIT`; free text is a warning | `DATA-LEAK`, `DATA-SPLIT` |
| `research check init` needed `.workflow/state.yaml`, and from `uws` it found no project | the checks and `bib` run without workflow state, from `uws` and `research.sh`; a fallback to UWS's own `.workflow` is never used as the project's (`UWS_WORKFLOW_SOURCE`); phase actions say they need the state | `init` |
| Ledger rows were appended by hand-written Python | `check numbers add '<json>'` / `check claims add '<json>'` fill `id`, `rev`, `supersedes` (numbers also `output_sha256`, `raw` at `pointer`, `printed`), validate the row and append it; existing lines are never touched | `numbers add`, `claims add` |
| `macros` refused to write anything while one row was invalid | it writes the valid rows, reports each skipped row and exits 1 | `macros` |
| `run.json` did not say which interpreter ran the command, nor which environment lock | the interpreter (resolved path, kind, version; Python is probed, other known interpreters are asked `--version`, unknown programs are recorded by path only) and `env_lock` [{path, sha256}] (`--env-lock`, else the usual lock files that exist) | `run` |
| The gate said "KB available" where `uws kb stats` said "No KB yet" | the note quotes `uws kb stats` | gate note |
| The scaffold could not be committed (git keeps no empty directory) | `init` writes `.gitkeep` into empty scaffold directories (not into the ignored source cache) | `init` |

Re-running the gates on a copy of the audit (below) found three more, fixed the same way:
"\textbf{First predictive models}" (`01-introduction-promise.tex:35`, the F10 example)
passed S1, so "First" before a contribution noun now counts (never "First, we ..." or
"First we train models"); a `where` note in parentheses produced a `NUM-WHERE` warning for
the line that inputs the missing section; and `numbers add` refused to record the paper's
F1 0.911 once `unrounded` showed it should print 0.912.

**Decisions [decision]:**
1. **C6 blocks only on evidence tied to the sentence**: a C-ID on it, a claim row whose
   `where` names its line, or a ledger number in it, resting on generated data or on data
   whose manifest `labels` is `generator-rule`. Without such a link the only evidence is that
   some registered data has generator labels, which says nothing about this sentence, so C6
   warns. A sentence that says the labels come from the generator passes.
2. **S1 idioms are an explicit list**, matched as whole phrases. A pattern broad enough to
   skip idioms would also skip claims; a missed idiom costs a C-ID or a rewording.
3. **Pre-rounded outputs warn, never pass**: a stored value with fewer digits than the
   printed rule needs cannot show the printed digits are right. `unrounded` names the run
   output that can, and must round to `raw`, so it cannot point at another quantity.
4. **A row records what the manuscript prints.** `numbers add` refuses a row for what is wrong
   with the row (schema, references, the value at its pointer, links), but appends a row
   whose printed value its evidence contradicts (`NUM-ROUND`, `NUM-FORMULA`), reports the
   finding and exits 0: an audit must be able to record a misprint, and the gate keeps
   failing until the manuscript or a later revision corrects it.
5. **No external attestation of reproduction.** Timestamped outputs are handled by globs,
   not by letting someone state that a number reproduced. A repro pass counts only when the
   report was written by the repro job and its entry names the row's current run; the job
   never passes a number without a run record, so a hand-written pass for such a number is
   `REPRO`. The audit's own exact re-run of the training (`audit/scripts/repro_train.py`,
   350/350 values) therefore does not clear the nine paper numbers: their command has to be
   recorded with `run` and re-run with `repro`. A complete forged report (one naming a
   recorded run) is not detected, because reports are not signed: review and git history are
   the control. An L3 deny rule `Edit(/research/repro/**)` (6.7) would stop such edits
   through Claude Code's tools, not through scripts.
6. **Code is not data.** A script is pinned by the commit the run records; the data
   manifest pins data by hash. Registering scripts as data would ask for a version, source
   and split that a script does not have.
7. **The split is declared, not inferred.** The checker tests the declared groups for
   overlap; it does not guess which column is the independent unit. Free text stays allowed
   (a warning), because a project may not have split files yet.

**Review of the fixes [obs]:** each finding below survived an attempt to refute it. Every
behavioural fix has a test that fails on the branch before it (`7dc9944`); a guarantee that
no test pinned has a test that fails on a mutant removing it.

| Finding | Fix | Rule |
|---|---|---|
| A value computed by a run before the freeze and reformatted by a run after it passed | provenance: every data input of the row and of its runs is followed to the run records that wrote that file version (same path and sha256), recursively; their records, outputs and commits are evidence | `PLAN-ORDER` |
| After a squash merge the run's commit is gone, and `PLAN-ORDER` said the run "happened before the plan was frozen" | an unknown commit is reported as an order that cannot be shown (record the run again); each run is reported once per experiment | `PLAN-ORDER` |
| `research check`/`bib` without a project `.workflow` created `.workflow/logs` in the current directory (uws then took it for a UWS project; the checker took it for the root, so a check from `paper/` exited 2) and wrote `decisions.log` into the installation | `research.sh` dispatches `check <name>`, `bib` and `help`, and refuses phase actions without state, before sourcing the libraries that create log directories; phase logs go to the project's `.workflow/logs` | `init` |
| `BIB-UNDEFINED` missed `\cite{a,` + newline + `b}`, `\parencite`, `\textcite`, `\autocite`, `\footcite`, `\Citet`, `\cite {k}` and `\cites{a}{b}` | the comment-stripped file is read as a whole; every command with "cite" in its name counts except natbib's `\citetext` and `\citestyle`; the retraction check and S2 use the same reading | `BIB-UNDEFINED` |
| A hand-appended manifest row with the same sha256 and `split: "none"` switched a blocking `DATA-LEAK` off with no trace | a row that changes the declaration (split, origin, labels, generator, seed) of unchanged content needs a reason; replacing a structured split by free text or "none" also needs a PI decision; `data add --reason` records it | `DATA-REPLACE` |
| `numbers add` appended a revision of N-0001 that took N-0002's macro (the duplicate was reported on N-0002's line and filtered out) | the add checks the macro against every other current row | `NUM-SCHEMA` |
| A run whose commit is not in the repository (or that names none) skipped `RUN-CODE` and passed the data_collection gate | both are blocking `RUN-CODE` findings | `RUN-CODE` |
| `run.json` recorded a venv's base interpreter (realpath before the probe) | the probe runs the path the command invokes (`invoked`); `path` is the resolved file | `run` |
| `--output 'artifacts/res[1].json'` was always a glob and failed; no output glob matched in a project at `.../proj [v2]` (run and repro) | a path that names an existing file is that file; glob roots are escaped | `run`, `repro` |
| A `where` naming `paper/sec one.tex:2` was read as `one.tex:2` | a place's path is the longest text before `.tex`/`.md` in its `;` segment that names a manuscript file | `NUM-WHERE` |
| A CSV with a UTF-8 byte-order mark (Excel "CSV UTF-8") failed a correct split as `DATA-SPLIT`; an empty unit value counted as the unit "" | CSV/TSV/JSON are read as utf-8-sig; an empty or null unit or split value is `DATA-SPLIT` | `DATA-SPLIT` |
| "0.912 in cross-validation" and "2.5ms in the worst case" passed: "in" after a number was taken for the TeX inch | "in" is a length only attached to the number | `NUM-LITERAL` |
| The status line said the gates name every unbuilt check; only the slop rules and INVENTORY were named | each gate names the unbuilt checks of its phases | gate notes |

Guarantees that no test pinned now have one (each kills a mutant that left the suites
green): the output-path evidence of `PLAN-ORDER`; the fallback clause that keeps phase
actions off UWS's own `.workflow`; `uws research bib` as the first command without
`.workflow`; the REPRO rejection of another tool's report and of an entry naming another
run; C3 and C6 on hand-typed numbers linked by `where`; the column form of a split;
abbreviations inside sentences; the KB note when a KB exists; the `supersedes` filled in by
`numbers add`; and the narrowness of the S1 idiom list.

Decisions of the review [decision]:
8. **Provenance runs through run records only.** A file that a recorded run wrote is a
   result of that run, wherever it is used next; data that no recorded run wrote (raw data,
   a public dataset) is not a result and is not followed. Data preparation recorded with
   `run` before the freeze therefore fails `PLAN-ORDER`, which matches the plan template
   ("freeze ... before collecting data").
9. **An order that cannot be shown fails, with the true reason.** A missing run commit is
   neither "before" nor "after" the freeze; the gate fails closed and says the commit is not
   in the repository, as `NUM-RUN`, `RUN-CODE` and the repro job already do.
10. **A re-declaration is a recorded change.** The leak, label and disclosure checks read a
   file's latest manifest row, so changing that row's declaration for unchanged content is a
   change like a new version: it needs a reason, and turning the leak check off needs the PI.

**Re-run of the gates on the audit** (a scratch clone of `audit/research-ledger` at
`dfb8b1f`; every check plus the `analysis` and `publication` gates, the base checker of
`2b53533` against this branch). Each finding was classified against the audit report
(`audit/REPORT.md`) and the ledgers' notes: *true* (a defect the audit confirms, or a
concrete violation of the rule), *process* (true under the tool's layout, but bookkeeping
the audit project had not done: its pre-registration is in `audit/EXP-LEAK.md`, eight
EXP-LEAK numbers were run outside the wrapper, no macro file, review or PI approval),
*false*. Publication gate:

| | before (`2b53533`) | after |
|---|---|---|
| findings (block / warn) | 138 / 3 | 173 / 13 |
| true | 113 (110 / 3) | 159 (146 / 13) |
| process | 20 | 20 |
| false positives | 5, plus 3 repeated lines | 7 |
| CV values presented as results (`NUM-SPLIT`, 10 places) | 0 | 10 |
| "ground truth" for generator labels (4 places, C-0001) | 2 (warn) | 4 (one blocks) |
| novelty claims without a verified claim (5 places) | 4 | 5 |
| hand-typed result numbers (`NUM-LITERAL`) | 6 | 25 |
| number tokens the audit found mismatched or untraceable (38 in the manuscript tree) | 0 flagged | 5 flagged |

- False positives before: code as unmanifested data (3), "best practices" (1), and N-0003's
  `0.912` (the unrounded value 0.91245 prints as 0.912). After: C3 on the 7 places that
  print the recovery-time numbers N-0001 and N-0002. The ledger labels them
  `synthetic-generated`, but the times are measured (on generated scenarios); see "Not
  fixed".
- N-0004 (`F1 0.911`, should be 0.912): before, a block that rested on the pre-rounded
  0.9115 (the same logic produced the N-0003 false positive); after, a warning, until a
  revision names `unrounded`. Appending the two revisions with `numbers add` turns N-0004
  into a block and clears N-0003 (174 blocking, 11 warnings).
- After the review fixes the re-run is unchanged: the same 173 blocking findings and 13
  warnings in the publication gate (171 and 13 in analysis), and two more notes naming
  unbuilt checks. The review's cases (multi-line or biblatex citations, "in" after a
  number, squash-merged runs, venvs, bracketed paths) do not occur in the audit.
- Still missed, before and after: statements that need reading, not patterns ("timeout
  reduces success" is backwards; MAE at the noise level; KaVE figures from another paper;
  DevGPT prompts called conversations; the Airflow citation names a different paper); wrong
  years and a non-author in BibTeX entries, which BIB-REFS reports only as "not
  downloaded"; and the evaluation section, which is missing (S4 reports it; its numbers are
  checked only through ledger rows such as N-0007's `NUM-FORMULA`). Of the 38 number tokens
  the audit found mismatched or untraceable, the 33 still missed are 12 numbers behind
  `\cite` (they need the cited full texts), an uncited range (8K-128K tokens), 5 counts
  "3,000 recovery scenarios" (1,000 scenarios × 3 trials; the number is right, its unit is
  not), 12 numbers in the method section (generator and feature ranges, a threshold, 2,000
  lines, and 93%/76% at `03-approach.tex:118`, which are caught in the introduction and
  conclusion), an illustrative 30% in related work, and a table that only the
  non-canonical `04-evaluation.tex` inputs.

**Not fixed, and why:**
1. **Measured outcomes under generated conditions.** `data_origin` describes a number as a
   whole. The audit labelled the recovery times, measured on generated scenarios,
   `synthetic-generated`, so C3 asks every sentence that prints them for a disclosure (the
   7 false positives above; the abstract discloses the generation one sentence earlier).
   Revisions labelling N-0001 and N-0002 `measured` remove exactly those 7 and nothing else
   (re-run: 166 blocking, 13 warnings), but then no rule asks for the disclosure at all. A
   label for "measured outcome, generated conditions" changes the vocabulary of A4
   (section 3): a PI decision, not a checker fix.
2. **Numbers in method sections.** `NUM-LITERAL` still covers result regions only (6.4 d).
   Method sections are mostly design parameters; checking them needs parameter rows in the
   ledger, which nothing produces yet. The 93%/76% at `03-approach.tex:118` stay missed
   there; the same values are caught in the introduction and conclusion.
3. **Statements that need reading.** Wrong directions, wrong units of a count, and citations
   that support a different claim are the verifier's and red team's work (claim rows with
   quotes); no pattern finds them reliably.
4. **BibTeX metadata cross-check** (6.3 step 6) is still not built, so wrong years and
   authors in a hand-written `references.bib` show up only as BIB-REFS.
5. **Forged complete repro reports** are not detectable without signing reports; see
   decision 5.
6. **`numbers add` cannot record a number with no output file** (the paper's FPR 5.8% has
   none): `output`, `pointer` and `output_sha256` stay required, so the audit's N-0007 can be
   written only by hand. Making them optional would let a number enter the ledger without
   provenance.
7. **Provenance outside run records.** `PLAN-ORDER` cannot trace an intermediate result
   written outside `run` (it looks like data); recording every step with `run` is the
   remedy, not a heuristic that guesses which data files are results (decision 8).
8. **User citation macros.** Any command with "cite" in its name counts as a citation, so
   a user macro such as `\mycite{key}` is checked; a macro with "cite" in its name that takes
   no keys (other than natbib's `\citetext` and `\citestyle`) would be read as citing its
   argument. The .tex files of the PROMISE audit use no citation command but `\cite`.

## 11c. Release-readiness probe fixes (implemented 2026-10-01)

A probe tried to get a wrong or unreported result past the gates of a small synthetic
project, using only the documented commands. These are the changes; each has a test in
`tests/integration/test_research_team_probe.bats`.

1. **`uws:literal`** (NUM-LITERAL). The marker no longer silences a number within 10% of a
   ledger value or a number in a sentence that names a metric of the number ledger (AUC,
   accuracy, F1 ...). Those need a recorded PI decision: `% uws:literal D-<n> <reason>`.
   The publication gate lists every number a marker accepts, as a warning.
2. **Scope.** Findings, analysis, performance and outcomes headings are results sections.
   Elsewhere a hand-typed number is reported when its sentence names a ledger metric or it
   is a ledger value. Where results are reported, a unit-less integer is reported when it
   is within 10% of a ledger count that its sentence is about (120 typed for 115 test rows).
3. **CV as held-out.** The key pattern also recognises `cv5_...`, `cv10`, `cvacc`, `kfold`,
   `oof` and `fold_mean`. A held-out row whose pointer names no split, in an output that
   also holds CV values, is a warning. In prose, a CV value in a sentence that also says
   held-out blocks at peer_review and publication (unless the line cites a recorded PI
   decision); a negated mention ("not a held-out result") is not counted.
4. **Append-only.** Ledgers are compared with HEAD and every commit that touched them, so an
   in-place edit stays reported however many commits follow; the finding names the row's
   real line.
5. **PI decisions.** A D-ID counts only when its record has a non-empty `PI DECISION:` line.
   A plan deviation must be named (DEV-ID or EXP-ID) in the manuscript before peer_review.
6. **Publication approval.** `PUBLICATION-APPROVAL: sha256:<manuscript hash> by <PI>` is
   checked against the manuscript as it is now. A `CR-...` approval is accepted only where
   `.uws/crs/` exists to check it.
7. **C3.** A non-measured number whose sentence does not disclose it, but whose paragraph,
   section heading or document title does, is a warning instead of a block.
8. **Messages and defaults.** An invalid rounding rule is named when the row is added; a
   review without a `Manuscript:` line and an unrecorded `--pi-decision` say so; `bib build`
   writes a new references.bib under `paper/` when the project has one.

## 12. Risks and failure modes

| # | Risk | Mitigation |
|---|---|---|
| R1 | The verifier shares the author's blind spots (same model family) | Fresh context. Claim-only input with no author quote. Deterministic quote and metadata checks. Red team. The PI spot-checks a random 10% of verified claims each gate. |
| R2 | Source is paywalled or unavailable | Status `unverifiable-access` cannot pass a gate. The PI can supply the text. |
| R3 | Bot blocking or rate limits (observed on DBLP) | Several authoritative endpoints, caching, backoff. Fails closed. Never falls back to generated text. |
| R4 | Checker false positives (years, section numbers, versions) | Scoped sections, a `% uws:literal <reason>` marker, warn-level for fuzzy rules. Fixtures from real papers. |
| R5 | Gate fatigue leads to `--force` abuse | Every force is logged and shown in the BRIEF. It is refused at publication. Count per phase is shown. |
| R6 | `SubagentStop` loop | Cap of 2 retries, then stop with a recorded blocker. |
| R7 | The ledger becomes bureaucracy | Only claims in deliverables are recorded. Extraction is agent-assisted. P7: record claims the PI will rely on, not every sentence of notes. |
| R8 | Nondeterminism (timing, GPU, thread order) makes the repro job flaky | Tolerance per number. Repeated runs with variance reported (P6 line 63). "Same-hardware" timing tolerance kept separate. |
| R9 | Scripts delete or alter data, which deny rules cannot stop [src S5] | Read-only raw files, manifest hashes checked at every gate, git, off-site backup [src S7]. Optional sandbox. |
| R10 | Prompt injection from fetched pages | Fetched content is data (P10 line 97). Agents never follow instructions in sources. The checker ignores prose in sources except for quote matching. |
| R11 | A KB item is treated as evidence | It enters the ledger as `unverified` (Section 9). |
| R12 | Copyright of cached full texts | Cache is gitignored. The repo keeps only hash, short quote and locator. The PI decides on sharing. |
| R13 | Regex slop checks give false comfort | The red team's semantic pass is mandatory at peer_review. Regex is the floor. |
| R14 | Cost of three opus roles | Tiers are overridable. The P7 cost estimate goes in each plan. The PI approves budgets. |

**Failure modes of each component:**

| Component | Failure | Detection | Recovery |
|---|---|---|---|
| research_check.py | crash or parse error | exit 2 | gate blocks (fails closed); fix the fixture and re-run |
| research_check.py | rule bug lets a bad row pass | AT fixtures, red team | add a regression fixture |
| research_check.py | slow on a large ledger | CI time | index by ID; one-pass parse |
| bib fetcher | HTML or empty body | strict parse | try another endpoint; ask the PI |
| bib fetcher | wrong paper returned | metadata cross-check | mark disputed; the scout re-identifies it |
| bib fetcher | network down | exit 2 | retry later; the gate is unaffected (offline) |
| SubagentStop hook | not fired (plugin name mismatch) | AT11 | the L1 gate still catches it |
| SubagentStop hook | loops | retry counter | forced stop plus blocker |
| SubagentStop hook | times out | hook timeout | L1 still applies |
| repro job | environment will not build | exit 2 | pin a fix and record it as a deviation |
| repro job | drift beyond tolerance | report | a finding goes to the PI; the number is not changed |
| repro job | worktree left behind | cleanup trap | `git worktree prune` |
| ledgers | merge conflict | git | append-only means union merge, then run the checker |
| ledgers | a row is deleted | AT9 | restore from git |
| ledgers | a row is corrupted | JSON parse | exit 1 with the line number |

---

## 13. Cross-cutting checklist

- **Security:**
  - Deny rules on `bib_sources`, raw data and the number ledger.
  - No secrets in `run.json`; environment variables are recorded as names only.
  - Fetched content is untrusted.
  - The PI gate for anything outward-facing.
- **Observability:** checker findings as `file:line RULE-ID`, `decisions.log`, the BRIEF,
  and the `INVENTORY` report.
- **Configuration:**
  - `UWS_AGENT_MODEL_<ROLE>`.
  - `UWS_RESEARCH_TOLERANCE_DEFAULT` (default: exact).
  - `UWS_RESEARCH_HOOK_RETRIES` (default 2).
  - `UWS_RESEARCH_SLOP_WARN_DENSITY` (default: the PI decides after calibrating on
    fixtures).
- **Deployment:** shipped in the UWS plugin (`scripts/`, `agents/`, `hooks/hooks.json`) and
  through the per-project installer. Needs Python 3 only for research projects.
- **Data:** append-only ledgers, hashed manifests, backups, and research CI.

---

## 14. Decisions and trade-offs (ADR summary)

1. **JSONL instead of YAML for the ledgers:** one record per line, parsed by the standard
   library, no dependency on `yq`. The cost: less pleasant to edit by hand. That is
   intentional.
2. **Python 3 standard library for the checkers:** robust parsing. The cost: a new
   runtime dependency, limited to research projects.
3. **Offline gates:** deterministic CI. The cost: evidence can go stale, which the
   `bib verify --online` job covers.
4. **Merged roles (7 instead of 9):** fewer handoffs. Independent checks are kept where
   they catch errors: verifier against author, red team against everyone, and scripts
   against data.
5. **Macros for numbers:** eliminates transcription errors. The cost: the writer has to
   write the paper through macros.

## 15. Assumptions made

- The PI wants the same gates for any research project, not only PROMISE.
- The research project's CI can run Python 3.
- Short verbatim quotes, meaning the quote field of a ledger row, may be committed.

## 16. Sources opened this session

- S1 `docs/personas/apocalypt.md` (local, verbatim persona)
- S2 Claude Code, Subagents: https://code.claude.com/docs/en/sub-agents
- S3 Claude Code, Hooks: https://code.claude.com/docs/en/hooks
- S4 Claude Code, Plugins reference: https://code.claude.com/docs/en/plugins-reference
- S5 Claude Code, Permissions: https://code.claude.com/docs/en/permissions
- S6 Sandve et al., *Ten Simple Rules for Reproducible Computational Research*, PLOS Comput Biol 2013: https://doi.org/10.1371/journal.pcbi.1003285
- S7 Wilson et al., *Good Enough Practices in Scientific Computing*, PLOS Comput Biol 2017: https://doi.org/10.1371/journal.pcbi.1005510
- S8 Pineau et al., *Improving Reproducibility in Machine Learning Research*, 2020: https://arxiv.org/abs/2003.12206
- S9 ACM SIGSOFT Empirical Standards, Benchmarking: https://github.com/acmsigsoft/EmpiricalStandards/blob/master/docs/standards/Benchmarking.md
- S10 Walters & Wilder, *Fabrication and errors in the bibliographic citations generated by ChatGPT*, Sci Rep 2023: https://pmc.ncbi.nlm.nih.gov/articles/PMC10484980/
- S11 Rao & Callison-Burch, *BibTeX Citation Errors in Scientific Publishing Agents: Evaluation and Mitigation*, 2026: https://arxiv.org/abs/2604.03159
- S12 Dhuliawala et al., *Chain-of-Verification Reduces Hallucination in LLMs*, 2023: https://arxiv.org/abs/2309.11495
- S13 Min et al., *FActScore*, 2023: https://arxiv.org/abs/2305.14251
- S14 Beel, Kan & Baumgart, *Evaluating Sakana's AI Scientist*, 2025: https://arxiv.org/abs/2502.14297
- S15 Kapoor & Narayanan, *Leakage and the Reproducibility Crisis in ML-based Science*, 2022: https://arxiv.org/abs/2207.07048
- S16 scikit-learn, Cross-validation iterators for grouped data: https://scikit-learn.org/stable/modules/cross_validation.html
- S17 DOI content negotiation: https://citation.doi.org/docs.html
- S18 arXiv BibTeX endpoint, tested: https://arxiv.org/bibtex/2309.11495
- S19 Wikipedia, *Signs of AI writing*: https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing
- S20 Crossref, *Retraction Watch* (metadata retrieval documentation), opened 2026-09-30: https://www.crossref.org/documentation/retrieve-metadata/retraction-watch/
- S21 Crossref, *Participating in Crossmark* (the 12 update types), opened 2026-09-30: https://www.crossref.org/documentation/crossmark/participating-in-crossmark/

Not cited, because the page returned 403: the ACM Artifact Review and Badging definitions.

## 17. Decisions needed from the PI

1. **Canonical PROMISE manuscript:** `main.tex` or `main-promise.tex`? The second does not
   compile at 778ab9a (F3).
2. **UWS commit the paper measured:** needed to pin the reproduction (A3).
3. **Compute and branch approval for the audit:** may the team run the benchmarks and
   EXP-LEAK, and may it push an `audit/2026-10` branch to the public paper repo? Or should
   it stay private or local?
4. **`--force` at publication:** refuse always (recommended), or allow with a D-ID?
5. **Python 3** as a dependency for research projects (recommended) instead of Bash-only
   checkers.
6. **Model tiers:** opus for verifier, methodologist and red team (recommended), or cheaper
   tiers.
7. **Source caches:** gitignored with quotes and hashes only (recommended), or committed
   for full auditability?
8. **AI-use disclosure:** the team does not "humanise" text to hide AI involvement. Which
   disclosure wording and venue policy should the writer draft for?
9. **Optional `research-assistant` plugin:** mention it to users as a complement (MIT), or
   leave it out entirely?
10. **Slop warn thresholds (S5):** calibrate on the PI's own past papers, or on public
    fixtures?

### PI decisions (recorded 2026-09-26)

Decided by the PI:
- **1:** the canonical manuscript is **`main-promise.tex`** (its missing
  `sections/04-evaluation-promise` input is audit finding F3).
- **3:** the audit may **re-run the experiments locally** (benchmarks and the grouped-split
  leakage experiment) and **report to the PI**. Nothing is pushed to the public paper repo and
  nothing in the paper is changed without the PI.
- The PI approves every knowledge-base promotion (see knowledge-base.md, D4).

Defaults adopted until the PI says otherwise:
- **2:** the team reconstructs the measured UWS commit from dates and artifacts and reports
  its evidence; the PI confirms before the reproduction is pinned.
- **4:** `--force` is always refused at the publication gate.
- **5:** Python 3 (standard library only) is acceptable for checkers.
- **6:** opus for verifier, methodologist and red team.
- **7:** source caches are gitignored; ledgers keep quotes and hashes.
- **8:** AI-use disclosure wording: open; the writer drafts nothing until the PI decides.
- **9:** UWS ships its own team; the optional plugin is not mentioned.
- **10:** calibrate slop thresholds on public fixtures first.
