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
#       Resolve current phase -> agent, record it, write the task brief, and
#       print a DISPATCH line for the session to act on.
#   ./scripts/orchestrate.sh collect "<summary>" [ticket]
#       After the subagent has written its artifact under workspace/<role>/,
#       stage it as a change request for human review (submit.sh).
#   ./scripts/orchestrate.sh status
#       Show the resolved methodology/phase/agent for the current state.
#
# Options (any position after the command):
#   --methodology sdlc|research
#       Use that methodology's phase. Without it, sdlc wins whenever sdlc_phase is set,
#       so a project with both phases active could never dispatch research work
#       (docs/design/research-team.md section 2).
#   --agent <role>
#       Dispatch a specific subagent instead of the phase's default, for example the
#       research team's rt-scout, rt-verifier or rt-redteam.
#
# RWF Compliance: R3 (State Safety)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/resolve_project.sh"
YAML_UTILS_QUIET=true source "${SCRIPT_DIR}/lib/yaml_utils.sh" 2>/dev/null || true
YAML_UTILS_QUIET=true source "${SCRIPT_DIR}/lib/workflow_routing.sh" 2>/dev/null || true
# Meta-learning outcomes (docs/kb/outcomes.tsv): best effort, no-op without a KB
# shellcheck source=lib/kb_utils.sh
source "${SCRIPT_DIR}/lib/kb_utils.sh" 2>/dev/null || true

PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

M=""; PHASE=""; AGENT=""
METHODOLOGY_OVERRIDE=""; AGENT_OVERRIDE=""

# Subagents gen_subagents.sh generates (.claude/agents/uws-<role>.md).
KNOWN_AGENTS=" researcher architect implementer experimenter optimizer deployer documenter rt-scout rt-verifier rt-redteam "

research_ledger_active() {
    [[ -d "${PROJECT_ROOT}/research/ledger" ]]
}

is_research_agent() {
    [[ "$1" == rt-* ]]
}

resolve_context() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${RED}Error: state file not found. Run ./scripts/init_workflow.sh${NC}" >&2
        exit 1
    fi
    local sdlc_phase research_phase
    sdlc_phase=$(yaml_get "$STATE_FILE" "sdlc_phase" 2>/dev/null || echo "null")
    research_phase=$(yaml_get "$STATE_FILE" "research_phase" 2>/dev/null || echo "null")
    [[ -z "$sdlc_phase" ]] && sdlc_phase="null"
    [[ -z "$research_phase" ]] && research_phase="null"

    case "$METHODOLOGY_OVERRIDE" in
        sdlc|research)
            M="$METHODOLOGY_OVERRIDE"
            if [[ "$M" == "sdlc" ]]; then PHASE="$sdlc_phase"; else PHASE="$research_phase"; fi
            if [[ "$PHASE" == "null" ]]; then
                echo -e "${RED}Error: no active ${M} phase. Start it first: ${CYAN}./scripts/${M}.sh start${NC}" >&2
                exit 1
            fi
            ;;
        *)
            if [[ "$sdlc_phase" != "null" ]]; then
                M="sdlc"; PHASE="$sdlc_phase"
                if [[ "$research_phase" != "null" ]]; then
                    echo -e "${YELLOW}note: sdlc and research phases are both active; using sdlc (pass --methodology research for research work)${NC}" >&2
                fi
            elif [[ "$research_phase" != "null" ]]; then
                M="research"; PHASE="$research_phase"
            else
                echo -e "${RED}Error: no active phase. Start one first:${NC}" >&2
                echo -e "  ${CYAN}./scripts/sdlc.sh start${NC}   or   ${CYAN}./scripts/research.sh start${NC}" >&2
                exit 1
            fi
            ;;
    esac

    if [[ -n "$AGENT_OVERRIDE" ]]; then
        AGENT="$AGENT_OVERRIDE"
        return 0
    fi
    if declare -f get_agent_for_phase >/dev/null 2>&1; then
        AGENT=$(get_agent_for_phase "$M" "$PHASE")
    fi
    # Research projects with ledgers route the phases the research team owns in
    # increment 1 to its roles (design section 5: scout owns literature_review, the
    # red team owns peer_review). Other phases keep their generic agent until the
    # methodologist, engineer and writer arrive in increment 2.
    if [[ "$M" == "research" ]] && research_ledger_active; then
        case "$PHASE" in
            literature_review) AGENT="rt-scout" ;;
            peer_review)       AGENT="rt-redteam" ;;
        esac
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

    # Record the dispatched agent (state.yaml active_agent + AGENT_DISPATCHED in
    # checkpoints.log) so submit.sh attributes the change to the right
    # workspace and handoff.md shows who is working.
    if declare -f record_active_agent >/dev/null 2>&1; then
        record_active_agent "$AGENT" "$STATE_FILE" || \
            echo -e "${YELLOW}warn: could not record active agent; continuing${NC}" >&2
    fi

    local goal deliv contract
    goal=$(yaml_get "$STATE_FILE" "goal" 2>/dev/null || echo ""); [[ "$goal" == "null" ]] && goal=""
    deliv=$(bash "${SCRIPT_DIR}/${M}.sh" deliverables "$PHASE" 2>/dev/null || true)
    if [[ "$M" == "research" ]] && research_ledger_active; then
        deliv="${deliv}
