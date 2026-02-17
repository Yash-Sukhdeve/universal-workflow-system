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

# Phase 1: Requirements
uws agent architect
uws sdlc status
# Gather requirements, define user stories
uws checkpoint create "Requirements: user auth, dashboard, REST API"

# Phase 2: Design
uws sdlc next
# Design system architecture, API contracts, DB schema
uws checkpoint create "Design: microservice arch, PostgreSQL, JWT auth"

# Phase 3: Implementation
uws sdlc next
uws agent implementer
# Write code, create tests
uws checkpoint create "Implementation: auth service, dashboard UI complete"

# Phase 4: Verification
uws sdlc next
uws agent experimenter
# Run tests, verify requirements
uws checkpoint create "Verification: 95% test coverage, all requirements met"

# Phase 5: Deployment
uws sdlc next
uws agent deployer
# Deploy to staging, then production
uws checkpoint create "Deployed to production"

# Phase 6: Maintenance
uws sdlc next
uws agent implementer
# Monitor, fix bugs, handle feedback
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
