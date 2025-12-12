# Skill: System Design

**Description**: Architect scalable and robust systems.
**Artifact**: `docs/design/<topic>.md`

## 🏗️ Design Template (C4 Model Inspired)
When creating a design doc, use this structure:

### 1. Context (The "Why")
*   What problem are we solving?
*   Who are the users?

### 2. Containers (The "What")
*   What are the high-level components? (e.g., Web App, API Server, DB, Worker)
*   Diagram (Mermaid):
    ```mermaid
    graph TD
    User --> WebApp
    WebApp --> API
    API --> DB
    ```

### 3. Components (The "How")
*   Deep dive into one container (e.g., API classes).

### 4. Cross-Cutting Concerns (The "Risks")
*   **Security**: Authentication, Authorization, Encryption.
*   **Reliability**: What happens if the DB is down? (Retries, Circuit Breakers).
*   **Observability**: Metrics, Logs, Tracing.