- Evidence gate passes: \`uws research check gate ${PHASE}\` (research.sh next runs it)"
    fi
    if is_research_agent "$AGENT"; then
        contract="Follow \`.claude/agents/uws-${AGENT}.md\` (research output contract). Every claim you author is a
C-ID row appended to \`research/ledger/claims.jsonl\` with status \`unverified\`; never verify a claim you authored.
BibTeX only through \`uws research bib fetch\`. Proposed manuscript edits go under \`workspace/${AGENT}/\`.
End your report with \"Open questions for the orchestrator\". STOP at your Quality Gate —
do NOT advance the workflow or mark deliverables; the lead + the PI own that."
    else
        contract="Follow \`.claude/agents/uws-${AGENT}.md\`. Write ONLY under \`workspace/${AGENT}/\`.
Complete artifacts, no stubs. Trace claims to REQ-IDs. STOP at your Quality Gate —
do NOT advance the workflow or mark deliverables; the orchestrator + human review own that."
    fi

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
${contract}
EOF

    # Meta-learning: which role and model got this phase's work (best effort)
    if declare -f kb_outcomes_enabled >/dev/null 2>&1 && kb_outcomes_enabled; then
        kb_outcome dispatch "${M}:${PHASE}" "$AGENT" "$(kb_agent_model "$AGENT" "$PROJECT_ROOT")" \
            "$target" dispatched "$(kb_head_ref "$PROJECT_ROOT")" || true
    fi

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
    local active_agent target="" phase="" brief
    active_agent=$(get_active_agent "$STATE_FILE" 2>/dev/null || true)
    brief="${PROJECT_ROOT}/workspace/${active_agent}/TASK.md"
    if [[ -n "$active_agent" && -f "$brief" ]]; then
        # The brief names the phase and target artifact; keep them for the outcome row
        target="$(sed -n 's/^- \*\*Target artifact\*\*: `workspace\/[^/]*\/\(.*\)`$/\1/p' "$brief" | head -1 || true)"
        phase="$(sed -n 's/^- \*\*Methodology \/ Phase\*\*: \([a-z]*\) \/ \([a-z_]*\).*/\1:\2/p' "$brief" | head -1 || true)"
        rm -f "$brief"
    fi
    local out rc=0 cr
    out="$(bash "${SCRIPT_DIR}/submit.sh" "$summary" "$ticket")" || rc=$?
    [[ -n "$out" ]] && printf '%s\n' "$out"
    (( rc == 0 )) || exit "$rc"
    # Meta-learning: the collected CR, so review decisions can be traced to the
    # role and model that produced it (best effort)
    cr="$(printf '%s\n' "$out" | sed -n 's/^CL ID: \(CR-[0-9A-Za-z_-]*\)$/\1/p' | tail -1)"
    if [[ -n "$cr" ]] && declare -f kb_outcomes_enabled >/dev/null 2>&1 && kb_outcomes_enabled; then
        [[ -n "$phase" ]] || phase="$(kb_current_phase)"
        kb_outcome dispatch "$phase" "${active_agent:-unknown}" \
            "$(kb_agent_model "${active_agent:-unknown}" "$PROJECT_ROOT")" "${target:--}" collected "$cr" || true
    fi
    echo ""
    echo -e "${YELLOW}Human gate:${NC} review the change request, then approve with"
    echo -e "  ${CYAN}./scripts/review.sh approve <CR-ID>${NC}"
    echo -e "After approval, mark deliverables and advance:"
    echo -e "  ${CYAN}./scripts/${M:-sdlc}.sh check <n>${NC}  then  ${CYAN}./scripts/${M:-sdlc}.sh next${NC}"
}

usage() {
    echo "Usage: $0 {dispatch \"<task>\" [target] | collect \"<summary>\" [ticket] | status}"
    echo "       [--methodology sdlc|research] [--agent <role>]"
}

COMMAND="${1:-help}"
[[ $# -gt 0 ]] && shift
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --methodology|--agent)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}Error: $1 needs a value${NC}" >&2
                exit 1
            fi
            if [[ "$1" == "--methodology" ]]; then METHODOLOGY_OVERRIDE="$2"; else AGENT_OVERRIDE="$2"; fi
            shift 2
            ;;
        --methodology=*) METHODOLOGY_OVERRIDE="${1#*=}"; shift ;;
        --agent=*)       AGENT_OVERRIDE="${1#*=}"; shift ;;
        *)               ARGS+=("$1"); shift ;;
    esac
done
if [[ -n "$METHODOLOGY_OVERRIDE" && "$METHODOLOGY_OVERRIDE" != "sdlc" && "$METHODOLOGY_OVERRIDE" != "research" ]]; then
    echo -e "${RED}Error: --methodology must be sdlc or research (got '${METHODOLOGY_OVERRIDE}')${NC}" >&2
    exit 1
fi
if [[ -n "$AGENT_OVERRIDE" && "$KNOWN_AGENTS" != *" ${AGENT_OVERRIDE} "* ]]; then
    echo -e "${RED}Error: unknown agent '${AGENT_OVERRIDE}' (known:${KNOWN_AGENTS})${NC}" >&2
    exit 1
fi
[[ -n "$METHODOLOGY_OVERRIDE" ]] && M="$METHODOLOGY_OVERRIDE"
ARG1="${ARGS[0]:-}"
ARG2="${ARGS[1]:-}"

case "$COMMAND" in
    dispatch) cmd_dispatch "$ARG1" "$ARG2" ;;
    collect)  cmd_collect  "$ARG1" "$ARG2" ;;
    status)   cmd_status ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: ${COMMAND}${NC}" >&2
        echo "Run: $0 help"
        exit 1
        ;;
esac
