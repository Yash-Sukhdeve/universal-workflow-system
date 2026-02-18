#!/bin/bash
#
# UWS (Universal Workflow System) - Claude Code Integration Installer
#
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash
#
# Or clone and run:
#   ./install.sh
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
UWS_VERSION="1.1.0"
PROJECT_DIR="${PWD}"
UWS_DIR="${PROJECT_DIR}/.uws"
WORKFLOW_DIR="${PROJECT_DIR}/.workflow"
CLAUDE_DIR="${PROJECT_DIR}/.claude"

echo -e "${BOLD}${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     UWS - Universal Workflow System for Claude Code          ║"
echo "║                    Version ${UWS_VERSION}                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if already installed
if [[ -d "${UWS_DIR}" ]] && [[ -f "${UWS_DIR}/version" ]]; then
    EXISTING_VERSION=$(cat "${UWS_DIR}/version" 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}UWS already installed (version: ${EXISTING_VERSION})${NC}"
    read -p "Reinstall/upgrade? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

echo -e "${CYAN}Installing UWS to: ${PROJECT_DIR}${NC}"
echo ""

# ============================================================================
# Step 1: Create directory structure
# ============================================================================
echo -e "${BLUE}[1/7]${NC} Creating directory structure..."

mkdir -p "${UWS_DIR}/hooks"
mkdir -p "${WORKFLOW_DIR}"
mkdir -p "${CLAUDE_DIR}/commands"

echo -e "  ${GREEN}✓${NC} Directories created"

# ============================================================================
# Step 2: Create hook scripts
# ============================================================================
echo -e "${BLUE}[2/7]${NC} Creating Claude Code hooks..."

# SessionStart hook - injects context silently
cat > "${UWS_DIR}/hooks/session_start.sh" << 'HOOK_EOF'
#!/bin/bash
# UWS SessionStart Hook - Silently inject workflow context into Claude

WORKFLOW_DIR="${CLAUDE_PROJECT_DIR:-.}/.workflow"

# Exit silently if no workflow
[[ ! -d "$WORKFLOW_DIR" ]] && exit 0

# Build context from state files
CONTEXT=""

# Read state.yaml
if [[ -f "$WORKFLOW_DIR/state.yaml" ]]; then
    PHASE=$(grep -E "^current_phase:" "$WORKFLOW_DIR/state.yaml" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "unknown")
    CHECKPOINT=$(grep -E "^current_checkpoint:" "$WORKFLOW_DIR/state.yaml" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "none")
    PROJECT_TYPE=$(grep -E "^project_type:" "$WORKFLOW_DIR/state.yaml" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "unknown")

    CONTEXT+="## Workflow State\n"
    CONTEXT+="- Phase: ${PHASE}\n"
    CONTEXT+="- Checkpoint: ${CHECKPOINT}\n"
    CONTEXT+="- Project Type: ${PROJECT_TYPE}\n\n"
fi

# Read recent checkpoints
if [[ -f "$WORKFLOW_DIR/checkpoints.log" ]]; then
    RECENT=$(tail -3 "$WORKFLOW_DIR/checkpoints.log" 2>/dev/null | grep -v "^#" || echo "")
    if [[ -n "$RECENT" ]]; then
        CONTEXT+="## Recent Checkpoints\n\`\`\`\n${RECENT}\n\`\`\`\n\n"
    fi
fi

# Read priority actions from handoff
if [[ -f "$WORKFLOW_DIR/handoff.md" ]]; then
    # Extract Next Actions section
    ACTIONS=$(sed -n '/^## Next Actions/,/^##/p' "$WORKFLOW_DIR/handoff.md" 2>/dev/null | head -10 | grep -E "^-|\[" || echo "")
    if [[ -n "$ACTIONS" ]]; then
        CONTEXT+="## Priority Actions\n${ACTIONS}\n\n"
    fi
fi

