#!/bin/bash
#
# Universal Workflow System - Orchestrator (Milestone 1)
#
# Binds the UWS state spine to Claude Code's real execution primitives. It does
# the deterministic setup a phase needs, then hands a machine-readable DISPATCH
# line to the main Claude session, which runs the matching .claude/agents/uws-<role>
# subagent (via the Agent/Workflow tools). Artifacts land in workspace/<role>/ and
# flow through the existing submit.sh -> review.sh human gate.
#
# Usage:
#   ./scripts/orchestrate.sh dispatch "<task>" [target-rel-path]
#       Resolve current phase -> agent, activate it, write the task brief, and
#       print a DISPATCH line for the session to act on.
#   ./scripts/orchestrate.sh collect "<summary>" [ticket]
#       After the subagent has written its artifact under workspace/<role>/,
#       stage it as a change request for human review (submit.sh).
#   ./scripts/orchestrate.sh status
#       Show the resolved methodology/phase/agent for the current state.
#
# RWF Compliance: R3 (State Safety)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/resolve_project.sh"
YAML_UTILS_QUIET=true source "${SCRIPT_DIR}/lib/yaml_utils.sh" 2>/dev/null || true
YAML_UTILS_QUIET=true source "${SCRIPT_DIR}/lib/workflow_routing.sh" 2>/dev/null || true

PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

M=""; PHASE=""; AGENT=""

resolve_context() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${RED}Error: state file not found. Run ./scripts/init_workflow.sh${NC}" >&2
        exit 1
    fi
    local sdlc_phase research_phase
    sdlc_phase=$(yaml_get "$STATE_FILE" "sdlc_phase" 2>/dev/null || echo "null")
    research_phase=$(yaml_get "$STATE_FILE" "research_phase" 2>/dev/null || echo "null")

    if [[ "$sdlc_phase" != "null" && -n "$sdlc_phase" ]]; then
        M="sdlc"; PHASE="$sdlc_phase"
    elif [[ "$research_phase" != "null" && -n "$research_phase" ]]; then
        M="research"; PHASE="$research_phase"
    else
        echo -e "${RED}Error: no active phase. Start one first:${NC}" >&2
        echo -e "  ${CYAN}./scripts/sdlc.sh start${NC}   or   ${CYAN}./scripts/research.sh start${NC}" >&2
        exit 1
    fi

    if declare -f get_agent_for_phase >/dev/null 2>&1; then
        AGENT=$(get_agent_for_phase "$M" "$PHASE")
    fi
    [[ -z "$AGENT" ]] && AGENT="researcher"
    return 0   # never let a trailing test's exit code abort the caller under set -e
}

cmd_status() {
    resolve_context
    local uws; uws=$(uws_phase_for_methodology "$M" "$PHASE" 2>/dev/null || echo "phase_1_planning")
    echo -e "${BOLD}Orchestrator context${NC}"
    echo -e "  Methodology: ${GREEN}${M}${NC}"
    echo -e "  Phase:       ${GREEN}${PHASE}${NC}  ${CYAN}(UWS: ${uws})${NC}"
    echo -e "  Agent:       ${GREEN}${AGENT}${NC}  ->  .claude/agents/uws-${AGENT}.md"
}

