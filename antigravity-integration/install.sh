#!/bin/bash
#
# UWS (Universal Workflow System) - Gemini Antigravity Integration Installer
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
UWS_VERSION="1.0.0"
PROJECT_DIR="${PWD}"
UWS_DIR="${PROJECT_DIR}/.uws"
WORKFLOW_DIR="${PROJECT_DIR}/.workflow"
AGENT_DIR="${PROJECT_DIR}/.agent"
WORKFLOWS_DIR="${AGENT_DIR}/workflows"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BOLD}${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     UWS - Universal Workflow System for Gemini Antigravity   ║"
echo "║                    Version ${UWS_VERSION}                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if already installed
if [[ -d "${UWS_DIR}" ]] && [[ -f "${UWS_DIR}/version" ]]; then
    EXISTING_VERSION=$(cat "${UWS_DIR}/version" 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}UWS already installed (version: ${EXISTING_VERSION})${NC}"
    # We continue to update workflows even if installed
fi

echo -e "${CYAN}Installing UWS Antigravity Integration to: ${PROJECT_DIR}${NC}"
echo ""

# ============================================================================
# Step 1: Create directory structure
# ============================================================================
echo -e "${BLUE}[1/4]${NC} Creating directory structure..."

mkdir -p "${UWS_DIR}"
mkdir -p "${WORKFLOW_DIR}"
mkdir -p "${WORKFLOWS_DIR}"

echo -e "  ${GREEN}✓${NC} Directories created"

# ============================================================================
# Step 2: Install Workflows
# ============================================================================
echo -e "${BLUE}[2/4]${NC} Installing Antigravity workflows..."

if [[ -d "${SCRIPT_DIR}/workflows" ]]; then
    cp "${SCRIPT_DIR}/workflows"/*.md "${WORKFLOWS_DIR}/"
    echo -e "  ${GREEN}✓${NC} Workflows copied to .agent/workflows/"
else
    echo -e "  ${RED}✗${NC} Source workflows not found in ${SCRIPT_DIR}/workflows"
    exit 1
fi

# ============================================================================
# Step 3: Initialize workflow state
# ============================================================================
echo -e "${BLUE}[3/4]${NC} Initializing workflow state..."

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

# Create state.yaml if not exists
if [[ ! -f "${WORKFLOW_DIR}/state.yaml" ]]; then
    cat > "${WORKFLOW_DIR}/state.yaml" << EOF
# UWS Workflow State
# Auto-generated on $(date -Iseconds)

project_type: "${PROJECT_TYPE}"
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
last_updated: "$(date -Iseconds)"

health:
  status: "healthy"
  last_check: "$(date -Iseconds)"
EOF
    echo -e "  ${GREEN}✓${NC} Created state.yaml (${PROJECT_TYPE} project)"
else
    echo -e "  ${YELLOW}→${NC} state.yaml already exists, keeping"
fi

# Create checkpoints.log if not exists
if [[ ! -f "${WORKFLOW_DIR}/checkpoints.log" ]]; then
    cat > "${WORKFLOW_DIR}/checkpoints.log" << EOF
# UWS Checkpoint Log
# Format: TIMESTAMP | CHECKPOINT_ID | DESCRIPTION
$(date -Iseconds) | CP_1_001 | UWS initialized with Gemini Antigravity integration
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

Project initialized with UWS (Universal Workflow System) for Gemini Antigravity.

## Next Actions

- [ ] Define project goals and scope
- [ ] Review existing codebase (if any)
- [ ] Set up development environment

## Blockers

None currently.

## Context

This project uses UWS for maintaining context across sessions.

### Quick Workflows
- \`uws-status.md\` - Check current workflow state
- \`uws-checkpoint.md\` - Create a checkpoint
- \`uws-recover.md\` - Full context recovery
- \`uws-handoff.md\` - Prepare for session end
EOF
    echo -e "  ${GREEN}✓${NC} Created handoff.md"
else
    echo -e "  ${YELLOW}→${NC} handoff.md already exists, keeping"
fi

# ============================================================================
# Done!
# ============================================================================

# Save version
echo "$UWS_VERSION" > "${UWS_DIR}/version"

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              UWS Installation Complete!                       ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Files created:${NC}"
echo "  .agent/workflows/uws-*.md     - Antigravity workflows"
echo "  .workflow/state.yaml          - Workflow state"
echo "  .workflow/handoff.md          - Context handoff"
echo "  .workflow/checkpoints.log     - Checkpoint history"
echo ""
echo -e "${CYAN}Usage:${NC}"
echo "  The workflows are now available in your .agent/workflows directory."
echo "  You can ask the agent to 'check status' or 'create checkpoint' and it should"
echo "  pick up the relevant workflow."
