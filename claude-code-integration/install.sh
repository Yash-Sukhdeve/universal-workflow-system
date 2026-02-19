#!/bin/bash
#
# UWS (Universal Workflow System) - Claude Code Integration Installer
# Version 1.2.0
#
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash
#
# Or clone and run:
#   ./install.sh
#
# Fixes in 1.2.0:
#   - Git precondition check with auto-init
#   - Self-contained workflow scripts (no external dependencies)
#   - /uws umbrella help command
#   - settings.json merge instead of overwrite
#   - Git-guarded code paths in all hooks/commands
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
UWS_VERSION="1.2.0"
PROJECT_DIR="${PWD}"
UWS_DIR="${PROJECT_DIR}/.uws"
WORKFLOW_DIR="${PROJECT_DIR}/.workflow"
CLAUDE_DIR="${PROJECT_DIR}/.claude"
HAS_GIT=false

echo -e "${BOLD}${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     UWS - Universal Workflow System for Claude Code          ║"
echo "║                    Version ${UWS_VERSION}                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if already installed
if [[ -d "${UWS_DIR}" ]] && [[ -f "${UWS_DIR}/version" ]]; then
    EXISTING_VERSION=$(cat "${UWS_DIR}/version" 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}UWS already installed (version: ${EXISTING_VERSION})${NC}"
    read -p "Reinstall/upgrade? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

echo -e "${CYAN}Installing UWS to: ${PROJECT_DIR}${NC}"
echo ""

# ============================================================================
# Step 1: Git precondition check
# ============================================================================
echo -e "${BLUE}[1/8]${NC} Checking git repository..."

if ! command -v git &>/dev/null; then
    echo -e "  ${RED}ERROR: git is not installed.${NC}"
    echo -e "  UWS requires git for version control integration."
    echo -e "  Install git first: ${BOLD}sudo apt install git${NC} (Debian/Ubuntu)"
    echo -e "                     ${BOLD}brew install git${NC} (macOS)"
    exit 1
fi

if git rev-parse --git-dir &>/dev/null; then
    HAS_GIT=true
    echo -e "  ${GREEN}✓${NC} Git repository detected"
else
    echo -e "  ${YELLOW}!${NC} Not a git repository"
    read -p "  Initialize git repo here? [Y/n]: " init_git
    if [[ ! "$init_git" =~ ^[Nn]$ ]]; then
        git init "${PROJECT_DIR}"
        HAS_GIT=true
        echo -e "  ${GREEN}✓${NC} Git repository initialized"
    else
        echo -e "  ${YELLOW}→${NC} Continuing without git (some features will be limited)"
    fi
fi

# ============================================================================
# Step 2: Create directory structure
# ============================================================================
echo -e "${BLUE}[2/8]${NC} Creating directory structure..."

mkdir -p "${UWS_DIR}/hooks"
mkdir -p "${UWS_DIR}/scripts"
mkdir -p "${WORKFLOW_DIR}"
mkdir -p "${CLAUDE_DIR}/commands"

echo -e "  ${GREEN}✓${NC} Directories created"

# ============================================================================
# Step 3: Create hook scripts (git-guarded)
# ============================================================================
echo -e "${BLUE}[3/8]${NC} Creating Claude Code hooks..."

# SessionStart hook - injects context silently
cat > "${UWS_DIR}/hooks/session_start.sh" << 'HOOK_EOF'
#!/bin/bash
# UWS SessionStart Hook - Silently inject workflow context into Claude

WORKFLOW_DIR="${CLAUDE_PROJECT_DIR:-.}/.workflow"

# Exit silently if no workflow
[[ ! -d "$WORKFLOW_DIR" ]] && exit 0

# Build context from state files
CONTEXT=""

# Read state.yaml
if [[ -f "$WORKFLOW_DIR/state.yaml" ]]; then
    PHASE=$(grep -E "^current_phase:" "$WORKFLOW_DIR/state.yaml" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "unknown")
    CHECKPOINT=$(grep -E "^current_checkpoint:" "$WORKFLOW_DIR/state.yaml" 2>/dev/null | cut -d: -f2 | tr -d ' "' || echo "none")
    PROJECT_TYPE=$(grep -E "^  type:" "$WORKFLOW_DIR/state.yaml" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' "' || echo "unknown")

    CONTEXT+="## Workflow State\n"
    CONTEXT+="- Phase: ${PHASE}\n"
    CONTEXT+="- Checkpoint: ${CHECKPOINT}\n"
    CONTEXT+="- Project Type: ${PROJECT_TYPE}\n\n"
fi

# Read recent checkpoints
if [[ -f "$WORKFLOW_DIR/checkpoints.log" ]]; then
    RECENT=$(tail -3 "$WORKFLOW_DIR/checkpoints.log" 2>/dev/null | grep -v "^#" || echo "")
    if [[ -n "$RECENT" ]]; then
        CONTEXT+="## Recent Checkpoints\n\`\`\`\n${RECENT}\n\`\`\`\n\n"
    fi
fi

# Read priority actions from handoff
if [[ -f "$WORKFLOW_DIR/handoff.md" ]]; then
    ACTIONS=$(sed -n '/^## Next Actions/,/^##/p' "$WORKFLOW_DIR/handoff.md" 2>/dev/null | head -10 | grep -E "^-|\[" || echo "")
    if [[ -n "$ACTIONS" ]]; then
        CONTEXT+="## Priority Actions\n${ACTIONS}\n\n"
    fi
fi

# Git status (only if git is available and this is a repo)
if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    MODIFIED=$(git status --porcelain 2>/dev/null | grep -c "^ M" || echo "0")
    if [[ -n "$BRANCH" ]]; then
        CONTEXT+="## Git\n- Branch: ${BRANCH}\n- Modified files: ${MODIFIED}\n\n"
    fi
fi

