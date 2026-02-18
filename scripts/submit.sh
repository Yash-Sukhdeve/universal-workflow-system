#!/bin/bash
#
# Universal Workflow System - Robust Submission (Company OS)
#
# Usage: ./scripts/submit.sh "Summary Message" [Ticket-ID]
#

set -e

MESSAGE="${1:-Update}"
TICKET_ID="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve WORKFLOW_DIR: CWD first, then git root, then UWS fallback
source "${SCRIPT_DIR}/lib/resolve_project.sh"

PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
UWS_DIR="${PROJECT_ROOT}/.uws"
STAGING_DIR="${UWS_DIR}/crs"
NOTIFICATIONS_FILE="${PROJECT_ROOT}/NOTIFICATIONS.md"
ACTIVE_AGENT_FILE="${WORKFLOW_DIR}/agents/active.yaml"

# 1. Identify Active Agent
if [[ -f "$ACTIVE_AGENT_FILE" ]]; then
    AGENT=$(grep "current_agent:" "$ACTIVE_AGENT_FILE" | cut -d: -f2 | tr -d ' "')
else
    AGENT="unknown"
    echo "Warning: No active agent found. Submitting as 'unknown'."
fi

WORKSPACE_DIR="${PROJECT_ROOT}/workspace/${AGENT}"

# Ensure directories exist
mkdir -p "$STAGING_DIR"
if [[ ! -f "$NOTIFICATIONS_FILE" ]]; then
    echo "# 📬 Notifications (Inbox)" > "$NOTIFICATIONS_FILE"
    echo "" >> "$NOTIFICATIONS_FILE"
    echo "Pending reviews/approvals for the Human Manager." >> "$NOTIFICATIONS_FILE"
    echo "" >> "$NOTIFICATIONS_FILE"
fi

# 2. Generate Change List ID
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CL_ID="CR-${TIMESTAMP}"
CL_DIR="${STAGING_DIR}/${CL_ID}"
mkdir -p "$CL_DIR"

echo "Creating Change List: $CL_ID"

# 3. Generate Patch (Diff between Workspace and Project Root)
# We assume Workspace mirrors Project Root structure
# This is a simplified diff generation. Robust implementation uses 'git diff' if workspace is a git worktree.
# For now, we manually diff files present in workspace.

PATCH_FILE="${CL_DIR}/patch.diff"
touch "$PATCH_FILE"

# Find all files in workspace
find "$WORKSPACE_DIR" -type f | while read -r ws_file; do
    rel_path="${ws_file#$WORKSPACE_DIR/}"
    root_file="${PROJECT_ROOT}/${rel_path}"
    
    if [[ -f "$root_file" ]]; then
        diff -u "$root_file" "$ws_file" >> "$PATCH_FILE" || true
    else
        # New file
        echo "diff -N $rel_path" >> "$PATCH_FILE"
        echo "--- /dev/null" >> "$PATCH_FILE"
        echo "+++ $rel_path" >> "$PATCH_FILE"
        diff -u /dev/null "$ws_file" | tail -n +3 >> "$PATCH_FILE" || true
    fi
done

# If patch is empty, abort
if [[ ! -s "$PATCH_FILE" ]]; then
    echo "Error: No changes detected in workspace/${AGENT}."
    rm -rf "$CL_DIR"
    exit 1
fi

# 4. Generate Human-Readable Summary
SUMMARY_FILE="${CL_DIR}/summary.md"
cat > "$SUMMARY_FILE" << EOF
# Change Request: ${CL_ID}

**Agent**: ${AGENT}
**Ticket**: ${TICKET_ID:-None}
**Date**: $(date)

## 📝 Summary
${MESSAGE}

## 📂 Files Changed
$(find "$WORKSPACE_DIR" -type f | sed "s|$WORKSPACE_DIR/|- |")

## ✅ Verification
- Automated tests should be run by the Reviewer.
- This change is isolated in \`.uws/crs/${CL_ID}\`.

## 🚀 Approval
Run this command to approve and merge:
\`./scripts/review.sh approve ${CL_ID}\`
EOF

# 5. Update Notifications (Inbox)
# Prepend to top of file (after header)
TEMP_NOTE="${UWS_DIR}/temp_note.md"
echo "- [ ] **${CL_ID}** (${AGENT}): ${MESSAGE} [View Summary](.uws/crs/${CL_ID}/summary.md)" > "$TEMP_NOTE"
sed -i '4r '"$TEMP_NOTE" "$NOTIFICATIONS_FILE"
rm "$TEMP_NOTE"

# 6. Update Ticket Status (if provided)
if [[ -n "$TICKET_ID" ]]; then
    bash "${SCRIPT_DIR}/pm.sh" move "$TICKET_ID" "Review"
    echo "Updated Ticket $TICKET_ID to 'Review'"
fi

echo "✅ Submitted successfully!"
echo "CL ID: ${CL_ID}"
echo "Check NOTIFICATIONS.md for review."
