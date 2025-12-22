#!/bin/bash
# Checksum Utility Library
# Provides SHA256 checksum verification for state files
# RWF compliance (R5: Reproducibility) - Verify integrity after recovery

set -euo pipefail

# Source dependencies
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/logging_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/logging_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/timestamp_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/timestamp_utils.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/atomic_utils.sh" ]]; then
    source "${SCRIPT_LIB_DIR}/atomic_utils.sh"
fi

# Color codes
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
fi

# Checksum configuration
CHECKSUM_FILE="${CHECKSUM_FILE:-.workflow/checksums.yaml}"
CHECKSUM_ALGORITHM="${CHECKSUM_ALGORITHM:-sha256}"

#######################################
# Calculate SHA256 checksum of a file
# Arguments:
#   $1 - File path
# Returns:
#   64-character hex checksum
#######################################
calculate_checksum() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    local checksum

    if command -v sha256sum &> /dev/null; then
        checksum=$(sha256sum "$file" | cut -d' ' -f1)
    elif command -v shasum &> /dev/null; then
        checksum=$(shasum -a 256 "$file" | cut -d' ' -f1)
    elif command -v openssl &> /dev/null; then
        checksum=$(openssl dgst -sha256 "$file" | awk '{print $NF}')
    else
        echo -e "${YELLOW}Warning: No SHA256 tool available${NC}" >&2
        echo ""
        return 1
    fi

    echo "$checksum"
}

#######################################
# Calculate checksums for all state files
# Returns:
#   Combined checksum of all state files
#######################################
calculate_state_checksum() {
    local workflow_dir="${1:-.workflow}"

    local files=(
        "${workflow_dir}/state.yaml"
        "${workflow_dir}/handoff.md"
        "${workflow_dir}/checkpoints.log"
    )

    local combined=""

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            local cs
            cs=$(calculate_checksum "$file")
            combined+="$cs"
        fi
    done

    # Hash the combined checksums
    echo -n "$combined" | sha256sum 2>/dev/null | cut -d' ' -f1 || \
    echo -n "$combined" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || \
    echo ""
}

#######################################
# Store checksums for all state files
# Arguments:
#   $1 - (Optional) Workflow directory
# Returns:
#   0 on success
#######################################
store_checksums() {
    local workflow_dir="${1:-.workflow}"
    local checksum_file="${workflow_dir}/checksums.yaml"

    local timestamp
    timestamp=$(get_iso_timestamp 2>/dev/null || date -Iseconds)

    # Start YAML content
    local content="# State file checksums - generated automatically
# Do not edit manually
generated: \"${timestamp}\"
algorithm: \"${CHECKSUM_ALGORITHM}\"
files:"

    # Calculate checksum for each state file
    local files=(
        "state.yaml"
        "handoff.md"
        "checkpoints.log"
        "config.yaml"
        "agents/registry.yaml"
        "skills/catalog.yaml"
    )

    for file in "${files[@]}"; do
        local full_path="${workflow_dir}/${file}"
        if [[ -f "$full_path" ]]; then
            local cs
            cs=$(calculate_checksum "$full_path")
            content+=$'\n'"  \"${file}\": \"${cs}\""
        fi
    done

    # Calculate combined checksum
    local combined
    combined=$(calculate_state_checksum "$workflow_dir")
    content+=$'\n'"combined: \"${combined}\""

    # Write atomically
    if declare -f atomic_write > /dev/null 2>&1; then
        atomic_write "$checksum_file" "$content"
    else
        echo "$content" > "$checksum_file"
    fi

    if declare -f log_debug > /dev/null 2>&1; then
        log_debug "checksum" "Stored checksums" "file=${checksum_file}"
    fi

    return 0
}