# Output as JSON for Claude to consume
if [[ -n "$CONTEXT" ]]; then
    CONTEXT_ESCAPED=$(echo -e "$CONTEXT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    echo "{\"additionalContext\": \"${CONTEXT_ESCAPED}\"}"
fi

exit 0
HOOK_EOF
chmod +x "${UWS_DIR}/hooks/session_start.sh"

# PreCompact hook - auto-checkpoint before context compaction
cat > "${UWS_DIR}/hooks/pre_compact.sh" << 'HOOK_EOF'
#!/bin/bash
# UWS PreCompact Hook - Auto-checkpoint before context compaction

WORKFLOW_DIR="${CLAUDE_PROJECT_DIR:-.}/.workflow"
CHECKPOINT_LOG="$WORKFLOW_DIR/checkpoints.log"

# Exit silently if no workflow
[[ ! -d "$WORKFLOW_DIR" ]] && exit 0

# Get current checkpoint number
if [[ -f "$CHECKPOINT_LOG" ]]; then
    LAST_CP=$(grep -oE "CP_[0-9]+_[0-9]+" "$CHECKPOINT_LOG" | tail -1 || echo "CP_1_000")
    PHASE=$(echo "$LAST_CP" | cut -d_ -f2)
    SEQ=$(echo "$LAST_CP" | cut -d_ -f3 | sed 's/^0*//')
    NEW_SEQ=$(printf "%03d" $((SEQ + 1)))
    NEW_CP="CP_${PHASE}_${NEW_SEQ}"
else
    NEW_CP="CP_1_001"
fi

# Create auto-checkpoint
TIMESTAMP=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
echo "${TIMESTAMP} | ${NEW_CP} | Auto-checkpoint before context compaction" >> "$CHECKPOINT_LOG"

# Update state.yaml checkpoint
if [[ -f "$WORKFLOW_DIR/state.yaml" ]]; then
    sed -i.bak "s/current_checkpoint:.*/current_checkpoint: \"${NEW_CP}\"/" "$WORKFLOW_DIR/state.yaml" 2>/dev/null || true
    sed -i.bak "s/last_updated:.*/last_updated: \"${TIMESTAMP}\"/" "$WORKFLOW_DIR/state.yaml" 2>/dev/null || true
    rm -f "$WORKFLOW_DIR/state.yaml.bak"
fi

echo "{\"status\": \"checkpoint_created\", \"checkpoint\": \"${NEW_CP}\"}"
exit 0
HOOK_EOF
chmod +x "${UWS_DIR}/hooks/pre_compact.sh"

echo -e "  ${GREEN}✓${NC} Hooks created (git-guarded)"

# Clean up stale files from v1.1.0
STALE_COMMANDS=("uws-pm" "uws-spiral" "uws-submit" "uws-review")
for cmd in "${STALE_COMMANDS[@]}"; do
    if [[ -f "${CLAUDE_DIR}/commands/${cmd}" ]]; then
        rm -f "${CLAUDE_DIR}/commands/${cmd}"
    fi
done

# ============================================================================
# Step 4: Create self-contained workflow scripts
# ============================================================================
echo -e "${BLUE}[4/8]${NC} Creating workflow scripts..."

# --- Common utilities (sourced by other scripts) ---
cat > "${UWS_DIR}/scripts/common.sh" << 'SCRIPT_EOF'
#!/bin/bash
# UWS Common Utilities - Shared by all workflow scripts

# Colors
readonly UWS_GREEN='\033[0;32m'
readonly UWS_YELLOW='\033[1;33m'
readonly UWS_RED='\033[0;31m'
readonly UWS_CYAN='\033[0;36m'
readonly UWS_BLUE='\033[0;34m'
readonly UWS_BOLD='\033[1m'
readonly UWS_NC='\033[0m'

# Resolve workflow directory
_uws_resolve_workflow_dir() {
    if [[ -n "${WORKFLOW_DIR:-}" ]]; then
        return 0
    fi
    if [[ -d "$(pwd)/.workflow" ]]; then
        WORKFLOW_DIR="$(pwd)/.workflow"
        return 0
    fi
    if command -v git &>/dev/null; then
        local git_root
        git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
        if [[ -n "$git_root" && -d "${git_root}/.workflow" ]]; then
            WORKFLOW_DIR="${git_root}/.workflow"
            return 0
        fi
    fi
    echo -e "${UWS_RED}ERROR: No .workflow/ directory found.${UWS_NC}" >&2
    echo -e "Run the UWS installer first or cd to your project root." >&2
    return 1
}

# Read a YAML value (simple grep-based, no yq dependency)
_uws_yaml_read() {
    local file="$1" key="$2"
    grep -E "^${key}:" "$file" 2>/dev/null | head -1 | cut -d: -f2- | tr -d ' "' || echo ""
}

# Write a YAML value (simple sed-based)
_uws_yaml_write() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^${key}:" "$file" 2>/dev/null; then
        sed -i.bak "s|^${key}:.*|${key}: \"${value}\"|" "$file"
        rm -f "${file}.bak"
    else
        echo "${key}: \"${value}\"" >> "$file"
    fi
}

# Get current timestamp
_uws_timestamp() {
    date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

# Find array index (-1 if not found)
_uws_array_index() {
    local needle="$1"; shift
    local arr=("$@")
    for i in "${!arr[@]}"; do
        if [[ "${arr[$i]}" == "$needle" ]]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
    return 1
}
SCRIPT_EOF
chmod +x "${UWS_DIR}/scripts/common.sh"

# --- SDLC Script (self-contained) ---
cat > "${UWS_DIR}/scripts/sdlc.sh" << 'SCRIPT_EOF'
#!/bin/bash
#
# UWS SDLC Workflow Manager (Self-Contained)
#
# Usage: .uws/scripts/sdlc.sh [action] [details]
#
# Actions:
#   status  - Show current SDLC phase
#   start   - Begin SDLC at requirements phase
#   next    - Advance to next phase
#   goto    - Jump to a specific phase
#   fail    - Report failure (triggers regression to previous phase)
#   reset   - Reset SDLC state
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# SDLC Phase definitions
SDLC_PHASES=("requirements" "design" "implementation" "verification" "deployment" "maintenance")
SDLC_STATE_KEY="sdlc_phase"

_uws_resolve_workflow_dir || exit 1
STATE_FILE="${WORKFLOW_DIR}/state.yaml"

# Ensure state file exists
if [[ ! -f "$STATE_FILE" ]]; then
    echo -e "${UWS_RED}ERROR: ${STATE_FILE} not found${UWS_NC}"
    exit 1
fi

# Get current SDLC phase from state
get_current_phase() {
    local phase
    phase=$(_uws_yaml_read "$STATE_FILE" "$SDLC_STATE_KEY")
    if [[ -z "$phase" || "$phase" == "null" ]]; then
        echo "not_started"
    else
        echo "$phase"
    fi
}

# Phase emoji
phase_emoji() {
    case "$1" in
        requirements)   echo "📋" ;;
        design)         echo "🏗️" ;;
        implementation) echo "💻" ;;
        verification)   echo "✅" ;;
        deployment)     echo "🚀" ;;
        maintenance)    echo "🔧" ;;
        *)              echo "❓" ;;
    esac
}

