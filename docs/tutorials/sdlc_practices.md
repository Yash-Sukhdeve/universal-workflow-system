# SDLC Best Practices with UWS

The Universal Workflow System enforces a structured Software Development Life Cycle.

## The 5 Phases

1.  **Requirements**: Don't skip this! Define *what* you are building. User stories, acceptance criteria.
2.  **Design**: Plan *how* you will build it. API signatures, database schemas.
3.  **Implementation**: Write the code. Focus on the requirements.
4.  **Verification**: Test the code. Run automated tests, linting, and manual checks.
5.  **Deployment**: Ship it.

## Error Handling

UWS introduces "State Regression" for quality control:
*   **Verification -> Implementation**: If tests fail, you go back to coding. You cannot deploy broken code.
*   **Deployment -> Verification**: If deployment fails, you go back to verification to diagnose the artifact.

## Tips

*   Use `uws-checkpoint` before every phase transition.
*   Keep `handoff.md` updated with "Next Actions" pointing to the specific phase requirements.
