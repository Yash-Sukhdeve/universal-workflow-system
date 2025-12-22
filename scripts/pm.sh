#!/bin/bash
#
# Universal Workflow System - Project Management Core
#
# Usage: ./scripts/pm.sh [command] [args...]
#

set -e

COMMAND="${1:-list}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
ISSUES_DIR="${PROJECT_ROOT}/.uws/issues"
BOARD_FILE="${PROJECT_ROOT}/BOARD.md"

# Ensure issues directory exists
mkdir -p "$ISSUES_DIR"

if [[ "$COMMAND" == "create" ]]; then
    TITLE="${2:-Untitled}"
    TYPE="${3:-Story}"
    PRIORITY="${4:-Medium}"
    
    # Generate ID (TASK-XXX)
    COUNT=$(ls "$ISSUES_DIR" 2>/dev/null | wc -l || echo 0)
    NEXT_ID=$(printf "TASK-%03d" $((COUNT + 1)))
    FILE="${ISSUES_DIR}/${NEXT_ID}.md"
    
    cat > "$FILE" << EOF
---
id: ${NEXT_ID}
title: ${TITLE}
type: ${TYPE}
status: To Do
priority: ${PRIORITY}
assignee: Unassigned
created: $(date -Iseconds)
---

# Description
(Add description here)

## Acceptance Criteria
- [ ] 

## Activity Log
- $(date -Iseconds): Created by User
EOF
    echo "Created ticket: ${NEXT_ID} - ${TITLE}"
    exit 0
fi

if [[ "$COMMAND" == "list" ]]; then
    # Simple list of tickets
    echo "ID | Status | Assigned | Title"
    echo "---|---|---|---"
    for file in "$ISSUES_DIR"/*.md; do
        [ -e "$file" ] || continue
        ID=$(grep "^id:" "$file" | cut -d: -f2 | xargs)
        STATUS=$(grep "^status:" "$file" | cut -d: -f2- | xargs)
        ASSIGNEE=$(grep "^assignee:" "$file" | cut -d: -f2 | xargs)
        TITLE=$(grep "^title:" "$file" | cut -d: -f2- | xargs)
        echo "$ID | $STATUS | $ASSIGNEE | $TITLE"
    done
    exit 0
fi

if [[ "$COMMAND" == "move" ]]; then
    ID="$2"
    NEW_STATUS="$3"
    FILE="${ISSUES_DIR}/${ID}.md"
    
    if [[ ! -f "$FILE" ]]; then
        echo "Error: Ticket $ID not found."
        exit 1
    fi
    
    # Use sed to update status (simple implementation)
    sed -i "s/^status:.*/status: ${NEW_STATUS}/" "$FILE"
    echo "Updated $ID status to $NEW_STATUS"
    exit 0
fi

if [[ "$COMMAND" == "board" ]]; then
    echo "# 📋 Project Board" > "$BOARD_FILE"
    echo "" >> "$BOARD_FILE"
    echo "Generated: $(date)" >> "$BOARD_FILE"
    echo "" >> "$BOARD_FILE"
    echo "| 📝 To Do | 🚧 In Progress | 👀 Review | ✅ Done |" >> "$BOARD_FILE"
    echo "| :--- | :--- | :--- | :--- |" >> "$BOARD_FILE"
    
    # This is a simplified generator. In a real script we'd buffer columns.
    # For now, we list tickets under headers for readability.
    
    echo "" >> "$BOARD_FILE"
    echo "## To Do" >> "$BOARD_FILE"
    grep -l "status: To Do" "$ISSUES_DIR"/*.md 2>/dev/null | while read f; do
        TITLE=$(grep "^title:" "$f" | cut -d: -f2- | xargs)
        ID=$(grep "^id:" "$f" | cut -d: -f2 | xargs)
        echo "- **[$ID]** $TITLE" >> "$BOARD_FILE"
    done
    
    echo "" >> "$BOARD_FILE"
    echo "## In Progress" >> "$BOARD_FILE"
    grep -l "status: In Progress" "$ISSUES_DIR"/*.md 2>/dev/null | while read f; do
        TITLE=$(grep "^title:" "$f" | cut -d: -f2- | xargs)
        ID=$(grep "^id:" "$f" | cut -d: -f2 | xargs)
        echo "- **[$ID]** $TITLE" >> "$BOARD_FILE"
    done
    
    echo "" >> "$BOARD_FILE"
    echo "## Done" >> "$BOARD_FILE"
    grep -l "status: Done" "$ISSUES_DIR"/*.md 2>/dev/null | while read f; do
         TITLE=$(grep "^title:" "$f" | cut -d: -f2- | xargs)
        ID=$(grep "^id:" "$f" | cut -d: -f2 | xargs)
        echo "- **[$ID]** $TITLE" >> "$BOARD_FILE"
    done
    
    echo "Board generated at $BOARD_FILE"
    exit 0
fi

echo "Unknown command: $COMMAND"
exit 1