cmd_status() {
    local current
    current=$(get_current_phase)
    echo -e "${UWS_BOLD}${UWS_BLUE}═══════════════════════════════════════${UWS_NC}"
    echo -e "${UWS_BOLD}        SDLC Workflow Status${UWS_NC}"
    echo -e "${UWS_BOLD}${UWS_BLUE}═══════════════════════════════════════${UWS_NC}"
    echo ""

    if [[ "$current" == "not_started" ]]; then
        echo -e "  Status: ${UWS_YELLOW}Not started${UWS_NC}"
        echo -e "  Run: ${UWS_CYAN}.uws/scripts/sdlc.sh start${UWS_NC}"
        return 0
    fi

    for phase in "${SDLC_PHASES[@]}"; do
        local emoji
        emoji=$(phase_emoji "$phase")
        if [[ "$phase" == "$current" ]]; then
            echo -e "  ${emoji} ${UWS_GREEN}${UWS_BOLD}${phase}${UWS_NC} ${UWS_GREEN}<-- CURRENT${UWS_NC}"
        else
            local idx current_idx
            idx=$(_uws_array_index "$phase" "${SDLC_PHASES[@]}" || echo "-1")
            current_idx=$(_uws_array_index "$current" "${SDLC_PHASES[@]}" || echo "-1")
            if [[ "$idx" -lt "$current_idx" ]]; then
                echo -e "  ${emoji} ${phase} ${UWS_CYAN}(done)${UWS_NC}"
            else
                echo -e "  ${emoji} ${phase}"
            fi
        fi
    done
    echo ""
}

cmd_start() {
    local current
    current=$(get_current_phase)
    if [[ "$current" != "not_started" ]]; then
        echo -e "${UWS_YELLOW}SDLC already started at phase: ${current}${UWS_NC}"
        echo -e "Use ${UWS_CYAN}reset${UWS_NC} first if you want to restart."
        return 1
    fi
    _uws_yaml_write "$STATE_FILE" "$SDLC_STATE_KEY" "requirements"
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"
    echo -e "${UWS_GREEN}SDLC started at phase: requirements${UWS_NC}"
    echo -e "$(phase_emoji requirements) Gather and document requirements."
}

cmd_next() {
    local current idx next_idx
    current=$(get_current_phase)
    if [[ "$current" == "not_started" ]]; then
        echo -e "${UWS_RED}SDLC not started. Run: .uws/scripts/sdlc.sh start${UWS_NC}"
        return 1
    fi
    idx=$(_uws_array_index "$current" "${SDLC_PHASES[@]}" || true)
    if [[ "$idx" == "-1" ]]; then
        echo -e "${UWS_RED}Unknown current phase: ${current}${UWS_NC}"
        return 1
    fi
    next_idx=$((idx + 1))
    if [[ "$next_idx" -ge "${#SDLC_PHASES[@]}" ]]; then
        echo -e "${UWS_GREEN}SDLC complete! All phases finished.${UWS_NC}"
        echo -e "Current phase remains: ${UWS_BOLD}${current}${UWS_NC}"
        return 0
    fi
    local next_phase="${SDLC_PHASES[$next_idx]}"
    _uws_yaml_write "$STATE_FILE" "$SDLC_STATE_KEY" "$next_phase"
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"
    echo -e "${UWS_GREEN}Advanced: ${current} -> ${next_phase}${UWS_NC}"
    echo -e "$(phase_emoji "$next_phase") Now in ${UWS_BOLD}${next_phase}${UWS_NC} phase."
}

cmd_goto() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        echo -e "${UWS_RED}Usage: .uws/scripts/sdlc.sh goto <phase>${UWS_NC}"
        echo -e "Phases: ${SDLC_PHASES[*]}"
        return 1
    fi
    local idx
    idx=$(_uws_array_index "$target" "${SDLC_PHASES[@]}" || true)
    if [[ "$idx" == "-1" ]]; then
        echo -e "${UWS_RED}Unknown phase: ${target}${UWS_NC}"
        echo -e "Valid phases: ${SDLC_PHASES[*]}"
        return 1
    fi
    local current
    current=$(get_current_phase)
    _uws_yaml_write "$STATE_FILE" "$SDLC_STATE_KEY" "$target"
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"
    echo -e "${UWS_GREEN}Jumped: ${current} -> ${target}${UWS_NC}"
}

cmd_fail() {
    local reason="${1:-unspecified}"
    local current idx
    current=$(get_current_phase)
    if [[ "$current" == "not_started" ]]; then
        echo -e "${UWS_RED}SDLC not started.${UWS_NC}"
        return 1
    fi
    idx=$(_uws_array_index "$current" "${SDLC_PHASES[@]}" || true)
    if [[ "$idx" -le 0 ]]; then
        echo -e "${UWS_YELLOW}Already at first phase. Cannot regress further.${UWS_NC}"
        echo -e "Failure noted: ${reason}"
        return 0
    fi
    local prev_phase="${SDLC_PHASES[$((idx - 1))]}"
    _uws_yaml_write "$STATE_FILE" "$SDLC_STATE_KEY" "$prev_phase"
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"

    # Log failure
    local ts
    ts=$(_uws_timestamp)
    echo "${ts} | SDLC_FAIL | ${current} -> ${prev_phase} | ${reason}" >> "${WORKFLOW_DIR}/checkpoints.log"

    echo -e "${UWS_RED}Failure in ${current}: ${reason}${UWS_NC}"
    echo -e "${UWS_YELLOW}Regressed to: ${prev_phase}${UWS_NC}"
}

