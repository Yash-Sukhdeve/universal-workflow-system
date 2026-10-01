---
description: Dispatch the current UWS phase to its subagent and route the artifact through the human review gate
argument-hint: "[dispatch \"<task>\" | collect \"<summary>\" | status] [--methodology sdlc|research] [--agent <role>]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws orchestrate:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws sdlc:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws research:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws review list:*), Task, Read, Write
---

Run one UWS phase as a checkpoint-gated step with the user's arguments (`$ARGUMENTS`).
If they start with `collect` or `status`, run that subcommand and summarise the result.
Otherwise treat them as the one-line task (ask for one if they are empty) and:

1. Prepare the dispatch:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/uws orchestrate dispatch "<task>"
   ```

   Read the `DISPATCH:` line it prints: `agent`, `phase`, `brief` (`workspace/<role>/TASK.md`)
   and `out` (where the artifact goes).
2. Read the brief, then launch the plugin subagent `uws:uws-<agent>` (Task tool) on it. Tell it
   to write its artifact to the `out` path, to address every deliverable in the brief, and to
   stop at its quality gate. It must not advance the workflow, checkpoint, or tick deliverables.
3. When the artifact exists, stage it for human review:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/uws orchestrate collect "<agent>: <one-line summary>"
   ```

4. Stop at the gate. Show the user the change request ID and the approve command it printed.
   Approving is the user's decision: never run `review approve` for them.
5. After the user approves, tick the deliverables the artifact satisfies with
   `/uws:sdlc check <n>` (or `/uws:research check <n>`) and advance with `next`, which refuses
   while deliverables are unmet once a goal is declared.

If no phase is active, tell the user to start one (`/uws:sdlc start` or `/uws:research start`)
and, to turn on deliverable gating, declare a goal (`/uws:sdlc goal "<objective>"`). A
requirements or design dispatch produces documents only, never application code.
