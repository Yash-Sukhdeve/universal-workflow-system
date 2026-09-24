---
description: Update .workflow/handoff.md before ending a session
allowed-tools: Read, Edit, Write, Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws checkpoint:*)
---

Update `.workflow/handoff.md` so the next session (human or Claude) can pick up
immediately. Current contents:

@.workflow/handoff.md

Rewrite it with:
1. **Status**: goal, phase and latest checkpoint (see `.workflow/state.yaml`).
2. **Done this session**: concrete changes, with file paths.
3. **Next actions**: prioritised, each small enough to start without more context.
4. **Blockers / open questions**.
5. **Critical context**: decisions and constraints that are not obvious from the code.

Remove anything that is no longer true. Then run `${CLAUDE_PLUGIN_ROOT}/bin/uws checkpoint create "Session handoff"`.
