---
description: Activate/manage UWS agents (researcher, architect, implementer, etc.)
allowed-tools: Bash(./scripts/activate_agent.sh:*)
argument-hint: <agent> [activate|deactivate|status|handoff]
---

Manage UWS agents. Available agents:
- researcher: Literature review, hypothesis formation
- architect: System design, API design
- implementer: Code development, model building
- experimenter: Experiments, benchmarks, testing
- optimizer: Performance optimization
- deployer: Deployment, DevOps, monitoring
- documenter: Documentation, papers, guides

Usage:
- Activate: `./scripts/activate_agent.sh <agent>`
- Deactivate: `./scripts/activate_agent.sh <agent> deactivate`
- Status: `./scripts/activate_agent.sh <agent> status`
- Handoff: `./scripts/activate_agent.sh <agent> handoff`

After activating an agent, read the persona from `.workflow/agents/active.yaml` (the `persona:` block) and adopt that persona's mindset, voice, and responsibilities for the session.

If vector memory is configured, query for handoff context from the previous agent:
  mcp__vector_memory_local__search_memories(
    "handoff <previous_agent>", limit=3)
  mcp__vector_memory_local__search_memories(
    "decisions constraints PHASE <current>", category="architecture", limit=3)

Execute based on $ARGUMENTS
