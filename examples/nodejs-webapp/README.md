# Example: Node.js Web Application

This walkthrough demonstrates using UWS for a software development project, cycling through the 6-phase SDLC workflow with agent handoffs and checkpoints.

## Prerequisites

- UWS installed (`./install.sh` from repo root, or use scripts directly)
- Bash 4.0+, Git 2.0+

## Walkthrough

### 1. Initialize the project

```bash
mkdir my-webapp && cd my-webapp
git init

# Initialize UWS with software project type
uws init software
# Or: /path/to/uws/scripts/init_workflow.sh software
```

### 2. SDLC Workflow (6 phases)

```bash
# Start the SDLC workflow
uws sdlc start

# Phase 1: Requirements (owned by the researcher subagent)
uws orchestrate dispatch "Gather requirements and user stories"
uws sdlc status
# Gather requirements, define user stories
uws checkpoint create "Requirements: user auth, dashboard, REST API"

# Phase 2: Design (architect)
uws sdlc next
uws orchestrate dispatch "Design the API, data model and components"
uws checkpoint create "Design: microservice arch, PostgreSQL, JWT auth"

# Phase 3: Implementation (implementer)
uws sdlc next
uws orchestrate dispatch "Implement auth service and dashboard UI"
uws checkpoint create "Implementation: auth service, dashboard UI complete"

# Phase 4: Verification (experimenter)
uws sdlc next
uws orchestrate dispatch "Verify requirements end to end"
uws checkpoint create "Verification: 95% test coverage, all requirements met"

# Phase 5: Deployment (deployer)
uws sdlc next
uws orchestrate dispatch "Deploy to staging, then production"
uws checkpoint create "Deployed to production"

# Phase 6: Maintenance (deployer)
uws sdlc next
uws orchestrate dispatch "Monitor production and triage issues"
uws checkpoint create "Maintenance: first week stable"
```

### 3. Handling failures

```bash
# If verification fails, SDLC regresses to implementation
uws sdlc fail "Integration tests failing on auth module"
uws sdlc status   # Back in implementation phase

# Fix the issue, then advance again
uws sdlc next     # Back to verification
```

### 4. Session continuity

```bash
# End of session
# Edit .workflow/handoff.md with notes

# Next session
uws recover        # Full context recovery
uws status         # See where you left off
```

## Automated Demo

Run `walkthrough.sh` to see a fully automated demo:

```bash
bash walkthrough.sh
```

## Key Concepts Demonstrated

- **SDLC workflow**: 6 phases from requirements to maintenance
- **Agent handoffs**: architect -> implementer -> experimenter -> deployer -> implementer
- **Failure handling**: SDLC regression on test failures
- **Checkpoints**: State preservation at each milestone