cmd_reset() {
    # Remove SDLC phase from state
    if grep -q "^${SDLC_STATE_KEY}:" "$STATE_FILE" 2>/dev/null; then
        sed -i.bak "/^${SDLC_STATE_KEY}:/d" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"
    fi
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"
    echo -e "${UWS_GREEN}SDLC state reset.${UWS_NC}"
}

# Main dispatch
ACTION="${1:-status}"
shift || true

case "$ACTION" in
    status) cmd_status ;;
    start)  cmd_start ;;
    next)   cmd_next ;;
    goto)   cmd_goto "$@" ;;
    fail)   cmd_fail "$*" ;;
    reset)  cmd_reset ;;
    *)
        echo -e "${UWS_RED}Unknown action: ${ACTION}${UWS_NC}"
        echo "Usage: sdlc.sh {status|start|next|goto|fail|reset}"
        exit 1
        ;;
esac
SCRIPT_EOF
chmod +x "${UWS_DIR}/scripts/sdlc.sh"

# --- Research Script (self-contained) ---
cat > "${UWS_DIR}/scripts/research.sh" << 'SCRIPT_EOF'
#!/bin/bash
#
# UWS Research Workflow Manager (Self-Contained)
#
# Usage: .uws/scripts/research.sh [action] [details]
#
# Actions:
#   status  - Show current research phase
#   start   - Begin research at hypothesis phase
#   next    - Advance to next phase
#   goto    - Jump to a specific phase
#   reject  - Hypothesis rejected (triggers refinement)
#   reset   - Reset research state
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Research Phase definitions (Scientific Method)
RESEARCH_PHASES=("hypothesis" "literature_review" "experiment_design" "data_collection" "analysis" "peer_review" "publication")
RESEARCH_STATE_KEY="research_phase"

_uws_resolve_workflow_dir || exit 1
STATE_FILE="${WORKFLOW_DIR}/state.yaml"

if [[ ! -f "$STATE_FILE" ]]; then
    echo -e "${UWS_RED}ERROR: ${STATE_FILE} not found${UWS_NC}"
    exit 1
fi

get_current_phase() {
    local phase
    phase=$(_uws_yaml_read "$STATE_FILE" "$RESEARCH_STATE_KEY")
    if [[ -z "$phase" || "$phase" == "null" ]]; then
        echo "not_started"
    else
        echo "$phase"
    fi
}

phase_emoji() {
    case "$1" in
        hypothesis)        echo "💡" ;;
        literature_review) echo "📚" ;;
        experiment_design) echo "🔬" ;;
        data_collection)   echo "📊" ;;
        analysis)          echo "📈" ;;
        peer_review)       echo "👥" ;;
        publication)       echo "📄" ;;
        *)                 echo "❓" ;;
    esac
}

cmd_status() {
    local current
    current=$(get_current_phase)
    echo -e "${UWS_BOLD}${UWS_BLUE}═══════════════════════════════════════${UWS_NC}"
    echo -e "${UWS_BOLD}      Research Workflow Status${UWS_NC}"
    echo -e "${UWS_BOLD}${UWS_BLUE}═══════════════════════════════════════${UWS_NC}"
    echo ""

    if [[ "$current" == "not_started" ]]; then
        echo -e "  Status: ${UWS_YELLOW}Not started${UWS_NC}"
        echo -e "  Run: ${UWS_CYAN}.uws/scripts/research.sh start${UWS_NC}"
        return 0
    fi

    for phase in "${RESEARCH_PHASES[@]}"; do
        local emoji
        emoji=$(phase_emoji "$phase")
        if [[ "$phase" == "$current" ]]; then
            echo -e "  ${emoji} ${UWS_GREEN}${UWS_BOLD}${phase}${UWS_NC} ${UWS_GREEN}<-- CURRENT${UWS_NC}"
        else
            local idx current_idx
            idx=$(_uws_array_index "$phase" "${RESEARCH_PHASES[@]}" || echo "-1")
            current_idx=$(_uws_array_index "$current" "${RESEARCH_PHASES[@]}" || echo "-1")
            if [[ "$idx" -lt "$current_idx" ]]; then
                echo -e "  ${emoji} ${phase} ${UWS_CYAN}(done)${UWS_NC}"
            else
                echo -e "  ${emoji} ${phase}"
            fi
        fi
    done
    echo ""
}

cmd_start() {
    local current
    current=$(get_current_phase)
    if [[ "$current" != "not_started" ]]; then
        echo -e "${UWS_YELLOW}Research already started at phase: ${current}${UWS_NC}"
        echo -e "Use ${UWS_CYAN}reset${UWS_NC} first if you want to restart."
        return 1
    fi
    _uws_yaml_write "$STATE_FILE" "$RESEARCH_STATE_KEY" "hypothesis"
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"
    echo -e "${UWS_GREEN}Research started at phase: hypothesis${UWS_NC}"
    echo -e "$(phase_emoji hypothesis) Formulate and document your hypothesis."
}

