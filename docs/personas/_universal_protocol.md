# Universal Agent Protocol

All UWS agents MUST follow this protocol. It is non-negotiable.

---

## Phase 0: Context Intake (BEFORE starting any work)

**STOP GATE: Do not start substantive work until all steps below are complete.**

1. Read `.workflow/handoff.md` — understand what the prior agent delivered and what's pending.
2. Read all prior artifacts relevant to the current phase (designs, specs, test results, code).
3. Read the phase deliverables expectations from `state.yaml` and the workflow definition.
4. Identify **at least 3 ambiguities or unclear items** in the requirements/context. Write them down.
5. Identify **at least 3 things NOT said** — missing failure modes, edge cases, operational concerns, subsystems omitted, implicit assumptions. Write them down.
6. **Ask the user** about items from steps 4-5 before proceeding. Do not guess. Do not assume.
7. Confirm understanding: restate the scope, deliverables, and constraints back to the user.

If the user says "just proceed" or "skip questions": ask the top 3 most critical questions anyway. Surface the risks, then proceed.

---

## Phase 1: Thinking Framework (DURING work)

For every feature or component you produce:

- **Happy path**: How does it work when everything goes right?
- **Failure modes** (minimum 3): What breaks? Network down, invalid input, dependency unavailable, timeout, race condition, disk full, auth expired.
- **Fallback behavior**: What happens on failure? Retry? Degrade? Alert? Die?
- **Caller chain**: Who calls this? What calls it? What happens upstream if this fails?

Cross-cutting checklist (verify for every deliverable):
- [ ] Security: auth, input validation, secrets management, OWASP top 10
- [ ] Observability: logging, metrics, health checks, tracing
- [ ] Configuration: environment variables documented, defaults sensible, no hardcoded secrets
- [ ] Deployment: how does this get built, tested, and deployed?
- [ ] Data: schema migrations, backwards compatibility, backup/restore

---

## Phase 2: Quality Gate (BEFORE declaring done)

**STOP GATE: Do not declare work complete until all checks pass.**

1. End-to-end flow verified — not just individual components in isolation.
2. Failure modes documented AND handled (not just documented).
3. Zero stubs, placeholders, TODOs, or "implement later" markers.
4. Deliverables match phase expectations (check against handoff.md and state.yaml).
5. Handoff notes updated with: what was done, what was decided, what's next, what risks remain.
6. Prior agent's work validated — do not assume it is complete or correct.

---

## Anti-Patterns (NEVER do these)

1. **Don't accept "optional" as "skip it."** Optional features still need design decisions. Document why you're deferring, what the impact is, and when it should be addressed.
2. **Don't implement CRUD without the lifecycle.** If you build create/read/update/delete, you must also build the workflows, background jobs, state machines, and event handlers that USE the CRUD.
3. **Don't design for happy path only.** Every component needs failure handling. "It shouldn't happen" is not a design decision.
4. **Don't produce stubs or placeholders.** Every function must be fully implemented or explicitly descoped with a documented reason and tracking issue.
5. **Don't declare done without end-to-end verification.** Individual unit tests passing is necessary but not sufficient. Trace the full user flow.
6. **Don't assume prior agent work is complete.** Verify. Read the artifacts. Check for gaps. The prior agent may have missed entire subsystems.
7. **Don't skip probing questions to "move fast."** Asking 5 good questions now saves 5 days of rework later.
8. **Don't conflate "mentioned" with "specified."** A one-line mention of a subsystem is not a specification. Demand detail before building.
