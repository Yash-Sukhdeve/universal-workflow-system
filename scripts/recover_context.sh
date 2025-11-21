#!/bin/bash

# Context Recovery Script
# Quickly restore context after a session break or context loss

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility libraries
if [[ -f "${SCRIPT_DIR}/lib/validation_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/validation_utils.sh"
fi

if [[ -f "${SCRIPT_DIR}/lib/yaml_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/yaml_utils.sh"
fi

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}           📡 CONTEXT RECOVERY SYSTEM${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if workflow is initialized
if ! validate_workflow_initialized 2>/dev/null; then
    if [[ ! -f .workflow/state.yaml ]]; then
        echo -e "${RED}❌ Error: Workflow not initialized${NC}"
        echo -e "   Run: ${CYAN}./scripts/init_workflow.sh${NC} first"
        exit 1
    fi
fi

# Function to extract YAML values using utilities
get_yaml_value() {
    local key="$1"
    local file="$2"

    if declare -f yaml_get > /dev/null 2>&1; then
        yaml_get "$file" "$key"
    else
        # Fallback
        grep "^$key:" "$file" | cut -d':' -f2- | sed 's/^ *//;s/"//g' | xargs
    fi
}

# Load current state
echo -e "${BLUE}📊 Current State:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PROJECT_TYPE=$(get_yaml_value "project.type" ".workflow/state.yaml")
CURRENT_PHASE=$(get_yaml_value "current_phase" ".workflow/state.yaml")
CURRENT_CHECKPOINT=$(get_yaml_value "current_checkpoint" ".workflow/state.yaml")
LAST_UPDATED=$(get_yaml_value "metadata.last_updated" ".workflow/state.yaml")

echo -e "  📁 Project Type:     ${GREEN}${PROJECT_TYPE}${NC}"
echo -e "  📍 Current Phase:    ${GREEN}${CURRENT_PHASE}${NC}"
echo -e "  ✓  Checkpoint:       ${GREEN}${CURRENT_CHECKPOINT}${NC}"
echo -e "  🕐 Last Updated:     ${YELLOW}${LAST_UPDATED}${NC}"
echo ""

# Show recent checkpoints
echo -e "${BLUE}📍 Recent Checkpoints:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f .workflow/checkpoints.log ]; then
    tail -5 .workflow/checkpoints.log | while IFS='|' read -r timestamp checkpoint description; do
        echo -e "  ${YELLOW}$checkpoint${NC} - $description"
        echo -e "    ${MAGENTA}$(echo $timestamp | xargs)${NC}"
    done
else
    echo -e "  ${YELLOW}No checkpoints found${NC}"
fi
echo ""

# Show active agents
echo -e "${BLUE}🤖 Active Agents:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f .workflow/agents/active.yaml ]; then
    ACTIVE_AGENT=$(get_yaml_value "current_agent" ".workflow/agents/active.yaml")
    AGENT_TASK=$(get_yaml_value "task" ".workflow/agents/active.yaml")
    echo -e "  👤 Agent:   ${GREEN}${ACTIVE_AGENT:-none}${NC}"
    echo -e "  📋 Task:    ${YELLOW}${AGENT_TASK:-none}${NC}"
else
    echo -e "  ${YELLOW}No active agents${NC}"
fi
echo ""

# Show enabled skills
echo -e "${BLUE}🛠️  Enabled Skills:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f .workflow/skills/enabled.yaml ]; then
    grep "^  - " .workflow/skills/enabled.yaml 2>/dev/null | while read -r line; do
        skill=$(echo $line | sed 's/^  - //')
        echo -e "  ✓ ${GREEN}$skill${NC}"
    done || echo -e "  ${YELLOW}No skills enabled${NC}"
else
    echo -e "  ${YELLOW}No skills configured${NC}"
fi
echo ""

# Show handoff notes
echo -e "${BLUE}📝 Handoff Notes:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f .workflow/handoff.md ]; then
    # Extract Next Actions section
    sed -n '/## Next Actions/,/## Commands/p' .workflow/handoff.md | grep "^- \[" | while read -r line; do
        if [[ $line == *"[x]"* ]]; then
            echo -e "  ✅ ${line#*] }"
        else
            echo -e "  ⬜ ${line#*] }"
        fi
    done
else
    echo -e "  ${YELLOW}No handoff notes found${NC}"
fi
echo ""

# Show critical context
echo -e "${BLUE}⚠️  Critical Context:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f .workflow/handoff.md ]; then
    sed -n '/## Critical Context/,/## Next Actions/p' .workflow/handoff.md | grep "^[0-9]" | while read -r line; do
        echo -e "  ${YELLOW}$line${NC}"
    done
fi
echo ""

# Git status summary
echo -e "${BLUE}📦 Git Status:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo -e "  🌿 Branch:     ${GREEN}${CURRENT_BRANCH}${NC}"

# Count uncommitted changes
MODIFIED=$(git status --porcelain 2>/dev/null | grep -c "^ M" || echo 0)
UNTRACKED=$(git status --porcelain 2>/dev/null | grep -c "^??" || echo 0)
STAGED=$(git status --porcelain 2>/dev/null | grep -c "^[AM]" || echo 0)

echo -e "  📝 Modified:   ${YELLOW}${MODIFIED} files${NC}"
echo -e "  ➕ Staged:     ${GREEN}${STAGED} files${NC}"
echo -e "  ❓ Untracked:  ${MAGENTA}${UNTRACKED} files${NC}"
echo ""

# Show recent commits
echo -e "${BLUE}📜 Recent Activity:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
git log --oneline -5 --format="  %C(yellow)%h%C(reset) %s %C(dim)(%cr)%C(reset)" 2>/dev/null || echo -e "  ${YELLOW}No commits yet${NC}"
echo ""

# Suggest next actions
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}💡 Suggested Actions:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Phase-specific suggestions
case $CURRENT_PHASE in
    "phase_1_planning")
        echo -e "  1. Review requirements:    ${CYAN}cat phases/phase_1_planning/requirements.md${NC}"
        echo -e "  2. Check scope:            ${CYAN}cat phases/phase_1_planning/scope.md${NC}"
        echo -e "  3. Continue planning:      ${CYAN}./scripts/activate_agent.sh researcher${NC}"
        ;;
    "phase_2_implementation")
        echo -e "  1. Check code status:      ${CYAN}ls -la workspace/${NC}"
        echo -e "  2. Run tests:              ${CYAN}./scripts/run_tests.sh${NC}"
        echo -e "  3. Continue coding:        ${CYAN}./scripts/activate_agent.sh implementer${NC}"
        ;;
    "phase_3_validation")
        echo -e "  1. View test results:      ${CYAN}cat artifacts/test_results.log${NC}"
        echo -e "  2. Check metrics:          ${CYAN}cat artifacts/metrics.yaml${NC}"
        echo -e "  3. Run validation:         ${CYAN}./scripts/activate_agent.sh experimenter${NC}"
        ;;
    *)
        echo -e "  1. View detailed state:    ${CYAN}cat .workflow/state.yaml${NC}"
        echo -e "  2. Check handoff notes:    ${CYAN}cat .workflow/handoff.md${NC}"
        echo -e "  3. View available agents:  ${CYAN}./scripts/list_agents.sh${NC}"
        ;;
esac

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Quick status check
READY=true
WARNINGS=""

if [ $MODIFIED -gt 5 ]; then
    WARNINGS="${WARNINGS}\n  ⚠️  Many uncommitted changes - consider committing"
    READY=false
fi

if [ ! -f .workflow/handoff.md ]; then
    WARNINGS="${WARNINGS}\n  ⚠️  No handoff notes - context might be incomplete"
fi

# Show final status
echo ""
if [ "$READY" = true ]; then
    echo -e "${GREEN}✅ Ready to continue!${NC}"
else
    echo -e "${YELLOW}⚠️  Warnings:${NC}"
    echo -e "$WARNINGS"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  Run ${CYAN}./scripts/status.sh --verbose${NC} for detailed information"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