cmd_next() {
    local current idx next_idx
    current=$(get_current_phase)
    if [[ "$current" == "not_started" ]]; then
        echo -e "${UWS_RED}Research not started. Run: .uws/scripts/research.sh start${UWS_NC}"
        return 1
    fi
    idx=$(_uws_array_index "$current" "${RESEARCH_PHASES[@]}" || true)
    if [[ "$idx" == "-1" ]]; then
        echo -e "${UWS_RED}Unknown current phase: ${current}${UWS_NC}"
        return 1
    fi
    next_idx=$((idx + 1))
    if [[ "$next_idx" -ge "${#RESEARCH_PHASES[@]}" ]]; then
        echo -e "${UWS_GREEN}Research complete! All phases finished.${UWS_NC}"
        echo -e "Current phase remains: ${UWS_BOLD}${current}${UWS_NC}"
        return 0
    fi
    local next_phase="${RESEARCH_PHASES[$next_idx]}"
    _uws_yaml_write "$STATE_FILE" "$RESEARCH_STATE_KEY" "$next_phase"
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"
    echo -e "${UWS_GREEN}Advanced: ${current} -> ${next_phase}${UWS_NC}"
    echo -e "$(phase_emoji "$next_phase") Now in ${UWS_BOLD}${next_phase}${UWS_NC} phase."
}

cmd_goto() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        echo -e "${UWS_RED}Usage: .uws/scripts/research.sh goto <phase>${UWS_NC}"
        echo -e "Phases: ${RESEARCH_PHASES[*]}"
        return 1
    fi
    local idx
    idx=$(_uws_array_index "$target" "${RESEARCH_PHASES[@]}" || true)
    if [[ "$idx" == "-1" ]]; then
        echo -e "${UWS_RED}Unknown phase: ${target}${UWS_NC}"
        echo -e "Valid phases: ${RESEARCH_PHASES[*]}"
        return 1
    fi
    local current
    current=$(get_current_phase)
    _uws_yaml_write "$STATE_FILE" "$RESEARCH_STATE_KEY" "$target"
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"
    echo -e "${UWS_GREEN}Jumped: ${current} -> ${target}${UWS_NC}"
}

cmd_reject() {
    local reason="${1:-hypothesis not supported by evidence}"
    local current
    current=$(get_current_phase)
    if [[ "$current" == "not_started" ]]; then
        echo -e "${UWS_RED}Research not started.${UWS_NC}"
        return 1
    fi

    # Rejection sends back to hypothesis for refinement
    _uws_yaml_write "$STATE_FILE" "$RESEARCH_STATE_KEY" "hypothesis"
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"

    local ts
    ts=$(_uws_timestamp)
    echo "${ts} | RESEARCH_REJECT | ${current} -> hypothesis | ${reason}" >> "${WORKFLOW_DIR}/checkpoints.log"

    echo -e "${UWS_RED}Rejected at ${current}: ${reason}${UWS_NC}"
    echo -e "${UWS_YELLOW}Returned to hypothesis phase for refinement.${UWS_NC}"
}

cmd_reset() {
    if grep -q "^${RESEARCH_STATE_KEY}:" "$STATE_FILE" 2>/dev/null; then
        sed -i.bak "/^${RESEARCH_STATE_KEY}:/d" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"
    fi
    _uws_yaml_write "$STATE_FILE" "last_updated" "$(_uws_timestamp)"
    echo -e "${UWS_GREEN}Research state reset.${UWS_NC}"
}

ACTION="${1:-status}"
shift || true

case "$ACTION" in
    status) cmd_status ;;
    start)  cmd_start ;;
    next)   cmd_next ;;
    goto)   cmd_goto "$@" ;;
    reject) cmd_reject "$*" ;;
    reset)  cmd_reset ;;
    *)
        echo -e "${UWS_RED}Unknown action: ${ACTION}${UWS_NC}"
        echo "Usage: research.sh {status|start|next|goto|reject|reset}"
        exit 1
        ;;
esac
SCRIPT_EOF
chmod +x "${UWS_DIR}/scripts/research.sh"

echo -e "  ${GREEN}✓${NC} Workflow scripts created (sdlc.sh, research.sh, common.sh)"

# ============================================================================
# Step 5: Create slash commands
# ============================================================================
echo -e "${BLUE}[5/8]${NC} Creating slash commands..."

mkdir -p "${CLAUDE_DIR}/commands"

# /uws - umbrella help command
cat > "${CLAUDE_DIR}/commands/uws" << 'CMD_EOF'
---
description: "UWS help - list all available commands"
---

# UWS - Universal Workflow System

Show the user the available UWS commands:

## Core Commands
| Command | Description |
|---------|-------------|
| `/uws` | This help menu |
| `/uws-status` | Show current workflow state (phase, checkpoint, activity) |
| `/uws-checkpoint "msg"` | Create a named checkpoint to save progress |
| `/uws-recover` | Full context recovery after a session break |
| `/uws-handoff` | Prepare handoff notes before ending a session |

## Workflow Commands
| Command | Description |
|---------|-------------|
| `/uws-sdlc` | Manage SDLC phases (requirements -> deployment) |
| `/uws-research` | Manage research phases (hypothesis -> publication) |

## Session Workflow
1. **Start**: Context loads automatically when Claude Code opens
2. **During**: Use `/uws-checkpoint "description"` at milestones
3. **End**: Run `/uws-handoff` to save context for next session
4. **Resume**: Run `/uws-recover` if context seems stale

## State Files
- `.workflow/state.yaml` - Machine-readable workflow state
- `.workflow/handoff.md` - Human-readable context (priority actions, blockers)
- `.workflow/checkpoints.log` - Checkpoint history

Present this information clearly to the user.
CMD_EOF

# /uws-status command
cat > "${CLAUDE_DIR}/commands/uws-status" << 'CMD_EOF'
---
description: "Show UWS workflow status"
allowed-tools:
  - "Bash(cat:*)"
  - "Bash(grep:*)"
  - "Bash(tail:*)"
  - "Bash(head:*)"
  - "Bash(./.uws/scripts/*:*)"
---

# UWS Workflow Status

Show the current workflow state including phase, checkpoint, and recent activity.

## Current State
! cat .workflow/state.yaml 2>/dev/null || echo "No state.yaml found"

## Recent Checkpoints
! tail -5 .workflow/checkpoints.log 2>/dev/null | grep -v "^#" || echo "No checkpoints"

## Handoff Summary
! head -30 .workflow/handoff.md 2>/dev/null || echo "No handoff.md found"

Summarize the workflow status concisely.
CMD_EOF

