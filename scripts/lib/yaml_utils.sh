#!/bin/bash
# YAML Utility Library
# Provides safe YAML parsing and manipulation functions
# Supports both yq (preferred) and fallback sed/grep methods

set -euo pipefail

# Color codes for output (only set if not already defined)
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m' # No Color
fi

# Check if yq is available
HAS_YQ=false
if command -v yq &> /dev/null; then
    HAS_YQ=true
fi

# Display warning if yq is not available
if [[ "$HAS_YQ" == "false" ]] && [[ "${YAML_UTILS_QUIET:-false}" != "true" ]]; then
    echo -e "${YELLOW}Warning: yq not found. Using fallback YAML parsing.${NC}" >&2
    echo -e "${YELLOW}Install yq for better performance: https://github.com/mikefarah/yq${NC}" >&2
fi

#######################################
# Get a value from a YAML file
# Arguments:
#   $1 - YAML file path
#   $2 - Key path (e.g., "project.type" or "agents.active")
# Returns:
#   The value at the specified key
#######################################
yaml_get() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        echo "Error: YAML file not found: $file" >&2
        return 1
    fi

    if [[ "$HAS_YQ" == "true" ]]; then
        # Use yq for robust parsing
        yq eval ".${key}" "$file" 2>/dev/null || echo "null"
    else
        # Fallback: safe grep/sed parsing
        # This handles simple dot-notation keys like "project.type"
        local result
        if [[ "$key" == *.* ]]; then
            # Nested key - extract the parent and child
            local parent="${key%.*}"
            local child="${key##*.}"

            # Find the parent section and then the child key
            result=$(sed -n "/^${parent}:/,/^[^ ]/p" "$file" | \
                     grep "^  ${child}:" | \
                     head -1 | \
                     sed 's/^[^:]*:[[:space:]]*//' | \
                     sed 's/^["'\'']\(.*\)["'\'']$/\1/')
        else
            # Top-level key
            result=$(grep "^${key}:" "$file" | \
                     head -1 | \
                     sed 's/^[^:]*:[[:space:]]*//' | \
                     sed 's/^["'\'']\(.*\)["'\'']$/\1/')
        fi

        if [[ -z "$result" ]]; then
            echo "null"
        else
            echo "$result"
        fi
    fi
}

#######################################
# Set a value in a YAML file
# Arguments:
#   $1 - YAML file path
#   $2 - Key path (e.g., "project.type")
#   $3 - New value
# Returns:
#   0 on success, 1 on failure
#######################################
yaml_set() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [[ ! -f "$file" ]]; then
        echo "Error: YAML file not found: $file" >&2
        return 1
    fi

    # Create backup before modification
    cp "$file" "${file}.backup" || {
        echo "Error: Could not create backup of $file" >&2
        return 1
    }

    if [[ "$HAS_YQ" == "true" ]]; then
        # Use yq for robust setting
        yq eval ".${key} = \"${value}\"" -i "$file" 2>/dev/null || {
            echo "Error: Failed to set ${key} in $file" >&2
            mv "${file}.backup" "$file"
            return 1
        }
    else
        # Fallback: sed-based setting (works for simple cases)
        if [[ "$key" == *.* ]]; then
            # Nested key
            local parent="${key%.*}"
            local child="${key##*.}"

            # Use awk for safer nested key updates
            awk -v parent="$parent" -v child="$child" -v val="$value" '
                /^[^ ]/ { in_section = 0 }
                $0 ~ "^" parent ":" { in_section = 1 }
                in_section && $0 ~ "^  " child ":" {
                    print "  " child ": " val
                    next
                }
                { print }
            ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file" || {
                echo "Error: Failed to set ${key} in $file" >&2
                mv "${file}.backup" "$file"
                return 1
            }
        else
            # Top-level key
            sed -i.tmp "s/^${key}:.*/${key}: ${value}/" "$file" || {
                echo "Error: Failed to set ${key} in $file" >&2
                mv "${file}.backup" "$file"
                return 1
            }
            rm -f "${file}.tmp"
        fi
    fi

    # Remove backup if successful
    rm -f "${file}.backup"
    return 0
}