#######################################
# Verify checksums for all state files
# Arguments:
#   $1 - (Optional) Workflow directory
# Returns:
#   0 if all valid, 1 if any mismatch
#######################################
verify_checksums() {
    local workflow_dir="${1:-.workflow}"
    local checksum_file="${workflow_dir}/checksums.yaml"

    if [[ ! -f "$checksum_file" ]]; then
        echo -e "${YELLOW}Warning: No checksums file found${NC}" >&2
        return 1
    fi

    local errors=0

    # Read stored checksums
    while IFS=': ' read -r key value; do
        # Skip comments and metadata
        [[ "$key" =~ ^# ]] && continue
        [[ "$key" == "generated" ]] && continue
        [[ "$key" == "algorithm" ]] && continue
        [[ "$key" == "combined" ]] && continue
        [[ -z "$key" ]] && continue

        # Remove quotes
        key="${key//\"/}"
        value="${value//\"/}"

        local file="${workflow_dir}/${key}"

        if [[ -f "$file" ]]; then
            local current_cs
            current_cs=$(calculate_checksum "$file")

            if [[ "$current_cs" != "$value" ]]; then
                echo -e "${RED}Checksum mismatch: ${key}${NC}" >&2
                ((errors++))
            fi
        else
            echo -e "${YELLOW}File missing: ${key}${NC}" >&2
            ((errors++))
        fi
    done < <(grep -E '^\s*"[^"]+":' "$checksum_file" 2>/dev/null || grep -E '^  [a-zA-Z]' "$checksum_file")

    # Verify combined checksum
    local stored_combined
    stored_combined=$(grep "^combined:" "$checksum_file" 2>/dev/null | sed 's/combined: *//' | tr -d '"' | tr -d ' ')

    if [[ -n "$stored_combined" ]]; then
        local current_combined
        current_combined=$(calculate_state_checksum "$workflow_dir")

        if [[ "$current_combined" != "$stored_combined" ]]; then
            echo -e "${RED}Combined checksum mismatch${NC}" >&2
            ((errors++))
        fi
    fi

    if (( errors > 0 )); then
        if declare -f log_error > /dev/null 2>&1; then
            log_error "checksum" "Verification failed" "errors=${errors}"
        fi
        return 1
    fi

    if declare -f log_debug > /dev/null 2>&1; then
        log_debug "checksum" "Verification passed"
    fi

    return 0
}

#######################################
# Verify single file checksum
# Arguments:
#   $1 - File path
#   $2 - Expected checksum
# Returns:
#   0 if valid, 1 if mismatch
#######################################
verify_file_checksum() {
    local file="$1"
    local expected="$2"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: ${file}${NC}" >&2
        return 1
    fi

    local actual
    actual=$(calculate_checksum "$file")

    if [[ "$actual" != "$expected" ]]; then
        echo -e "${RED}Checksum mismatch for ${file}${NC}" >&2
        echo -e "${RED}  Expected: ${expected}${NC}" >&2
        echo -e "${RED}  Actual:   ${actual}${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Create checkpoint manifest with checksums
# Arguments:
#   $1 - Snapshot directory
# Returns:
#   0 on success
#######################################
create_snapshot_manifest() {
    local snapshot_dir="$1"

    if [[ ! -d "$snapshot_dir" ]]; then
        echo -e "${RED}Error: Snapshot directory not found: ${snapshot_dir}${NC}" >&2
        return 1
    fi

    local manifest_file="${snapshot_dir}/manifest.yaml"
    local snapshot_id
    snapshot_id=$(basename "$snapshot_dir")

    local timestamp
    timestamp=$(get_iso_timestamp 2>/dev/null || date -Iseconds)

    # Build manifest
    local content="# Checkpoint Manifest - v2 format
snapshot_id: \"${snapshot_id}\"
created: \"${timestamp}\"
version: \"2.0\"
files:"

    local total_files=0

    # Add each file with checksum
    for file in "${snapshot_dir}"/*; do
        if [[ -f "$file" ]]; then
            local filename
            filename=$(basename "$file")
            [[ "$filename" == "manifest.yaml" ]] && continue

            local cs
            cs=$(calculate_checksum "$file")
            local required="true"
            [[ "$filename" =~ ^(decisions|execution)\.log$ ]] && required="false"

            content+=$'\n'"  - path: \"${filename}\""
            content+=$'\n'"    checksum: \"${cs}\""
            content+=$'\n'"    required: ${required}"

            total_files=$((total_files + 1))
        fi
    done

    # Add active_state directory if exists
    if [[ -d "${snapshot_dir}/active_state" ]]; then
        for file in "${snapshot_dir}/active_state"/*; do
            if [[ -f "$file" ]]; then
                local filename
                filename=$(basename "$file")
                local cs
                cs=$(calculate_checksum "$file")

                content+=$'\n'"  - path: \"active_state/${filename}\""
                content+=$'\n'"    checksum: \"${cs}\""
                content+=$'\n'"    required: false"

                total_files=$((total_files + 1))
            fi
        done
    fi

    # Add totals
    content+=$'\n'"total_files: ${total_files}"

    # Calculate combined checksum
    local combined=""
    for file in "${snapshot_dir}"/*; do
        if [[ -f "$file" ]]; then
            local cs
            cs=$(calculate_checksum "$file")
            combined+="$cs"
        fi
    done
    local combined_hash
    combined_hash=$(echo -n "$combined" | sha256sum 2>/dev/null | cut -d' ' -f1 || echo "")
    content+=$'\n'"combined_checksum: \"${combined_hash}\""

    # Write manifest
    echo "$content" > "$manifest_file"

    if declare -f log_debug > /dev/null 2>&1; then
        log_debug "checksum" "Created snapshot manifest" "dir=${snapshot_dir} files=${total_files}"
    fi

    return 0
}

#######################################
# Verify checkpoint manifest
# Arguments:
#   $1 - Snapshot directory
# Returns:
#   0 if valid, 1 if invalid
#######################################
verify_snapshot_manifest() {
    local snapshot_dir="$1"
    local manifest_file="${snapshot_dir}/manifest.yaml"

    if [[ ! -f "$manifest_file" ]]; then
        echo -e "${YELLOW}No manifest found (v1 checkpoint)${NC}" >&2
        return 0  # v1 checkpoints don't have manifests
    fi

    local errors=0
    local version
    version=$(grep "^version:" "$manifest_file" 2>/dev/null | sed 's/version: *//' | tr -d '"' | tr -d ' ')

    if [[ "$version" != "2.0" ]]; then
        echo -e "${YELLOW}Unknown manifest version: ${version}${NC}" >&2
    fi

    # Verify each file in manifest
    while IFS= read -r line; do
        if [[ "$line" =~ path:.*\"([^\"]+)\" ]]; then
            local path="${BASH_REMATCH[1]}"
            local file="${snapshot_dir}/${path}"

            # Read next line for checksum
            read -r checksum_line
            if [[ "$checksum_line" =~ checksum:.*\"([^\"]+)\" ]]; then
                local expected="${BASH_REMATCH[1]}"

                # Read next line for required
                read -r required_line
                local required="true"
                if [[ "$required_line" =~ required:.*false ]]; then
                    required="false"
                fi

                if [[ -f "$file" ]]; then
                    local actual
                    actual=$(calculate_checksum "$file")
                    if [[ "$actual" != "$expected" ]]; then
                        echo -e "${RED}Checksum mismatch: ${path}${NC}" >&2
                        ((errors++))
                    fi
                elif [[ "$required" == "true" ]]; then
                    echo -e "${RED}Required file missing: ${path}${NC}" >&2
                    ((errors++))
                fi
            fi
        fi
    done < "$manifest_file"

    if (( errors > 0 )); then
        if declare -f log_error > /dev/null 2>&1; then
            log_error "checksum" "Manifest verification failed" "errors=${errors} dir=${snapshot_dir}"
        fi
        return 1
    fi

    if declare -f log_debug > /dev/null 2>&1; then
        log_debug "checksum" "Manifest verification passed" "dir=${snapshot_dir}"
    fi

    return 0
}

#######################################
# Get checksum info as JSON
# Returns:
#   JSON object with checksum info
#######################################
get_checksums_json() {
    local workflow_dir="${1:-.workflow}"

    echo "{"
    echo "  \"generated\": \"$(get_iso_timestamp 2>/dev/null || date -Iseconds)\","
    echo "  \"algorithm\": \"${CHECKSUM_ALGORITHM}\","
    echo "  \"files\": {"

    local first=true
    local files=("state.yaml" "handoff.md" "checkpoints.log")

    for file in "${files[@]}"; do
        local full_path="${workflow_dir}/${file}"
        if [[ -f "$full_path" ]]; then
            local cs
            cs=$(calculate_checksum "$full_path")

            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi

            echo -n "    \"${file}\": \"${cs}\""
        fi
    done

    echo ""
    echo "  },"
    echo "  \"combined\": \"$(calculate_state_checksum "$workflow_dir")\""
    echo "}"
}

#######################################
# Print usage information
#######################################
checksum_usage() {
    cat << 'EOF'
Checksum Utility Library - RWF Reproducibility (R5)

File Checksums:
  calculate_checksum <file>           Get SHA256 hash of file
  calculate_state_checksum [dir]      Combined hash of all state files
  verify_file_checksum <file> <hash>  Verify single file

State Checksums:
  store_checksums [dir]               Store checksums for all state files
  verify_checksums [dir]              Verify all stored checksums
  get_checksums_json [dir]            Get checksums as JSON

Snapshot Manifests:
  create_snapshot_manifest <dir>      Create v2 manifest with checksums
  verify_snapshot_manifest <dir>      Verify manifest and files

Configuration:
  CHECKSUM_FILE       Checksum storage location
  CHECKSUM_ALGORITHM  Algorithm to use (default: sha256)

Example:
  source scripts/lib/checksum_utils.sh

  # Store and verify checksums
  store_checksums
  verify_checksums || echo "State corrupted!"

  # Create checkpoint with manifest
  mkdir -p .workflow/checkpoints/snapshots/CP_1_010
  cp .workflow/state.yaml .workflow/checkpoints/snapshots/CP_1_010/
  create_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_010

  # Verify before restore
  verify_snapshot_manifest .workflow/checkpoints/snapshots/CP_1_010
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f calculate_checksum
    export -f calculate_state_checksum
    export -f store_checksums
    export -f verify_checksums
    export -f verify_file_checksum
    export -f create_snapshot_manifest
    export -f verify_snapshot_manifest
    export -f get_checksums_json
    export -f checksum_usage
fi
