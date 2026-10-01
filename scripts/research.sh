#!/bin/bash
#
# Universal Workflow System - Research Workflow Script (Production-Hardened)
#
# Usage: ./scripts/research.sh [action] [details]
#
# Actions:
#   status  - Show current research phase
#   start   - Begin research cycle at hypothesis phase
#   next    - Advance to next phase
#   reject  - Hypothesis rejected or analysis failed (triggers refinement)
#   reset   - Reset research state
#
# RWF Compliance: R3 (State Safety), R4 (Error-Free)

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

# Resolve WORKFLOW_DIR: CWD first, then git root, then UWS fallback
source "${SCRIPT_LIB_DIR}/resolve_project.sh"

# Research Phase definitions (Scientific Method - 7 phases)
readonly RESEARCH_PHASES=("hypothesis" "literature_review" "experiment_design" "data_collection" "analysis" "peer_review" "publication")

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Source utility libraries
source_lib() {
    local lib="$1"
    if [[ -f "${SCRIPT_LIB_DIR}/${lib}" ]]; then
        # Suppress yq warning noise
        # shellcheck source=/dev/null
        YAML_UTILS_QUIET=true source "${SCRIPT_LIB_DIR}/${lib}"
        return 0
    fi
    return 1
}

# decisions.log lives in the project's .workflow/logs (decision_utils.sh defaults to a
# CWD-relative path, which is wrong when research.sh runs from a subdirectory).
# shellcheck disable=SC2034  # read by decision_utils.sh
DECISION_LOG_DIR="${WORKFLOW_DIR}/logs"

# Source core utilities
source_lib "yaml_utils.sh" || true
source_lib "atomic_utils.sh" || true
source_lib "validation_utils.sh" || true
source_lib "logging_utils.sh" || true
source_lib "workflow_routing.sh" || true
source_lib "decision_utils.sh" || true
source_lib "kb_utils.sh" || true   # meta-learning outcomes (docs/kb/outcomes.tsv)

PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
RESEARCH_CHECK="${SCRIPT_DIR}/research_check.py"
# Subcommands of `research.sh check <name>` that run the evidence checker instead of
# ticking a numbered deliverable (docs/design/research-team.md section 6.6).
RESEARCH_CHECK_COMMANDS=" ledger bib quotes numbers claims slop gate init role-exit plan data run repro retraction manuscript-hash macros "

#######################################
# Validate workflow is initialized. Only the phase actions (status, start, next, reject,
# reset, goal, check <n>, deliverables) need it; the evidence checks do not.
# Arguments: $1 - the action that needs the state
#######################################
validate_workflow() {
    local action="${1:-status}"
    # A .workflow that resolve_project.sh fell back to belongs to UWS itself, not to this
    # project: using it would change UWS's own research phase.
    if [[ "${UWS_WORKFLOW_SOURCE:-}" == "fallback" || ! -d "$WORKFLOW_DIR" || ! -f "$STATE_FILE" ]]; then
        echo -e "${RED}Error: research.sh ${action} needs .workflow/state.yaml, and this project has none.${NC}"
        echo -e "Run: ${CYAN}uws init research${NC} (or ./scripts/init_workflow.sh) in the project root."
        echo -e "The evidence checks need no workflow state: ${CYAN}research.sh check init|ledger|gate <phase>|...${NC}"
        exit 1
    fi
}

#######################################
# Run the evidence checker (docs/design/research-team.md section 6.6). It needs no
# workflow state. When no .workflow belongs to this project, the checker finds the project
# from the current directory (nearest research/ledger, else the current directory), so
# `check init` scaffolds here and never inside the UWS installation.
# Arguments: checker command and its arguments
#######################################
run_checker() {
    if ! command -v python3 > /dev/null 2>&1; then
        echo -e "${RED}Error: python3 is required for research checks.${NC}" >&2
        exit 2
    fi
    if [[ "${UWS_WORKFLOW_SOURCE:-}" == "fallback" ]]; then
        exec python3 "$RESEARCH_CHECK" "$@"
    fi
    exec python3 "$RESEARCH_CHECK" --root "$PROJECT_ROOT" "$@"
}

