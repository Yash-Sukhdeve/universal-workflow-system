# Company OS Architecture Flowcharts

These diagrams provide a comprehensive view of the Company OS system architecture and operational workflows.
You can render these in any Mermaid-compatible viewer (GitHub, VS Code with Mermaid extension, or [mermaid.live](https://mermaid.live)).

---

## 1. System Hierarchy (Top-Level Architecture)

This diagram shows the layered architecture and data flow between components.

```mermaid
graph TD
    subgraph "Frontend Layer (React + TypeScript + Tailwind)"
        direction LR
        A1[Pages<br/>Dashboard, Tasks, Agents, Memory, Settings]
        A2[Components<br/>LoginForm, Header, Sidebar, AppLayout]
        A3[Hooks<br/>useWebSocket]
        A4[Contexts<br/>AuthContext, WebSocketContext]
        A5[Services<br/>api.ts]
        A1 --> A2 --> A3 & A4 --> A5
    end

    subgraph "API Layer (FastAPI)"
        direction LR
        B1[API Routes<br/>/auth, /tasks, /agents, /memory, /health]
        B2[Core Services<br/>AuthService, EventStore, ProjectionManager, SemanticMemoryService]
        B3[UWSAdapter]
        B1 --> B2
        B1 --> B3
    end

    subgraph "Real-time Layer (WebSocket)"
        C1[ConnectionManager]
        C2[EventPublisher]
        C1 <--> C2
    end

    subgraph "Database Layer (PostgreSQL + pgvector)"
        direction LR
        D1[Event Store<br/>events table]
        D2[Auth Tables<br/>users, organizations, tokens]
        D3[Memory Tables<br/>memories with vector(1536)]
        D4[Read Models<br/>tasks, sessions, approvals]
    end

    subgraph "UWS Workflow System"
        direction LR
        E1[7 Agents<br/>researcher, architect, implementer...]
        E2[Shell Scripts<br/>activate_agent.sh, checkpoint.sh]
        E3[State Files<br/>state.yaml, registry.yaml, handoff.md]
        E1 --> E2 --> E3
    end

    %% Data Flow
    A5 -- "HTTP Requests" --> B1
    B1 -- "Returns JSON" --> A5
    A3 -- "Connects & Listens" --> C1
    C2 -- "Broadcasts Events" --> C1
    C1 -- "Pushes Updates" --> A3
    B2 -- "Reads/Writes" --> D1 & D2 & D3 & D4
    B3 -- "Executes & Reads" --> E2 & E3
```

---

## 2. Authentication Flow

Shows how users authenticate and establish secure WebSocket connections.

```mermaid
flowchart TD
    subgraph "Frontend"
        A1(User enters credentials in LoginForm) --> A2(api.ts sends POST /api/auth/login)
        A2 --> A3(Waits for response...)
        A4(AuthContext stores JWT token) --> A5(useWebSocket hook connects)
        A5 --> A6(Client sends 'auth' event with token)
        A7(Receives 'auth_success' event) --> A8(User is authenticated, UI unlocked)
    end

    subgraph "Backend API (FastAPI)"
        B1(Route /api/auth/login receives request) --> B2(AuthService validates credentials)
        B2 -- "Valid" --> B3(AuthService generates JWT)
        B2 -- "Invalid" --> B4(Returns 401 Unauthorized)
        B3 --> B5(API returns JWT to client)
        B6(ConnectionManager receives WebSocket connection) --> B7(Verifies token from 'auth' event)
        B7 -- "Valid" --> B8(Sends 'auth_success' event to client)
        B7 -- "Invalid" --> B9(Sends 'auth_error' and closes connection)
    end

    A3 --> B1
    B5 --> A4
    A6 --> B6
    B8 --> A7
```

---

## 3. Task Creation & Assignment (Event Sourcing / CQRS)

Demonstrates the event sourcing pattern used for task management.

```mermaid
flowchart TD
    subgraph "User Action (Frontend)"
        T1(User creates task in UI) --> T2(api.ts sends POST /api/tasks)
        T3(UI updates optimistically or on WebSocket event)
        T4(User assigns task to Agent) --> T5(api.ts sends POST /api/tasks/id/assign)
    end

    subgraph "Backend API (FastAPI)"
        subgraph "CQRS Flow"
            direction LR
            E1(EventStore: Appends 'TaskCreated' or 'TaskAssigned' event) --> E2(EventPublisher: Broadcasts 'task_update' via WebSocket)
            E1 --> E3(ProjectionManager: Updates 'tasks_read_model' in PostgreSQL)
        end

        R1(/api/tasks receives request) --> E1
        R2(Client's WebSocket receives 'task_update')
        R3(/api/tasks/id/assign receives request) --> E1
    end

    subgraph "Database (PostgreSQL)"
        DB1(events table - append-only)
        DB2(tasks_read_model table - queryable)
    end

    T2 --> R1
    E2 --> R2 --> T3
    E3 -- "writes to" --> DB2
    E1 -- "writes to" --> DB1
    T5 --> R3
```

---

## 4. Agent Activation & Session Management

Shows how agents are activated and managed through the UWS integration.

```mermaid
flowchart TD
    subgraph "Frontend"
        AG1(User clicks 'Activate Agent' on AgentsPage) --> AG2(api.ts sends POST /api/agents/activate)
        AG3(UI listens for WebSocket 'agent_status' event) --> AG4(Updates agent status to 'Active')
    end

    subgraph "Backend API (FastAPI)"
        AA1(Route /api/agents/activate) --> AA2(Calls UWSAdapter)
        AA2 --> AA3(UWSAdapter validates args - prevents injection)
        AA3 --> AA4(Executes activate_agent.sh via subprocess)
        AA5(Script finishes) --> AA6(UWSAdapter reads updated state.yaml)
        AA6 --> AA7(Returns session ID to frontend)
        AA4 --> AA8(EventPublisher broadcasts 'agent_status' update)
    end

    subgraph "UWS Workflow System (File System)"
        SH1(activate_agent.sh runs) --> SH2(Creates session in sessions.yaml)
        SH2 --> SH3(Updates .workflow/state.yaml with active_agent)
    end

    AG2 --> AA1
    AA4 --> SH1
    AA8 --> AG3
    SH3 --> AA5
```

---

## 5. Semantic Memory Storage & Retrieval

Demonstrates the vector-based memory system for AI learning.

```mermaid
flowchart TD
    subgraph "Action Trigger (Agent or User)"
        M1(Action generates text to memorize<br/>e.g., 'decision', 'code_pattern', 'error')
        M1 --> M2(Client sends POST /api/memory/store)
    end

    subgraph "Backend API - Storage"
        MS1(/api/memory/store receives request) --> MS2(Calls EmbeddingService)
        MS2 --> MS3(EmbeddingService sends text to OpenAI)
        MS4(Receives 1536-dimensional vector) --> MS5(SemanticMemoryService stores text + vector)
    end

    subgraph "External Service"
        O1(OpenAI text-embedding-3-small API)
    end

    subgraph "Backend API - Retrieval"
        MR1(Client sends POST /api/memory/search with query) --> MR2(Calls EmbeddingService with query)
        MR3(Gets vector for query) --> MR4(SemanticMemoryService performs cosine similarity search)
        MR4 --> MR5(Returns top matching memories with similarity scores)
    end

    subgraph "Database (PostgreSQL + pgvector)"
        DBM1(memories table<br/>with vector index IVFFlat)
    end

    %% Storage Flows
    M2 --> MS1
    MS3 --> O1
    O1 --> MS4
    MS5 -- "INSERT INTO" --> DBM1

    %% Retrieval Flows
    MR2 --> O1
    O1 --> MR3
    MR4 -- "SELECT ... ORDER BY embedding <=> query" --> DBM1
```

---

## 6. Complete Data Flow Summary

```mermaid
flowchart LR
    subgraph User["User Interface"]
        Browser[React Dashboard]
    end

    subgraph Backend["Company OS Backend"]
        API[FastAPI Server]
        WS[WebSocket Server]
        UWS[UWS Adapter]
    end

    subgraph Storage["Data Layer"]
        PG[(PostgreSQL)]
        VEC[(pgvector Extension)]
        FS[File System<br/>.workflow/]
    end

    subgraph External["External Services"]
        OAI[OpenAI Embeddings API]
    end

    Browser -- "REST API" --> API
    Browser <-- "Real-time Events" --> WS
    API -- "Event Sourcing" --> PG
    API -- "Vector Search" --> VEC
    API -- "Embeddings" --> OAI
    UWS -- "Shell Scripts" --> FS
    API --> UWS
```

---

## 7. UWS Phase Workflow

```mermaid
stateDiagram-v2
    [*] --> phase_1_planning
    phase_1_planning --> phase_2_implementation: Requirements Complete
    phase_2_implementation --> phase_3_validation: Code Complete
    phase_3_validation --> phase_4_delivery: Tests Pass
    phase_4_delivery --> phase_5_maintenance: Deployed
    phase_5_maintenance --> [*]: Project Complete

    phase_3_validation --> phase_2_implementation: Tests Fail
    phase_4_delivery --> phase_3_validation: Deployment Fail
```

---

## 8. Agent Hierarchy

```mermaid
graph TB
    subgraph "Research Phase"
        R[Researcher<br/>literature_review, experimental_design]
    end

    subgraph "Design Phase"
        A[Architect<br/>system_design, api_design, patterns]
    end

    subgraph "Build Phase"
        I[Implementer<br/>code_generation, debugging, testing]
        E[Experimenter<br/>experimental_design, data_collection]
    end

    subgraph "Quality Phase"
        O[Optimizer<br/>performance_tuning, refactoring]
    end

    subgraph "Release Phase"
        D[Deployer<br/>containerization, ci_cd, monitoring]
        Doc[Documenter<br/>documentation, api_docs, guides]
    end

    R --> A
    A --> I
    A --> E
    I --> O
    E --> O
    O --> D
    D --> Doc
```

---

## How to Render These Diagrams

1. **GitHub**: Copy the Mermaid code blocks into any `.md` file in a GitHub repo - they render automatically
2. **VS Code**: Install the "Mermaid Preview" or "Markdown Preview Mermaid Support" extension
3. **Online**: Paste into [mermaid.live](https://mermaid.live) for interactive editing
4. **Export**: Use mermaid.live to export as PNG, SVG, or PDF

---

*Generated from Company OS architecture analysis - December 2025*
