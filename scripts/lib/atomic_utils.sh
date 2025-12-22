#!/bin/bash
# Atomic Utility Library
# Provides atomic file operations with rollback support for RWF compliance
# R3: State Safety - All modifications are atomic and recoverable

set -euo pipefail

# Source YAML utilities if available
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output (only set if not already defined)
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# Atomic operation tracking
declare -a ATOMIC_BACKUPS=()
declare -a ATOMIC_TEMPS=()
ATOMIC_TRANSACTION_ACTIVE=false
ATOMIC_TRANSACTION_ID=""

#######################################
# Generate unique transaction ID
# Returns:
#   Unique transaction ID string
#######################################
generate_transaction_id() {
    echo "TX_$(date +%s)_$$_${RANDOM}"
}

#######################################
# Start an atomic transaction
# Groups multiple operations for atomic commit/rollback
# Arguments:
#   $1 - (Optional) Transaction description
# Returns:
#   0 on success, 1 if transaction already active
#######################################
atomic_begin() {
    local description="${1:-unnamed transaction}"

    if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
        echo -e "${RED}Error: Transaction already active: ${ATOMIC_TRANSACTION_ID}${NC}" >&2
        return 1
    fi

    ATOMIC_TRANSACTION_ACTIVE=true
    ATOMIC_TRANSACTION_ID=$(generate_transaction_id)
    ATOMIC_BACKUPS=()
    ATOMIC_TEMPS=()

    # Log transaction start if logging available
    if declare -f log_debug > /dev/null 2>&1; then
        log_debug "atomic_utils" "Transaction started: ${ATOMIC_TRANSACTION_ID} - ${description}"
    fi

    return 0
}

#######################################
# Commit an atomic transaction
# Cleans up backups after successful commit
# Returns:
#   0 on success, 1 if no transaction active
#######################################
atomic_commit() {
    if [[ "$ATOMIC_TRANSACTION_ACTIVE" != "true" ]]; then
        echo -e "${RED}Error: No active transaction to commit${NC}" >&2
        return 1
    fi

    # Clean up backups (transaction succeeded)
    for backup in "${ATOMIC_BACKUPS[@]}"; do
        rm -f "$backup" 2>/dev/null || true
    done

    # Clean up any temp files
    for temp in "${ATOMIC_TEMPS[@]}"; do
        rm -f "$temp" 2>/dev/null || true
    done

    local tx_id="$ATOMIC_TRANSACTION_ID"
    ATOMIC_TRANSACTION_ACTIVE=false
    ATOMIC_TRANSACTION_ID=""
    ATOMIC_BACKUPS=()
    ATOMIC_TEMPS=()

    if declare -f log_debug > /dev/null 2>&1; then
        log_debug "atomic_utils" "Transaction committed: ${tx_id}"
    fi

    return 0
}

#######################################
# Rollback an atomic transaction
# Restores all files from backups
# Returns:
#   0 on success, 1 if no transaction active
#######################################
atomic_rollback() {
    local reason="${1:-unspecified}"

    if [[ "$ATOMIC_TRANSACTION_ACTIVE" != "true" ]]; then
        echo -e "${YELLOW}Warning: No active transaction to rollback${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}Rolling back transaction ${ATOMIC_TRANSACTION_ID}: ${reason}${NC}" >&2

    local rollback_errors=0

    # Restore from backups
    for backup in "${ATOMIC_BACKUPS[@]}"; do
        local original="${backup%.atomic_backup.*}"
        original="${original%.atomic_backup}"

        if [[ -f "$backup" ]]; then
            if mv "$backup" "$original" 2>/dev/null; then
                echo -e "${GREEN}Restored: ${original}${NC}" >&2
            else
                echo -e "${RED}Failed to restore: ${original}${NC}" >&2
                ((rollback_errors++))
            fi
        fi
    done

    # Clean up temp files
    for temp in "${ATOMIC_TEMPS[@]}"; do
        rm -f "$temp" 2>/dev/null || true
    done

    local tx_id="$ATOMIC_TRANSACTION_ID"
    ATOMIC_TRANSACTION_ACTIVE=false
    ATOMIC_TRANSACTION_ID=""
    ATOMIC_BACKUPS=()
    ATOMIC_TEMPS=()

    if declare -f log_warn > /dev/null 2>&1; then
        log_warn "atomic_utils" "Transaction rolled back: ${tx_id} - ${reason}"
    fi

    if (( rollback_errors > 0 )); then
        echo -e "${RED}Rollback completed with ${rollback_errors} errors${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Create a backup of a file for atomic operation
# Arguments:
#   $1 - File path to backup
# Returns:
#   Backup file path on stdout
#   0 on success, 1 on failure
#######################################
safe_backup() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        # File doesn't exist - no backup needed
        echo ""
        return 0
    fi

    local backup_file
    if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
        backup_file="${file}.atomic_backup.${ATOMIC_TRANSACTION_ID}"
    else
        backup_file="${file}.atomic_backup.$(date +%s).$$"
    fi

    if ! cp -p "$file" "$backup_file" 2>/dev/null; then
        echo -e "${RED}Error: Failed to create backup of ${file}${NC}" >&2
        return 1
    fi

    # Track backup for transaction
    if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
        ATOMIC_BACKUPS+=("$backup_file")
    fi

    echo "$backup_file"
    return 0
}

