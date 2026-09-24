---
name: uws-orchestrate
description: Run the current UWS phase as an autonomous, checkpoint-gated step — dispatch the phase's work to the matching subagent, then route its artifact through the human review gate. USE WHEN the user asks the framework to produce the current phase's deliverables, advance a UWS task, or "work on the current phase".
allowed-tools: Bash, Task, Read, Write, Grep, Glob
---

# UWS Orchestrate

Drive one UWS phase end-to-end using real subagents, keeping the human review + deliverable gate in the loop. This is the execution core that binds the UWS state spine to Claude Code's Agent/Workflow primitives.

## Procedure

1. **Prepare the dispatch.** Run:
   `./scripts/orchestrate.sh dispatch "<one-line task>" [target-rel-path]`
   Parse the emitted `DISPATCH:` line — it names `agent`, `subagent` (a `.claude/agents/uws-<role>.md`), `phase`, `brief` (`workspace/<role>/TASK.md`), and `out` (the artifact path to write).

2. **Read the brief.** Read the `brief` file. It contains the goal, phase, target artifact path, and the deliverables checklist that will gate advancement.

3. **Run the subagent.** Launch the named `uws-<role>` subagent (Agent tool; or Workflow for multi-agent phases) with a prompt that:
   - points it at the `brief`,
   - tells it to write its artifact to the `out` path (under `workspace/<role>/`, mirroring the intended repo path),
   - requires it to address every deliverable and STOP at its persona Quality Gate.
   Do not let the subagent advance the workflow, checkpoint, or mark deliverables.

4. **Stage for review.** When the artifact exists, run:
   `./scripts/orchestrate.sh collect "<summary>"`
   This calls `submit.sh` to create a change request under `.uws/crs/` and post it to `NOTIFICATIONS.md`.

5. **STOP at the gate.** Tell the user the change request is ready and show how to approve:
   `./scripts/review.sh approve <CR-ID>`
   **Do not approve on the user's behalf** — approval is the human checkpoint (this is checkpoint-gated autonomy).

6. **After the user approves**, mark the satisfied deliverables and advance:
   `./scripts/<methodology>.sh check <n>` for each, then `./scripts/<methodology>.sh next`.
   The hard gate will refuse to advance until every deliverable for the phase is checked (unless `--force`).

## Notes
- Methodology + phase + agent are resolved from `.workflow/state.yaml`; run `./scripts/orchestrate.sh status` to see them.
- If no phase is active, tell the user to run `./scripts/sdlc.sh start` (or `research.sh start`) and declare a goal with `./scripts/sdlc.sh goal "<objective>"` first — the deliverable gate only activates once a goal is declared.
- Never write application code during a planning-phase (requirements/design) dispatch — those produce documents only.
