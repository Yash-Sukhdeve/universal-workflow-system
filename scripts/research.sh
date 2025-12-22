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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"
# Use environment variable if set, otherwise default to script-relative path
WORKFLOW_DIR="${WORKFLOW_DIR:-${SCRIPT_DIR}/../.workflow}"
STATE_FILE="${WORKFLOW_DIR}/state.yaml"

# Research Phase definitions (Scientific Method)
readonly RESEARCH_PHASES=("hypothesis" "experiment_design" "data_collection" "analysis" "publication")

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
        YAML_UTILS_QUIET=true source "${SCRIPT_LIB_DIR}/${lib}"
        return 0
    fi
    return 1
}

# Source core utilities
source_lib "yaml_utils.sh" || true
source_lib "atomic_utils.sh" || true
source_lib "validation_utils.sh" || true
source_lib "logging_utils.sh" || true

#######################################
# Validate workflow is initialized
#######################################
validate_workflow() {
    if [[ ! -d "$WORKFLOW_DIR" ]]; then
        echo -e "${RED}Error: Workflow not initialized.${NC}"
        echo -e "Run: ${CYAN}./scripts/init_workflow.sh${NC}"
        exit 1
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${RED}Error: State file not found: ${STATE_FILE}${NC}"
        exit 1
    fi
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
    for p in "${RESEARCH_PHASES[@]}"; do
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
            sed -i "s|^research_phase:.*|research_phase: \"${escaped_phase}\"|" "$STATE_FILE"
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

    for phase in "${RESEARCH_PHASES[@]}"; do
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
        "analysis")
            # Failed analysis → refine experiment design
            echo "experiment_design"
            ;;
        "data_collection")
            # Issues during collection → refine design
            echo "experiment_design"
            ;;
        "publication")
            # Rejected paper → re-analyze or redesign
            echo "analysis"
            ;;
        *)
            # For hypothesis phase, stay there to refine
            echo ""
            ;;
    esac
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
        for phase in "${RESEARCH_PHASES[@]}"; do
            local display_name
            case "$phase" in
                "hypothesis") display_name="Hypothesis Formation" ;;
                "experiment_design") display_name="Experiment Design" ;;
                "data_collection") display_name="Data Collection" ;;
                "analysis") display_name="Analysis & Results" ;;
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

    # Validate workflow first
    validate_workflow

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

            local next_phase
            if next_phase=$(get_next_phase "$current_phase"); then
                set_phase "$next_phase"
                echo -e "${GREEN}✅ Advancing to: ${next_phase}${NC}"

                # Phase-specific hints
                case "$next_phase" in
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
                    publication)
                        echo -e "  • Write up findings (paper/report)"
                        echo -e "  • Prepare figures and tables"
                        echo -e "  • Submit for peer review"
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
                sed -i '/^research_phase:/d' "$STATE_FILE"
            fi

            echo -e "${GREEN}Research state reset.${NC}"
            echo -e "Run ${CYAN}./scripts/research.sh start${NC} to begin a new research project."
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
            echo ""
            echo "Research Phases (Scientific Method):"
            echo "  hypothesis → experiment_design → data_collection → analysis → publication"
            echo ""
            echo "Rejection Handling:"
            echo "  analysis rejected   → returns to experiment_design"
            echo "  data issues         → returns to experiment_design"
            echo "  publication rejected → returns to analysis"
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