#######################################
# Atomically write content to a file
# Uses temp file + atomic rename pattern
# Arguments:
#   $1 - Target file path
#   $2 - Content to write (or - for stdin)
# Returns:
#   0 on success, 1 on failure
#######################################
atomic_write() {
    local target="$1"
    local content="${2:-}"

    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$target")
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || {
            echo -e "${RED}Error: Cannot create directory ${parent_dir}${NC}" >&2
            return 1
        }
    fi

    # Create backup if file exists
    local backup_file=""
    if [[ -f "$target" ]]; then
        # Call safe_backup and capture output, but also add to ATOMIC_BACKUPS here
        # since subshell won't preserve array modification
        if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
            backup_file="${target}.atomic_backup.${ATOMIC_TRANSACTION_ID}"
        else
            backup_file="${target}.atomic_backup.$(date +%s).$$"
        fi
        if ! cp -p "$target" "$backup_file" 2>/dev/null; then
            echo -e "${RED}Error: Failed to create backup of ${target}${NC}" >&2
            return 1
        fi
        if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
            ATOMIC_BACKUPS+=("$backup_file")
        fi
    fi

    # Generate temp file in same directory (for atomic rename)
    local temp_file="${target}.tmp.$$"

    # Track temp file for cleanup
    if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
        ATOMIC_TEMPS+=("$temp_file")
    fi

    # Write content to temp file
    if [[ "$content" == "-" ]]; then
        cat > "$temp_file" || {
            echo -e "${RED}Error: Failed to write to temp file${NC}" >&2
            rm -f "$temp_file"
            [[ -n "$backup_file" ]] && mv "$backup_file" "$target"
            return 1
        }
    else
        echo "$content" > "$temp_file" || {
            echo -e "${RED}Error: Failed to write to temp file${NC}" >&2
            rm -f "$temp_file"
            [[ -n "$backup_file" ]] && mv "$backup_file" "$target"
            return 1
        }
    fi

    # Atomic rename (same filesystem guarantees atomicity)
    if ! mv "$temp_file" "$target" 2>/dev/null; then
        echo -e "${RED}Error: Failed atomic rename to ${target}${NC}" >&2
        rm -f "$temp_file"
        [[ -n "$backup_file" ]] && mv "$backup_file" "$target"
        return 1
    fi

    # Clean up non-transaction backup
    if [[ -n "$backup_file" && "$ATOMIC_TRANSACTION_ACTIVE" != "true" ]]; then
        rm -f "$backup_file"
    fi

    return 0
}

#######################################
# Atomically write content from a file or command
# Arguments:
#   $1 - Target file path
#   $2 - Source file path or command with | prefix
# Returns:
#   0 on success, 1 on failure
#######################################
atomic_write_from() {
    local target="$1"
    local source="$2"

    if [[ "$source" == "|"* ]]; then
        # Command source - execute and pipe
        local cmd="${source#|}"
        eval "$cmd" | atomic_write "$target" "-"
        return "${PIPESTATUS[0]}"
    elif [[ -f "$source" ]]; then
        # File source - cat and write
        atomic_write "$target" "$(cat "$source")"
        return $?
    else
        echo -e "${RED}Error: Source not found: ${source}${NC}" >&2
        return 1
    fi
}

#######################################
# Atomically append content to a file
# Arguments:
#   $1 - Target file path
#   $2 - Content to append
# Returns:
#   0 on success, 1 on failure
#######################################
atomic_append() {
    local target="$1"
    local content="$2"

    local existing=""
    if [[ -f "$target" ]]; then
        existing=$(cat "$target")
        # Command substitution strips trailing newlines, so add one back if file was non-empty
        if [[ -n "$existing" ]]; then
            existing="${existing}"$'\n'
        fi
    fi

    atomic_write "$target" "${existing}${content}"
    return $?
}