# Output as JSON for Claude to consume
if [[ -n "$CONTEXT" ]]; then
    # Escape for JSON
    CONTEXT_ESCAPED=$(echo -e "$CONTEXT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    echo "{\"additionalContext\": \"${CONTEXT_ESCAPED}\"}"
fi

exit 0
HOOK_EOF
chmod +x "${UWS_DIR}/hooks/session_start.sh"

# PreCompact hook - auto-checkpoint before context compaction
cat > "${UWS_DIR}/hooks/pre_compact.sh" << 'HOOK_EOF'
#!/bin/bash
# UWS PreCompact Hook - Auto-checkpoint before context compaction

WORKFLOW_DIR="${CLAUDE_PROJECT_DIR:-.}/.workflow"
CHECKPOINT_LOG="$WORKFLOW_DIR/checkpoints.log"

# Exit silently if no workflow
[[ ! -d "$WORKFLOW_DIR" ]] && exit 0

# Get current checkpoint number
if [[ -f "$CHECKPOINT_LOG" ]]; then
    LAST_CP=$(grep -oE "CP_[0-9]+_[0-9]+" "$CHECKPOINT_LOG" | tail -1 || echo "CP_1_000")
    PHASE=$(echo "$LAST_CP" | cut -d_ -f2)
    SEQ=$(echo "$LAST_CP" | cut -d_ -f3 | sed 's/^0*//')
    NEW_SEQ=$(printf "%03d" $((SEQ + 1)))
    NEW_CP="CP_${PHASE}_${NEW_SEQ}"
else
    NEW_CP="CP_1_001"
fi

# Create auto-checkpoint
TIMESTAMP=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
echo "${TIMESTAMP} | ${NEW_CP} | Auto-checkpoint before context compaction" >> "$CHECKPOINT_LOG"

# Update state.yaml checkpoint
if [[ -f "$WORKFLOW_DIR/state.yaml" ]]; then
    sed -i.bak "s/current_checkpoint:.*/current_checkpoint: \"${NEW_CP}\"/" "$WORKFLOW_DIR/state.yaml" 2>/dev/null || true
    sed -i.bak "s/last_updated:.*/last_updated: \"${TIMESTAMP}\"/" "$WORKFLOW_DIR/state.yaml" 2>/dev/null || true
    rm -f "$WORKFLOW_DIR/state.yaml.bak"
fi

# Output status
echo "{\"status\": \"checkpoint_created\", \"checkpoint\": \"${NEW_CP}\"}"
exit 0
HOOK_EOF
chmod +x "${UWS_DIR}/hooks/pre_compact.sh"

echo -e "  ${GREEN}✓${NC} Hooks created"

# ============================================================================
# Step 3: Create slash commands
# ============================================================================
echo -e "${BLUE}[3/7]${NC} Creating slash commands..."

mkdir -p "${CLAUDE_DIR}/commands"

# /uws-status command
cat > "${CLAUDE_DIR}/commands/uws-status" << 'CMD_EOF'
---
description: "Show UWS workflow status"
allowed-tools:
  - "Bash(cat:*)"
  - "Bash(grep:*)"
  - "Bash(tail:*)"
---

# UWS Workflow Status

Show the current workflow state including phase, checkpoint, and recent activity.

## Current State
! cat .workflow/state.yaml 2>/dev/null || echo "No state.yaml found"

## Recent Checkpoints
! tail -5 .workflow/checkpoints.log 2>/dev/null | grep -v "^#" || echo "No checkpoints"

## Handoff Summary
! head -30 .workflow/handoff.md 2>/dev/null || echo "No handoff.md found"

Summarize the workflow status concisely.
CMD_EOF

# /uws-checkpoint command
cat > "${CLAUDE_DIR}/commands/uws-checkpoint" << 'CMD_EOF'
---
description: "Create a UWS checkpoint with message"
argument-hint: "<message>"
allowed-tools:
  - "Bash(date:*)"
  - "Bash(grep:*)"
  - "Bash(sed:*)"
  - "Bash(echo:*)"
---

# Create UWS Checkpoint

Create a checkpoint with the message: $ARGUMENTS

Execute this to create the checkpoint:

```bash
# Get current checkpoint info
LAST_CP=$(grep -oE "CP_[0-9]+_[0-9]+" .workflow/checkpoints.log 2>/dev/null | tail -1 || echo "CP_1_000")
PHASE=$(echo "$LAST_CP" | cut -d_ -f2)
SEQ=$(echo "$LAST_CP" | cut -d_ -f3 | sed 's/^0*//')
NEW_SEQ=$(printf "%03d" $((SEQ + 1)))
NEW_CP="CP_${PHASE}_${NEW_SEQ}"
TIMESTAMP=$(date -Iseconds)

# Create checkpoint entry
echo "${TIMESTAMP} | ${NEW_CP} | $ARGUMENTS" >> .workflow/checkpoints.log

# Update state.yaml
sed -i "s/current_checkpoint:.*/current_checkpoint: \"${NEW_CP}\"/" .workflow/state.yaml
sed -i "s/last_updated:.*/last_updated: \"${TIMESTAMP}\"/" .workflow/state.yaml

echo "Checkpoint ${NEW_CP} created: $ARGUMENTS"
```

After creating the checkpoint, confirm it was created successfully.
CMD_EOF

# /uws-recover command
cat > "${CLAUDE_DIR}/commands/uws-recover" << 'CMD_EOF'
---
description: "Recover full UWS context after session break"
allowed-tools:
  - "Bash(cat:*)"
  - "Bash(grep:*)"
  - "Bash(tail:*)"
  - "Bash(head:*)"
  - "Bash(ls:*)"
---

# UWS Context Recovery

Recover full workflow context after a session break.

## State File
! cat .workflow/state.yaml 2>/dev/null || echo "ERROR: No state.yaml"

## Full Handoff Document
! cat .workflow/handoff.md 2>/dev/null || echo "ERROR: No handoff.md"

## Checkpoint History
! cat .workflow/checkpoints.log 2>/dev/null | grep -v "^#" || echo "No checkpoints"

## Git Status
! git status --short 2>/dev/null | head -20 || echo "Not a git repo"

Based on this context:
1. Summarize where we left off
2. List the priority next actions
3. Note any blockers or issues
4. Ask if I should continue with the next action
CMD_EOF

# /uws-handoff command
cat > "${CLAUDE_DIR}/commands/uws-handoff" << 'CMD_EOF'
---
description: "Prepare handoff document for session end"
allowed-tools:
  - "Bash(cat:*)"
  - "Bash(date:*)"
  - "Read"
  - "Write"
---

# Prepare UWS Handoff

Update the handoff document (.workflow/handoff.md) with:

1. **Current Status**: What phase/checkpoint we're at
2. **Work Completed This Session**: Summary of what was done
3. **Next Actions**: Prioritized list of what to do next
4. **Blockers**: Any issues preventing progress
5. **Critical Context**: Important decisions or information

Read the current handoff:
! cat .workflow/handoff.md 2>/dev/null || echo "No existing handoff"

Then update it with fresh information from this session. Make sure to:
- Update the timestamp
- Keep it concise but complete
- Focus on actionable next steps
CMD_EOF


# /uws:sdlc command
cat > "${CLAUDE_DIR}/commands/uws-sdlc" << 'CMD_EOF'
---
description: "Manage SDLC status"
allowed-tools:
  - "Bash(./scripts/sdlc.sh:*)"
---

# UWS SDLC Management

Manage the Software Development Life Cycle.

Usage:
- Status: \`./scripts/sdlc.sh status\`
- Start: \`./scripts/sdlc.sh start\`
- Next Phase: \`./scripts/sdlc.sh next\`
- Report Failure: \`./scripts/sdlc.sh fail "details"\`

Execute the appropriate command based on user request.
CMD_EOF

# /uws:research command
cat > "${CLAUDE_DIR}/commands/uws-research" << 'CMD_EOF'
---
description: "Manage Research workflow"
allowed-tools:
  - "Bash(./scripts/research.sh:*)"
---

# UWS Research Management

Manage the Research Methodology lifecycle.

Usage:
- Status: \`./scripts/research.sh status\`
- Start: \`./scripts/research.sh start\`
- Next Phase: \`./scripts/research.sh next\`
- Reject Hypothesis: \`./scripts/research.sh reject\`

Execute the appropriate command based on user request.
CMD_EOF


# /uws:spiral command
cat > "${CLAUDE_DIR}/commands/uws-spiral" << 'CMD_EOF'
---
description: "Manage Spiral SDLC"
allowed-tools:
  - "Bash(./scripts/spiral.sh:*)"
---

# UWS Spiral SDLC

Manage the Risk-Driven Spiral Lifecycle.

Usage:
- Status: \`./scripts/spiral.sh status\`
- Start Cycle: \`./scripts/spiral.sh start-cycle\`
- Next Quadrant: \`./scripts/spiral.sh next\`

CMD_EOF

# /uws:pm command
cat > "${CLAUDE_DIR}/commands/uws-pm" << 'CMD_EOF'
---
description: "Project Management (Issues/board)"
allowed-tools:
  - "Bash(./scripts/pm.sh:*)"
---

# UWS Project Management

Manage tickets and boards.

Usage:
- List: \`./scripts/pm.sh list\`
- Create: \`./scripts/pm.sh create "Title" "Type" "Priority"\`
- Move: \`./scripts/pm.sh move TASK-XXX "Status"\`
- Generate Board: \`./scripts/pm.sh board\`

CMD_EOF

# /uws:submit command
cat > "${CLAUDE_DIR}/commands/uws-submit" << 'CMD_EOF'
---
description: "Submit Code (Generate CL)"
allowed-tools:
  - "Bash(./scripts/submit.sh:*)"
---

# UWS Code Submission

Submit work for review.

Usage: \`./scripts/submit.sh "Message" "TASK-ID"\`
CMD_EOF

# /uws:review command
cat > "${CLAUDE_DIR}/commands/uws-review" << 'CMD_EOF'
---
description: "Review/Approve CLs"
allowed-tools:
  - "Bash(./scripts/review.sh:*)"
---

# UWS Code Review

Review and Approve/Reject changes.

Usage:
- List: \`./scripts/review.sh list\`
- Approve: \`./scripts/review.sh approve CR-XXX\`
- Reject: \`./scripts/review.sh reject CR-XXX\`
CMD_EOF

echo -e "  ${GREEN}✓${NC} Slash commands created"




# ============================================================================
# Step 4: Initialize workflow state
# ============================================================================
echo -e "${BLUE}[4/7]${NC} Initializing workflow state..."

# Detect project type
PROJECT_TYPE="software"
if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then
    if grep -qE "torch|tensorflow|transformers|sklearn" requirements.txt pyproject.toml 2>/dev/null; then
        PROJECT_TYPE="ml"
    else
        PROJECT_TYPE="python"
    fi
elif [[ -f "package.json" ]]; then
    PROJECT_TYPE="nodejs"
elif [[ -d "paper" ]] || [[ -d "experiments" ]]; then
    PROJECT_TYPE="research"
fi

# Get project name from directory
PROJECT_NAME=$(basename "${PROJECT_DIR}")
TIMESTAMP=$(date -Iseconds)

# Create state.yaml if not exists (Full v2.0 Schema)
if [[ ! -f "${WORKFLOW_DIR}/state.yaml" ]]; then
    cat > "${WORKFLOW_DIR}/state.yaml" << EOF
# UWS Workflow State (Schema v2.0)
# Auto-generated on ${TIMESTAMP}

# Current workflow position
current_phase: "phase_1_planning"
current_checkpoint: "CP_INIT"

# Project metadata
project:
  name: "${PROJECT_NAME}"
  type: "${PROJECT_TYPE}"
  initialized: true
  init_date: "${TIMESTAMP}"

# Active agent tracking
active_agent:
  name: null
  activated_at: null
  status: "inactive"

# Enabled skills
enabled_skills: []

# Phase progress tracking
phases:
  phase_1_planning:
    status: "active"
    progress: 0
    started_at: "${TIMESTAMP}"
  phase_2_implementation:
    status: "pending"
    progress: 0
  phase_3_validation:
    status: "pending"
    progress: 0
  phase_4_delivery:
    status: "pending"
    progress: 0
  phase_5_maintenance:
    status: "pending"
    progress: 0

# System health
health:
  status: "healthy"
  last_check: "${TIMESTAMP}"

# Schema metadata
metadata:
  schema_version: "2.0"
  last_updated: "${TIMESTAMP}"
  created_by: "claude-code-integration"
EOF
    echo -e "  ${GREEN}✓${NC} Created state.yaml (${PROJECT_TYPE} project, schema v2.0)"
else
    echo -e "  ${YELLOW}→${NC} state.yaml already exists, keeping"
fi

# Create checkpoints.log if not exists
if [[ ! -f "${WORKFLOW_DIR}/checkpoints.log" ]]; then
    cat > "${WORKFLOW_DIR}/checkpoints.log" << EOF
# UWS Checkpoint Log
# Format: TIMESTAMP | CHECKPOINT_ID | DESCRIPTION
$(date -Iseconds) | CP_1_001 | UWS initialized with Claude Code integration
EOF
    echo -e "  ${GREEN}✓${NC} Created checkpoints.log"
else
    echo -e "  ${YELLOW}→${NC} checkpoints.log already exists, keeping"
fi

# Create handoff.md if not exists
if [[ ! -f "${WORKFLOW_DIR}/handoff.md" ]]; then
    cat > "${WORKFLOW_DIR}/handoff.md" << EOF
# Workflow Handoff

**Last Updated**: $(date -Iseconds)
**Phase**: phase_1_planning
**Checkpoint**: CP_1_001

---

## Current Status

Project initialized with UWS (Universal Workflow System) for Claude Code.

## Next Actions

- [ ] Define project goals and scope
- [ ] Review existing codebase (if any)
- [ ] Set up development environment

## Blockers

None currently.

## Context

This project uses UWS for maintaining context across Claude Code sessions.

### Quick Commands
- \`/uws-status\` - Check current workflow state
- \`/uws-checkpoint "message"\` - Create a checkpoint
- \`/uws-recover\` - Full context recovery
- \`/uws-handoff\` - Prepare for session end
EOF
    echo -e "  ${GREEN}✓${NC} Created handoff.md"
else
    echo -e "  ${YELLOW}→${NC} handoff.md already exists, keeping"
fi

# ============================================================================
# Step 5: Configure Claude Code settings
# ============================================================================
echo -e "${BLUE}[5/7]${NC} Configuring Claude Code hooks..."

# Create or merge settings.json
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    # Backup existing
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup"
    echo -e "  ${YELLOW}→${NC} Backed up existing settings.json"
fi

# Create settings with hooks
cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "permissions": {
    "allow": [
      "Bash(./.uws/hooks/*:*)",
      "Bash(./scripts/sdlc.sh:*)",
      "Bash(./scripts/research.sh:*)",
      "Bash(./scripts/spiral.sh:*)",
      "Bash(./scripts/pm.sh:*)",
      "Bash(./scripts/submit.sh:*)",
      "Bash(./scripts/review.sh:*)",
      "Bash(cat .workflow/*:*)",
      "Bash(grep:*)",
      "Bash(tail:*)",
      "Bash(head:*)",
      "Bash(date:*)",
      "Bash(sed:*)"
    ]
  },
  "hooks": [
    {
      "event": "SessionStart",
      "type": "command",
      "command": "./.uws/hooks/session_start.sh"
    },
    {
      "event": "PreCompact",
      "type": "command",
      "command": "./.uws/hooks/pre_compact.sh"
    }
  ]
}
SETTINGS_EOF

echo -e "  ${GREEN}✓${NC} Configured hooks in settings.json"

# ============================================================================
# Step 6: Update CLAUDE.md
# ============================================================================
echo -e "${BLUE}[6/7]${NC} Updating CLAUDE.md..."

UWS_SECTION='
<!-- UWS-BEGIN -->
## UWS Workflow System

This project uses UWS (Universal Workflow System) for context persistence across sessions.

### Quick Commands
- `/uws-status` - Show current workflow state
- `/uws-checkpoint "msg"` - Create checkpoint
- `/uws-recover` - Full context recovery after break
- `/uws-handoff` - Prepare handoff before ending session

### Workflow Files
- `.workflow/state.yaml` - Current phase and checkpoint
- `.workflow/handoff.md` - Human-readable context (READ THIS ON SESSION START)
- `.workflow/checkpoints.log` - Checkpoint history

### Session Workflow
1. **Start**: Context is automatically loaded via SessionStart hook
2. **During**: Create checkpoints at milestones with `/uws-checkpoint`
3. **End**: Run `/uws-handoff` to update context for next session

### Auto-Checkpoint
UWS automatically creates checkpoints before context compaction to prevent state loss.
<!-- UWS-END -->
'

if [[ -f "CLAUDE.md" ]]; then
    # Check if UWS section already exists
    if grep -q "<!-- UWS-BEGIN -->" "CLAUDE.md"; then
        # Replace existing section
        sed -i '/<!-- UWS-BEGIN -->/,/<!-- UWS-END -->/d' "CLAUDE.md"
    fi
    # Append UWS section
    echo "$UWS_SECTION" >> "CLAUDE.md"
    echo -e "  ${GREEN}✓${NC} Updated existing CLAUDE.md"
else
    # Create new CLAUDE.md
    cat > "CLAUDE.md" << EOF
# CLAUDE.md

Project-specific instructions for Claude Code.
${UWS_SECTION}
EOF
    echo -e "  ${GREEN}✓${NC} Created CLAUDE.md with UWS section"
fi

# Save version
echo "$UWS_VERSION" > "${UWS_DIR}/version"

# ============================================================================
# Step 7: Setup vector memory (requires UWS source tree)
# ============================================================================
echo -e "${BLUE}[7/7]${NC} Setting up vector memory..."

VECTOR_SETUP_LIB=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${_INSTALLER_DIR}/../scripts/lib/vector_memory_setup.sh" ]]; then
        VECTOR_SETUP_LIB="${_INSTALLER_DIR}/../scripts/lib/vector_memory_setup.sh"
    fi
fi

if [[ -n "${VECTOR_SETUP_LIB}" ]]; then
    source "${VECTOR_SETUP_LIB}"
    if ! setup_vector_memory "${PROJECT_DIR}"; then
        echo -e "  ${YELLOW}Vector memory setup skipped (optional)${NC}"
    fi
else
    echo -e "  ${YELLOW}Skipped (run ./scripts/lib/vector_memory_setup.sh from UWS repo)${NC}"
fi

# ============================================================================
# Done!
# ============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              UWS Installation Complete!                       ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Files created:${NC}"
echo "  .uws/hooks/session_start.sh   - Context injection hook"
echo "  .uws/hooks/pre_compact.sh     - Auto-checkpoint hook"
echo "  .claude/commands/uws-*        - Slash commands"
echo "  .claude/settings.json         - Hook configuration"
echo "  .workflow/state.yaml          - Workflow state"
echo "  .workflow/handoff.md          - Context handoff"
echo "  .workflow/checkpoints.log     - Checkpoint history"
echo ""
echo -e "${CYAN}Quick start:${NC}"
echo "  1. Open project in Claude Code: ${BOLD}claude${NC}"
echo "  2. Context loads automatically on session start"
echo "  3. Use ${BOLD}/uws-status${NC} to see current state"
echo "  4. Use ${BOLD}/uws-checkpoint \"message\"${NC} to save progress"
echo ""
echo -e "${YELLOW}Tip:${NC} Add .uws/ to .gitignore if you don't want to share hooks"
echo -e "${YELLOW}Tip:${NC} Commit .workflow/ to preserve state across clones"
echo ""
