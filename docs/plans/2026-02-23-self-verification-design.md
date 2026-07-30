# UWS Self-Verification Design

**Date**: 2026-02-23
**Approach**: Full SDLC Dogfood with Parallel Agent Orchestration
**Project**: Universal Workflow System verifying itself

## Overview

Use UWS's own SDLC workflow (6 phases) to verify UWS. All 7 agents participate,
dispatched as parallel subagents where dependencies allow. Real UWS checkpoints
are created at each phase boundary. The system verifies itself.

## SDLC Phase Map

| Phase | Agents | Parallel | Tasks |
|---|---|---|---|
| Requirements | Researcher + Architect | Yes | Audit scripts, validate schema, verify registry |
| Design | Architect + Documenter | Yes | Validate architecture, check docs vs code |
| Implementation | Implementer | Solo | Run 690+ BATS tests, ShellCheck linting |
| Verification | Experimenter + Optimizer | Yes | Benchmark, stress-test, validate memory |
| Deployment | Deployer | Solo | Test install/uninstall, validate hooks/CLI |
| Maintenance | Documenter + Researcher | Yes | Validate handoff, produce final report |

## Agent Responsibilities

### Researcher (Requirements + Maintenance)
- Audit agent registry: all 7 agents with capabilities
- Audit skills catalog: all 23 skills present
- Verify RWF compliance (R1-R5)
- Search vector memory for prior results

### Architect (Requirements + Design)
- Validate scripts/lib/ dependency graph
- Check workflow_routing.sh agent/phase mappings
- Verify state.yaml schema against docs
- Validate checkpoint v2 format

### Implementer (Implementation)
- Run unit tests (431), integration tests (189), system tests (70)
- Run ShellCheck on all scripts
- Report pass/fail with evidence

### Experimenter (Verification)
- Run benchmark suite
- Stress-test checkpoint cycle (10x)
- Test recovery completeness scoring
- Validate phase transitions

### Optimizer (Verification)
- Profile script execution times
- Check performance regressions
- Validate vector memory search latency

### Deployer (Deployment)
- Test init_workflow.sh in clean environment
- Test uninstall.sh --dry-run
- Verify Claude Code hooks
- Validate .mcp.json configuration

### Documenter (Design + Maintenance)
- Cross-reference CLAUDE.md vs capabilities
- Verify slash commands functional
- Check handoff.md completeness
- Produce final verification summary

## Success Criteria

- All 690+ BATS tests pass
- All 17 scripts executable and return 0
- Checkpoint roundtrip preserves state
- Recovery completeness >= 80%
- All 7 agent activations succeed
- SDLC phase transitions complete
- Vector memory operations work
- ShellCheck zero errors
- No partial state from failures

## Artifacts

- `docs/verification/2026-02-23-self-verification-report.md`
- 6 checkpoints (CP per phase)
- Test results in `test-results/` (TAP)
- Benchmark data in `artifacts/benchmark_results/`
- Vector memory entries documenting verification
