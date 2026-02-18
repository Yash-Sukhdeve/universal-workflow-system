#!/bin/bash

# Status Display Script
# Show comprehensive workflow status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve WORKFLOW_DIR: CWD first, then git root, then UWS fallback
source "${SCRIPT_DIR}/lib/resolve_project.sh"

# Source utility libraries (suppress yq warning)
YAML_UTILS_QUIET=true
if [[ -f "${SCRIPT_DIR}/lib/validation_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/validation_utils.sh"
fi

if [[ -f "${SCRIPT_DIR}/lib/yaml_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/yaml_utils.sh"
fi

if [[ -f "${SCRIPT_DIR}/lib/workflow_routing.sh" ]]; then
    source "${SCRIPT_DIR}/lib/workflow_routing.sh"
fi

# Color codes (no readonly — safe to reassign if sourced libraries set them)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Parse arguments
VERBOSE=false
COMPACT=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -c|--compact)
            COMPACT=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -v, --verbose    Show detailed information"
            echo "  -c, --compact    Show compact view"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Check if workflow is initialized
if ! validate_workflow_initialized 2>/dev/null; then
    if [[ ! -d "${WORKFLOW_DIR}" ]]; then
        echo -e "${RED}Error: Workflow not initialized in $(pwd)${NC}"
        echo -e "   Run: ${CYAN}~/Documents/universal-workflow-system/scripts/init_workflow.sh${NC} first"
        exit 1
    fi
fi

# Helper function to extract YAML values
get_yaml_value() {
    local key="$1"
    local file="$2"

    if declare -f yaml_get > /dev/null 2>&1; then
        local value
        value=$(yaml_get "$file" "$key" 2>/dev/null || echo "N/A")
        [[ "$value" == "null" ]] && echo "N/A" || echo "$value"
    else
        # Fallback
        grep "^$key:" "$file" 2>/dev/null | cut -d':' -f2- | sed 's/^ *//;s/"//g' | xargs || echo "N/A"
    fi
}

# Helper function to get nested phase status from state.yaml
# Extracts phases.<phase_name>.status using sed (yaml_get only supports top-level)
get_phase_status() {
    local phase_name="$1"
    local file="${2:-.workflow/state.yaml}"
    sed -n "/^  ${phase_name}:/,/^  [^ ]/{ s/^    status: *\"\{0,1\}\([^\"]*\)\"\{0,1\}/\1/p; }" "$file" 2>/dev/null | head -1
}

# Helper function to create progress bar
create_progress_bar() {
    local current=$1
    local total=$2
    local width=20
    
    if [ $total -eq 0 ]; then
        echo "[--------------------]"
        return
    fi
    
    local progress=$((current * width / total))
    local bar="["
    
    for ((i=0; i<width; i++)); do
        if [ $i -lt $progress ]; then
            bar="${bar}█"
        else
            bar="${bar}░"
        fi
    done
    bar="${bar}]"
    
    echo "$bar"
}

# Compact view
if [ "$COMPACT" = true ]; then
    PROJECT_TYPE=$(get_yaml_value "project_type" "${STATE_FILE}")
    CURRENT_PHASE=$(get_yaml_value "current_phase" "${STATE_FILE}")
    CURRENT_CHECKPOINT=$(get_yaml_value "current_checkpoint" "${STATE_FILE}")
    
    echo -e "${BOLD}Workflow:${NC} ${GREEN}${PROJECT_TYPE}${NC} | ${BOLD}Phase:${NC} ${YELLOW}${CURRENT_PHASE}${NC} | ${BOLD}CP:${NC} ${CYAN}${CURRENT_CHECKPOINT}${NC}"
    
    if [ -f ${WORKFLOW_DIR}/agents/active.yaml ]; then
        ACTIVE_AGENT=$(get_yaml_value "current_agent" "${WORKFLOW_DIR}/agents/active.yaml")
        echo -e "${BOLD}Agent:${NC} ${GREEN}${ACTIVE_AGENT}${NC}"
    fi
    
    exit 0
fi

# Full status display
clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                       UNIVERSAL WORKFLOW SYSTEM STATUS                        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Project Information
echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ${BOLD}PROJECT INFORMATION${NC}                                                        ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

PROJECT_NAME=$(basename "$(pwd)")
PROJECT_TYPE=$(get_yaml_value "project_type" "${STATE_FILE}")
CREATED=$(get_yaml_value "created" "${STATE_FILE}")

echo -e "  ${CYAN}Name:${NC}         ${BOLD}${PROJECT_NAME}${NC}"
echo -e "  ${CYAN}Type:${NC}         ${GREEN}${PROJECT_TYPE}${NC}"
echo -e "  ${CYAN}Location:${NC}     $(pwd)"
echo -e "  ${CYAN}Initialized:${NC}  ${DIM}${CREATED}${NC}"
echo ""

# Workflow State
echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ${BOLD}WORKFLOW STATE${NC}                                                             ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

CURRENT_PHASE=$(get_yaml_value "current_phase" "${STATE_FILE}")
CURRENT_CHECKPOINT=$(get_yaml_value "current_checkpoint" "${STATE_FILE}")
LAST_UPDATED=$(get_yaml_value "last_updated" "${STATE_FILE}")

echo -e "  ${CYAN}Current Phase:${NC}     ${YELLOW}${CURRENT_PHASE}${NC}"
echo -e "  ${CYAN}Checkpoint:${NC}        ${GREEN}${CURRENT_CHECKPOINT}${NC}"
echo -e "  ${CYAN}Last Updated:${NC}      ${DIM}${LAST_UPDATED}${NC}"
echo ""

# Per-phase progress display
echo -e "  ${CYAN}Phase Progress:${NC}"
for _phase_name in phase_1_planning phase_2_implementation phase_3_validation phase_4_delivery phase_5_maintenance; do
    _phase_stat=$(get_phase_status "$_phase_name" "${STATE_FILE}")
    _phase_stat="${_phase_stat:-pending}"
    _phase_num=$(echo "$_phase_name" | cut -d'_' -f2)
    _cp_count=$(grep -c "CP_${_phase_num}_" ${WORKFLOW_DIR}/checkpoints.log 2>/dev/null) || _cp_count=0

    case "$_phase_stat" in
        completed)
            _icon="${GREEN}✓${NC}"
            _status_label="${GREEN}completed${NC}"
            _cp_info="  (${_cp_count} checkpoints)"
            ;;
        active)
            _icon="${YELLOW}►${NC}"
            _status_label="${YELLOW}active${NC}"
            _cp_info="  (${_cp_count} checkpoints)"
            ;;
        *)
            _icon="${DIM}○${NC}"
            _status_label="${DIM}pending${NC}"
            _cp_info=""
            ;;
    esac

    printf "    %b %-25s %b%b\n" "$_icon" "$_phase_name" "$_status_label" "$_cp_info"