cmd_dispatch() {
    local task="${1:-}"
    local target="${2:-}"
    if [[ -z "$task" ]]; then
        echo -e "${RED}Usage: $0 dispatch \"<task>\" [target-rel-path]${NC}" >&2
        exit 1
    fi
    resolve_context

    [[ -z "$target" ]] && target="docs/uws-work/${M}-${PHASE}.md"

    local ws="${PROJECT_ROOT}/workspace/${AGENT}"
    mkdir -p "${ws}/$(dirname "$target")"

    # Activate the agent so submit.sh attributes the change to the right workspace.
    if [[ -f "${SCRIPT_DIR}/activate_agent.sh" ]]; then
        bash "${SCRIPT_DIR}/activate_agent.sh" "$AGENT" >/dev/null 2>&1 || \
            echo -e "${YELLOW}warn: activate_agent.sh failed; continuing${NC}" >&2
    fi

    local goal deliv
    goal=$(yaml_get "$STATE_FILE" "goal" 2>/dev/null || echo ""); [[ "$goal" == "null" ]] && goal=""
    deliv=$(bash "${SCRIPT_DIR}/${M}.sh" deliverables "$PHASE" 2>/dev/null || true)

    cat > "${ws}/TASK.md" << EOF
# Task Brief — ${AGENT}

- **Methodology / Phase**: ${M} / ${PHASE}  (UWS: $(uws_phase_for_methodology "$M" "$PHASE" 2>/dev/null || echo "?"))
- **Goal**: ${goal:-$task}
- **Task**: ${task}
- **Target artifact**: \`workspace/${AGENT}/${target}\`
  (on approval the review pipeline places this at \`./${target}\`)

## Deliverables — exit criteria (address every one; they are the gate)
${deliv}

## Output Contract
Follow \`.claude/agents/uws-${AGENT}.md\`. Write ONLY under \`workspace/${AGENT}/\`.
Complete artifacts, no stubs. Trace claims to REQ-IDs. STOP at your Quality Gate —
do NOT advance the workflow or mark deliverables; the orchestrator + human review own that.
EOF

    echo -e "${GREEN}✓ Prepared dispatch for ${AGENT} (${M}:${PHASE})${NC}"
    echo -e "  Brief:  ${CYAN}workspace/${AGENT}/TASK.md${NC}"
    echo -e "  Output: ${CYAN}workspace/${AGENT}/${target}${NC}"
    echo ""
    # Machine-readable line for the main session / uws-orchestrate skill.
    echo "DISPATCH: agent=${AGENT} subagent=.claude/agents/uws-${AGENT}.md phase=${M}:${PHASE} brief=workspace/${AGENT}/TASK.md out=workspace/${AGENT}/${target}"
    echo ""
    echo -e "${YELLOW}Next:${NC} run the ${CYAN}uws-${AGENT}${NC} subagent on the brief, then:"
    echo -e "  ${CYAN}$0 collect \"${AGENT}: ${PHASE} artifact\"${NC}   (stages it for review)"
}

cmd_collect() {
    local summary="${1:-UWS artifact produced}"
    local ticket="${2:-}"
    if [[ ! -f "${SCRIPT_DIR}/submit.sh" ]]; then
        echo -e "${RED}Error: submit.sh not found${NC}" >&2
        exit 1
    fi
    # The TASK.md brief is a transient control file, NOT a deliverable. submit.sh
    # diffs the whole workspace/<agent>/ dir, so leaving TASK.md in would submit it
    # as a repo-root file and cause cross-CR conflicts. Strip it before staging.
    local active_agent
    active_agent=$(grep 'current_agent:' "${WORKFLOW_DIR}/agents/active.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
    if [[ -n "$active_agent" && -f "${PROJECT_ROOT}/workspace/${active_agent}/TASK.md" ]]; then
        rm -f "${PROJECT_ROOT}/workspace/${active_agent}/TASK.md"
    fi
    bash "${SCRIPT_DIR}/submit.sh" "$summary" "$ticket"
    echo ""
    echo -e "${YELLOW}Human gate:${NC} review the change request, then approve with"
    echo -e "  ${CYAN}./scripts/review.sh approve <CR-ID>${NC}"
    echo -e "After approval, mark deliverables and advance:"
    echo -e "  ${CYAN}./scripts/${M:-sdlc}.sh check <n>${NC}  then  ${CYAN}./scripts/${M:-sdlc}.sh next${NC}"
}

case "${1:-help}" in
    dispatch) cmd_dispatch "${2:-}" "${3:-}" ;;
    collect)  cmd_collect  "${2:-}" "${3:-}" ;;
    status)   cmd_status ;;
    help|--help|-h)
        echo "Usage: $0 {dispatch \"<task>\" [target] | collect \"<summary>\" [ticket] | status}"
        ;;
    *)
        echo -e "${RED}Unknown command: ${1}${NC}" >&2
        echo "Run: $0 help"
        exit 1
        ;;
esac
