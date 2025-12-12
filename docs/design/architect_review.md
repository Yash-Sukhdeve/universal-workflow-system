# Architectural Review: UWS Spiral & PM System

**Reviewer**: Chief Software Architect (Simulated)
**Date**: 2025-12-12
**Context**: Evaluation of the "Git-Native PM" and "Spiral SDLC" implementation for scalable, autonomous software development.

## 1. Executive Summary

The proposed system is **promising but immature**. 

While the "Spiral" model is correctly identified as superior to pure Agile for autonomous agents (limiting "hallucination loops" via risk gates), the current implementation lacks the rigor found in enterprise-grade systems like Google's internal tools or Amazon's builder pipelines. Specifically, it lacks a formal **Code Review / Critique** mechanism and a robust **Merge Strategy**.

## 2. Critique of Current Design

### 🟢 Strengths (The "Good")
1.  **Git-Native Truth**: Storing tickets as Markdown (`.uws/issues/`) aligns perfectly with Infrastructure-as-Code principles. It allows Agents to reason about tasks using their native toolset (reading files) without separate API tokens for Jira/Linear.
2.  **The Spiral Choice**: For AI, "Risk Analysis" is strictly required. Pure Agile assumes competent human judgment during sprints. Agents need the explicit "Feasibility Check" that Spiral provides.
3.  **Workspace Isolation**: The `workspace/<agent>` pattern mirrors Google's **CitC (Clients in the Cloud)**, allowing safe experimentation without contaminating `main`.

### 🔴 Weaknesses (The "Bad")
1.  **Missing "Critique" Phase**: In Google/Meta, **Code Review** is the primary quality gate, not just automated tests. Currently, `scripts/sdlc.sh` moves from `Implementation` → `Verification` (Tests). It skips the **Peer Review** step. Use of `lint` is not a substitute for architectural review.
2.  **The Integration Gap**: How does code move from `workspace/implementer` to `main`? The current design implies a manual "handoff". Information silos will form. We need a "Submit Queue" or "Merge Request" concept equivalent to GitHub PRs or Google CLs.
3.  **Human Usability**: A `BOARD.md` is fine for a single user, but for a "Big Team" simulation, the Human Manager needs a way to *approve* gates without editing YAML files manually.

## 3. Benchmarking against Industry Standards

| Feature | Google (Piper/Critique) | Amazon (Builder) | Current UWS Design | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| **Source Control** | Monorepo (Piper) | Package-based | Git Repo | **Pass** (Standard) |
| **Workspace** | Cloud (CitC) | Local/Cloud9 | `workspace/` dirs | **Pass** (Simulated CitC) |
| **Quality Gate** | **Human Code Review** | Automated Pipelines | Automated Tests | **FAIL** (Needs Reviewer) |
| **Task Tracking** | Buganizer | Internal | `.uws/issues/*.md` | **Pass** (Agent-Optimized) |
| **Deployment** | Borg (Container) | Apollo | `scripts/deploy.sh` | **Partial** |

## 4. Recommendations ("The Fix")

To make this "Industry Grade", we must implement the following changes immediately:

### A. Introduce the `Review` Phase
Modify the SDLC to insert a gate between `Implementation` and `Verification`:
`Implementation` → **`Review`** (Diff generated, Human/Agent Architect approves) → `Verification`.

### B. The "Pull Request" Simulation
Agents should not just "finish". They should "submit a CL" (Change List).
*   Create `scripts/submit.sh`.
*   Effect: Moves code from `workspace/implementer` to a staging area (`.uws/staging/`) and generates a `DIFF.md` for the Manager to review.

### C. Formalize the "Risk Gate"
The Spiral `Risk Analysis` phase is currently just a ticket creation. It needs to be a **Blocking Gate**.
*   The `Researcher` must produce a `RISK_REPORT.md`.
*   The cycle cannot proceed to `Engineering` until that file contains `status: APPROVED`.

## 5. Conclusion

The system is creating a solid foundation for *individual* agent work, but fails to simulate the *team dynamics* of a software company. We are building a "Freelancer OS", not a "Company OS". Implementing **Review Gates** and **Submission Queues** will fix this.