done
echo ""

# Active Methodology
echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ${BOLD}ACTIVE METHODOLOGY${NC}                                                         ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

if declare -f get_active_methodology > /dev/null 2>&1; then
    ACTIVE_METHODOLOGY=$(get_active_methodology "$PROJECT_TYPE")
    echo -e "  ${CYAN}Project Type:${NC}   ${GREEN}${PROJECT_TYPE}${NC}"
    echo -e "  ${CYAN}Methodology:${NC}    ${GREEN}${ACTIVE_METHODOLOGY}${NC}"

    # Show relevant phase(s)
    RESEARCH_PHASE=$(get_yaml_value "research_phase" "${STATE_FILE}")
    SDLC_PHASE=$(get_yaml_value "sdlc_phase" "${STATE_FILE}")

    if [[ "$ACTIVE_METHODOLOGY" == "research" || "$ACTIVE_METHODOLOGY" == "both" ]]; then
        echo -e "  ${CYAN}Research Phase:${NC} ${YELLOW}${RESEARCH_PHASE:-none}${NC}"
    fi
    if [[ "$ACTIVE_METHODOLOGY" == "sdlc" || "$ACTIVE_METHODOLOGY" == "both" ]]; then
        echo -e "  ${CYAN}SDLC Phase:${NC}    ${YELLOW}${SDLC_PHASE:-none}${NC}"
    fi
