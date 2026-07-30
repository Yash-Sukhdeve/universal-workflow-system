#!/bin/bash
#
# Workflow Routing Library - Centralizes methodology/agent/phase routing
#
# Fixes: #1 (subsystem communication), #7 (agent defaults), #8 (transition validation)
#
# Usage: source this via source_lib "workflow_routing.sh"

# Guard against double-sourcing
if [[ "${_WORKFLOW_ROUTING_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_WORKFLOW_ROUTING_LOADED="true"

# Resolve paths — use WORKFLOW_DIR from resolve_project.sh if already set
_WR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${WORKFLOW_DIR:-}" ]]; then
    source "${_WR_SCRIPT_DIR}/lib/resolve_project.sh"
fi
_WR_WORKFLOW_DIR="${WORKFLOW_DIR}"

#######################################
# Map project type to active methodology
# Arguments: $1 - project type (from config/state)
# Returns: "research" | "sdlc" | "both"
#######################################
get_active_methodology() {
    local project_type="${1:-hybrid}"

    case "$project_type" in
        research)       echo "research" ;;
        ml|llm)         echo "both" ;;
        software)       echo "sdlc" ;;
        deployment)     echo "sdlc" ;;
        optimization)   echo "sdlc" ;;
        hybrid|*)       echo "both" ;;
    esac
}

#######################################
# Map methodology + phase to the right agent
# Arguments: $1 - methodology ("research"|"sdlc")
#            $2 - phase name
# Returns: agent name
#######################################
get_agent_for_phase() {
    local methodology="$1"
    local phase="$2"

    if [[ "$methodology" == "research" ]]; then
        case "$phase" in
            hypothesis)         echo "researcher" ;;
            literature_review)  echo "researcher" ;;
            experiment_design)  echo "researcher" ;;
            data_collection)    echo "experimenter" ;;
            analysis)           echo "experimenter" ;;
            peer_review)        echo "researcher" ;;
            publication)        echo "documenter" ;;
            *)                  echo "researcher" ;;
        esac
    elif [[ "$methodology" == "sdlc" ]]; then
        case "$phase" in
            requirements)       echo "researcher" ;;
            design)             echo "architect" ;;
            implementation)     echo "implementer" ;;
            verification)       echo "experimenter" ;;
            deployment)         echo "deployer" ;;
            maintenance)        echo "deployer" ;;
            *)                  echo "architect" ;;
        esac
    else
        echo "researcher"
    fi
}

#######################################
# Get default agent for project type
# Reads agents.default_agent from config.yaml, falls back to type-based default
# Arguments: $1 - project type
# Returns: agent name
#######################################
get_default_agent() {
    local project_type="${1:-hybrid}"
    local config_file="${_WR_WORKFLOW_DIR}/config.yaml"

    # Try config.yaml first
    if [[ -f "$config_file" ]]; then
        local configured
        configured=$(grep "default_agent:" "$config_file" 2>/dev/null | head -1 | sed 's/.*default_agent: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | xargs)
        if [[ -n "$configured" && "$configured" != "null" ]]; then
            echo "$configured"
            return 0
        fi
    fi

    # Fallback based on project type
    case "$project_type" in
        research)       echo "researcher" ;;
        ml|llm)         echo "researcher" ;;
        software)       echo "architect" ;;
        deployment)     echo "deployer" ;;
        optimization)   echo "optimizer" ;;
        hybrid|*)       echo "architect" ;;
    esac
}

#######################################
# Validate agent transition against registry rules
# Arguments: $1 - from agent, $2 - to agent
# Returns: 0 if valid, 1 if invalid (prints warning)
#######################################
validate_agent_transition() {
    local from_agent="$1"
    local to_agent="$2"
    local registry="${_WR_WORKFLOW_DIR}/agents/registry.yaml"

    # Same agent is always valid
    [[ "$from_agent" == "$to_agent" ]] && return 0

    # No registry = allow all
    [[ ! -f "$registry" ]] && return 0

    # Check wildcard rules (any agent -> documenter)
    if grep -q "from: \"\*\"" "$registry" 2>/dev/null; then
        local wildcard_targets
        wildcard_targets=$(sed -n '/from: "\*"/,/condition:/{ /to:/{ s/.*to: \[//; s/\].*//; p; } }' "$registry" 2>/dev/null)
        if echo "$wildcard_targets" | grep -q "$to_agent" 2>/dev/null; then
            return 0
        fi
    fi

    # Check specific transition rules
    local allowed_targets
    allowed_targets=$(sed -n "/from: ${from_agent}/,/condition:/{ /to:/{ s/.*to: \[//; s/\].*//; p; } }" "$registry" 2>/dev/null)

    if [[ -z "$allowed_targets" ]]; then
        # No rule found for this agent = allow (open-world assumption)
        return 0
    fi

    if echo "$allowed_targets" | grep -q "$to_agent" 2>/dev/null; then
        return 0
    fi

    # Transition not in rules
    return 1
}