# /uws-checkpoint command
cat > "${CLAUDE_DIR}/commands/uws-checkpoint" << 'CMD_EOF'
---
description: "Create a UWS checkpoint with message"
argument-hint: "<message>"
allowed-tools:
  - "Bash(date:*)"
  - "Bash(grep:*)"
  - "Bash(sed:*)"
  - "Bash(echo:*)"
---

# Create UWS Checkpoint

Create a checkpoint with the message: $ARGUMENTS

Execute this to create the checkpoint:

```bash
# Get current checkpoint info
LAST_CP=$(grep -oE "CP_[0-9]+_[0-9]+" .workflow/checkpoints.log 2>/dev/null | tail -1 || echo "CP_1_000")
PHASE=$(echo "$LAST_CP" | cut -d_ -f2)
SEQ=$(echo "$LAST_CP" | cut -d_ -f3 | sed 's/^0*//')
NEW_SEQ=$(printf "%03d" $((SEQ + 1)))
NEW_CP="CP_${PHASE}_${NEW_SEQ}"
TIMESTAMP=$(date -Iseconds)

# Create checkpoint entry
echo "${TIMESTAMP} | ${NEW_CP} | $ARGUMENTS" >> .workflow/checkpoints.log

# Update state.yaml
sed -i "s/current_checkpoint:.*/current_checkpoint: \"${NEW_CP}\"/" .workflow/state.yaml
sed -i "s/last_updated:.*/last_updated: \"${TIMESTAMP}\"/" .workflow/state.yaml

echo "Checkpoint ${NEW_CP} created: $ARGUMENTS"
```

After creating the checkpoint, confirm it was created successfully.
CMD_EOF

# /uws-recover command (git-guarded)
cat > "${CLAUDE_DIR}/commands/uws-recover" << 'CMD_EOF'
---
description: "Recover full UWS context after session break"
allowed-tools:
  - "Bash(cat:*)"
  - "Bash(grep:*)"
  - "Bash(tail:*)"
  - "Bash(head:*)"
  - "Bash(git:*)"
  - "Bash(ls:*)"
---

# UWS Context Recovery

Recover full workflow context after a session break.

## State File
! cat .workflow/state.yaml 2>/dev/null || echo "ERROR: No state.yaml"

## Full Handoff Document
! cat .workflow/handoff.md 2>/dev/null || echo "ERROR: No handoff.md"

## Checkpoint History
! cat .workflow/checkpoints.log 2>/dev/null | grep -v "^#" || echo "No checkpoints"

## Version Control
! if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then echo "Branch: $(git branch --show-current 2>/dev/null)"; git status --short 2>/dev/null | head -20; else echo "Git not available or not a git repository"; fi

Based on this context:
1. Summarize where we left off
2. List the priority next actions
3. Note any blockers or issues
4. Ask if I should continue with the next action
CMD_EOF

# /uws-handoff command
cat > "${CLAUDE_DIR}/commands/uws-handoff" << 'CMD_EOF'
---
description: "Prepare handoff document for session end"
allowed-tools:
  - "Bash(cat:*)"
  - "Bash(date:*)"
  - "Read"
  - "Write"
---

# Prepare UWS Handoff

Update the handoff document (.workflow/handoff.md) with:

1. **Current Status**: What phase/checkpoint we're at
2. **Work Completed This Session**: Summary of what was done
3. **Next Actions**: Prioritized list of what to do next
4. **Blockers**: Any issues preventing progress
5. **Critical Context**: Important decisions or information

Read the current handoff:
! cat .workflow/handoff.md 2>/dev/null || echo "No existing handoff"

Then update it with fresh information from this session. Make sure to:
- Update the timestamp
- Keep it concise but complete
- Focus on actionable next steps
CMD_EOF

# /uws-sdlc command (references bundled script)
cat > "${CLAUDE_DIR}/commands/uws-sdlc" << 'CMD_EOF'
---
description: "Manage SDLC workflow phases"
argument-hint: "<status|start|next|goto|fail|reset> [details]"
allowed-tools:
  - "Bash(./.uws/scripts/sdlc.sh:*)"
---

# UWS SDLC Management

Manage the Software Development Life Cycle.

**Phases**: requirements -> design -> implementation -> verification -> deployment -> maintenance

Run the appropriate command based on the user's request. If no argument given, show status.

Arguments provided: $ARGUMENTS

```bash
./.uws/scripts/sdlc.sh $ARGUMENTS
```

If $ARGUMENTS is empty, run `./.uws/scripts/sdlc.sh status`.
CMD_EOF

# /uws-research command (references bundled script)
cat > "${CLAUDE_DIR}/commands/uws-research" << 'CMD_EOF'
---
description: "Manage Research workflow phases"
argument-hint: "<status|start|next|goto|reject|reset> [details]"
allowed-tools:
  - "Bash(./.uws/scripts/research.sh:*)"
---

# UWS Research Management

Manage the Research Methodology lifecycle (Scientific Method).

**Phases**: hypothesis -> literature_review -> experiment_design -> data_collection -> analysis -> peer_review -> publication

Run the appropriate command based on the user's request. If no argument given, show status.

Arguments provided: $ARGUMENTS

```bash
./.uws/scripts/research.sh $ARGUMENTS
```

If $ARGUMENTS is empty, run `./.uws/scripts/research.sh status`.
CMD_EOF

echo -e "  ${GREEN}✓${NC} Slash commands created (8 commands including /uws help)"

# ============================================================================
# Step 6: Initialize workflow state
# ============================================================================
echo -e "${BLUE}[6/8]${NC} Initializing workflow state..."

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

PROJECT_NAME=$(basename "${PROJECT_DIR}")
TIMESTAMP=$(date -Iseconds)

# Create state.yaml if not exists (Full v2.0 Schema)
if [[ ! -f "${WORKFLOW_DIR}/state.yaml" ]]; then
    cat > "${WORKFLOW_DIR}/state.yaml" << EOF
# UWS Workflow State (Schema v2.0)
# Auto-generated on ${TIMESTAMP}

