# Skill: Submit Change List (submit_cl)

**Description**: Package your work into a formal Change List (CL) for review.
**Key Command**: \`./scripts/submit.sh "Message" "TICKET-ID"\`

## 🛡️ Pre-Flight Checklist (MANDATORY)
Before running the submit command, you **MUST** ensure:

1.  **Unit Tests**: Do you have unit tests for new logic? Do they pass?
2.  **Linting**: Is the code formatted correctly? No debug prints?
3.  **Documentation**:
    *   Do public functions have docstrings?
    *   Did you update the README if architecture changed?
4.  **Isolation**: Are you only submitting files relevant to the Ticket? (No accidental unrelated changes).

## 📝 The Commit Message
*   **Bad**: "Fixed stuff"
*   **Good**: "Fix(Auth): Handle null token in login flow (Fixes TASK-123)"
    *   Explain *why* the change is needed.
    *   Reference the Ticket ID.