#######################################
# Check if a methodology is valid for the current project type
# Arguments: $1 - methodology ("research"|"sdlc")
# Returns: 0 if active, 1 if not
#######################################
is_methodology_active() {
    local methodology="$1"
    local state_file="${_WR_WORKFLOW_DIR}/state.yaml"

    # Read project type
    local project_type="hybrid"
    if [[ -f "$state_file" ]]; then
        project_type=$(grep "^  type:" "$state_file" 2>/dev/null | head -1 | sed 's/.*type: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | xargs)
        [[ -z "$project_type" ]] && project_type="hybrid"
    fi

    local active
    active=$(get_active_methodology "$project_type")

    [[ "$active" == "$methodology" || "$active" == "both" ]]
}

#######################################
# --- Milestone 1: phase-sync + goal-driven-phase helpers ---
# All helpers below are guarded for `set -euo pipefail` callers.
#######################################

# Canonical UWS meta-phase order (5 phases).
_UWS_PHASES=(phase_1_planning phase_2_implementation phase_3_validation phase_4_delivery phase_5_maintenance)

# Resolve the active state file path.
_wr_state_file() {
    echo "${STATE_FILE:-${_WR_WORKFLOW_DIR}/state.yaml}"
}

#######################################
# Map a methodology phase to the UWS meta-phase (current_phase).
# Collapses 6 SDLC / 7 research phases into the 5 UWS phases that
# generate_checkpoint_id() and status.sh already understand.
# Arguments: $1 - methodology ("sdlc"|"research"), $2 - phase
# Returns (echo): phase_1_planning .. phase_5_maintenance
#######################################
uws_phase_for_methodology() {
    local methodology="$1"
    local phase="$2"

    if [[ "$methodology" == "sdlc" ]]; then
        case "$phase" in
            requirements|design)   echo "phase_1_planning" ;;
            implementation)        echo "phase_2_implementation" ;;
            verification)          echo "phase_3_validation" ;;
            deployment)            echo "phase_4_delivery" ;;
            maintenance)           echo "phase_5_maintenance" ;;
            *)                     echo "phase_1_planning" ;;
        esac
    elif [[ "$methodology" == "research" ]]; then
        case "$phase" in
            hypothesis|literature_review|experiment_design) echo "phase_1_planning" ;;
            data_collection)       echo "phase_2_implementation" ;;
            analysis)              echo "phase_3_validation" ;;
            peer_review)           echo "phase_4_delivery" ;;
            publication)           echo "phase_5_maintenance" ;;
            *)                     echo "phase_1_planning" ;;
        esac
    else
        echo "phase_1_planning"
    fi
}

#######################################
# Read phases.<phase>.status from state.yaml (block style: 2-space phase
# key, 4-space status). Mirrors the reader in status.sh so both stay in sync.
# Arguments: $1 - phase name, $2 - (optional) file
# Returns (echo): status string, or "pending" if absent
#######################################
get_phase_status() {
    local phase="$1"
    local file="${2:-$(_wr_state_file)}"
    local status=""
    [[ -f "$file" ]] || { echo "pending"; return 0; }
    status=$(sed -n "/^  ${phase}:/,/^  [^ ]/{ s/^    status:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}.*/\1/p; }" "$file" 2>/dev/null | head -1 || true)
    status=$(printf '%s' "$status" | tr -d '[:space:]')
    [[ -z "$status" ]] && status="pending"
    echo "$status"
}