else
    echo -e "  ${DIM}Routing library not available${NC}"
fi
echo ""

# Active Agents
echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ${BOLD}ACTIVE AGENTS${NC}                                                              ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

if [ -f ${WORKFLOW_DIR}/agents/active.yaml ]; then
    ACTIVE_AGENT=$(get_yaml_value "current_agent" "${WORKFLOW_DIR}/agents/active.yaml")
    AGENT_TASK=$(get_yaml_value "task" "${WORKFLOW_DIR}/agents/active.yaml")
    AGENT_PROGRESS=$(get_yaml_value "progress" "${WORKFLOW_DIR}/agents/active.yaml")
    
    # Get agent icon from registry
    if [ -f ${WORKFLOW_DIR}/agents/registry.yaml ]; then
        AGENT_ICON=$(grep -A2 "^  ${ACTIVE_AGENT}:" ${WORKFLOW_DIR}/agents/registry.yaml | grep "icon:" | cut -d'"' -f2 || echo "👤")
    else
        AGENT_ICON="👤"
    fi
    
    echo -e "  ${AGENT_ICON} ${BOLD}${ACTIVE_AGENT}${NC}"
    echo -e "     ${CYAN}Task:${NC}     ${YELLOW}${AGENT_TASK}${NC}"
    agent_pct="${AGENT_PROGRESS:-0}"
    [[ "$agent_pct" == "N/A" ]] && agent_pct=0
    echo -e "     ${CYAN}Progress:${NC} $(create_progress_bar "${agent_pct}" 100) ${agent_pct}%"
else
    echo -e "  ${DIM}No active agents${NC}"
fi
echo ""

# Enabled Skills
echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ${BOLD}ENABLED SKILLS${NC}                                                             ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

if [ -f ${WORKFLOW_DIR}/skills/enabled.yaml ]; then
    SKILL_COUNT=$(grep -c "^  - " ${WORKFLOW_DIR}/skills/enabled.yaml 2>/dev/null || echo 0)
    SKILL_COUNT=$(echo "$SKILL_COUNT" | tr -d '[:space:]')

    if [ "$SKILL_COUNT" -gt 0 ] 2>/dev/null; then
        echo -e "  ${CYAN}Active Skills (${SKILL_COUNT}):${NC}"
        grep "^  - " ${WORKFLOW_DIR}/skills/enabled.yaml | head -5 | while read -r line; do
            skill=$(echo "$line" | sed 's/^  - //')
            echo -e "    ✓ ${GREEN}${skill}${NC}"
        done

        if [ "$SKILL_COUNT" -gt 5 ] 2>/dev/null; then
            echo -e "    ${DIM}... and $((SKILL_COUNT - 5)) more${NC}"
        fi
    else
        echo -e "  ${DIM}No skills enabled${NC}"
    fi
else
    echo -e "  ${DIM}Skills not configured${NC}"
fi
echo ""

# Git Status
echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ${BOLD}VERSION CONTROL${NC}                                                            ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "not initialized")
LAST_COMMIT=$(git log -1 --format="%h - %s (%cr)" 2>/dev/null || echo "No commits yet")
MODIFIED=$(git status --porcelain 2>/dev/null | grep -c "^ M" || echo 0)
UNTRACKED=$(git status --porcelain 2>/dev/null | grep -c "^??" || echo 0)
STAGED=$(git status --porcelain 2>/dev/null | grep -c "^[AM]" || echo 0)
MODIFIED=$(echo "$MODIFIED" | tr -d '[:space:]')
UNTRACKED=$(echo "$UNTRACKED" | tr -d '[:space:]')
STAGED=$(echo "$STAGED" | tr -d '[:space:]')

