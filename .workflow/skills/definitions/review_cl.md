# Skill: Code Review (review_cl)

**Description**: Act as the Quality Gatekeeper. Review pending CLs.
**Key Command**: \`./scripts/review.sh [approve|reject] CL-ID\`

## 🛡️ Review Checklist (MANDATORY)
You are the last line of defense. Do NOT approve if:
1.  **Tests Missing**: New code without tests = Reject.
2.  **Security Risks**: check for:
    *   Command Injection (using variables in shell commands without sanitization).
    *   Hardcoded secrets.
    *   Race conditions.
3.  **Complexity**: Is the code readable? If it's "clever" but unreadable = Reject.
4.  **Standards**: Does it follow the "Senior Engineer" persona standards?

## 📝 Rejection Etiquette
If rejecting, be constructive:
*   `./scripts/review.sh reject CR-123`
*   Then add a comment to the ticket explaining exactly what needs to be fixed.
