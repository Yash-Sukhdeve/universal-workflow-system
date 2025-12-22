---
description: Manage Software Development Life Cycle (SDLC) workflow phases
allowed-tools: Bash(./scripts/sdlc.sh:*)
argument-hint: <action> [details]
---

Manage the SDLC workflow for software development projects.

## Actions

- `status` - Show current SDLC phase (default)
- `start` - Begin SDLC at requirements phase
- `next` - Advance to next phase
- `fail` - Report failure (triggers regression to previous phase)
- `reset` - Reset SDLC state

## SDLC Phases

```
requirements → design → implementation → verification → deployment → maintenance
```

## Examples

```bash
./scripts/sdlc.sh status           # Check current phase
./scripts/sdlc.sh start            # Begin SDLC cycle
./scripts/sdlc.sh next             # Move to next phase
./scripts/sdlc.sh fail "Tests failed"  # Report failure
```

## Failure Handling

- `verification` fails → regresses to `implementation`
- `deployment` fails → regresses to `verification`

Execute based on $ARGUMENTS or default to status: `./scripts/sdlc.sh $ARGUMENTS`
