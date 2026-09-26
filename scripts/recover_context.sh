#!/bin/bash

# Context Recovery Script - RWF Enhanced
# Quickly restore context after a session break or context loss
# RWF Compliance: R5 (Reproducibility) - Any agent must continue from saved state
#
# Usage:
#   recover_context.sh          Human-readable recovery report (colour only on
#                               a terminal and when NO_COLOR is unset)
#   recover_context.sh --hook   One line of Claude Code SessionStart hook JSON
#                               with a compact plain-text summary; read-only,
#                               silent outside UWS projects

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

MODE="human"
case "${1:-}" in
    --hook) MODE="hook" ;;
    -h|--help)
        sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

# ── Hook mode ────────────────────────────────────────────────────────────────
# Must never fail a session start and never write state: find the project's
# .workflow (WORKFLOW_DIR, then CWD, then git root) and emit JSON, or nothing.
# Unlike human mode it does NOT fall back to UWS's own .workflow, which would
# inject an unrelated project's state.
if [[ "$MODE" == "hook" ]]; then
    source "${SCRIPT_LIB_DIR}/hook_context.sh"
    hook_wf="${WORKFLOW_DIR:-}"
    if [[ -z "$hook_wf" ]]; then
        if [[ -f "${PWD}/.workflow/state.yaml" ]]; then
            hook_wf="${PWD}/.workflow"
        else
            hook_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
            if [[ -n "$hook_root" && -f "${hook_root}/.workflow/state.yaml" ]]; then
                hook_wf="${hook_root}/.workflow"
            fi
        fi
    fi
    [[ -n "$hook_wf" && -f "${hook_wf}/state.yaml" ]] || exit 0
    uws_hook_json "$hook_wf" || echo "uws: could not build session context from ${hook_wf}" >&2
    exit 0
fi

# ── Human mode ───────────────────────────────────────────────────────────────

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
source_lib "hook_context.sh"

# Colour only for a terminal, and never when NO_COLOR is set (no-color.org).
# Library functions read these globals too, so this also silences their colour.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
    USE_COLOR=true
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' NC=''
    USE_COLOR=false
fi

# Get recovery start time
source "${SCRIPT_LIB_DIR}/portable.sh"
RECOVERY_START_TIME=$(now_ms)

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
        echo -e "   Run: ${CYAN}uws init${NC} first"
        exit 1
    fi
elif ! validate_workflow_initialized 2>/dev/null; then
    if [[ ! -f .workflow/state.yaml ]]; then
        echo -e "${RED}❌ Error: Workflow not initialized${NC}"
        echo -e "   Run: ${CYAN}uws init${NC} first"
        exit 1
    fi
fi

STATE=".workflow/state.yaml"
HANDOFF=".workflow/handoff.md"

# Calculate and display recovery completeness
echo -e "${BLUE}📊 Recovery Completeness:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
SCORE_COLOR=""
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
            echo -e "  ${YELLOW}Missing files: ${MISSING_FILES}${NC}"
        fi
        MISSING_FIELDS=$(check_required_fields "$STATE" 2>/dev/null || echo "")
        if [[ -n "$MISSING_FIELDS" ]]; then
            echo -e "  ${YELLOW}Missing state fields: ${MISSING_FIELDS}${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}(Completeness check not available)${NC}"
fi
echo ""

# Load current state (flat schema written by init_workflow.sh; legacy nested
# locations are accepted as a fallback for older state files)
echo -e "${BLUE}📊 Current State:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PROJECT_TYPE=$(uws_state_value "$STATE" project_type project.type)
GOAL=$(uws_state_value "$STATE" goal)
CURRENT_PHASE=$(uws_state_value "$STATE" current_phase)
CURRENT_CHECKPOINT=$(uws_state_value "$STATE" current_checkpoint)
LAST_UPDATED=$(uws_state_value "$STATE" last_updated metadata.last_updated)
RESEARCH_PHASE=$(uws_state_value "$STATE" research_phase)
SDLC_PHASE=$(uws_state_value "$STATE" sdlc_phase)

echo -e "  🎯 Goal:             ${GREEN}${GOAL:-(none declared)}${NC}"
echo -e "  📁 Project Type:     ${GREEN}${PROJECT_TYPE:-unknown}${NC}"

