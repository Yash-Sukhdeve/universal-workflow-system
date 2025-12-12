# Design Document: Git-Native Project Management (The "Jira" Layer)

## 1. Concept
To support a "Big Team" feel where a **Human Manager** directs **AI Agents**, we need a persistent, structured Issue Tracking System (ITS) living directly in the repository.

Instead of a SaaS (Jira/Linear), we use the filesystem. This allows Agents to read/write tickets naturally as code, while Humans can view them via Markdown or CLI.

## 2. Structure: The `.uws/issues/` Directory

Every ticket is a Markdown file with YAML frontmatter (metadata).

**Path**: `.uws/issues/TASK-001.md`

```markdown
---
id: TASK-001
title: Implement User Authentication
type: Story         # Story, Bug, Epic, Task
status: In Progress # To Do, In Progress, Review, Done
priority: High      # Low, Medium, High, Critical
assignee: Implementer
sprint: Sprint-1
created: 2025-12-12T10:00:00Z
points: 5
---

# Description
As a user, I need to log in so that I can access my profile.

## Acceptance Criteria
- [ ] Email/Password login
- [ ] OAuth support (Google)
- [ ] Error handling for bad password

## Activity Log
- 2025-12-12: Created by Human Manager
- 2025-12-12: Assigned to Implementer by System
```

## 3. The "Board" View

We generate a read-only `BOARD.md` in the root (or `.uws/`) that simulates a Kanban board for the human manager.

```markdown
# 📋 Project Board (Sprint 1)

| 📝 To Do | 🚧 In Progress | 👀 Review | ✅ Done |
| :--- | :--- | :--- | :--- |
| **[TASK-002]**<br>Fix CSS Bug<br>*(Implementer)* | **[TASK-001]**<br>Auth System<br>*(Implementer)* | | **[TASK-000]**<br>Setup<br>*(Architect)* |
```

## 4. Workflows

### The Manager (Human) Role
1.  **Create Epics/Stories**: Human creates high-level tickets.
2.  **Prioritize**: Human arranges the order/priority.
3.  **Review**: Human comments on tickets (appending to `.md` file) to give feedback.

### The Agent Roles
1.  **Project Manager (System)**:
    *   Scans `issues/` directory.
    *   Generates `BOARD.md`.
    *   Assigns unassigned tickets based on workload.
2.  **Worker Agents (Implementer, etc.)**:
    *   "Check my tickets": `grep assignee: Implementer .uws/issues/*.md`
    *   "Move to In Progress": Update metadata status.
    *   "Update Ticket": Check off acceptance criteria in the file.

## 5. Integration with SDLC

*   **Agile**: Tickets are linked to Sprints (`sprint: Sprint-1`).
*   **Spiral**: Tickets can represent Risk Spikes (`type: Spike`).
*   **Waterfall**: Tickets can be gated by phases (`phase: Requirements`).

## 6. Implementation: `scripts/pm.sh`

*   `pm.sh create --title "..." --type Story`
*   `pm.sh list --status "In Progress"`
*   `pm.sh move TASK-001 "Done"`
*   `pm.sh generate-board`