#######################################
# Check if a key exists in a YAML file
# Arguments:
#   $1 - YAML file path
#   $2 - Key path
# Returns:
#   0 if key exists, 1 otherwise
#######################################
yaml_has_key() {
    local file="$1"
    local key="$2"

    local value
    value=$(yaml_get "$file" "$key")

    if [[ "$value" == "null" || -z "$value" ]]; then
        return 1
    else
        return 0
    fi
}

#######################################
# Validate YAML file syntax
# Arguments:
#   $1 - YAML file path
# Returns:
#   0 if valid, 1 if invalid
#######################################
yaml_validate() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Error: YAML file not found: $file" >&2
        return 1
    fi

    if [[ "$HAS_YQ" == "true" ]]; then
        # Use yq to validate
        yq eval '.' "$file" > /dev/null 2>&1 || {
            echo "Error: Invalid YAML syntax in $file" >&2
            return 1
        }
    else
        # Basic validation: check for common syntax errors
        # This is not comprehensive but catches obvious issues

        # Check for tab characters (YAML doesn't allow tabs for indentation)
        if grep -q $'\t' "$file"; then
            echo "Error: YAML file contains tabs (use spaces): $file" >&2
            return 1
        fi

        # Check for balanced quotes
        local single_quotes
        local double_quotes
        single_quotes=$(grep -o "'" "$file" | wc -l)
        double_quotes=$(grep -o '"' "$file" | wc -l)

        if (( single_quotes % 2 != 0 )); then
            echo "Error: Unbalanced single quotes in $file" >&2
            return 1
        fi

        if (( double_quotes % 2 != 0 )); then
            echo "Error: Unbalanced double quotes in $file" >&2
            return 1
        fi
    fi

    return 0
}

#######################################
# Get array values from YAML
# Arguments:
#   $1 - YAML file path
#   $2 - Key path to array
# Returns:
#   Array values, one per line
#######################################
yaml_get_array() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        echo "Error: YAML file not found: $file" >&2
        return 1
    fi

    if [[ "$HAS_YQ" == "true" ]]; then
        # Use yq to get array
        yq eval ".${key}[]" "$file" 2>/dev/null || echo ""
    else
        # Fallback: extract array items
        # This is a simplified version that works for simple arrays
        sed -n "/^${key}:/,/^[^ ]/p" "$file" | \
            grep "^  - " | \
            sed 's/^  - //' | \
            sed 's/^["'\'']\(.*\)["'\'']$/\1/'
    fi
}

#######################################
# Add item to YAML array
# Arguments:
#   $1 - YAML file path
#   $2 - Key path to array
#   $3 - Value to add
# Returns:
#   0 on success, 1 on failure
#######################################
yaml_array_add() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [[ ! -f "$file" ]]; then
        echo "Error: YAML file not found: $file" >&2
        return 1
    fi

    # Create backup
    cp "$file" "${file}.backup" || return 1

    if [[ "$HAS_YQ" == "true" ]]; then
        # Use yq to append to array
        yq eval ".${key} += [\"${value}\"]" -i "$file" 2>/dev/null || {
            echo "Error: Failed to add to array ${key} in $file" >&2
            mv "${file}.backup" "$file"
            return 1
        }
    else
        # Fallback: append to array section
        # Find the array section and add a new item
        awk -v key="$key" -v val="$value" '
            /^[^ ]/ { in_section = 0 }
            $0 ~ "^" key ":" {
                in_section = 1
                print
                next
            }
            in_section && /^[^ ]/ {
                print "  - " val
                in_section = 0
            }
            { print }
            END {
                if (in_section) print "  - " val
            }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file" || {
            echo "Error: Failed to add to array ${key} in $file" >&2
            mv "${file}.backup" "$file"
            return 1
        }
    fi

    rm -f "${file}.backup"
    return 0
}

