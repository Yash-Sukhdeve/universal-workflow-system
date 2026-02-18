#!/bin/bash

# Context Recovery Script - RWF Enhanced
# Quickly restore context after a session break or context loss
# RWF Compliance: R5 (Reproducibility) - Any agent must continue from saved state

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

# Resolve WORKFLOW_DIR: CWD first, then git root, then UWS fallback
source "${SCRIPT_LIB_DIR}/resolve_project.sh"

# Source utility libraries in dependency order
source_lib() {
    local lib="$1"
    if [[ -f "${SCRIPT_LIB_DIR}/${lib}" ]]; then
        YAML_UTILS_QUIET=true source "${SCRIPT_LIB_DIR}/${lib}"
        return 0
    fi
    return 1
}

# Core utilities
source_lib "yaml_utils.sh" || true
source_lib "validation_utils.sh" || true

# RWF utilities
source_lib "timestamp_utils.sh" || true
source_lib "logging_utils.sh" || true
source_lib "error_utils.sh" || true
source_lib "precondition_utils.sh" || true
source_lib "completeness_utils.sh" || true
source_lib "checksum_utils.sh" || true
source_lib "workflow_routing.sh" || true

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Get recovery start time
RECOVERY_START_TIME=$(date +%s%3N 2>/dev/null || date +%s)

echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}           📡 CONTEXT RECOVERY SYSTEM (RWF Enhanced)${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Log recovery start
if declare -f log_recovery > /dev/null 2>&1; then
    log_recovery "start" "" "context_recovery"
fi

# Check if workflow is initialized using preconditions
if declare -f require_workflow_initialized > /dev/null 2>&1; then
    if ! require_workflow_initialized; then
        echo -e "${RED}❌ Error: Workflow not initialized${NC}"
        echo -e "   Run: ${CYAN}./scripts/init_workflow.sh${NC} first"
        exit 1
    fi
elif ! validate_workflow_initialized 2>/dev/null; then
    if [[ ! -f .workflow/state.yaml ]]; then
        echo -e "${RED}❌ Error: Workflow not initialized${NC}"
        echo -e "   Run: ${CYAN}./scripts/init_workflow.sh${NC} first"
        exit 1
    fi
fi

# Calculate and display recovery completeness
echo -e "${BLUE}📊 Recovery Completeness:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if declare -f calculate_completeness_score > /dev/null 2>&1; then
    COMPLETENESS_SCORE=$(calculate_completeness_score 2>/dev/null || echo "0")

    # Determine color based on score
    if (( COMPLETENESS_SCORE >= 80 )); then
        SCORE_COLOR="${GREEN}"
        SCORE_STATUS="GOOD"
    elif (( COMPLETENESS_SCORE >= 50 )); then
        SCORE_COLOR="${YELLOW}"
        SCORE_STATUS="PARTIAL"
    else
        SCORE_COLOR="${RED}"
        SCORE_STATUS="INCOMPLETE"
    fi

    echo -e "  Score: ${SCORE_COLOR}${COMPLETENESS_SCORE}%${NC} [${SCORE_STATUS}]"

    # Show missing items if incomplete
    if (( COMPLETENESS_SCORE < 80 )); then
        MISSING_FILES=$(check_required_files 2>/dev/null || echo "")
        if [[ -n "$MISSING_FILES" ]]; then
            echo -e "  ${YELLOW}Missing: ${MISSING_FILES}${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}(Completeness check not available)${NC}"
fi
echo ""

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

# Show active methodology
if declare -f get_active_methodology > /dev/null 2>&1; then
    ACTIVE_METHODOLOGY=$(get_active_methodology "$PROJECT_TYPE")
    echo -e "  🔀 Methodology:      ${GREEN}${ACTIVE_METHODOLOGY}${NC}"

    RESEARCH_PHASE=$(get_yaml_value "research_phase" ".workflow/state.yaml")
    SDLC_PHASE=$(get_yaml_value "sdlc_phase" ".workflow/state.yaml")

    if [[ "$ACTIVE_METHODOLOGY" == "research" || "$ACTIVE_METHODOLOGY" == "both" ]]; then
        echo -e "  🔬 Research Phase:   ${YELLOW}${RESEARCH_PHASE:-none}${NC}"
    fi
    if [[ "$ACTIVE_METHODOLOGY" == "sdlc" || "$ACTIVE_METHODOLOGY" == "both" ]]; then
        echo -e "  🏗️  SDLC Phase:      ${YELLOW}${SDLC_PHASE:-none}${NC}"
    fi
fi

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
    sed -n '/## Next Actions/,/## Commands/p' .workflow/handoff.md | grep "^- \[" 2>/dev/null | while read -r line; do
        if [[ $line == *"[x]"* ]]; then
            echo -e "  ✅ ${line#*] }"
        else
            echo -e "  ⬜ ${line#*] }"
        fi
    done || true
else
    echo -e "  ${YELLOW}No handoff notes found${NC}"
fi
echo ""

# Show critical context
echo -e "${BLUE}⚠️  Critical Context:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f .workflow/handoff.md ]; then
    sed -n '/## Critical Context/,/## Next Actions/p' .workflow/handoff.md | grep "^[0-9]" 2>/dev/null | while read -r line; do
        echo -e "  ${YELLOW}$line${NC}"
    done || true
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

# Methodology-aware suggestions
if declare -f get_active_methodology > /dev/null 2>&1; then
    case "${ACTIVE_METHODOLOGY:-both}" in
        "research")
            echo -e "  1. Check research phase:   ${CYAN}./scripts/research.sh status${NC}"
            echo -e "  2. Advance research:       ${CYAN}./scripts/research.sh next${NC}"
            echo -e "  3. Check handoff notes:    ${CYAN}cat .workflow/handoff.md${NC}"
            ;;
        "sdlc")
            echo -e "  1. Check SDLC phase:       ${CYAN}./scripts/sdlc.sh status${NC}"
            echo -e "  2. Advance SDLC:           ${CYAN}./scripts/sdlc.sh next${NC}"
            echo -e "  3. Check handoff notes:    ${CYAN}cat .workflow/handoff.md${NC}"
            ;;
        "both")
            echo -e "  1. Research workflow:       ${CYAN}./scripts/research.sh status${NC}"
            echo -e "  2. SDLC workflow:           ${CYAN}./scripts/sdlc.sh status${NC}"
            echo -e "  3. Check handoff notes:    ${CYAN}cat .workflow/handoff.md${NC}"
            ;;
    esac