# Show active methodology
if declare -f get_active_methodology > /dev/null 2>&1; then
    ACTIVE_METHODOLOGY=$(get_active_methodology "${PROJECT_TYPE:-hybrid}")
    echo -e "  🔀 Methodology:      ${GREEN}${ACTIVE_METHODOLOGY}${NC}"

    if [[ "$ACTIVE_METHODOLOGY" == "research" || "$ACTIVE_METHODOLOGY" == "both" ]]; then
        echo -e "  🔬 Research Phase:   ${YELLOW}${RESEARCH_PHASE:-none}${NC}"
    fi
    if [[ "$ACTIVE_METHODOLOGY" == "sdlc" || "$ACTIVE_METHODOLOGY" == "both" ]]; then
        echo -e "  🏗️  SDLC Phase:      ${YELLOW}${SDLC_PHASE:-none}${NC}"
    fi
fi

echo -e "  📍 Current Phase:    ${GREEN}${CURRENT_PHASE:-unknown}${NC}"
echo -e "  ✓  Checkpoint:       ${GREEN}${CURRENT_CHECKPOINT:-none}${NC}"
echo -e "  🕐 Last Updated:     ${YELLOW}${LAST_UPDATED:-unknown}${NC}"
echo ""

# Show recent checkpoints (real "| CP_" entries only: no comments, INIT/AUTO
# markers or AGENT_*/SKILL_* events)
echo -e "${BLUE}📍 Recent Checkpoints:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
RECENT_CPS="$(uws_real_checkpoints .workflow/checkpoints.log 5)"
if [[ -n "$RECENT_CPS" ]]; then
    while IFS='|' read -r timestamp checkpoint description; do
        timestamp="${timestamp#"${timestamp%%[![:space:]]*}"}"; timestamp="${timestamp%"${timestamp##*[![:space:]]}"}"
        checkpoint="${checkpoint//[[:space:]]/}"
        description="${description# }"
        echo -e "  ${YELLOW}${checkpoint}${NC} - ${description}"
        echo -e "    ${MAGENTA}${timestamp}${NC}"
    done <<< "$RECENT_CPS"
else
    echo -e "  ${YELLOW}No checkpoints found${NC}"
fi
echo ""

# Show the active agent: the subagent orchestrate.sh last dispatched
# (state.yaml active_agent). Informational only: agents run as Claude Code
# subagents, the main session does not adopt a persona.
echo -e "${BLUE}🤖 Active Agent:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ACTIVE_AGENT="$(uws_state_value .workflow/state.yaml _uws_no_such_key active_agent.name)"
AGENT_STATUS="$(uws_state_value .workflow/state.yaml _uws_no_such_key active_agent.status)"
if [[ -n "$ACTIVE_AGENT" && "$AGENT_STATUS" == "active" ]]; then
    echo -e "  👤 Agent:   ${GREEN}${ACTIVE_AGENT}${NC} (subagent uws-${ACTIVE_AGENT})"
else
    echo -e "  ${YELLOW}No agent dispatched${NC}"
fi
echo ""

# Show handoff notes (open items of the first Next Actions section)
echo -e "${BLUE}📝 Handoff Notes:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f "$HANDOFF" ]; then
    NEXT_ITEMS="$(uws_handoff_items "$HANDOFF" '(next (actions|steps)|priority actions|todo)' 10)"
    if [[ -n "$NEXT_ITEMS" ]]; then
        while IFS= read -r line; do
            echo -e "  ⬜ ${line#- }"
        done <<< "$NEXT_ITEMS"
    else
        echo -e "  ${YELLOW}No open next actions${NC}"
    fi
    BLOCKERS="$(uws_handoff_items "$HANDOFF" 'blocker' 10)"
    if [[ -n "$BLOCKERS" ]]; then
        echo -e "  ${RED}Blockers:${NC}"
        while IFS= read -r line; do
            echo -e "  ⛔ ${line#- }"
        done <<< "$BLOCKERS"
    fi
else
    echo -e "  ${YELLOW}No handoff notes found${NC}"
fi
echo ""

# Show critical context (numbered items of the Critical Context section)
echo -e "${BLUE}⚠️  Critical Context:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f "$HANDOFF" ]; then
    CRITICAL="$(awk '
        /^#+[[:space:]]/ { if (insec) exit; insec = (tolower($0) ~ /critical context/); next }
        insec && /^[0-9]+[.)][[:space:]]/ { print }
    ' "$HANDOFF" 2>/dev/null || true)"
    if [[ -n "$CRITICAL" ]]; then
        while IFS= read -r line; do
            echo -e "  ${YELLOW}${line}${NC}"
        done <<< "$CRITICAL"
    fi