#######################################
# Atomically append a line to a file
# Ensures newline before and after
# Arguments:
#   $1 - Target file path
#   $2 - Line to append
# Returns:
#   0 on success, 1 on failure
#######################################
atomic_append_line() {
    local target="$1"
    local line="$2"

    local existing=""
    if [[ -f "$target" ]]; then
        existing=$(cat "$target")
        # Ensure existing content ends with newline
        if [[ -n "$existing" && "${existing: -1}" != $'\n' ]]; then
            existing="${existing}"$'\n'
        fi
    fi

    atomic_write "$target" "${existing}${line}"$'\n'
    return $?
}

#######################################
# Atomically set a value in a YAML file
# Wrapper around yaml_set with atomic guarantees
# Arguments:
#   $1 - YAML file path
#   $2 - Key path (e.g., "project.type")
#   $3 - New value
# Returns:
#   0 on success, 1 on failure
#######################################
atomic_yaml_set() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: YAML file not found: ${file}${NC}" >&2
        return 1
    fi

    # Create backup
    local backup_file
    backup_file=$(safe_backup "$file") || return 1

    # Source yaml_utils if needed
    if ! declare -f yaml_set > /dev/null 2>&1; then
        if [[ -f "${SCRIPT_LIB_DIR}/yaml_utils.sh" ]]; then
            source "${SCRIPT_LIB_DIR}/yaml_utils.sh"
        else
            echo -e "${RED}Error: yaml_utils.sh not found${NC}" >&2
            [[ -n "$backup_file" ]] && mv "$backup_file" "$file"
            return 1
        fi
    fi

    # Create working copy
    local temp_file="${file}.tmp.$$"
    cp "$file" "$temp_file" || {
        echo -e "${RED}Error: Failed to create working copy${NC}" >&2
        [[ -n "$backup_file" ]] && rm -f "$backup_file"
        return 1
    }

    # Track temp file
    if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
        ATOMIC_TEMPS+=("$temp_file")
    fi

    # Perform yaml_set on temp file
    # Suppress the backup that yaml_set creates internally
    if ! yaml_set "$temp_file" "$key" "$value" 2>/dev/null; then
        echo -e "${RED}Error: Failed to set ${key} in ${file}${NC}" >&2
        rm -f "$temp_file" "${temp_file}.backup"
        [[ -n "$backup_file" ]] && mv "$backup_file" "$file"
        return 1
    fi

    # Atomic rename
    if ! mv "$temp_file" "$file" 2>/dev/null; then
        echo -e "${RED}Error: Failed atomic rename${NC}" >&2
        rm -f "$temp_file" "${temp_file}.backup"
        [[ -n "$backup_file" ]] && mv "$backup_file" "$file"
        return 1
    fi

    # Clean up yaml_set's backup
    rm -f "${temp_file}.backup" 2>/dev/null || true

    # Clean up our backup (unless in transaction)
    if [[ -n "$backup_file" && "$ATOMIC_TRANSACTION_ACTIVE" != "true" ]]; then
        rm -f "$backup_file"
    fi

    return 0
}

#######################################
# Atomically set multiple YAML values
# Groups multiple yaml_set operations atomically
# Arguments:
#   $1 - YAML file path
#   $2+ - Key=value pairs
# Returns:
#   0 on success, 1 on failure
#######################################
atomic_yaml_set_multi() {
    local file="$1"
    shift

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: YAML file not found: ${file}${NC}" >&2
        return 1
    fi

    # Start implicit transaction if not already in one
    local implicit_transaction=false
    if [[ "$ATOMIC_TRANSACTION_ACTIVE" != "true" ]]; then
        atomic_begin "yaml_set_multi" || return 1
        implicit_transaction=true
    fi

    local success=true
    for pair in "$@"; do
        if [[ "$pair" == *=* ]]; then
            local key="${pair%%=*}"
            local value="${pair#*=}"

            if ! atomic_yaml_set "$file" "$key" "$value"; then
                success=false
                break
            fi
        else
            echo -e "${YELLOW}Warning: Ignoring invalid pair: ${pair}${NC}" >&2
        fi
    done

    # Handle implicit transaction
    if [[ "$implicit_transaction" == "true" ]]; then
        if [[ "$success" == "true" ]]; then
            atomic_commit
        else
            atomic_rollback "yaml_set_multi failed"
            return 1
        fi
    elif [[ "$success" != "true" ]]; then
        return 1
    fi

    return 0
}

#######################################
# Rollback on error trap handler
# Use with: trap 'rollback_on_error' ERR
#######################################
rollback_on_error() {
    local exit_code=$?
    if [[ "$ATOMIC_TRANSACTION_ACTIVE" == "true" ]]; then
        atomic_rollback "Error occurred (exit code: ${exit_code})"
    fi
    return $exit_code
}

