#!/bin/bash
# Vector Memory Setup Library
# Handles installation and configuration of vector-memory-mcp server.
# Can be sourced by init_workflow.sh / install.sh or run standalone.

# Double-source guard
if [[ "${_VECTOR_MEMORY_SETUP_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_VECTOR_MEMORY_SETUP_LOADED="true"

set -euo pipefail

# Color codes (guard matching validation_utils.sh:14-19)
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# Source config resolution library
_VMS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_VMS_LIB_DIR}/uws_config.sh" ]]; then
    source "${_VMS_LIB_DIR}/uws_config.sh"
fi

# Constants — resolve via config chain if available, else use defaults
UWS_VECTOR_REPO="https://github.com/cornebidouil/vector-memory-mcp.git"
if declare -f uws_resolve_vector_server_dir &>/dev/null; then
    UWS_VECTOR_INSTALL_DIR="$(uws_resolve_vector_server_dir)"
    UWS_VECTOR_GLOBAL_DIR="$(uws_resolve_global_memory_dir)"
else
    UWS_VECTOR_INSTALL_DIR="${HOME}/.uws/tools/vector-memory"
    UWS_VECTOR_GLOBAL_DIR="${HOME}/uws-global-knowledge"
fi
UWS_VECTOR_PACKAGES="sqlite-vec sentence-transformers fastmcp"
UWS_VECTOR_MIN_DISK_KB=8388608  # 8 GB in KB

#######################################
# Check if Python 3.9+ is available
# Returns:
#   0 if Python 3.9+ found, 1 otherwise
#######################################
uws_vm_check_python() {
    local python_cmd=""

    for cmd in python3 python; do
        if command -v "$cmd" &>/dev/null; then
            python_cmd="$cmd"
            break
        fi
    done

    if [[ -z "$python_cmd" ]]; then
        echo -e "${YELLOW}  Python not found — vector memory requires Python 3.9+${NC}" >&2
        return 1
    fi

    # Check version >= 3.9
    local version
    version="$("$python_cmd" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)" || {
        echo -e "${YELLOW}  Could not determine Python version${NC}" >&2
        return 1
    }

    local major minor
    major="${version%%.*}"
    minor="${version#*.}"

    if (( major < 3 )) || { (( major == 3 )) && (( minor < 9 )); }; then
        echo -e "${YELLOW}  Python ${version} found — vector memory requires 3.9+ ${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Check if sufficient disk space is available
# Returns:
#   0 if >= 8GB free, 1 otherwise
#######################################
uws_vm_check_disk_space() {
    local target_dir="${1:-$HOME}"
    local available_kb

    available_kb="$(df -k "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')" || {
        echo -e "${YELLOW}  Could not check disk space${NC}" >&2
        return 1
    }

    if [[ -z "$available_kb" ]] || ! [[ "$available_kb" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}  Could not parse disk space${NC}" >&2
        return 1
    fi

    if (( available_kb < UWS_VECTOR_MIN_DISK_KB )); then
        local available_gb=$(( available_kb / 1048576 ))
        echo -e "${YELLOW}  Insufficient disk space: ${available_gb}GB available, 8GB recommended${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Check if vector memory is fully installed
# Returns:
#   0 if repo+venv+packages all OK, 1 otherwise
#######################################
uws_vm_is_installed() {
    # Check repo exists
    if [[ ! -d "${UWS_VECTOR_INSTALL_DIR}" ]] || [[ ! -f "${UWS_VECTOR_INSTALL_DIR}/main.py" ]]; then
        return 1
    fi

    # Check venv exists
    local venv_dir="${UWS_VECTOR_INSTALL_DIR}/.venv"
    if [[ ! -d "$venv_dir" ]] || [[ ! -f "$venv_dir/bin/python" ]]; then
        return 1
    fi

    # Check packages importable
    if ! "$venv_dir/bin/python" -c "import sqlite_vec; import sentence_transformers; import fastmcp" 2>/dev/null; then
        return 1
    fi

    return 0
}

#######################################
# Clone or update the vector-memory-mcp repo
# Returns:
#   0 on success, 1 on failure
#######################################
uws_vm_clone_or_update() {
    if [[ -d "${UWS_VECTOR_INSTALL_DIR}" ]] && [[ -d "${UWS_VECTOR_INSTALL_DIR}/.git" ]]; then
        echo -e "  Updating vector-memory-mcp..."
        git -C "${UWS_VECTOR_INSTALL_DIR}" fetch --quiet 2>/dev/null || {
            echo -e "${YELLOW}  Could not fetch updates (network issue?)${NC}" >&2
            return 1
        }
        git -C "${UWS_VECTOR_INSTALL_DIR}" reset --hard origin/HEAD --quiet 2>/dev/null || {
            echo -e "${YELLOW}  Could not reset to latest${NC}" >&2
            return 1
        }
        echo -e "  ${GREEN}✓${NC} Repository updated"
    else
        echo -e "  Cloning vector-memory-mcp..."
        mkdir -p "$(dirname "${UWS_VECTOR_INSTALL_DIR}")"
        git clone --quiet "${UWS_VECTOR_REPO}" "${UWS_VECTOR_INSTALL_DIR}" 2>/dev/null || {
            echo -e "${YELLOW}  Could not clone repository (network issue?)${NC}" >&2
            return 1
        }
        echo -e "  ${GREEN}✓${NC} Repository cloned"
    fi

    return 0
}

#######################################
# Create and populate the Python venv
# On pip failure, deletes incomplete venv and returns 1
# Returns:
#   0 on success, 1 on failure
#######################################
uws_vm_setup_venv() {
    local venv_dir="${UWS_VECTOR_INSTALL_DIR}/.venv"

    if [[ -d "$venv_dir" ]] && [[ -f "$venv_dir/bin/python" ]]; then
        # Venv exists — check if packages are already installed
        if "$venv_dir/bin/python" -c "import sqlite_vec; import sentence_transformers; import fastmcp" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Virtual environment already configured"
            return 0
        fi
    fi

    echo -e "  Creating virtual environment..."

    # Find system python
    local python_cmd=""
    for cmd in python3 python; do
        if command -v "$cmd" &>/dev/null; then
            python_cmd="$cmd"
            break
        fi
    done

    if [[ -z "$python_cmd" ]]; then
        echo -e "${YELLOW}  Python not found${NC}" >&2
        return 1
    fi

    # Create venv
    "$python_cmd" -m venv "$venv_dir" 2>/dev/null || {
        echo -e "${YELLOW}  Failed to create virtual environment${NC}" >&2
        rm -rf "$venv_dir"
        return 1
    }

    # Install packages
    echo -e "  Installing packages (~1.5GB, this may take a few minutes)..."
    # shellcheck disable=SC2086
    "$venv_dir/bin/pip" install --quiet $UWS_VECTOR_PACKAGES 2>/dev/null || {
        echo -e "${YELLOW}  pip install failed — removing incomplete venv${NC}" >&2
        rm -rf "$venv_dir"
        return 1
    }

    echo -e "  ${GREEN}✓${NC} Virtual environment created and packages installed"
    return 0
}

#######################################
# Create the global knowledge directory
# Returns:
#   0 on success, 1 on failure
#######################################
uws_vm_create_global_dir() {
    if [[ -d "${UWS_VECTOR_GLOBAL_DIR}" ]]; then
        return 0
    fi

    # Validate path has no dot-prefixed components (security.py rejects them)
    if declare -f uws_validate_global_dir_path &>/dev/null; then
        if ! uws_validate_global_dir_path "${UWS_VECTOR_GLOBAL_DIR}"; then
            echo -e "${YELLOW}  Global dir path rejected: ${UWS_VECTOR_GLOBAL_DIR}${NC}" >&2
            return 1
        fi
    fi

    mkdir -p "${UWS_VECTOR_GLOBAL_DIR}" || {
        echo -e "${YELLOW}  Could not create ${UWS_VECTOR_GLOBAL_DIR}${NC}" >&2
        return 1
    }
    echo -e "  ${GREEN}✓${NC} Global knowledge directory created"
    return 0
}

#######################################
# Configure .mcp.json with vector memory server entries
# Uses Python with sys.argv[] for safe JSON manipulation (no injection)
# Arguments:
#   $1 - project root directory
# Returns:
#   0 on success, 1 on failure
#######################################
uws_vm_configure_mcp_json() {
    local project_root="${1:?project_root required}"
    local mcp_json="${project_root}/.mcp.json"
    local venv_python="${UWS_VECTOR_INSTALL_DIR}/.venv/bin/python"
    local main_py="${UWS_VECTOR_INSTALL_DIR}/main.py"

    # Need the venv python to exist for configuration
    if [[ ! -f "$venv_python" ]]; then
        echo -e "${YELLOW}  Cannot configure .mcp.json: venv not found${NC}" >&2
        return 1
    fi

    # Use Python for safe JSON manipulation — paths passed via sys.argv, never interpolated
    "$venv_python" - "$mcp_json" "$venv_python" "$main_py" "$project_root" "${UWS_VECTOR_GLOBAL_DIR}" << 'PYEOF'
import json
import sys
import os

mcp_json_path = sys.argv[1]
venv_python   = sys.argv[2]
main_py       = sys.argv[3]
project_root  = sys.argv[4]
global_dir    = sys.argv[5]

# Load existing or create new
if os.path.exists(mcp_json_path):
    with open(mcp_json_path, 'r') as f:
        data = json.load(f)
else:
    data = {}

if "mcpServers" not in data:
    data["mcpServers"] = {}

servers = data["mcpServers"]
changed = False

# Helper: build expected server config
def make_server(working_dir):
    return {
        "command": venv_python,
        "args": [main_py, "--working-dir", working_dir]
    }

# Configure vector_memory_local
local_expected = make_server(project_root)
if "vector_memory_local" in servers:
    existing = servers["vector_memory_local"]
    # Check if --working-dir matches
    try:
        wd_idx = existing["args"].index("--working-dir")
        existing_wd = existing["args"][wd_idx + 1]
        if existing_wd != project_root:
            servers["vector_memory_local"] = local_expected
            changed = True
    except (ValueError, IndexError):
        servers["vector_memory_local"] = local_expected
        changed = True
else:
    servers["vector_memory_local"] = local_expected
    changed = True

# Configure vector_memory_global
global_expected = make_server(global_dir)
if "vector_memory_global" in servers:
    existing = servers["vector_memory_global"]
    try:
        wd_idx = existing["args"].index("--working-dir")
        existing_wd = existing["args"][wd_idx + 1]
        if existing_wd != global_dir:
            servers["vector_memory_global"] = global_expected
            changed = True
    except (ValueError, IndexError):
        servers["vector_memory_global"] = global_expected
        changed = True
else:
    servers["vector_memory_global"] = global_expected
    changed = True

if changed:
    with open(mcp_json_path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print("  \033[0;32m✓\033[0m .mcp.json updated with vector memory servers")
else:
    print("  \033[0;32m✓\033[0m .mcp.json already configured")

PYEOF

    local exit_code=$?
    if (( exit_code != 0 )); then
        echo -e "${YELLOW}  Failed to configure .mcp.json${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Ensure memory/ is in .gitignore
# Arguments:
#   $1 - project root directory
# Returns:
#   0 on success, 1 on failure
#######################################
uws_vm_update_gitignore() {
    local project_root="${1:?project_root required}"
    local gitignore="${project_root}/.gitignore"

    if [[ -f "$gitignore" ]]; then
        if grep -q '^memory/$' "$gitignore" 2>/dev/null; then
            return 0
        fi
        # Append with a blank line separator
        printf '\n# Vector memory database\nmemory/\n' >> "$gitignore"
    else
        printf '# Vector memory database\nmemory/\n' > "$gitignore"
    fi

    echo -e "  ${GREEN}✓${NC} Added memory/ to .gitignore"
    return 0
}

#######################################
# Quick smoke test: verify packages importable in venv
# Returns:
#   0 if OK, 1 on failure
#######################################
uws_vm_verify() {
    local venv_python="${UWS_VECTOR_INSTALL_DIR}/.venv/bin/python"

    if [[ ! -f "$venv_python" ]]; then
        echo -e "${YELLOW}  Verify failed: venv python not found${NC}" >&2
        return 1
    fi

    "$venv_python" -c "import sqlite_vec; import sentence_transformers; import fastmcp; print('OK')" 2>/dev/null || {
        echo -e "${YELLOW}  Verify failed: package imports failed${NC}" >&2
        return 1
    }

    return 0
}

#######################################
# Orchestrator: install and configure vector memory
# Exits early if UWS_SKIP_VECTOR_MEMORY=true.
# Each step wrapped in `if ! step; then warn; return 0; fi` — never fatal.
# Arguments:
#   $1 - project root directory
#   $2 - (optional) "skip_prompt" to skip interactive confirmation
# Returns:
#   0 always (failures are warnings, not errors)
#######################################
setup_vector_memory() {
    local project_root="${1:?project_root required}"
    local skip_prompt="${2:-}"

    # Opt-out via environment variable
    if [[ "${UWS_SKIP_VECTOR_MEMORY:-}" == "true" ]]; then
        echo -e "  ${YELLOW}Vector memory setup skipped (UWS_SKIP_VECTOR_MEMORY=true)${NC}"
        return 0
    fi

    echo ""
    echo "🧠 Setting up vector memory (semantic search)..."

    # Check Python
    if ! uws_vm_check_python; then
        echo -e "  ${YELLOW}Skipping vector memory (Python 3.9+ required)${NC}"
        return 1
    fi

    # Check disk space
    if ! uws_vm_check_disk_space "$HOME"; then
        echo -e "  ${YELLOW}Skipping vector memory (insufficient disk space)${NC}"
        return 1
    fi

    # Check if already fully installed
    if uws_vm_is_installed; then
        echo -e "  ${GREEN}✓${NC} Vector memory server already installed"
        # Still configure .mcp.json for this project (may be a new project)
        if ! uws_vm_configure_mcp_json "$project_root"; then
            echo -e "  ${YELLOW}Warning: could not configure .mcp.json${NC}"
        fi
        uws_vm_update_gitignore "$project_root" || true
        return 0
    fi

    # Interactive prompt (only if terminal attached and not skipped)
    if [[ "$skip_prompt" != "skip_prompt" ]] && [[ -t 0 ]]; then
        echo ""
        echo "  Vector memory provides semantic search across sessions."
        echo "  Requires ~1.5GB disk space for packages + model download."
        read -p "  Install vector memory server? [Y/n]: " vm_confirm
        if [[ "${vm_confirm:-}" =~ ^[Nn]$ ]]; then
            echo -e "  ${YELLOW}Skipped. Set UWS_SKIP_VECTOR_MEMORY=true to always skip.${NC}"
            return 0
        fi
    fi

    # Clone or update repo
    if ! uws_vm_clone_or_update; then
        echo -e "  ${YELLOW}Vector memory setup incomplete (clone failed)${NC}"
        return 1
    fi

    # Setup venv and packages
    if ! uws_vm_setup_venv; then
        echo -e "  ${YELLOW}Vector memory setup incomplete (venv/packages failed)${NC}"
        return 1
    fi

    # Create global knowledge directory
    if ! uws_vm_create_global_dir; then
        echo -e "  ${YELLOW}Warning: could not create global knowledge directory${NC}"
    fi

    # Configure .mcp.json for this project
    if ! uws_vm_configure_mcp_json "$project_root"; then
        echo -e "  ${YELLOW}Warning: could not configure .mcp.json${NC}"
    fi

    # Update .gitignore
    uws_vm_update_gitignore "$project_root" || true

    # Verify installation
    if uws_vm_verify; then
        echo -e "  ${GREEN}✓${NC} Vector memory setup complete"
    else
        echo -e "  ${YELLOW}Warning: verification failed, but files are in place${NC}"
    fi

    # Persist resolved paths to global config for subsequent project inits
    if declare -f uws_persist_config &>/dev/null; then
        uws_persist_config || true
    fi

    return 0
}

# Standalone mode: when run directly, call setup_vector_memory with current directory
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_vector_memory "$(pwd)"
fi