#######################################
# Run the BibTeX fetcher; like the checker it needs no workflow state.
#######################################
run_bib() {
    if [[ "${UWS_WORKFLOW_SOURCE:-}" == "fallback" ]]; then
        exec bash "${SCRIPT_DIR}/research_bib.sh" "$@"
    fi
    UWS_RESEARCH_ROOT="$PROJECT_ROOT" exec bash "${SCRIPT_DIR}/research_bib.sh" "$@"
}

#######################################
# Get current research phase safely
# Returns: Phase name or "none"
#######################################
get_phase() {
    if declare -f yaml_get > /dev/null 2>&1; then
        local phase
        phase=$(yaml_get "$STATE_FILE" "research_phase" 2>/dev/null || echo "null")
        if [[ "$phase" == "null" || -z "$phase" ]]; then
            echo "none"
        else
            echo "$phase"
        fi
    else
        # Fallback to grep
        grep "^research_phase:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "none"
    fi
}

#######################################
# Set research phase safely with atomic operations
# Arguments: $1 - new phase
#######################################
set_phase() {
    local new_phase="$1"

    # Validate phase
    local valid=false
    for p in ${RESEARCH_PHASES[@]+"${RESEARCH_PHASES[@]}"}; do
        if [[ "$p" == "$new_phase" ]]; then
            valid=true
            break
        fi
    done

    if [[ "$valid" != "true" ]]; then
        echo -e "${RED}Error: Invalid research phase: ${new_phase}${NC}"
        return 1
    fi

    # Use atomic operations if available
    if declare -f atomic_begin > /dev/null 2>&1; then
        atomic_begin "research_phase_update" 2>/dev/null || true
    fi

    # Try yaml_set first (handles escaping properly)
    if declare -f yaml_set > /dev/null 2>&1; then
        yaml_set "$STATE_FILE" "research_phase" "$new_phase" 2>/dev/null || {
            # Fallback to safe_sed_replace
            set_phase_fallback "$new_phase"
        }
    else
        set_phase_fallback "$new_phase"
    fi

    if declare -f atomic_commit > /dev/null 2>&1; then
        atomic_commit 2>/dev/null || true
    fi

    # Milestone 1: sync current_phase + board, seed the ledger, refresh handoff.
    if declare -f sync_meta_phase > /dev/null 2>&1; then
        local _total
        _total=$(get_phase_deliverables "$new_phase" | wc -l | tr -d '[:space:]')
        sync_meta_phase "research" "$new_phase" "${_total:-0}"
    fi

    # Log the transition
    if declare -f log_info > /dev/null 2>&1; then
        log_info "research" "Phase changed to: $new_phase"
    fi

    return 0
}

#######################################
# Fallback phase setter with safe escaping
#######################################
set_phase_fallback() {
    local new_phase="$1"

    # Check if research_phase key exists
    if ! grep -q "^research_phase:" "$STATE_FILE" 2>/dev/null; then
        # Add the key
        echo "research_phase: \"${new_phase}\"" >> "$STATE_FILE"
    else
        # Use safe_sed_replace if available
        if declare -f safe_sed_replace > /dev/null 2>&1; then
            safe_sed_replace "$STATE_FILE" "research_phase" "$new_phase"
        else
            # Manual escaping as last resort
            local escaped_phase
            escaped_phase=$(printf '%s\n' "$new_phase" | sed 's/[&/\]/\\&/g')
            sed_inplace "s|^research_phase:.*|research_phase: \"${escaped_phase}\"|" "$STATE_FILE"
        fi
    fi
}

#######################################
# Get next phase in research cycle
# Arguments: $1 - current phase
# Returns: Next phase or empty if at end
#######################################
get_next_phase() {
    local current="$1"
    local found=false

    for phase in ${RESEARCH_PHASES[@]+"${RESEARCH_PHASES[@]}"}; do
        if [[ "$found" == "true" ]]; then
            echo "$phase"
            return 0
        fi
        if [[ "$phase" == "$current" ]]; then
            found=true
        fi
    done

    # No next phase (at publication)
    return 1
}

#######################################
# Get refinement phase for rejection handling
# Arguments: $1 - current phase
# Returns: Phase to return to for refinement
#######################################
get_refinement_phase() {
    local current="$1"

    case "$current" in
        "hypothesis")
            # At hypothesis phase - stay to refine
            echo ""
            ;;
        "literature_review")
            # Gaps in literature → refine hypothesis
            echo "hypothesis"
            ;;
        "experiment_design")
            # Design issues → refine hypothesis
            echo "hypothesis"
            ;;
        "data_collection")
            # Issues during collection → refine design
            echo "experiment_design"
            ;;
        "analysis")
            # Failed analysis → refine experiment design
            echo "experiment_design"
            ;;
        "peer_review")
            # Reviewer feedback → re-analyze
            echo "analysis"
            ;;
        "publication")
            # Rejected paper → re-analyze
            echo "analysis"
            ;;
    esac
}

