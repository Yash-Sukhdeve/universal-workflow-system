#!/bin/bash
#
# Universal Workflow System - SDLC Core Script (Production-Hardened)
#
# Usage: ./scripts/sdlc.sh [action] [details]
#
# Actions:
#   status  - Show current SDLC phase
#   start   - Begin SDLC cycle at requirements phase
#   next    - Advance to next phase
#   fail    - Report failure in current phase (triggers regression)
#   reset   - Reset SDLC state
#
# RWF Compliance: R3 (State Safety), R4 (Error-Free)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

# Resolve WORKFLOW_DIR: CWD first, then git root, then UWS fallback
source "${SCRIPT_LIB_DIR}/resolve_project.sh"

# SDLC Phase definitions
readonly SDLC_PHASES=("requirements" "design" "implementation" "verification" "deployment" "maintenance")

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
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
source_lib "workflow_routing.sh" || true

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
# Get current SDLC phase safely
# Returns: Phase name or "none"
#######################################
get_phase() {
    if declare -f yaml_get > /dev/null 2>&1; then
        local phase
        phase=$(yaml_get "$STATE_FILE" "sdlc_phase" 2>/dev/null || echo "null")
        if [[ "$phase" == "null" || -z "$phase" ]]; then
            echo "none"
        else
            echo "$phase"
        fi
    else
        # Fallback to grep
        grep "^sdlc_phase:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "none"
    fi
}

