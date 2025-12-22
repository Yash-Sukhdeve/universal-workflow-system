# Getting Started with Gemini Antigravity & UWS

This guide will help you get the most out of the Universal Workflow System when using Gemini Antigravity.

## Installation

Run the installer from your project root:
```bash
./antigravity-integration/install.sh
```
This installs the workflow definitions into `.agent/workflows/`.

## Core Workflows

### 1. Status Checks
Always start your session by checking where you left off.
> "Check the workflow status"

This runs `uws-status`, showing the current phase, last checkpoint, and handoff notes.

### 2. SDLC Management
For software projects, use the SDLC workflow to ensure quality.

**Start a new feature:**
> "Start the SDLC for the new login feature"

**Advance through phases:**
> "Move to design phase"
> "Move to implementation"

**Handle Failures:**
If testing fails, the workflow supports error states:
> "Report a validation failure: Unit tests failed"
*The system will guide you back to the Implementation phase.*

### 3. Research Projects
For academic or experimental work, use the Research workflow.

**Start research:**
> "Start a new research cycle"

**Validate Hypothesis:**
> "Analyze the results"
*If results are negative, you can choose to refine the hypothesis or publish negative results.*

## Best Practices

*   **Checkpoint Often**: "Create a checkpoint: Finished basic auth."
*   **Use Handoffs**: Before you leave, say "Prepare handoff." The agent will summarize your session for the next time.
*   **Stay in Mode**: If you are in `Implementation`, try to finish it before moving to `Verification`.