#######################################
# Phase deliverables (exit criteria) for the scientific-method phases.
# Returns one deliverable per line; count backs the goal-driven gate.
#######################################
get_phase_deliverables() {
    local phase="$1"

    case "$phase" in
        "hypothesis")
            echo "- Research question (RQ) stated"
            echo "- Testable, falsifiable hypothesis defined"
            echo "- Variables and expected outcomes identified"
            ;;
        "literature_review")
            echo "- Survey of prior work related to the hypothesis"
            echo "- Gap analysis documented"
            echo "- Key references catalogued with citations"
            ;;
        "experiment_design")
            echo "- Experimental methodology defined"
            echo "- Sample size and controls specified"
            echo "- Data-collection protocol documented"
            ;;
        "data_collection")
            echo "- Data collected per protocol"
            echo "- Deviations from protocol documented"
            ;;
        "analysis")
            echo "- Statistical analysis performed"
            echo "- Hypothesis tested against results"
            echo "- Visualizations generated"
            ;;
        "peer_review")
            echo "- Manuscript prepared for review"
            echo "- Reviewer feedback addressed"
            ;;
        "publication")
            echo "- Findings written up (paper/report)"
            echo "- Figures and tables prepared"
            echo "- Submitted to venue"
            ;;
    esac
}

#######################################
# Hard deliverable gate for `next` (active once a goal is declared; --force overrides)
# Arguments: $1 - current phase, $2 - force flag
#######################################
_deliverable_gate() {
    local phase="$1" force="${2:-}"
    [[ "$force" == "--force" ]] && return 0
    declare -f gate_enabled > /dev/null 2>&1 || return 0
    gate_enabled || return 0

    local total
    total=$(get_phase_deliverables "$phase" | wc -l | tr -d '[:space:]')
    declare -f mp_ensure > /dev/null 2>&1 && mp_ensure "research" "$phase" "${total:-0}"

    local remaining=0
    declare -f deliverables_remaining > /dev/null 2>&1 && remaining=$(deliverables_remaining "research" "$phase" 2>/dev/null || echo 0)
    [[ "$remaining" =~ ^[0-9]+$ ]] || remaining=0

    if (( remaining > 0 )); then
        echo -e "${RED}✗ Blocked: ${remaining} unmet deliverable(s) in '${phase}'.${NC}" >&2
        echo -e "${CYAN}Deliverables (mark done with: $0 check <n>):${NC}"
        local i=1 line
        while IFS= read -r line; do
            echo -e "   [${i}] ${line#- }"
            i=$(( i + 1 ))
        done < <(get_phase_deliverables "$phase")
        echo -e "${YELLOW}Override with:${NC} $0 next --force"
        return 1
    fi
    return 0
}

#######################################
# The research team's evidence gate is active when the project keeps research ledgers.
#######################################
research_ledger_active() {
    [[ -d "${PROJECT_ROOT}/research/ledger" ]]
}

#######################################
# Record a gate override in .workflow/logs/decisions.log (design section 5: every
# --force is logged and shown in the next PI brief).
# Arguments: $1 - phase, $2 - reason
#######################################
_log_gate_force() {
    local phase="$1" reason="$2" id
    # decisions.log is YAML with double-quoted scalars: one line, no quotes or backslashes.
    reason="$(printf '%s' "$reason" | tr '\n\r"\\' "  ''")"
    declare -f log_decision > /dev/null 2>&1 || return 1
    id=$(log_decision "Research evidence gate forced at ${phase}" "research-gate-force" "$reason") || return 1
    echo -e "${YELLOW}⚠ Evidence gate overridden at '${phase}' (${id}): ${reason}${NC}"
    echo -e "  Recorded in ${CYAN}.workflow/logs/decisions.log${NC}; the next PI brief must list it."
    return 0
}

