# Design Document: Spiral (Risk-Driven) SDLC for UWS

## 1. Concept
The **Spiral Model** combines the iterative nature of Agile with the controlled, systematic aspects of the Waterfall model, with a specific focus on **Risk Analysis**.

In UWS, this maps perfectly to our multi-agent system, where specialized agents can perform the "Risk Analysis" (e.g., Researcher/Experimenter) before the "Engineering" (Implementer) begins.

## 2. The Four Quadrants of UWS Spiral

Each "Turn of the Spiral" (Iteration) goes through these 4 steps:

### Q1: Determine Objectives (Planning)
*   **Active Agent**: Architect / Researcher
*   **Artifacts**: `backlog.md` (Updated objectives)
*   **Goal**: Define *what* we want to achieve in this cycle (e.g., "Build Auth System v0.1").

### Q2: Identify & Resolve Risks (Risk Analysis)
*   **Active Agent**: Researcher / Experimenter
*   **Actions**:
    *   Prototyping
    *   Feasibility studies
    *   "Spike" solutions
*   **Goal**: Determine *if* it can be built and *what* might go wrong.
*   **Exit Criteria**: "Risk Review" signed off. If risk is too high, we spiral back to Planning (reduce scope).

### Q3: Development & Test (Engineering)
*   **Active Agent**: Implementer
*   **Actions**: Standard coding and unit testing.
*   **Goal**: Build the operational artifact.
*   **Exit Criteria**: Passing tests (Verification).

### Q4: Plan Next Iteration (Evaluation)
*   **Active Agent**: Project Lead (System) / User
*   **Actions**:
    *   Review the artifact.
    *   Update `state.yaml` with lessons learned.
    *   Commit changes.
*   **Goal**: Decide the scope of the *next* spiral.

## 3. Hybrid Agile-Spiral Workflow

We can combine Agile's "Sprints" with Spiral's "Risk Phase".

**The "Risk-Aware Sprint":**

1.  **Sprint Planning**: Pick stories.
2.  **Risk Gate**: Before coding starts, the **Researcher** agent performs a check:
    *   "Do we know how to do this?"
    *   "Are there unknown libraries?"
    *   *If High Risk*: Spawn a "Research Task" first.
    *   *If Low Risk*: Proceed to Implementation.
3.  **Implementation**: Coding (Agile style).
4.  **Review/Evaluation**: Demo & Planning.

## 4. Implementation Details

### New `state.yaml` Structure
```yaml
sdlc:
  mode: "spiral"
  cycle: 1
  quadrant: "risk_analysis" # planning, risk, engineering, evaluation
  current_risks:
    - "Library compatibility untest"
```

### New Core Script: `scripts/spiral.sh`
*   `./scripts/spiral.sh start-cycle`
*   `./scripts/spiral.sh assess-risk` (Triggers Researcher)
*   `./scripts/spiral.sh build` (Triggers Implementer)
*   `./scripts/spiral.sh evaluate` (Triggers Checkpoint)

## 5. Benefits for Autonomous Agents
A pure Agile model can lead agents to "spin their wheels" on impossible tasks. The Spiral model forces a **Feasibility Check** (Q2) before they commit resources to coding. This saves token costs and time by failing fast on high-risk features.