#######################################
# Clean up stale atomic backups
# Removes backup files older than specified age
# Arguments:
#   $1 - Directory to clean
#   $2 - (Optional) Max age in minutes (default: 60)
# Returns:
#   Number of files cleaned
#######################################
atomic_cleanup_stale() {
    local directory="${1:-.workflow}"
    local max_age_minutes="${2:-60}"

    local count=0

    # Find and remove stale backup files
    while IFS= read -r -d '' file; do
        rm -f "$file" && ((count++))
    done < <(find "$directory" -name "*.atomic_backup.*" -mmin +"$max_age_minutes" -print0 2>/dev/null)

    # Clean up stale temp files
    while IFS= read -r -d '' file; do
        rm -f "$file" && ((count++))
    done < <(find "$directory" -name "*.tmp.*" -mmin +"$max_age_minutes" -print0 2>/dev/null)

    if (( count > 0 )); then
        echo -e "${GREEN}Cleaned ${count} stale atomic files${NC}" >&2
    fi

    echo "$count"
}

#######################################
# Verify file integrity after write
# Arguments:
#   $1 - File path
#   $2 - Expected checksum (SHA256)
# Returns:
#   0 if valid, 1 if mismatch or error
#######################################
atomic_verify_checksum() {
    local file="$1"
    local expected="$2"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found for verification: ${file}${NC}" >&2
        return 1
    fi

    local actual
    if command -v sha256sum &> /dev/null; then
        actual=$(sha256sum "$file" | cut -d' ' -f1)
    elif command -v shasum &> /dev/null; then
        actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
    else
        echo -e "${YELLOW}Warning: No SHA256 tool available${NC}" >&2
        return 0
    fi

    if [[ "$actual" != "$expected" ]]; then
        echo -e "${RED}Error: Checksum mismatch for ${file}${NC}" >&2
        echo -e "${RED}Expected: ${expected}${NC}" >&2
        echo -e "${RED}Actual:   ${actual}${NC}" >&2
        return 1
    fi

    return 0
}

#######################################
# Get file checksum
# Arguments:
#   $1 - File path
# Returns:
#   SHA256 checksum on stdout
#######################################
atomic_get_checksum() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 0  # Return success with empty string for non-existent files
    fi

    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        echo ""
        return 1
    fi
}

#######################################
# Print usage information
#######################################
atomic_usage() {
    cat << 'EOF'
Atomic Utility Library - RWF State Safety (R3)

Transaction Functions:
  atomic_begin [description]              Start atomic transaction
  atomic_commit                           Commit transaction (clean up backups)
  atomic_rollback [reason]                Rollback transaction (restore files)
  rollback_on_error                       Trap handler for automatic rollback

File Operations:
  atomic_write <file> <content>           Atomically write content to file
  atomic_write_from <file> <source>       Write from file or command (|cmd)
  atomic_append <file> <content>          Atomically append content
  atomic_append_line <file> <line>        Atomically append line with newline
  safe_backup <file>                      Create backup, return backup path

YAML Operations:
  atomic_yaml_set <file> <key> <value>    Atomically set YAML value
  atomic_yaml_set_multi <file> k=v...     Set multiple YAML values atomically

Utility Functions:
  atomic_cleanup_stale [dir] [age_min]    Clean up stale backup/temp files
  atomic_get_checksum <file>              Get SHA256 checksum
  atomic_verify_checksum <file> <hash>    Verify file checksum

Example:
  source scripts/lib/atomic_utils.sh

  # Single operation
  atomic_write ".workflow/test.txt" "content"

  # Transaction (multiple operations)
  atomic_begin "update state"
  atomic_yaml_set ".workflow/state.yaml" "current_phase" "phase_2"
  atomic_yaml_set ".workflow/state.yaml" "last_updated" "$(date -Iseconds)"
  atomic_commit  # or atomic_rollback on error

  # Error trap
  trap 'rollback_on_error' ERR
  atomic_begin "risky operation"
  # ... operations that might fail ...
  atomic_commit
  trap - ERR
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f generate_transaction_id
    export -f atomic_begin
    export -f atomic_commit
    export -f atomic_rollback
    export -f safe_backup
    export -f atomic_write
    export -f atomic_write_from
    export -f atomic_append
    export -f atomic_append_line
    export -f atomic_yaml_set
    export -f atomic_yaml_set_multi
    export -f rollback_on_error
    export -f atomic_cleanup_stale
    export -f atomic_verify_checksum
    export -f atomic_get_checksum
    export -f atomic_usage
fi