#######################################
# Set phases.<phase>.status. Assumes the phases block + phase key exist
# (created by init_workflow.sh / migrate_state.sh). Replaces only the
# status line within this phase's block range.
# Arguments: $1 - phase, $2 - status, $3 - (optional) file
#######################################
set_phase_status() {
    local phase="$1"
    local status="$2"
    local file="${3:-$(_wr_state_file)}"
    [[ -f "$file" ]] || return 0
    sed -i "/^  ${phase}:/,/^  [^ ]/ s|^    status:.*|    status: \"${status}\"|" "$file" 2>/dev/null || true
}

#######################################
# Sync current_phase (top-level scalar) AND the phases: board to a target
# UWS phase. Marks earlier phases completed, the target active, later pending.
# Arguments: $1 - uws phase (phase_N_...), $2 - (optional) file
#######################################
set_uws_phase() {
    local target="$1"
    local file="${2:-$(_wr_state_file)}"
    [[ -f "$file" ]] || return 0

    # Top-level scalar: yaml_set handles quoting; fall back to sed.
    if declare -f yaml_set >/dev/null 2>&1 && yaml_set "$file" "current_phase" "$target" >/dev/null 2>&1; then
        :
    else
        sed -i "s|^current_phase:.*|current_phase: \"${target}\"|" "$file" 2>/dev/null || true
    fi

    # Update the board only if a phases: block exists.
    grep -q "^phases:" "$file" 2>/dev/null || return 0

    local target_num="${target#phase_}"; target_num="${target_num%%_*}"
    [[ "$target_num" =~ ^[1-5]$ ]] || return 0

    local i=1 name st
    for name in "${_UWS_PHASES[@]}"; do
        if   (( i <  target_num )); then st="completed"
        elif (( i == target_num )); then st="active"
        else                             st="pending"
        fi
        set_phase_status "$name" "$st" "$file"
        i=$(( i + 1 ))
    done
}

#######################################
# Deliverable ledger — single-line flow entries under methodology_progress:
#   methodology_progress:
#     <m>_<phase>: {total: N, done: [i, j]}
# Chosen over deep nesting because `yq` is absent and single-line entries
# are safe to edit with sed and never collide with the phases: reader.
#######################################
_mp_key() { echo "${1}_${2}"; }

# Ensure an entry exists. Args: methodology, phase, total, [file]
mp_ensure() {
    local m="$1" phase="$2" total="$3" file="${4:-$(_wr_state_file)}"
    local key; key="$(_mp_key "$m" "$phase")"
    [[ -f "$file" ]] || return 0
    grep -q "^  ${key}:" "$file" 2>/dev/null && return 0
    grep -q "^methodology_progress:" "$file" 2>/dev/null || printf 'methodology_progress:\n' >> "$file"
    sed -i "/^methodology_progress:/a\\  ${key}: {total: ${total}, done: []}" "$file" 2>/dev/null || \
        printf '  %s: {total: %s, done: []}\n' "$key" "$total" >> "$file"
}

# Echo the inner done list (e.g. "1, 3") or empty. Args: m, phase, [file]
_mp_done_inner() {
    local key; key="$(_mp_key "$1" "$2")"
    local file="${3:-$(_wr_state_file)}"
    local line
    line=$(grep "^  ${key}:" "$file" 2>/dev/null | head -1 || true)
    [[ -z "$line" ]] && { echo ""; return 0; }
    printf '%s' "$line" | sed -n 's/.*done:[[:space:]]*\[\([^]]*\)\].*/\1/p'
}

# Echo total. Args: m, phase, [file]
_mp_total() {
    local key; key="$(_mp_key "$1" "$2")"
    local file="${3:-$(_wr_state_file)}"
    local line t
    line=$(grep "^  ${key}:" "$file" 2>/dev/null | head -1 || true)
    [[ -z "$line" ]] && { echo "0"; return 0; }
    t=$(printf '%s' "$line" | sed -n 's/.*total:[[:space:]]*\([0-9]*\).*/\1/p')
    [[ -z "$t" ]] && t=0
    echo "$t"
}

# Count done items. Args: m, phase, [file]
_mp_done_count() {
    local inner; inner="$(_mp_done_inner "$@")"
    inner="$(printf '%s' "$inner" | tr -d '[:space:]')"
    [[ -z "$inner" ]] && { echo 0; return 0; }
    printf '%s' "$inner" | tr ',' '\n' | grep -c '[0-9]' || true
}