# Current workflow position
current_phase: "phase_1_planning"
current_checkpoint: "CP_INIT"

# Project metadata
project:
  name: "${PROJECT_NAME}"
  type: "${PROJECT_TYPE}"
  initialized: true
  init_date: "${TIMESTAMP}"

# Active agent tracking
active_agent:
  name: null
  activated_at: null
  status: "inactive"

# Enabled skills
enabled_skills: []

# Phase progress tracking
phases:
  phase_1_planning:
    status: "active"
    progress: 0
    started_at: "${TIMESTAMP}"
  phase_2_implementation:
    status: "pending"
    progress: 0
  phase_3_validation:
    status: "pending"
    progress: 0
  phase_4_delivery:
    status: "pending"
    progress: 0
  phase_5_maintenance:
    status: "pending"
    progress: 0

# System health
health:
  status: "healthy"
  last_check: "${TIMESTAMP}"

# Schema metadata
metadata:
  schema_version: "2.0"
  last_updated: "${TIMESTAMP}"
  created_by: "claude-code-integration"
EOF
    echo -e "  ${GREEN}✓${NC} Created state.yaml (${PROJECT_TYPE} project, schema v2.0)"
else
    echo -e "  ${YELLOW}→${NC} state.yaml already exists, keeping"
fi

# Create checkpoints.log if not exists
if [[ ! -f "${WORKFLOW_DIR}/checkpoints.log" ]]; then
    cat > "${WORKFLOW_DIR}/checkpoints.log" << EOF
# UWS Checkpoint Log
# Format: TIMESTAMP | CHECKPOINT_ID | DESCRIPTION
$(date -Iseconds) | CP_1_001 | UWS initialized with Claude Code integration
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

Project initialized with UWS (Universal Workflow System) for Claude Code.

## Next Actions

- [ ] Define project goals and scope
- [ ] Review existing codebase (if any)
- [ ] Set up development environment

## Blockers

None currently.

## Context

This project uses UWS for maintaining context across Claude Code sessions.

