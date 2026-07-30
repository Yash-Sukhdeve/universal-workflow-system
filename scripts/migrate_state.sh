#!/bin/bash
#
# Universal Workflow System - State Migration (Milestone 1)
#
# Brings an existing .workflow/state.yaml up to the goal-driven-phase schema:
#   - adds a top-level `goal:` (if absent)
#   - adds the `phases:` board (5 UWS phases) (if absent)
#   - adds a `methodology_progress:` header (if absent)
#   - reconciles `current_phase` to match the active methodology phase
#     (fixes the historical desync where current_phase was stuck at phase_1)
#   - refreshes the handoff.md header so recovery is honest
#   - (--clean) prunes bogus/unknown skills from enabled.yaml
#
# Idempotent and backup-first: safe to run repeatedly.
#
# Usage: ./scripts/migrate_state.sh [--clean] [state_file]
#
# RWF Compliance: R3 (State Safety), R5 (Reproducibility)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

source "${SCRIPT_LIB_DIR}/resolve_project.sh"
YAML_UTILS_QUIET=true source "${SCRIPT_LIB_DIR}/yaml_utils.sh" 2>/dev/null || true
YAML_UTILS_QUIET=true source "${SCRIPT_LIB_DIR}/workflow_routing.sh" 2>/dev/null || true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

CLEAN=false
STATE=""
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=true ;;
        *)       STATE="$arg" ;;
    esac
done
STATE="${STATE:-${STATE_FILE:-${WORKFLOW_DIR}/state.yaml}}"

if [[ ! -f "$STATE" ]]; then
    echo -e "${RED}Error: state file not found: ${STATE}${NC}" >&2
    exit 1
fi

# --- Backup first (consistent with the repo's .workflow.backup.* convention) ---
ts="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo manual)"
backup="${STATE}.bak-${ts}"
cp "$STATE" "$backup"
echo -e "${CYAN}Backup:${NC} ${backup}"

changed=false

# --- 1. goal: (top-level) ---
if ! grep -q '^goal:' "$STATE"; then
    if grep -q '^project_type:' "$STATE"; then
        sed -i '/^project_type:/a goal: ""' "$STATE"
    else
        printf 'goal: ""\n' >> "$STATE"
    fi
    changed=true
    echo -e "  ${GREEN}+${NC} added goal:"
fi

# --- 2. phases: board ---
if ! grep -q '^phases:' "$STATE"; then
    cat >> "$STATE" << 'EOF'

phases:
  phase_1_planning:
    status: "pending"
  phase_2_implementation:
    status: "pending"
  phase_3_validation:
    status: "pending"
  phase_4_delivery:
    status: "pending"
  phase_5_maintenance:
    status: "pending"
EOF
    changed=true
    echo -e "  ${GREEN}+${NC} added phases: board"
fi

# --- 3. methodology_progress: header ---
if ! grep -q '^methodology_progress:' "$STATE"; then
    printf '\nmethodology_progress:\n' >> "$STATE"
    changed=true
    echo -e "  ${GREEN}+${NC} added methodology_progress:"
fi

# --- 4. Reconcile current_phase to the active methodology phase ---
sdlc_phase="$(grep '^sdlc_phase:' "$STATE" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/"//g' | xargs || true)"
research_phase="$(grep '^research_phase:' "$STATE" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/"//g' | xargs || true)"

methodology=""; mphase=""
if [[ -n "$sdlc_phase" && "$sdlc_phase" != "null" ]]; then
    methodology="sdlc"; mphase="$sdlc_phase"
elif [[ -n "$research_phase" && "$research_phase" != "null" ]]; then
    methodology="research"; mphase="$research_phase"
fi

if [[ -n "$methodology" ]] && declare -f uws_phase_for_methodology >/dev/null 2>&1; then
    uws="$(uws_phase_for_methodology "$methodology" "$mphase")"
    old_cp="$(grep '^current_phase:' "$STATE" | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/"//g' | xargs || true)"
    set_uws_phase "$uws" "$STATE"
    echo -e "  ${GREEN}~${NC} current_phase reconciled: ${old_cp:-none} -> ${uws} (from ${methodology}:${mphase})"
    changed=true

    # Refresh the handoff header so recovery no longer reports stale 'Initial setup'
    if declare -f refresh_handoff_header >/dev/null 2>&1; then
        cp_id="$(grep '^current_checkpoint:' "$STATE" | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/"//g' | xargs || true)"
        goal_txt="$(grep '^goal:' "$STATE" | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/"//g' | xargs || true)"
        [[ -z "$goal_txt" ]] && goal_txt="$methodology:$mphase"
        refresh_handoff_header "$uws" "${cp_id}" "$goal_txt"
    fi
else
    echo -e "  ${YELLOW}i${NC} no active methodology phase found; current_phase left as-is"
fi

# --- 5. (--clean) prune unknown/bogus enabled skills ---
if [[ "$CLEAN" == "true" ]]; then
    enabled="${WORKFLOW_DIR}/skills/enabled.yaml"
    catalog="${WORKFLOW_DIR}/skills/catalog.yaml"
    if [[ -f "$enabled" && -f "$catalog" ]]; then
        while IFS= read -r skill; do
            [[ -z "$skill" ]] && continue
            if ! grep -qE "^  ${skill}:" "$catalog"; then
                sed -i "/^  - ${skill}\$/d" "$enabled"
                echo -e "  ${YELLOW}-${NC} pruned unknown enabled skill: ${skill}"
                changed=true
            fi
        done < <(grep '^  - ' "$enabled" 2>/dev/null | sed 's/^  - //' || true)
    fi
fi

if [[ "$changed" == "true" ]]; then
    echo -e "${GREEN}✓ Migration complete.${NC} (backup: ${backup})"
else
    echo -e "${GREEN}✓ Already up to date.${NC} No changes needed. (backup: ${backup})"
fi