#######################################
# Set SDLC phase safely with atomic operations
# Arguments: $1 - new phase
#######################################
set_phase() {
    local new_phase="$1"

    # Validate phase
    local valid=false
    for p in "${SDLC_PHASES[@]}"; do
        if [[ "$p" == "$new_phase" ]]; then
            valid=true
            break
        fi
    done

    if [[ "$valid" != "true" ]]; then
        echo -e "${RED}Error: Invalid SDLC phase: ${new_phase}${NC}"
        return 1
    fi

    # Use atomic operations if available
    if declare -f atomic_begin > /dev/null 2>&1; then
        atomic_begin "sdlc_phase_update" 2>/dev/null || true
    fi

    # Try yaml_set first (handles escaping properly)
    if declare -f yaml_set > /dev/null 2>&1; then
        yaml_set "$STATE_FILE" "sdlc_phase" "$new_phase" 2>/dev/null || {
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
        log_info "sdlc" "Phase changed to: $new_phase"
    fi

    return 0
}

#######################################
# Fallback phase setter with safe escaping
#######################################
set_phase_fallback() {
    local new_phase="$1"

    # Check if sdlc_phase key exists
    if ! grep -q "^sdlc_phase:" "$STATE_FILE" 2>/dev/null; then
        # Add the key
        echo "sdlc_phase: \"${new_phase}\"" >> "$STATE_FILE"
    else
        # Use safe_sed_replace if available
        if declare -f safe_sed_replace > /dev/null 2>&1; then
            safe_sed_replace "$STATE_FILE" "sdlc_phase" "$new_phase"
        else
            # Manual escaping as last resort
            local escaped_phase
            escaped_phase=$(printf '%s\n' "$new_phase" | sed 's/[&/\]/\\&/g')
            sed -i "s|^sdlc_phase:.*|sdlc_phase: \"${escaped_phase}\"|" "$STATE_FILE"
        fi
    fi
}

#######################################
# Get next phase in SDLC cycle
# Arguments: $1 - current phase
# Returns: Next phase or empty if at end
#######################################
get_next_phase() {
    local current="$1"
    local found=false

    for phase in "${SDLC_PHASES[@]}"; do
        if [[ "$found" == "true" ]]; then
            echo "$phase"
            return 0
        fi
        if [[ "$phase" == "$current" ]]; then
            found=true
        fi
    done

    # No next phase (at maintenance)
    return 1
}

#######################################
# Get regression phase for failure handling
# Arguments: $1 - current phase
# Returns: Phase to regress to
#######################################
get_regression_phase() {
    local current="$1"

    case "$current" in
        "verification")
            echo "implementation"
            ;;
        "deployment")
            echo "verification"
            ;;
        "maintenance")
            echo "deployment"
            ;;
        *)
            # No regression for earlier phases
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

    echo -e "${BOLD}SDLC Status${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ "$current_phase" == "none" ]]; then
        echo -e "  Phase: ${YELLOW}Not started${NC}"
        echo -e ""
        echo -e "  Run ${CYAN}./scripts/sdlc.sh start${NC} to begin SDLC cycle."
    else
        echo -e "  Phase: ${GREEN}${current_phase}${NC}"
        echo -e ""

        # Show phase progression
        echo -e "  ${BOLD}Progress:${NC}"
        local found_current=false
        for phase in "${SDLC_PHASES[@]}"; do
            if [[ "$phase" == "$current_phase" ]]; then
                echo -e "    ${GREEN}► ${phase}${NC} (current)"
                found_current=true
            elif [[ "$found_current" == "false" ]]; then
                echo -e "    ${GREEN}✓ ${phase}${NC}"
            else
                echo -e "    ${YELLOW}○ ${phase}${NC}"
            fi
        done

        # Show next action hint
        echo -e ""
        local next_phase
        if next_phase=$(get_next_phase "$current_phase"); then
            echo -e "  Next: ${CYAN}./scripts/sdlc.sh next${NC} → ${next_phase}"
        else
            echo -e "  ${GREEN}SDLC cycle complete!${NC}"
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

    # Methodology guard: warn if SDLC workflow is not active for this project type
    if declare -f is_methodology_active > /dev/null 2>&1; then
        if ! is_methodology_active "sdlc"; then
            echo -e "${YELLOW}⚠  SDLC methodology is not the active workflow for this project type.${NC}"
            echo -e "  Use ${CYAN}./scripts/research.sh${NC} for research workflow,"
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
                echo -e "${YELLOW}SDLC already in progress at phase: ${current_phase}${NC}"
                echo -e "Use ${CYAN}./scripts/sdlc.sh reset${NC} to restart."
                exit 1
            fi

            set_phase "requirements"
            echo -e "${GREEN}Starting SDLC: Requirements Phase${NC}"
            echo -e ""
            echo -e "Next steps:"
            echo -e "  1. Define user stories and acceptance criteria"
            echo -e "  2. Document project scope and constraints"
            echo -e "  3. Run ${CYAN}./scripts/sdlc.sh next${NC} when complete"
            ;;

        next)
            local current_phase
            current_phase=$(get_phase)

            if [[ "$current_phase" == "none" ]]; then
                echo -e "${RED}Error: SDLC not started.${NC}"
                echo -e "Run ${CYAN}./scripts/sdlc.sh start${NC} first."
                exit 1
            fi

            local next_phase
            if next_phase=$(get_next_phase "$current_phase"); then
                set_phase "$next_phase"
                echo -e "${GREEN}✅ Advancing to: ${next_phase}${NC}"

                # Auto-switch agent if routing library and config allow
                if declare -f get_agent_for_phase > /dev/null 2>&1; then
                    local auto_select="false"
                    local config_file="${WORKFLOW_DIR}/config.yaml"
                    [[ -f "$config_file" ]] && auto_select=$(grep "auto_select:" "$config_file" 2>/dev/null | head -1 | awk '{print $2}' || echo "false")
                    if [[ "$auto_select" == "true" ]]; then
                        local suggested_agent
                        suggested_agent=$(get_agent_for_phase "sdlc" "$next_phase")
                        local current_agent
                        current_agent=$(grep "current_agent:" "${WORKFLOW_DIR}/agents/active.yaml" 2>/dev/null | cut -d'"' -f2 || echo "")
                        if [[ -n "$suggested_agent" && "$suggested_agent" != "$current_agent" ]]; then
                            echo -e "  ${CYAN}🤖 Auto-switching agent: ${current_agent:-none} → ${suggested_agent}${NC}"
                            "${SCRIPT_DIR}/activate_agent.sh" "$suggested_agent" 2>/dev/null || true
                        fi
                    fi
                fi

                # Phase-specific hints
                case "$next_phase" in
                    design)
                        echo -e "  • Create system architecture documents"
                        echo -e "  • Define APIs and data models"
                        ;;
                    implementation)
                        echo -e "  • Write code following design specs"
                        echo -e "  • Create unit tests as you go"
                        ;;
                    verification)
                        echo -e "  • Run full test suite"
                        echo -e "  • Perform code review"
                        echo -e "  • If tests fail: ${CYAN}./scripts/sdlc.sh fail \"reason\"${NC}"
                        ;;
                    deployment)
                        echo -e "  • Deploy to staging environment"
                        echo -e "  • Run integration tests"
                        echo -e "  • If deployment fails: ${CYAN}./scripts/sdlc.sh fail \"reason\"${NC}"
                        ;;
                    maintenance)
                        echo -e "  • Monitor production systems"
                        echo -e "  • Handle bug reports and improvements"
                        echo -e "  ${GREEN}SDLC cycle complete!${NC}"
                        ;;
                esac
            else
                echo -e "${GREEN}SDLC cycle complete!${NC}"
                echo -e "Already at maintenance phase (final phase)."
            fi
            ;;

        fail)
            local current_phase
            current_phase=$(get_phase)

            if [[ "$current_phase" == "none" ]]; then
                echo -e "${RED}Error: SDLC not started.${NC}"
                exit 1
            fi

            echo -e "${YELLOW}⚠️  Failure reported in phase: ${current_phase}${NC}"
            if [[ -n "$details" ]]; then
                echo -e "Details: $details"
            fi

            local regression_phase
            regression_phase=$(get_regression_phase "$current_phase")

            if [[ -n "$regression_phase" ]]; then
                set_phase "$regression_phase"
                echo -e "${CYAN}🔄 Reverting to ${regression_phase} phase${NC}"
                echo -e ""
                echo -e "Address the failure and run ${CYAN}./scripts/sdlc.sh next${NC} when resolved."
            else
                echo -e "${YELLOW}No regression available for ${current_phase} phase.${NC}"
                echo -e "Resolve the blocking issue before proceeding."
            fi
            ;;

        reset)
            echo -e "${YELLOW}Resetting SDLC state...${NC}"

            # Remove sdlc_phase from state file
            if grep -q "^sdlc_phase:" "$STATE_FILE" 2>/dev/null; then
                sed -i '/^sdlc_phase:/d' "$STATE_FILE"
            fi

            echo -e "${GREEN}SDLC state reset.${NC}"
            echo -e "Run ${CYAN}./scripts/sdlc.sh start${NC} to begin a new cycle."
            ;;

        help|--help|-h)
            echo "Usage: ./scripts/sdlc.sh [action] [details]"
            echo ""
            echo "Actions:"
            echo "  status  Show current SDLC phase (default)"
            echo "  start   Begin SDLC at requirements phase"
            echo "  next    Advance to next phase"
            echo "  fail    Report failure (optional: details message)"
            echo "  reset   Reset SDLC state to start over"
            echo ""
            echo "SDLC Phases:"
            echo "  requirements → design → implementation → verification → deployment → maintenance"
            echo ""
            echo "Failure Handling:"
            echo "  verification fails → regresses to implementation"
            echo "  deployment fails   → regresses to verification"
            ;;

        *)
            echo -e "${RED}Error: Unknown action: ${action}${NC}"
            echo "Run ${CYAN}./scripts/sdlc.sh help${NC} for usage."
            exit 1
            ;;
    esac
}

# Run main with all arguments
main "$@"
