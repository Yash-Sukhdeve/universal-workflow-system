---
description: Activate/manage UWS agents (researcher, architect, implementer, etc.)
allowed-tools: Bash(./scripts/activate_agent.sh:*), Read
argument-hint: <agent> [activate|deactivate|status|handoff]
---

Manage UWS agents. Available agents:
- researcher: Requirements deep-dive, gap analysis, failure mode inventory
- architect: System design, API contracts, failure mode analysis, end-to-end flows
- implementer: Production-grade code, zero stubs, full test coverage
- experimenter: End-to-end verification, failure injection, performance baselines
- optimizer: Baseline-first measurement, hypothesis-driven optimization
- deployer: Health checks, graceful shutdown, CI/CD, monitoring
- documenter: Tested code examples, complete API docs, troubleshooting guides

Execute based on $ARGUMENTS

After activation completes:

1. **Read the active persona** from `.workflow/agents/active.yaml`. It contains TWO protocol blocks:
   - `universal_protocol:` — the shared protocol ALL agents follow (Phase 0, Phase 1, Phase 2, Anti-Patterns)
   - `persona:` — the agent-specific operational protocol with numbered steps and quality gates

2. **Execute Phase 0: Context Intake** (from Universal Protocol) IMMEDIATELY:
   - Read `.workflow/handoff.md` and all prior artifacts for the current phase
   - Identify at least 3 ambiguities or unclear items
   - Identify at least 3 things NOT said (missing failure modes, edge cases, omitted subsystems)
   - Ask the user about these items BEFORE starting substantive work
   - Restate scope, deliverables, and constraints for user confirmation

3. **MANDATORY**: Do NOT start substantive work until Phase 0 is complete. The checklists in the protocol are gates, not suggestions.

4. **During work**, follow the agent-specific Operational Protocol steps in order.

5. **Before declaring done**, execute Phase 2: Quality Gate (Universal Protocol) AND the agent-specific Quality Gate. Every checkbox must pass.

If vector memory is configured, query for handoff context:
  mcp__vector_memory_local__search_memories(
    "handoff decisions PHASE <current>", limit=5)
  mcp__vector_memory_local__search_memories(
    "decisions constraints PHASE <current>", category="architecture", limit=3)