#######################################
# Remove item from YAML array
# Arguments:
#   $1 - YAML file path
#   $2 - Key path to array
#   $3 - Value to remove
# Returns:
#   0 on success, 1 on failure
#######################################
yaml_array_remove() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [[ ! -f "$file" ]]; then
        echo "Error: YAML file not found: $file" >&2
        return 1
    fi

    # Create backup
    cp "$file" "${file}.backup" || return 1

    if [[ "$HAS_YQ" == "true" ]]; then
        # Use yq to remove from array
        yq eval "del(.${key}[] | select(. == \"${value}\"))" -i "$file" 2>/dev/null || {
            echo "Error: Failed to remove from array ${key} in $file" >&2
            mv "${file}.backup" "$file"
            return 1
        }
    else
        # Fallback: remove matching array item
        awk -v key="$key" -v val="$value" '
            /^[^ ]/ { in_section = 0 }
            $0 ~ "^" key ":" { in_section = 1 }
            in_section && $0 ~ "^  - " val { next }
            { print }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file" || {
            echo "Error: Failed to remove from array ${key} in $file" >&2
            mv "${file}.backup" "$file"
            return 1
        }
    fi

    rm -f "${file}.backup"
    return 0
}

#######################################
# Create a new YAML file with initial structure
# Arguments:
#   $1 - YAML file path
#   $2+ - Key-value pairs (format: key=value)
# Returns:
#   0 on success, 1 on failure
#######################################
yaml_create() {
    local file="$1"
    shift

    if [[ -f "$file" ]]; then
        echo "Warning: YAML file already exists: $file" >&2
        return 1
    fi

    # Create parent directory if it doesn't exist
    local dir
    dir=$(dirname "$file")
    mkdir -p "$dir" || return 1

    # Create empty YAML file with comment header
    cat > "$file" << EOF
# YAML configuration file
# Generated: $(date -Iseconds 2>/dev/null || date)
#
EOF

    # Add key-value pairs if provided
    for pair in "$@"; do
        if [[ "$pair" == *=* ]]; then
            local key="${pair%%=*}"
            local value="${pair#*=}"

            # Add top-level key
            echo "${key}: ${value}" >> "$file"
        fi
    done

    # Validate the created file
    yaml_validate "$file" || {
        rm -f "$file"
        return 1
    }

    return 0
}

#######################################
# Pretty-print YAML file
# Arguments:
#   $1 - YAML file path
# Returns:
#   Formatted YAML content
#######################################
yaml_format() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Error: YAML file not found: $file" >&2
        return 1
    fi

    if [[ "$HAS_YQ" == "true" ]]; then
        yq eval '.' "$file"
    else
        # Just cat the file as-is (no reformatting without yq)
        cat "$file"
    fi
}

#######################################
# Check if yq is available
# Returns:
#   0 if yq is available, 1 otherwise
#######################################
yaml_has_yq() {
    [[ "$HAS_YQ" == "true" ]]
}

#######################################
# Print usage information
#######################################
yaml_usage() {
    cat << EOF
YAML Utility Library

Functions:
  yaml_get <file> <key>                    Get value from YAML
  yaml_set <file> <key> <value>           Set value in YAML
  yaml_has_key <file> <key>               Check if key exists
  yaml_validate <file>                     Validate YAML syntax
  yaml_get_array <file> <key>             Get array values
  yaml_array_add <file> <key> <value>     Add to array
  yaml_array_remove <file> <key> <value>  Remove from array
  yaml_create <file> [key=value...]       Create new YAML file
  yaml_format <file>                       Pretty-print YAML
  yaml_has_yq                              Check if yq is available

Example:
  source scripts/lib/yaml_utils.sh
  yaml_get ".workflow/state.yaml" "current_phase"
  yaml_set ".workflow/state.yaml" "current_phase" "phase_2"
  yaml_validate ".workflow/config.yaml"

Note: Install yq for optimal performance and features
  https://github.com/mikefarah/yq
EOF
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f yaml_get
    export -f yaml_set
    export -f yaml_has_key
    export -f yaml_validate
    export -f yaml_get_array
    export -f yaml_array_add
    export -f yaml_array_remove
    export -f yaml_create
    export -f yaml_format
    export -f yaml_has_yq
    export -f yaml_usage
fi
