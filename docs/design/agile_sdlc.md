# Design Document: Agile SDLC for UWS

## 1. Concept
Transform UWS from a purely linear (Waterfall-like) system to an iterative **Agile/Scrum** system.
Instead of a single project lifecycle, the timeline is broken into **Sprints** (e.g., 2 weeks, or agent-session based).

## 2. Terminology Mapping

| Agile Concept | UWS Equivalent |
| :--- | :--- |
| **Product Owner** | `Architect` / `Researcher` (Define tasks) |
| **Scrum Master** | `UWS System` (Enforces process, removes blockers) |
| **Dev Team** | `Implementer`, `Experimenter`, `Optimizer` |
| **Product Backlog** | `.workflow/backlog.md` (New Artifact) |
| **Sprint Backlog** | `.workflow/sprint_current.md` |
| **User Story** | Item in Backlog |
| **Definition of Done** | `Verification` pass by Experimenter |

## 3. The New Workflow Cycle (The Sprint)

Unlike the "Project Phase" which advances linearly (`sdlc_phase`), the **Sprint** cycles repeatedly.

### Phase 1: Sprint Planning
*   **Active Agent**: Architect
*   **Action**: Select items from `backlog.md` → `sprint_current.md`.
*   **Goal**: Define "What are we building *now*?"

### Phase 2: Active Sprint (The Loop)
*   **Active Agent**: Implementer
*   **Action**: Pick a task from `sprint_current.md`.
*   **Micro-Lifecycle**:
    *   `To Do` → `In Progress` (Coding)
    *   `In Progress` → `Review` (Hand off to Experimenter)
    *   `Review` → `Done` (If tests pass) OR `In Progress` (If fail)

### Phase 3: Sprint Review / Retrospective
*   **Active Agent**: Documenter / Experimenter
*   **Action**: Archive `sprint_current.md` to `checkpoints.log`.
*   **Goal**: Update `state.yaml` (Increment Sprint #).

## 4. Required Changes

### Data Structures (`state.yaml`)
Add support for tracking sprints:
```yaml
sdlc:
  mode: "agile" # vs "waterfall"
  sprint:
    id: 1
    status: "active" # planning, active, review
```

### New Artifact: `backlog.md`
A structured markdown file parsed by agents.
```markdown
# Product Backlog

## High Priority
- [ ] As a user, I want login functionality (Points: 5)
- [ ] As a dev, I want a CI pipeline (Points: 3)

## Sprint 1 (Current)
- [ ] [IN_PROGRESS] Setup project structure
```

### New Script: `scripts/agile.sh`
*   `./scripts/agile.sh init` (Setup backlog)
*   `./scripts/agile.sh start-sprint`
*   `./scripts/agile.sh pick-task <task_id>`
*   `./scripts/agile.sh complete-task <task_id>`
*   `./scripts/agile.sh close-sprint`

## 5. Agent Adaptations

*   **Implementer**: Instead of "Working on Implementation Phase", it becomes "Working on Task X from Sprint Y".
*   **Experimenter**: acts as the QA gatekeeper for moving tasks to "Done".
