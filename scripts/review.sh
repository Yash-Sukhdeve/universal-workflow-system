#!/bin/bash
#
# Universal Workflow System - Robust Review (Company OS)
#
# Usage: ./scripts/review.sh [command] [args...]
#

set -e

COMMAND="${1:-list}"
ARG="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
UWS_DIR="${PROJECT_ROOT}/.uws"
STAGING_DIR="${UWS_DIR}/crs"
NOTIFICATIONS_FILE="${PROJECT_ROOT}/NOTIFICATIONS.md"

if [[ "$COMMAND" == "list" ]]; then
    echo "Pending Change Requests:"
    echo "ID | Agent | Summary"
    echo "---|---|---"
    for dir in "$STAGING_DIR"/CR-*; do
        [ -d "$dir" ] || continue
        ID=$(basename "$dir")
        SUMMARY_FILE="$dir/summary.md"
        AGENT=$(grep "**Agent**:" "$SUMMARY_FILE" 2>/dev/null | cut -d: -f2 | xargs)
        MSG=$(grep "## 📝 Summary" -A 1 "$SUMMARY_FILE" 2>/dev/null | tail -1 | xargs)
        echo "$ID | $AGENT | $MSG"
    done
    exit 0
fi

if [[ "$COMMAND" == "approve" ]]; then
    CL_ID="$ARG"
    CL_DIR="${STAGING_DIR}/${CL_ID}"
    PATCH_FILE="${CL_DIR}/patch.diff"
    
    if [[ ! -d "$CL_DIR" ]]; then
        echo "Error: CR $CL_ID not found."
        exit 1
    fi
    
    echo "Reviewing $CL_ID..."
    
    # 1. Check for conflicts
    if ! patch --dry-run -p0 -d "$PROJECT_ROOT" < "$PATCH_FILE" > /dev/null 2>&1; then
        echo "❌ CONFLICT DETECTED!"
        echo "This patch cannot be applied cleanly. Manual resolution required."
        exit 1
    fi
    
    # 2. Apply Patch
    echo "Applying changes..."
    patch -p0 -d "$PROJECT_ROOT" < "$PATCH_FILE"
    
    # 3. Mark Ticket as Done (extract ID from summary)
    TICKET_ID=$(grep -m 1 "**Ticket**:" "${CL_DIR}/summary.md" | cut -d: -f2 | tr -d ' *' || echo "None")
    
    if [[ -n "$TICKET_ID" ]] && [[ "$TICKET_ID" != "None" ]]; then
        bash "${SCRIPT_DIR}/pm.sh" move "$TICKET_ID" "Done"
        echo "Ticket $TICKET_ID moved to Done."
    else
        echo "No associated ticket to update."
    fi
    
    # 4. Cleanup Notifications
    # Remove the line containing the CL_ID
    if [[ -f "$NOTIFICATIONS_FILE" ]]; then
        sed -i "/${CL_ID}/d" "$NOTIFICATIONS_FILE"
        echo "Removed from Notifications."
    fi
    
    # 5. Archive CR (Optional, here we delete for simplicity or move to archive)
    mv "$CL_DIR" "${STAGING_DIR}/ARCHIVED_${CL_ID}"
    
    echo "✅ Approved and Merged Successfully!"
    exit 0
fi

if [[ "$COMMAND" == "reject" ]]; then
    CL_ID="$ARG"
    CL_DIR="${STAGING_DIR}/${CL_ID}"
    
    if [[ ! -d "$CL_DIR" ]]; then
        echo "Error: CR $CL_ID not found."
        exit 1
    fi
    
    # 1. Move Ticket Back
    TICKET_ID=$(grep -m 1 "**Ticket**:" "${CL_DIR}/summary.md" | cut -d: -f2 | tr -d ' *' || echo "None")
    
    if [[ -n "$TICKET_ID" ]] && [[ "$TICKET_ID" != "None" ]]; then
        bash "${SCRIPT_DIR}/pm.sh" move "$TICKET_ID" "In Progress"
        echo "Ticket $TICKET_ID moved back to In Progress."
    fi
    
    # 2. Cleanup
    sed -i "/${CL_ID}/d" "$NOTIFICATIONS_FILE"
    rm -rf "$CL_DIR"
    
    echo "❌ CR Rejected. Feedback sent."
    exit 0
fi

echo "Unknown command: $COMMAND"
exit 1