fi
echo ""

# Git status summary
echo -e "${BLUE}📦 Git Status:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo -e "  🌿 Branch:     ${GREEN}${CURRENT_BRANCH}${NC}"

# Count changes from porcelain columns: X = index (staged), Y = worktree
# (modified), "??" = untracked
read -r MODIFIED STAGED UNTRACKED <<< "$(git status --porcelain 2>/dev/null | awk '
    { x = substr($0, 1, 1); y = substr($0, 2, 1)
      if (x == "?") { u++ } else { if (x != " ") s++; if (y != " ") m++ } }
    END { printf "%d %d %d\n", m, s, u }' || echo "0 0 0")"

echo -e "  📝 Modified:   ${YELLOW}${MODIFIED:-0} files${NC}"
echo -e "  ➕ Staged:     ${GREEN}${STAGED:-0} files${NC}"
echo -e "  ❓ Untracked:  ${MAGENTA}${UNTRACKED:-0} files${NC}"
echo ""

# Show recent commits
echo -e "${BLUE}📜 Recent Activity:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "$USE_COLOR" == "true" ]]; then
    git log --oneline -5 --format="  %C(yellow)%h%C(reset) %s %C(dim)(%cr)%C(reset)" 2>/dev/null || echo -e "  ${YELLOW}No commits yet${NC}"
else
    git log --oneline -5 --no-color --format="  %h %s (%cr)" 2>/dev/null || echo "  No commits yet"
fi
echo ""

# Suggest next actions
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}💡 Suggested Actions:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Methodology-aware suggestions
if declare -f get_active_methodology > /dev/null 2>&1; then
    case "${ACTIVE_METHODOLOGY:-both}" in
        "research")
            echo -e "  1. Check research phase:   ${CYAN}uws research status${NC}"
            echo -e "  2. Advance research:       ${CYAN}uws research next${NC}"
            echo -e "  3. Check handoff notes:    ${CYAN}cat .workflow/handoff.md${NC}"
            ;;
        "sdlc")
            echo -e "  1. Check SDLC phase:       ${CYAN}uws sdlc status${NC}"
            echo -e "  2. Advance SDLC:           ${CYAN}uws sdlc next${NC}"
            echo -e "  3. Check handoff notes:    ${CYAN}cat .workflow/handoff.md${NC}"
            ;;
        "both")
            echo -e "  1. Research workflow:       ${CYAN}uws research status${NC}"
            echo -e "  2. SDLC workflow:           ${CYAN}uws sdlc status${NC}"
            echo -e "  3. Check handoff notes:    ${CYAN}cat .workflow/handoff.md${NC}"
            ;;
    esac
else
    echo -e "  1. View detailed state:    ${CYAN}cat .workflow/state.yaml${NC}"
    echo -e "  2. Check handoff notes:    ${CYAN}cat .workflow/handoff.md${NC}"
    echo -e "  3. Show status:            ${CYAN}uws status${NC}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Quick status check
READY=true
WARNINGS=""

if (( ${MODIFIED:-0} > 5 )); then
    WARNINGS="${WARNINGS}\n  ⚠️  Many uncommitted changes - consider committing"
    READY=false
fi

if [ ! -f "$HANDOFF" ]; then
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
RECOVERY_END_TIME=$(now_ms)
RECOVERY_TIME_MS=$((RECOVERY_END_TIME - RECOVERY_START_TIME))

# Update session state to mark context as recovered
if declare -f get_iso_timestamp > /dev/null 2>&1; then
    RECOVERY_TIMESTAMP=$(get_iso_timestamp)
else
    RECOVERY_TIMESTAMP=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
fi

if declare -f yaml_set > /dev/null 2>&1; then
    yaml_set "$STATE" "session.context_recovered" "true" 2>/dev/null || true
    yaml_set "$STATE" "session.last_recovery" "$RECOVERY_TIMESTAMP" 2>/dev/null || true
    yaml_set "$STATE" "session.recovery_time_ms" "$RECOVERY_TIME_MS" 2>/dev/null || true
fi

# Log successful recovery
if declare -f log_recovery > /dev/null 2>&1; then
    log_recovery "success" "${COMPLETENESS_SCORE:-}" "context_recovery" 2>/dev/null || true
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
echo -e "  Run ${CYAN}uws status --verbose${NC} for detailed information"
echo -e "  Run ${CYAN}uws checkpoint completeness${NC} for the full report"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
