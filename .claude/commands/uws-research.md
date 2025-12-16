---
description: Manage Research Methodology workflow (Scientific Method)
allowed-tools: Bash(./scripts/research.sh:*)
argument-hint: <action> [details]
---

Manage the research workflow following the Scientific Method.

## Actions

- `status` - Show current research phase (default)
- `start` - Begin research at hypothesis phase
- `next` - Advance to next phase
- `reject` - Report rejected hypothesis or failed analysis
- `reset` - Reset research state

## Research Phases (Scientific Method)

```
hypothesis → experiment_design → data_collection → analysis → publication
```

## Examples

```bash
./scripts/research.sh status                    # Check current phase
./scripts/research.sh start                     # Begin research cycle
./scripts/research.sh next                      # Move to next phase
./scripts/research.sh reject "Results inconclusive"  # Hypothesis rejected
```

## Rejection Handling

- `analysis` rejected → returns to `experiment_design`
- `publication` rejected → returns to `analysis`

Note: Negative results are valuable in research!

Execute based on $ARGUMENTS or default to status: `./scripts/research.sh $ARGUMENTS`