# Mark deliverable n done (idempotent). Args: m, phase, n, [file]
mark_deliverable() {
    local m="$1" phase="$2" n="$3" file="${4:-$(_wr_state_file)}"
    local key; key="$(_mp_key "$m" "$phase")"
    [[ -f "$file" ]] || return 1
    grep -q "^  ${key}:" "$file" 2>/dev/null || return 1
    local total inner
    total="$(_mp_total "$m" "$phase" "$file")"
    inner="$(_mp_done_inner "$m" "$phase" "$file")"
    inner="$(printf '%s' "$inner" | tr -d '[:space:]')"
    [[ ",${inner}," == *",${n},"* ]] && return 0
    local newinner
    if [[ -z "$inner" ]]; then newinner="$n"; else newinner="${inner}, ${n}"; fi
    sed -i "s|^  ${key}:.*|  ${key}: {total: ${total}, done: [${newinner}]}|" "$file" 2>/dev/null || true
}

# Remaining unmet count. Args: m, phase, [file]  -> echoes an integer
deliverables_remaining() {
    local total done rem
    total="$(_mp_total "$@")"
    done="$(_mp_done_count "$@")"
    rem=$(( total - done ))
    (( rem < 0 )) && rem=0
    echo "$rem"
}

#######################################
# Refresh the handoff.md "Last Session Summary" header in place, leaving the
# appended transition log intact.
# Arguments: $1 - phase, $2 - checkpoint, $3 - working_on, $4 - (optional) file
#######################################
refresh_handoff_header() {
    local phase="$1" checkpoint="$2" working_on="$3"
    local file="${4:-${_WR_WORKFLOW_DIR}/handoff.md}"
    [[ -f "$file" ]] || return 0
    local ts
    ts=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    awk -v ts="$ts" -v ph="$phase" -v cp="$checkpoint" -v wo="$working_on" '
        BEGIN { in_summary = 0 }
        /^## Last Session Summary/ {
            print
            print "- **Date**: " ts
            print "- **Phase**: " ph
            print "- **Checkpoint**: " cp
            print "- **Working on**: " wo
            in_summary = 1
            next
        }
        in_summary == 1 {
            if ($0 ~ /^## /) { in_summary = 0; print; next }
            next
        }
        { print }
    ' "$file" > "${file}.tmp" 2>/dev/null && mv "${file}.tmp" "$file" || rm -f "${file}.tmp"
}

#######################################
# Whether the deliverable gate is active. Goal-driven mode: the hard gate
# turns on only once a non-empty goal is declared. With no goal, phases are
# plain position labels and `next`/`goto` advance freely.
# Arguments: $1 - (optional) file
#######################################
gate_enabled() {
    local file="${1:-$(_wr_state_file)}"
    local g=""
    if declare -f yaml_get >/dev/null 2>&1; then
        g=$(yaml_get "$file" "goal" 2>/dev/null || echo "")
    else
        g=$(grep '^goal:' "$file" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/"//g' | xargs || true)
    fi
    [[ -n "$g" && "$g" != "null" ]]
}

#######################################
# One-shot sync on a methodology phase change: advance current_phase + the
# board, seed the deliverable ledger, and refresh the handoff header.
# Called from sdlc.sh / research.sh set_phase().
# Arguments: $1 - methodology, $2 - phase, $3 - total deliverables, $4 - (opt) file
#######################################
sync_meta_phase() {
    local m="$1" phase="$2" total="$3" file="${4:-$(_wr_state_file)}"
    local uws; uws="$(uws_phase_for_methodology "$m" "$phase")"
    set_uws_phase "$uws" "$file"
    mp_ensure "$m" "$phase" "${total:-0}" "$file"

    local cp="" goal=""
    if declare -f yaml_get >/dev/null 2>&1; then
        cp=$(yaml_get "$file" "current_checkpoint" 2>/dev/null || echo "")
        goal=$(yaml_get "$file" "goal" 2>/dev/null || echo "")
    fi
    [[ "$cp" == "null" ]] && cp=""
    [[ "$goal" == "null" || -z "$goal" ]] && goal="$phase"
    refresh_handoff_header "$phase" "$cp" "$goal"
}