#######################################
# Evidence gate for `next` (docs/design/research-team.md section 5). Runs
# research_check.py gate <phase> when research/ledger exists. Fails closed: a missing
# python3 or a checker error (exit 2) blocks. --force needs a reason, is logged, and is
# always refused at publication (PI decision 4, recorded 2026-09-26).
# Arguments: $1 - current phase, $2 - force flag, $3 - reason
#######################################
_evidence_gate() {
    local phase="$1" force="${2:-}" reason="${3:-}"
    research_ledger_active || return 0

    if [[ "$force" == "--force" ]]; then
        if [[ "$phase" == "publication" ]]; then
            echo -e "${RED}✗ Refused: --force is never accepted at the publication gate (PI decision).${NC}" >&2
            echo -e "  Fix the findings of: ${CYAN}$0 check gate publication${NC}" >&2
            return 1
        fi
        if [[ -z "${reason// /}" ]]; then
            echo -e "${RED}✗ --force needs a reason:${NC} $0 next --force \"<reason>\"" >&2
            return 1
        fi
        if ! _log_gate_force "$phase" "$reason"; then
            echo -e "${RED}✗ Could not record the override in decisions.log; refusing to advance.${NC}" >&2
            return 1
        fi
        return 0
    fi

    if ! command -v python3 > /dev/null 2>&1; then
        echo -e "${RED}✗ Blocked: the evidence gate needs python3, which was not found (the gate fails closed).${NC}" >&2
        return 1
    fi
    local rc=0
    python3 "$RESEARCH_CHECK" --root "$PROJECT_ROOT" gate "$phase" || rc=$?
    case "$rc" in
        0) return 0 ;;
        1)
            echo -e "${RED}✗ Blocked: the evidence gate for '${phase}' found problems (listed above).${NC}" >&2
            echo -e "${YELLOW}Override (logged, shown to the PI):${NC} $0 next --force \"<reason>\"" >&2
            ;;
        *)
            echo -e "${RED}✗ Blocked: the evidence gate could not run (exit ${rc}); it fails closed.${NC}" >&2
            ;;
    esac
    return 1
}

