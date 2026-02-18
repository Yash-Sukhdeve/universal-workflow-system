#!/bin/bash
#
# Project Resolution Library
# Resolves WORKFLOW_DIR to the correct .workflow/ for the CALLING project.
#
# Resolution order:
#   1. WORKFLOW_DIR env var (if already set)
#   2. CWD/.workflow (if exists)
#   3. Git repo root/.workflow (if in a git repo)
#   4. SCRIPT_DIR/../.workflow (UWS's own .workflow — last resort)
#
# Also exports UWS_SCRIPTS_DIR so scripts can find each other.

# Guard against double-sourcing
if [[ "${_RESOLVE_PROJECT_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_RESOLVE_PROJECT_LOADED="true"

# Always know where UWS scripts live
UWS_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_resolve_workflow_dir() {
    # 1. Explicit env var takes priority
    if [[ -n "${WORKFLOW_DIR:-}" ]]; then
        return 0
    fi

    # 2. CWD has a .workflow/
    if [[ -d "$(pwd)/.workflow" ]]; then
        WORKFLOW_DIR="$(pwd)/.workflow"
        return 0
    fi

    # 3. Git repo root has a .workflow/
    local git_root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
    if [[ -n "$git_root" && -d "${git_root}/.workflow" ]]; then
        WORKFLOW_DIR="${git_root}/.workflow"
        return 0
    fi

    # 4. Fallback: UWS's own .workflow/
    WORKFLOW_DIR="${UWS_SCRIPTS_DIR}/../.workflow"
}

_resolve_workflow_dir

# Derived paths used by many scripts
STATE_FILE="${WORKFLOW_DIR}/state.yaml"

export WORKFLOW_DIR STATE_FILE UWS_SCRIPTS_DIR
