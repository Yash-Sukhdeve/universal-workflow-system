#!/bin/bash
# UWS Global Configuration Library
# Reads/writes ~/.config/uws/config.yaml for cross-project settings.
# Resolution chain: environment variable → config file → default convention.

# Double-source guard
if [[ "${_UWS_CONFIG_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_UWS_CONFIG_LOADED="true"

set -euo pipefail

# Color codes (guard matching validation_utils.sh:14-19)
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
fi

# XDG-compliant config location
UWS_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/uws"
UWS_CONFIG_FILE="${UWS_CONFIG_DIR}/config.yaml"

#######################################
# Read a single key from the config file
# Arguments:
#   $1 - key name (e.g. "global_memory_dir")
# Outputs:
#   The value (unquoted), or empty string if not found
# Returns:
#   0 if key found, 1 if not
#######################################
uws_config_read_key() {
    local key="${1:?key required}"

    if [[ ! -f "$UWS_CONFIG_FILE" ]]; then
        return 1
    fi

    local value
    # Match "key: value" or "key: \"value\"" — grep-based, no yq dependency
    value="$(grep -E "^${key}:" "$UWS_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")" || true

    if [[ -z "$value" ]]; then
        return 1
    fi

    printf '%s' "$value"
    return 0
}

#######################################
# Write one or more key=value pairs to the config file
# Creates the directory and file if absent. Updates in-place if key exists.
# Arguments:
#   key=value pairs (e.g. global_memory_dir=/path uws_install_dir=/path2)
# Returns:
#   0 on success, 1 on failure
#######################################
uws_config_write() {
    if (( $# == 0 )); then
        return 1
    fi

    # Create directory if needed
    if [[ ! -d "$UWS_CONFIG_DIR" ]]; then
        mkdir -p "$UWS_CONFIG_DIR" || {
            echo -e "${YELLOW}  Could not create ${UWS_CONFIG_DIR}${NC}" >&2
            return 1
        }
    fi

    # Create file with header if absent
    if [[ ! -f "$UWS_CONFIG_FILE" ]]; then
        cat > "$UWS_CONFIG_FILE" << 'HEADER'
# UWS Global Configuration (auto-generated, editable)
HEADER
    fi

    local pair key value
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"

        if [[ -z "$key" ]] || [[ "$key" == "$pair" ]]; then
            continue  # Skip malformed entries
        fi

        if grep -qE "^${key}:" "$UWS_CONFIG_FILE" 2>/dev/null; then
            # Update existing key in-place
            sed -i "s|^${key}:.*|${key}: \"${value}\"|" "$UWS_CONFIG_FILE"
        else
            # Append new key
            echo "${key}: \"${value}\"" >> "$UWS_CONFIG_FILE"
        fi
    done

    return 0
}

#######################################
# Validate that a path has no dot-prefixed components
# (catches security.py violations for --working-dir paths)
# Arguments:
#   $1 - path to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
uws_validate_global_dir_path() {
    local path="${1:?path required}"

    # Expand ~ to $HOME for checking
    path="${path/#\~/$HOME}"

    # Split on / and check each component
    local IFS='/'
    local component
    for component in $path; do
        [[ -z "$component" ]] && continue
        if [[ "$component" == .* ]] && [[ "$component" != ".gitkeep" ]]; then
            echo -e "${YELLOW}  Invalid path: component '${component}' starts with dot${NC}" >&2
            return 1
        fi
    done

    return 0
}

#######################################
# Resolve global memory directory
# Chain: UWS_GLOBAL_MEMORY_DIR env → config file → ~/uws-global-knowledge
# Returns:
#   Prints resolved path to stdout
#######################################
uws_resolve_global_memory_dir() {
    # 1. Environment variable
    if [[ -n "${UWS_GLOBAL_MEMORY_DIR:-}" ]]; then
        printf '%s' "$UWS_GLOBAL_MEMORY_DIR"
        return 0
    fi

    # 2. Config file
    local config_val
    if config_val="$(uws_config_read_key global_memory_dir)" && [[ -n "$config_val" ]]; then
        printf '%s' "$config_val"
        return 0
    fi

    # 3. Default
    printf '%s' "${HOME}/uws-global-knowledge"
    return 0
}

#######################################
# Resolve UWS install directory
# Chain: UWS_INSTALL_DIR env → config file → self-discovery via BASH_SOURCE
# Returns:
#   Prints resolved path to stdout
#######################################
uws_resolve_install_dir() {
    # 1. Environment variable
    if [[ -n "${UWS_INSTALL_DIR:-}" ]]; then
        printf '%s' "$UWS_INSTALL_DIR"
        return 0
    fi

    # 2. Config file
    local config_val
    if config_val="$(uws_config_read_key uws_install_dir)" && [[ -n "$config_val" ]]; then
        printf '%s' "$config_val"
        return 0
    fi

    # 3. Self-discovery: this file lives in scripts/lib/, so go up two levels
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s' "$(cd "$self_dir/../.." && pwd)"
    return 0
}

#######################################
# Resolve vector memory server directory
# Chain: UWS_VECTOR_SERVER_DIR env → config file → ~/.uws/tools/vector-memory
# Returns:
#   Prints resolved path to stdout
#######################################
uws_resolve_vector_server_dir() {
    # 1. Environment variable
    if [[ -n "${UWS_VECTOR_SERVER_DIR:-}" ]]; then
        printf '%s' "$UWS_VECTOR_SERVER_DIR"
        return 0
    fi

    # 2. Config file
    local config_val
    if config_val="$(uws_config_read_key vector_memory_server)" && [[ -n "$config_val" ]]; then
        printf '%s' "$config_val"
        return 0
    fi

    # 3. Default
    printf '%s' "${HOME}/.uws/tools/vector-memory"
    return 0
}

#######################################
# Persist all resolved values to config file
# Writes global_memory_dir, uws_install_dir, vector_memory_server
# Returns:
#   0 on success
#######################################
uws_persist_config() {
    local global_dir install_dir vector_dir

    global_dir="$(uws_resolve_global_memory_dir)"
    install_dir="$(uws_resolve_install_dir)"
    vector_dir="$(uws_resolve_vector_server_dir)"

    uws_config_write \
        "global_memory_dir=${global_dir}" \
        "uws_install_dir=${install_dir}" \
        "vector_memory_server=${vector_dir}"
}