echo -e "  ${CYAN}Branch:${NC}       ${GREEN}${CURRENT_BRANCH}${NC}"
echo -e "  ${CYAN}Last Commit:${NC}  ${DIM}${LAST_COMMIT}${NC}"
echo -e "  ${CYAN}Changes:${NC}      "

if [ "$STAGED" -gt 0 ] 2>/dev/null; then
    echo -e "    ${GREEN}●${NC} Staged: ${STAGED} files"
fi
if [ "$MODIFIED" -gt 0 ] 2>/dev/null; then
    echo -e "    ${YELLOW}●${NC} Modified: ${MODIFIED} files"
fi
if [ "$UNTRACKED" -gt 0 ] 2>/dev/null; then
    echo -e "    ${MAGENTA}●${NC} Untracked: ${UNTRACKED} files"
fi
if [ "$STAGED" -eq 0 ] 2>/dev/null && [ "$MODIFIED" -eq 0 ] 2>/dev/null && [ "$UNTRACKED" -eq 0 ] 2>/dev/null; then
    echo -e "    ${GREEN}✓${NC} Working tree clean"
fi
echo ""

# Verbose mode - additional information
if [ "$VERBOSE" = true ]; then
    # Recent Checkpoints
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│ ${BOLD}RECENT CHECKPOINTS${NC}                                                         ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
    
    if [ -f ${WORKFLOW_DIR}/checkpoints.log ]; then
        tail -3 ${WORKFLOW_DIR}/checkpoints.log | while IFS='|' read -r timestamp checkpoint description; do
            echo -e "  ${YELLOW}$(echo $checkpoint | xargs)${NC} - $(echo $description | xargs)"
            echo -e "    ${DIM}$(echo $timestamp | xargs)${NC}"
        done
    else
        echo -e "  ${DIM}No checkpoints recorded${NC}"
    fi
    echo ""
    
    # Knowledge Base Stats
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│ ${BOLD}KNOWLEDGE BASE${NC}                                                             ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
    
    if [ -d ${WORKFLOW_DIR}/knowledge ]; then
        PATTERN_COUNT=$(grep -c "pattern:" ${WORKFLOW_DIR}/knowledge/*.yaml 2>/dev/null || echo 0)
        SOLUTION_COUNT=$(grep -c "solution:" ${WORKFLOW_DIR}/knowledge/*.yaml 2>/dev/null || echo 0)
        
        echo -e "  ${CYAN}Patterns Learned:${NC}  ${GREEN}${PATTERN_COUNT}${NC}"
        echo -e "  ${CYAN}Solutions Stored:${NC}  ${GREEN}${SOLUTION_COUNT}${NC}"
    else
        echo -e "  ${DIM}Knowledge base empty${NC}"
    fi
    echo ""
fi

# Quick Actions
echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ${BOLD}QUICK ACTIONS${NC}                                                              ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

echo -e "  ${CYAN}Continue work:${NC}     ${GREEN}./scripts/recover_context.sh${NC}"
echo -e "  ${CYAN}Create checkpoint:${NC} ${GREEN}./scripts/checkpoint.sh \"message\"${NC}"
echo -e "  ${CYAN}Change agent:${NC}      ${GREEN}./scripts/activate_agent.sh [agent]${NC}"
echo -e "  ${CYAN}Enable skill:${NC}      ${GREEN}./scripts/enable_skill.sh [skill]${NC}"
echo ""

# Footer
echo -e "${BOLD}────────────────────────────────────────────────────────────────────────────────${NC}"
echo -e "${DIM}Universal Workflow System v1.1.0 | $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BOLD}────────────────────────────────────────────────────────────────────────────────${NC}"
