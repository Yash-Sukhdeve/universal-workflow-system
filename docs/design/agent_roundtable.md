# Roundtable Session: Company OS Robustness

**Topic**: Ensuring `submit.sh` and `review.sh` are robust, easy, and human-centric.
**Date**: 2025-12-12

## Participants
1.  **UX Designer Agent** (Focus: Ease of use, Human Friction)
2.  **DevOps Agent** (Focus: Reliability, Conflict Handling)
3.  **Product Manager Agent** (Focus: Process Flow, "Human in Loop")

---

## 1. UX Designer: "Ease of Use" Critique

**Critique**: 
"Command line tools (`submit.sh`, `review.sh`) are powerful but intimidating for high-level management. A human manager doesn't want to type `grep` to see what changed."

**Suggestion: "The Human-Readable Digest"**
When an agent submits a change, don't just dump a `diff`. Create a **Summary Artifact** (`CL_SUMMARY.md`) that explains:
*   *Why* I made this change.
*   *What* files I touched.
*   *How* to test it.
*   Human-readable "Approve/Reject" commands at the bottom (copy-pasteable).

**Implementation**:
Modify `submit.sh` to generate a `CL_SUMMARY.md` in the `cr` directory.

## 2. DevOps Agent: "Robustness" Critique

**Critique**:
"What happens if two agents submit changes to the same file? Or if the Human approves `CR-002` before `CR-001`? We'll get merge conflicts, and your scripts will break because they just `cp` files."

**Suggestion: "The Staging Area & Three-Way Merge"**
*   Do NOT just copy files from `workspace/` to `main`.
*   Use `git` commands under the hood. 
*   When `approve` is run, try `git merge`. If conflict, **HALT** and ask Human to resolve.
*   This ensures the "Robustness" requirement is met by leveraging Git's 20 years of conflict resolution logic.

## 3. Product Manager: "Human in the Loop" Critique

**Critique**:
"We need to make sure the Human is *Always* in control. Agents shouldn't be able to sneak changes in."

**Suggestion: "The Approval Token"**
*   The `submit.sh` script should be **read-only** for Agents (they can create CRs, but never apply them).
*   The `review.sh approve` command should require a "Human Token" or confirmation flag (e.g., `--confirm`) that only you (the user) provide.
*   Add a `notifications.md` file where pending approvals pile up, so the Human has *one place* to check.

---

## Synthesized Action Plan

1.  **Refine `submit.sh`**: 
    *   Use `git diff` to generate the patch.
    *   Generate `CL_SUMMARY.md` (UX requirement).
2.  **Refine `review.sh`**:
    *   Use `git apply` (safer than `cp`).
    *   Check for conflicts.
    *   Update `BOARD.md` automatically (DevOps requirement).
3.  **New Artifact**: `NOTIFICATIONS.md` (PM requirement) as the central "Inbox" for the Human.