### Quick Commands
- \`/uws\` - Show all available commands
- \`/uws-status\` - Check current workflow state
- \`/uws-checkpoint "message"\` - Create a checkpoint
- \`/uws-recover\` - Full context recovery
- \`/uws-handoff\` - Prepare for session end
EOF
    echo -e "  ${GREEN}✓${NC} Created handoff.md"
else
    echo -e "  ${YELLOW}→${NC} handoff.md already exists, keeping"
fi

# ============================================================================
# Step 7: Configure Claude Code settings (MERGE, not overwrite)
# ============================================================================
echo -e "${BLUE}[7/8]${NC} Configuring Claude Code hooks..."

SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# UWS permissions (only reference scripts that actually exist)
UWS_PERMISSIONS=(
    'Bash(./.uws/hooks/*:*)'
    'Bash(./.uws/scripts/*:*)'
    'Bash(cat .workflow/*:*)'
    'Bash(grep:*)'
    'Bash(tail:*)'
    'Bash(head:*)'
    'Bash(date:*)'
    'Bash(sed:*)'
    'Bash(git:*)'
)

# UWS hooks
UWS_HOOKS_JSON='[
    {
      "event": "SessionStart",
      "type": "command",
      "command": "./.uws/hooks/session_start.sh"
    },
    {
      "event": "PreCompact",
      "type": "command",
      "command": "./.uws/hooks/pre_compact.sh"
    }
  ]'

if [[ -f "$SETTINGS_FILE" ]]; then
    # Backup existing
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%s)"
    echo -e "  ${YELLOW}→${NC} Backed up existing settings.json"

    if command -v jq &>/dev/null; then
        # Smart merge with jq
        TEMP_SETTINGS=$(mktemp)

        # Build permissions array for jq
        PERM_JSON="["
        for i in "${!UWS_PERMISSIONS[@]}"; do
            [[ $i -gt 0 ]] && PERM_JSON+=","
            PERM_JSON+="\"${UWS_PERMISSIONS[$i]}\""
        done
        PERM_JSON+="]"

        # Merge: add UWS permissions (deduplicated), remove stale v1.1.0 perms, refresh hooks
        jq --argjson uws_perms "$PERM_JSON" \
           --argjson uws_hooks "$UWS_HOOKS_JSON" '
          # Remove stale v1.1.0 permissions that reference non-existent ./scripts/*.sh
          .permissions.allow = ([(.permissions.allow // [])[] |
            select(test("^Bash\\(\\./scripts/") | not)] + $uws_perms | unique) |
          # Remove any old hooks pointing to .uws/ then add fresh ones
          .hooks = ([(.hooks // [])[] | select(.command | test("^\\./.uws/") | not)] + $uws_hooks)
        ' "$SETTINGS_FILE" > "$TEMP_SETTINGS"

        if jq empty "$TEMP_SETTINGS" 2>/dev/null; then
            mv "$TEMP_SETTINGS" "$SETTINGS_FILE"
            echo -e "  ${GREEN}✓${NC} Merged UWS config into existing settings.json (jq)"
        else
            echo -e "  ${RED}ERROR: Merge produced invalid JSON. Restoring backup.${NC}"
            cp "${SETTINGS_FILE}.backup."* "$SETTINGS_FILE" 2>/dev/null
            rm -f "$TEMP_SETTINGS"
        fi
    else
        # No jq available - check if file has UWS hooks already
        if grep -q ".uws/hooks" "$SETTINGS_FILE" 2>/dev/null; then
            echo -e "  ${YELLOW}→${NC} UWS hooks already present in settings.json, keeping"
        else
            # Simple fallback: warn user to merge manually
            echo -e "  ${YELLOW}!${NC} Existing settings.json found but jq not available for smart merge."
            echo -e "  ${YELLOW}!${NC} Creating settings.json.uws with UWS config."
            echo -e "  ${YELLOW}!${NC} Please merge manually or install jq: ${BOLD}sudo apt install jq${NC}"

            cat > "${SETTINGS_FILE}.uws" << SETTINGS_EOF
{
  "_comment": "Merge these into your existing .claude/settings.json",
  "permissions": {
    "allow": [
      "Bash(./.uws/hooks/*:*)",
      "Bash(./.uws/scripts/*:*)",
      "Bash(cat .workflow/*:*)",
      "Bash(grep:*)",
      "Bash(tail:*)",
      "Bash(head:*)",
      "Bash(date:*)",
      "Bash(sed:*)",
      "Bash(git:*)"
    ]
  },
  "hooks": ${UWS_HOOKS_JSON}
}
SETTINGS_EOF
        fi
    fi
else
    # No existing settings - create fresh
    cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "permissions": {
    "allow": [
      "Bash(./.uws/hooks/*:*)",
      "Bash(./.uws/scripts/*:*)",
      "Bash(cat .workflow/*:*)",
      "Bash(grep:*)",
      "Bash(tail:*)",
      "Bash(head:*)",
      "Bash(date:*)",
      "Bash(sed:*)",
      "Bash(git:*)"
    ]
  },
  "hooks": [
    {
      "event": "SessionStart",
      "type": "command",
      "command": "./.uws/hooks/session_start.sh"
    },
    {
      "event": "PreCompact",
      "type": "command",
      "command": "./.uws/hooks/pre_compact.sh"
    }
  ]
}
SETTINGS_EOF
    echo -e "  ${GREEN}✓${NC} Created settings.json with UWS hooks"
fi

# ============================================================================
# Step 8: Update CLAUDE.md
# ============================================================================
echo -e "${BLUE}[8/8]${NC} Updating CLAUDE.md..."

UWS_SECTION='
<!-- UWS-BEGIN -->
## UWS Workflow System

This project uses UWS (Universal Workflow System) for context persistence across sessions.

### Commands
- `/uws` - Show all available UWS commands
- `/uws-status` - Show current workflow state
- `/uws-checkpoint "msg"` - Create checkpoint
- `/uws-recover` - Full context recovery after break
- `/uws-handoff` - Prepare handoff before ending session
- `/uws-sdlc <action>` - Manage SDLC phases (status/start/next/goto/fail/reset)
- `/uws-research <action>` - Manage research phases (status/start/next/goto/reject/reset)

### Workflow Files
- `.workflow/state.yaml` - Current phase and checkpoint
- `.workflow/handoff.md` - Human-readable context (READ THIS ON SESSION START)
- `.workflow/checkpoints.log` - Checkpoint history

### Session Workflow
1. **Start**: Context is automatically loaded via SessionStart hook
2. **During**: Create checkpoints at milestones with `/uws-checkpoint`
3. **End**: Run `/uws-handoff` to update context for next session

### Auto-Checkpoint
UWS automatically creates checkpoints before context compaction to prevent state loss.
<!-- UWS-END -->
'

if [[ -f "CLAUDE.md" ]]; then
    if grep -q "<!-- UWS-BEGIN -->" "CLAUDE.md"; then
        sed -i '/<!-- UWS-BEGIN -->/,/<!-- UWS-END -->/d' "CLAUDE.md"
    fi
    echo "$UWS_SECTION" >> "CLAUDE.md"
    echo -e "  ${GREEN}✓${NC} Updated existing CLAUDE.md"
else
    cat > "CLAUDE.md" << EOF
# CLAUDE.md

Project-specific instructions for Claude Code.
${UWS_SECTION}
EOF
    echo -e "  ${GREEN}✓${NC} Created CLAUDE.md with UWS section"
fi

# Save version
echo "$UWS_VERSION" > "${UWS_DIR}/version"

# ============================================================================
# Auto-add .uws/ to .gitignore if git is initialized
# ============================================================================
if [[ "$HAS_GIT" == true ]]; then
    if [[ -f ".gitignore" ]]; then
        if ! grep -qF ".uws/" ".gitignore" 2>/dev/null; then
            echo "" >> ".gitignore"
            echo "# UWS internal hooks (session-specific)" >> ".gitignore"
            echo ".uws/" >> ".gitignore"
            echo -e "  ${GREEN}✓${NC} Added .uws/ to existing .gitignore"
        fi
    else
        cat > ".gitignore" << 'EOF'
# UWS internal hooks (session-specific)
.uws/

# Claude Code project config
.claude/
EOF
        echo -e "  ${GREEN}✓${NC} Created .gitignore with .uws/ and .claude/ excluded"
    fi
fi

# ============================================================================
# Done!
# ============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              UWS Installation Complete!                       ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Files created:${NC}"
echo "  .uws/hooks/session_start.sh    - Context injection hook"
echo "  .uws/hooks/pre_compact.sh      - Auto-checkpoint hook"
echo "  .uws/scripts/common.sh         - Shared utilities"
echo "  .uws/scripts/sdlc.sh           - SDLC workflow manager"
echo "  .uws/scripts/research.sh       - Research workflow manager"
echo "  .claude/commands/uws*           - Slash commands (8 total)"
echo "  .claude/settings.json           - Hook configuration"
echo "  .workflow/state.yaml            - Workflow state"
echo "  .workflow/handoff.md            - Context handoff"
echo "  .workflow/checkpoints.log       - Checkpoint history"
if [[ "$HAS_GIT" == true ]]; then
echo "  .gitignore                      - Updated with .uws/ exclusion"
fi
echo ""
echo -e "${CYAN}Quick start:${NC}"
echo -e "  1. Open project in Claude Code: ${BOLD}claude${NC}"
echo -e "  2. Context loads automatically on session start"
echo -e "  3. Use ${BOLD}/uws${NC} to see all available commands"
echo -e "  4. Use ${BOLD}/uws-status${NC} to see current state"
echo -e "  5. Use ${BOLD}/uws-checkpoint \"message\"${NC} to save progress"
echo ""
if [[ "$HAS_GIT" == true ]]; then
echo -e "${YELLOW}Tip:${NC} Commit .workflow/ to preserve state across clones"
echo -e "     ${CYAN}git add .workflow/ CLAUDE.md && git commit -m 'Add UWS workflow'${NC}"
fi
echo ""