else
    # Fallback to phase-specific suggestions
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
            echo -e "  3. View available agents:  ${CYAN}./scripts/activate_agent.sh --help${NC}"
            ;;
    esac
fi

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

# Calculate recovery time
RECOVERY_END_TIME=$(date +%s%3N 2>/dev/null || date +%s)
RECOVERY_TIME_MS=$((RECOVERY_END_TIME - RECOVERY_START_TIME))

# Update session state to mark context as recovered
if declare -f get_iso_timestamp > /dev/null 2>&1; then
    RECOVERY_TIMESTAMP=$(get_iso_timestamp)
else
    RECOVERY_TIMESTAMP=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
fi

if declare -f yaml_set > /dev/null 2>&1; then
    yaml_set .workflow/state.yaml "session.context_recovered" "true" 2>/dev/null || true
    yaml_set .workflow/state.yaml "session.last_recovery" "$RECOVERY_TIMESTAMP" 2>/dev/null || true
    yaml_set .workflow/state.yaml "session.recovery_time_ms" "$RECOVERY_TIME_MS" 2>/dev/null || true
fi

# Log successful recovery
if declare -f log_recovery > /dev/null 2>&1; then
    log_recovery "success" "$COMPLETENESS_SCORE" "context_recovery" 2>/dev/null || true
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Recovery Time: ${GREEN}${RECOVERY_TIME_MS}ms${NC}"
if [[ -n "${COMPLETENESS_SCORE:-}" ]]; then
    echo -e "  Completeness:  ${SCORE_COLOR}${COMPLETENESS_SCORE}%${NC}"
fi
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  Run ${CYAN}./scripts/status.sh --verbose${NC} for detailed information"
echo -e "  Run ${CYAN}./scripts/checkpoint.sh completeness${NC} for full report"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