#######################################
# Show phase status with formatting
#######################################
show_status() {
    local current_phase
    current_phase=$(get_phase)

    echo -e "${BOLD}${MAGENTA}Research Workflow Status${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ "$current_phase" == "none" ]]; then
        echo -e "  Phase: ${YELLOW}Not started${NC}"
        echo -e ""
        echo -e "  Run ${CYAN}./scripts/research.sh start${NC} to begin research cycle."
    else
        echo -e "  Phase: ${GREEN}${current_phase}${NC}"
        echo -e ""

        # Show phase progression (Scientific Method)
        echo -e "  ${BOLD}Scientific Method Progress:${NC}"
        local found_current=false
        for phase in ${RESEARCH_PHASES[@]+"${RESEARCH_PHASES[@]}"}; do
            local display_name
            case "$phase" in
                "hypothesis") display_name="Hypothesis Formation" ;;
                "literature_review") display_name="Literature Review" ;;
                "experiment_design") display_name="Experiment Design" ;;
                "data_collection") display_name="Data Collection" ;;
                "analysis") display_name="Analysis & Results" ;;
                "peer_review") display_name="Peer Review" ;;
                "publication") display_name="Publication" ;;
                *) display_name="$phase" ;;
            esac

            if [[ "$phase" == "$current_phase" ]]; then
                echo -e "    ${GREEN}► ${display_name}${NC} (current)"
                found_current=true
            elif [[ "$found_current" == "false" ]]; then
                echo -e "    ${GREEN}✓ ${display_name}${NC}"
            else
                echo -e "    ${YELLOW}○ ${display_name}${NC}"
            fi
        done

        # Show next action hint
        echo -e ""
        local next_phase
        if next_phase=$(get_next_phase "$current_phase"); then
            echo -e "  Next: ${CYAN}./scripts/research.sh next${NC} → ${next_phase}"
        else
            echo -e "  ${GREEN}Research cycle complete!${NC}"
        fi
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#######################################
# Main logic
#######################################
main() {
    local action="${1:-status}"
    local details="${2:-}"
    local extra="${3:-}"

    # The evidence checker and the BibTeX fetcher work from the project files alone.
    if [[ "$action" == "check" && -n "$details" && "$RESEARCH_CHECK_COMMANDS" == *" ${details} "* ]]; then
        shift
        run_checker "$@"
    fi
    if [[ "$action" == "bib" ]]; then
        shift
        run_bib "$@"
    fi
    case "$action" in
        help|--help|-h) ;;
        *) validate_workflow "$action" ;;
    esac

    # Methodology guard: warn if research workflow is not active for this project type
    if declare -f is_methodology_active > /dev/null 2>&1; then
        if ! is_methodology_active "research"; then
            echo -e "${YELLOW}⚠  Research methodology is not the active workflow for this project type.${NC}"
            echo -e "  Use ${CYAN}./scripts/sdlc.sh${NC} for software development workflow,"
            echo -e "  or run ${CYAN}./scripts/detect_and_configure.sh${NC} to reconfigure."
            echo ""
        fi
    fi

    case "$action" in
        status)
            show_status
            ;;

        start)
            local current_phase
            current_phase=$(get_phase)

            if [[ "$current_phase" != "none" ]]; then
                echo -e "${YELLOW}Research already in progress at phase: ${current_phase}${NC}"
                echo -e "Use ${CYAN}./scripts/research.sh reset${NC} to restart."
                exit 1
            fi

            set_phase "hypothesis"
            echo -e "${GREEN}Starting Research: Hypothesis Phase${NC}"
            echo -e ""
            echo -e "Next steps:"
            echo -e "  1. Formulate your research question (RQ)"
            echo -e "  2. State your hypothesis clearly"
            echo -e "  3. Identify variables and expected outcomes"
            echo -e "  4. Run ${CYAN}./scripts/research.sh next${NC} when complete"
            ;;

        next)
            local current_phase
            current_phase=$(get_phase)

            if [[ "$current_phase" == "none" ]]; then
                echo -e "${RED}Error: Research not started.${NC}"
                echo -e "Run ${CYAN}./scripts/research.sh start${NC} first."
                exit 1
            fi

            # Evidence gate (active when research/ledger exists; --force is logged, and
            # refused at publication), then the deliverable gate (active once a goal is
            # declared; --force overrides).
            _evidence_gate "$current_phase" "${details:-}" "$extra" || exit 1
            _deliverable_gate "$current_phase" "${details:-}" || exit 1

            local next_phase
            if next_phase=$(get_next_phase "$current_phase"); then
                set_phase "$next_phase"
                echo -e "${GREEN}✅ Advancing to: ${next_phase}${NC}"
                # Meta-learning: record the gate pass (best effort; no-op without docs/kb)
                declare -f kb_record_gate_pass > /dev/null 2>&1 && kb_record_gate_pass research "$current_phase" "$next_phase" \
                    "$(get_phase_deliverables "$current_phase" | wc -l)" "${details:-}" || true

                # Point at the subagent that owns the new phase. Agents are real
                # Claude Code subagents now, dispatched on demand by
                # orchestrate.sh (which records active_agent); nothing to switch.
                if declare -f get_agent_for_phase > /dev/null 2>&1; then
                    local phase_agent
                    phase_agent=$(get_agent_for_phase "research" "$next_phase")
                    if [[ -n "$phase_agent" ]]; then
                        echo -e "  ${CYAN}🤖 Phase agent: uws-${phase_agent} (dispatch: uws orchestrate dispatch \"<task>\")${NC}"
                    fi
                fi

                # Phase-specific hints
                case "$next_phase" in
                    literature_review)
                        echo -e "  • Survey existing work related to hypothesis"
                        echo -e "  • Identify gaps in current literature"
                        echo -e "  • Document key references and findings"
                        echo -e "  • Refine hypothesis based on prior work"
                        ;;
                    experiment_design)
                        echo -e "  • Design experimental methodology"
                        echo -e "  • Define sample size and controls"
                        echo -e "  • Plan data collection procedures"
                        echo -e "  • Consider ethics approval if needed"
                        ;;
                    data_collection)
                        echo -e "  • Execute experiments per design"
                        echo -e "  • Collect and organize data"
                        echo -e "  • Document any deviations from protocol"
                        ;;
                    analysis)
                        echo -e "  • Perform statistical analysis"
                        echo -e "  • Test hypothesis against results"
                        echo -e "  • Generate visualizations"
                        echo -e "  • If results don't support hypothesis:"
                        echo -e "    ${CYAN}./scripts/research.sh reject \"reason\"${NC}"
                        ;;
                    peer_review)
                        echo -e "  • Prepare manuscript for review"
                        echo -e "  • Address reviewer feedback"
                        echo -e "  • Revise analysis if needed"
                        echo -e "  • If major revisions required:"
                        echo -e "    ${CYAN}./scripts/research.sh reject \"reviewer feedback\"${NC}"
                        ;;
                    publication)
                        echo -e "  • Write up findings (paper/report)"
                        echo -e "  • Prepare figures and tables"
                        echo -e "  • Submit to venue"
                        echo -e "  ${GREEN}Research cycle nearly complete!${NC}"
                        ;;
                esac
            else
                echo -e "${GREEN}Research cycle complete!${NC}"
                echo -e "Congratulations on completing your research!"
                echo -e ""
                echo -e "You can start a new research project with:"
                echo -e "  ${CYAN}./scripts/research.sh reset${NC}"
                echo -e "  ${CYAN}./scripts/research.sh start${NC}"
            fi
            ;;

        reject)
            local current_phase
            current_phase=$(get_phase)

            if [[ "$current_phase" == "none" ]]; then
                echo -e "${RED}Error: Research not started.${NC}"
                exit 1
            fi

            echo -e "${YELLOW}⚠️  Hypothesis Rejected / Analysis Issues${NC}"
            echo -e "  Current phase: ${current_phase}"
            if [[ -n "$details" ]]; then
                echo -e "  Reason: $details"
            fi

            local refinement_phase
            refinement_phase=$(get_refinement_phase "$current_phase")
            # Meta-learning: keep the reason (docs/kb/outcomes.tsv; best effort, no-op without docs/kb)
            declare -f kb_record_gate_fail > /dev/null 2>&1 && kb_record_gate_fail research "$current_phase" "$refinement_phase" "$details" || true

            if [[ -n "$refinement_phase" ]]; then
                set_phase "$refinement_phase"
                echo -e ""
                echo -e "${CYAN}🔄 Returning to ${refinement_phase} for refinement${NC}"
                echo -e ""
                echo -e "This is part of the scientific method - negative results"
                echo -e "are valuable and guide hypothesis refinement."
                echo -e ""
                echo -e "Options:"
                echo -e "  1. Refine your hypothesis and experimental design"
                echo -e "  2. Consider publishing negative results"
                echo -e ""
                echo -e "When ready: ${CYAN}./scripts/research.sh next${NC}"
            else
                echo -e "${YELLOW}At hypothesis phase - refine your research question.${NC}"
                echo -e "When ready: ${CYAN}./scripts/research.sh next${NC}"
            fi
            ;;

        reset)
            echo -e "${YELLOW}Resetting research state...${NC}"

            # Remove research_phase from state file
            if grep -q "^research_phase:" "$STATE_FILE" 2>/dev/null; then
                sed_inplace '/^research_phase:/d' "$STATE_FILE"
            fi

            echo -e "${GREEN}Research state reset.${NC}"
            echo -e "Run ${CYAN}./scripts/research.sh start${NC} to begin a new research project."
            ;;

        goal)
            if [[ -z "$details" ]]; then
                local _g
                _g=$(yaml_get "$STATE_FILE" "goal" 2>/dev/null || echo "")
                [[ "$_g" == "null" ]] && _g=""
                if [[ -z "$_g" ]]; then
                    echo -e "${YELLOW}No goal declared.${NC} Set one with: ${CYAN}$0 goal \"<objective>\"${NC}"
                else
                    echo -e "${CYAN}Goal:${NC} ${_g}"
                fi
            else
                yaml_set "$STATE_FILE" "goal" "$details" >/dev/null 2>&1 || true
                # Keep the handoff's managed summary (which shows the goal) current
                if declare -f refresh_handoff_header > /dev/null 2>&1; then
                    refresh_handoff_header "" "" "" "${WORKFLOW_DIR}/handoff.md"
                fi
                echo -e "${GREEN}✓ Goal declared:${NC} ${details}"
                echo -e "  Deliverable gating is now ${GREEN}active${NC} — use ${CYAN}$0 check <n>${NC} then ${CYAN}$0 next${NC}."
            fi
            ;;

        check)
            # `check <name>` ran the evidence checker above; `check <n>` ticks a deliverable.
            local current_phase
            current_phase=$(get_phase)
            if [[ "$current_phase" == "none" ]]; then
                echo -e "${RED}Error: Research not started.${NC}"
                exit 1
            fi
            local _total
            _total=$(get_phase_deliverables "$current_phase" | wc -l | tr -d '[:space:]')
            if [[ ! "$details" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Usage: $0 check <deliverable-number>${NC}"
                local _i=1 _l
                while IFS= read -r _l; do echo -e "   [${_i}] ${_l#- }"; _i=$(( _i + 1 )); done < <(get_phase_deliverables "$current_phase")
                exit 1
            fi
            if (( details < 1 || details > _total )); then
                echo -e "${RED}Error: deliverable number out of range (1..${_total}).${NC}"
                exit 1
            fi
            declare -f mp_ensure > /dev/null 2>&1 && mp_ensure "research" "$current_phase" "${_total:-0}"
            declare -f mark_deliverable > /dev/null 2>&1 && mark_deliverable "research" "$current_phase" "$details"
            local _line
            _line=$(get_phase_deliverables "$current_phase" | sed -n "${details}p")
            echo -e "${GREEN}✓ Marked [${details}]:${NC} ${_line#- }"
            local _rem=0
            declare -f deliverables_remaining > /dev/null 2>&1 && _rem=$(deliverables_remaining "research" "$current_phase" 2>/dev/null || echo 0)
            if (( _rem == 0 )); then
                echo -e "  ${GREEN}All deliverables met for ${current_phase}.${NC} Advance with ${CYAN}$0 next${NC}."
            else
                echo -e "  ${YELLOW}${_rem} remaining.${NC}"
            fi
            ;;

        deliverables)
            local _p="${details:-}"
            [[ -z "$_p" ]] && _p="$(get_phase)"
            [[ "$_p" == "none" || -z "$_p" ]] && _p="hypothesis"
            get_phase_deliverables "$_p"
            ;;

        help|--help|-h)
            echo "Usage: ./scripts/research.sh [action] [details]"
            echo ""
            echo "Actions:"
            echo "  status  Show current research phase (default)"
            echo "  start   Begin research at hypothesis phase"
            echo "  next    Advance to next phase"
            echo "  reject  Report rejected hypothesis or failed analysis"
            echo "  reset   Reset research state to start over"
            echo "  check <n>                  Mark deliverable <n> of the current phase done"
            echo ""
            echo "Research team (active when research/ledger exists; docs/design/research-team.md):"
            echo "  check init                 Scaffold research/ and bib_sources/"
            echo "  check ledger|bib|quotes|numbers|slop   Run one evidence check"
            echo "  check gate <phase>         Run a phase's evidence gate (next runs it too)"
            echo "  check plan [new|freeze <EXP-ID>]   Pre-register an experiment plan (frozen by hash)"
            echo "  check data [add <path> ...]        Data manifest: hashes, sources, splits, seeds"
            echo "  check run [--exp E] [--input P] [--output P] -- <cmd>   Run and record a command"
            echo "  check repro <N-ID ...|all> Re-run recorded commands in a scratch copy and compare"
            echo "  check retraction [--online]        Retraction notices (Crossref) for bib_sources/"
            echo "  check manuscript-hash      The hash a red-team review must name"
            echo "  check macros               Write the number macros from the number ledger"
            echo "  bib fetch <id> [--key K]   Download authoritative BibTeX (arXiv, DOI, DBLP, ACL)"
            echo "  bib build                  Write references.bib from bib_sources/ only"
            echo "  next --force \"<reason>\"    Override a failing gate (logged; refused at publication)"
            echo ""
            echo "Research Phases (Scientific Method):"
            echo "  hypothesis → literature_review → experiment_design → data_collection"
            echo "    → analysis → peer_review → publication"
            echo ""
            echo "Rejection Handling:"
            echo "  literature_review rejected → returns to hypothesis"
            echo "  experiment_design rejected → returns to hypothesis"
            echo "  data issues               → returns to experiment_design"
            echo "  analysis rejected          → returns to experiment_design"
            echo "  peer_review rejected       → returns to analysis"
            echo "  publication rejected       → returns to analysis"
            echo ""
            echo "Note: Negative results are valuable in research!"
            ;;

        *)
            echo -e "${RED}Error: Unknown action: ${action}${NC}"
            echo "Run ${CYAN}./scripts/research.sh help${NC} for usage."
            exit 1
            ;;
    esac
}

# Run main with all arguments
main "$@"
