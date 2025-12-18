# Critical Issue #1: Data Architecture Deep-Dive

## The Problem

Your current architecture has **three separate data stores** with no consistency guarantees:

```
Event Store → PostgreSQL → Vector DB
     ↓            ↓           ↓
  Events      State       Embeddings
```

**What happens:**
1. Agent completes task
2. Event written to Event Store ✓
3. PostgreSQL update FAILS (timeout)
4. Vector DB updated ✓

**Result:** Your system now has THREE different views of reality. This WILL happen under load.

---

## The Solution: Event Store as Single Source of Truth

### Architecture Pattern: Event Sourcing + CQRS

```
┌─────────────────────────────────────────────────────────────────┐
│                    WRITE PATH (Commands)                         │
│                                                                  │
│  API Request → Validate → Append Event → Return Success          │
│                              │                                   │
│                              ▼                                   │
│                    ┌─────────────────┐                          │
│                    │  EVENT STORE    │ ← Single Source of Truth │
│                    │  (PostgreSQL)   │                          │
│                    └────────┬────────┘                          │
│                             │                                    │
└─────────────────────────────┼────────────────────────────────────┘
                              │ Events published
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    READ PATH (Queries)                           │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ State View   │    │ Search View  │    │ Analytics    │      │
│  │ (PostgreSQL) │    │ (pgvector)   │    │   View       │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│        ↑                    ↑                    ↑              │
│        └────────────────────┴────────────────────┘              │
│                    Event Handlers (async)                        │
│                    - Retry on failure                            │
│                    - Dead letter queue                           │
│                    - Eventually consistent                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## PostgreSQL Schema Implementation

### 1. Event Store Table

```sql
-- migrations/001_create_event_store.sql

-- Event Store: The ONLY place writes happen
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,

    -- Stream identification (e.g., "task:123", "agent:456")
    stream_id VARCHAR(255) NOT NULL,
    stream_version INT NOT NULL,

    -- Event metadata
    event_type VARCHAR(100) NOT NULL,
    event_version VARCHAR(10) NOT NULL DEFAULT '1.0',

    -- Event payload (the actual data)
    event_data JSONB NOT NULL,

    -- Audit fields
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Optimistic concurrency control
    UNIQUE(stream_id, stream_version)
);

-- Indexes for common query patterns
CREATE INDEX idx_events_stream ON events(stream_id, stream_version);
CREATE INDEX idx_events_type ON events(event_type);
CREATE INDEX idx_events_created ON events(created_at);
CREATE INDEX idx_events_data ON events USING GIN(event_data);

-- Function to append event with optimistic locking
CREATE OR REPLACE FUNCTION append_event(
    p_stream_id VARCHAR(255),
    p_expected_version INT,
    p_event_type VARCHAR(100),
    p_event_data JSONB,
    p_metadata JSONB DEFAULT '{}'
) RETURNS BIGINT AS $$
DECLARE
    v_new_version INT;
    v_event_id BIGINT;
BEGIN
    -- Calculate new version
    v_new_version := p_expected_version + 1;

    -- Try to insert (will fail if version conflict)
    INSERT INTO events (stream_id, stream_version, event_type, event_data, metadata)
    VALUES (p_stream_id, v_new_version, p_event_type, p_event_data, p_metadata)
    RETURNING id INTO v_event_id;

    -- Notify listeners
    PERFORM pg_notify('events', json_build_object(
        'id', v_event_id,
        'stream_id', p_stream_id,
        'event_type', p_event_type
    )::text);

    RETURN v_event_id;

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Concurrency conflict: stream % expected version %, but conflict occurred',
            p_stream_id, p_expected_version;
END;
$$ LANGUAGE plpgsql;
```

### 2. State Projection Tables (Read Models)

```sql
-- migrations/002_create_read_models.sql

-- Organizations (denormalized for fast reads)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    version INT NOT NULL DEFAULT 0
);

-- Users with Row-Level Security
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id),
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    role VARCHAR(50) NOT NULL DEFAULT 'member',
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    version INT NOT NULL DEFAULT 0,

    UNIQUE(org_id, email)
);

-- Enable Row-Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_org_isolation ON users
    USING (org_id = current_setting('app.current_org_id')::uuid);

-- Projects
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    version INT NOT NULL DEFAULT 0
);

ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

CREATE POLICY projects_org_isolation ON projects
    USING (org_id = current_setting('app.current_org_id')::uuid);

-- Tasks
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id),
    project_id UUID REFERENCES projects(id),
    title VARCHAR(500) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'todo',
    priority VARCHAR(20) DEFAULT 'medium',
    assignee_id UUID REFERENCES users(id),
    agent_session_id VARCHAR(255),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    version INT NOT NULL DEFAULT 0
);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY tasks_org_isolation ON tasks
    USING (org_id = current_setting('app.current_org_id')::uuid);

-- Agent Sessions
CREATE TABLE agent_sessions (
    id VARCHAR(255) PRIMARY KEY,
    org_id UUID NOT NULL REFERENCES organizations(id),
    agent_type VARCHAR(50) NOT NULL,
    task_id UUID REFERENCES tasks(id),
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    progress INT DEFAULT 0,
    checkpoint_state JSONB,
    thought_stream TEXT[],
    started_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    result VARCHAR(50)
);

ALTER TABLE agent_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY sessions_org_isolation ON agent_sessions
    USING (org_id = current_setting('app.current_org_id')::uuid);

-- Projections tracking (what version each projection is at)
CREATE TABLE projection_checkpoints (
    projection_name VARCHAR(100) PRIMARY KEY,
    last_event_id BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 3. Vector Storage with pgvector

```sql
-- migrations/003_create_vector_storage.sql

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Knowledge embeddings
CREATE TABLE knowledge_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id),

    -- Source reference
    source_type VARCHAR(50) NOT NULL,  -- 'task', 'document', 'decision'
    source_id UUID NOT NULL,
    chunk_index INT DEFAULT 0,

    -- Content
    content TEXT NOT NULL,
    content_hash VARCHAR(64) NOT NULL,  -- SHA256 for dedup

    -- Vector embedding (1536 dimensions for OpenAI, 1024 for others)
    embedding vector(1536),

    -- Metadata for filtering
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(source_type, source_id, chunk_index)
);

ALTER TABLE knowledge_embeddings ENABLE ROW LEVEL SECURITY;

CREATE POLICY embeddings_org_isolation ON knowledge_embeddings
    USING (org_id = current_setting('app.current_org_id')::uuid);

-- Vector similarity search index (IVFFlat for large datasets)
CREATE INDEX idx_embeddings_vector ON knowledge_embeddings
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Function for semantic search
CREATE OR REPLACE FUNCTION search_knowledge(
    p_org_id UUID,
    p_query_embedding vector(1536),
    p_limit INT DEFAULT 10,
    p_source_type VARCHAR(50) DEFAULT NULL
) RETURNS TABLE (
    id UUID,
    source_type VARCHAR(50),
    source_id UUID,
    content TEXT,
    similarity FLOAT
) AS $$
BEGIN
    -- Set org context for RLS
    PERFORM set_config('app.current_org_id', p_org_id::text, true);

    RETURN QUERY
    SELECT
        ke.id,
        ke.source_type,
        ke.source_id,
        ke.content,
        1 - (ke.embedding <=> p_query_embedding) as similarity
    FROM knowledge_embeddings ke
    WHERE (p_source_type IS NULL OR ke.source_type = p_source_type)
    ORDER BY ke.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## Python Implementation

### 1. Event Store Client

```python
# company_os/core/events/store.py

from typing import Any, Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime
import json
import asyncpg
from asyncpg import Connection, Pool

@dataclass
class Event:
    """Domain event representation."""
    stream_id: str
    event_type: str
    data: Dict[str, Any]
    metadata: Dict[str, Any] = field(default_factory=dict)
    version: int = 0
    id: Optional[int] = None
    created_at: Optional[datetime] = None


class EventStore:
    """
    Event Store implementation using PostgreSQL.

    This is the SINGLE SOURCE OF TRUTH for all state changes.
    All writes go through here. Read models are projections.
    """

    def __init__(self, pool: Pool):
        self.pool = pool
        self._handlers: Dict[str, List[callable]] = {}

    async def append(
        self,
        stream_id: str,
        event_type: str,
        data: Dict[str, Any],
        expected_version: int = -1,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Event:
        """
        Append an event to a stream with optimistic concurrency.

        Args:
            stream_id: Unique identifier for the stream (e.g., "task:123")
            event_type: Type of event (e.g., "TaskCreated")
            data: Event payload
            expected_version: Expected current version (-1 for new stream)
            metadata: Additional metadata (user_id, correlation_id, etc.)

        Returns:
            The created Event

        Raises:
            ConcurrencyError: If version conflict occurs
        """
        metadata = metadata or {}
        metadata['timestamp'] = datetime.utcnow().isoformat()

        async with self.pool.acquire() as conn:
            try:
                row = await conn.fetchrow(
                    "SELECT append_event($1, $2, $3, $4, $5)",
                    stream_id,
                    expected_version,
                    event_type,
                    json.dumps(data),
                    json.dumps(metadata)
                )

                event = Event(
                    id=row[0],
                    stream_id=stream_id,
                    event_type=event_type,
                    data=data,
                    metadata=metadata,
                    version=expected_version + 1,
                    created_at=datetime.utcnow()
                )

                # Trigger async handlers
                await self._dispatch(event)

                return event

            except asyncpg.UniqueViolationError:
                raise ConcurrencyError(
                    f"Version conflict on stream {stream_id}. "
                    f"Expected version {expected_version}"
                )

    async def read_stream(
        self,
        stream_id: str,
        from_version: int = 0,
        to_version: Optional[int] = None
    ) -> List[Event]:
        """Read all events from a stream."""
        async with self.pool.acquire() as conn:
            query = """
                SELECT id, stream_id, stream_version, event_type,
                       event_data, metadata, created_at
                FROM events
                WHERE stream_id = $1 AND stream_version >= $2
            """
            params = [stream_id, from_version]

            if to_version is not None:
                query += " AND stream_version <= $3"
                params.append(to_version)

            query += " ORDER BY stream_version"

            rows = await conn.fetch(query, *params)

            return [
                Event(
                    id=row['id'],
                    stream_id=row['stream_id'],
                    event_type=row['event_type'],
                    data=json.loads(row['event_data']),
                    metadata=json.loads(row['metadata']),
                    version=row['stream_version'],
                    created_at=row['created_at']
                )
                for row in rows
            ]

    async def read_all(
        self,
        from_id: int = 0,
        batch_size: int = 100,
        event_types: Optional[List[str]] = None
    ) -> List[Event]:
        """Read all events across all streams (for projections)."""
        async with self.pool.acquire() as conn:
            query = """
                SELECT id, stream_id, stream_version, event_type,
                       event_data, metadata, created_at
                FROM events
                WHERE id > $1
            """
            params = [from_id]

            if event_types:
                query += " AND event_type = ANY($2)"
                params.append(event_types)

            query += " ORDER BY id LIMIT $" + str(len(params) + 1)
            params.append(batch_size)

            rows = await conn.fetch(query, *params)

            return [
                Event(
                    id=row['id'],
                    stream_id=row['stream_id'],
                    event_type=row['event_type'],
                    data=json.loads(row['event_data']),
                    metadata=json.loads(row['metadata']),
                    version=row['stream_version'],
                    created_at=row['created_at']
                )
                for row in rows
            ]

    def subscribe(self, event_type: str, handler: callable):
        """Subscribe to events of a specific type."""
        if event_type not in self._handlers:
            self._handlers[event_type] = []
        self._handlers[event_type].append(handler)

    async def _dispatch(self, event: Event):
        """Dispatch event to registered handlers."""
        handlers = self._handlers.get(event.event_type, [])
        handlers.extend(self._handlers.get('*', []))  # Wildcard handlers

        for handler in handlers:
            try:
                await handler(event)
            except Exception as e:
                # Log error but don't fail the write
                # Dead letter queue should pick this up
                print(f"Handler error for {event.event_type}: {e}")


class ConcurrencyError(Exception):
    """Raised when optimistic concurrency check fails."""
    pass
```

### 2. Projection Engine

```python
# company_os/core/events/projections.py

from typing import Dict, Any, Optional
from abc import ABC, abstractmethod
import asyncio
import asyncpg

from .store import EventStore, Event


class Projection(ABC):
    """
    Base class for read model projections.

    Projections transform events into queryable read models.
    They are eventually consistent with the event store.
    """

    name: str  # Unique projection name

    @abstractmethod
    async def handle(self, event: Event, conn: asyncpg.Connection):
        """Process an event and update the read model."""
        pass

    @abstractmethod
    def handles(self) -> list[str]:
        """Return list of event types this projection handles."""
        pass


class TaskProjection(Projection):
    """Projects task events into the tasks read model."""

    name = "tasks"

    def handles(self) -> list[str]:
        return [
            "TaskCreated",
            "TaskUpdated",
            "TaskAssigned",
            "TaskStatusChanged",
            "TaskDeleted"
        ]

    async def handle(self, event: Event, conn: asyncpg.Connection):
        handlers = {
            "TaskCreated": self._on_created,
            "TaskUpdated": self._on_updated,
            "TaskAssigned": self._on_assigned,
            "TaskStatusChanged": self._on_status_changed,
            "TaskDeleted": self._on_deleted,
        }

        handler = handlers.get(event.event_type)
        if handler:
            await handler(event, conn)

    async def _on_created(self, event: Event, conn: asyncpg.Connection):
        data = event.data
        await conn.execute("""
            INSERT INTO tasks (id, org_id, project_id, title, description,
                             status, priority, created_at, updated_at, version)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8, $9)
            ON CONFLICT (id) DO NOTHING
        """,
            data['id'],
            data['org_id'],
            data.get('project_id'),
            data['title'],
            data.get('description'),
            data.get('status', 'todo'),
            data.get('priority', 'medium'),
            event.created_at,
            event.version
        )

    async def _on_updated(self, event: Event, conn: asyncpg.Connection):
        data = event.data
        # Only update if our version is newer
        await conn.execute("""
            UPDATE tasks
            SET title = COALESCE($2, title),
                description = COALESCE($3, description),
                priority = COALESCE($4, priority),
                metadata = metadata || $5,
                updated_at = $6,
                version = $7
            WHERE id = $1 AND version < $7
        """,
            data['id'],
            data.get('title'),
            data.get('description'),
            data.get('priority'),
            data.get('metadata', {}),
            event.created_at,
            event.version
        )

    async def _on_assigned(self, event: Event, conn: asyncpg.Connection):
        data = event.data
        await conn.execute("""
            UPDATE tasks
            SET assignee_id = $2,
                agent_session_id = $3,
                updated_at = $4,
                version = $5
            WHERE id = $1 AND version < $5
        """,
            data['id'],
            data.get('assignee_id'),
            data.get('agent_session_id'),
            event.created_at,
            event.version
        )

    async def _on_status_changed(self, event: Event, conn: asyncpg.Connection):
        data = event.data
        await conn.execute("""
            UPDATE tasks
            SET status = $2,
                updated_at = $3,
                version = $4
            WHERE id = $1 AND version < $4
        """,
            data['id'],
            data['status'],
            event.created_at,
            event.version
        )

    async def _on_deleted(self, event: Event, conn: asyncpg.Connection):
        # Soft delete - mark as deleted rather than remove
        await conn.execute("""
            UPDATE tasks
            SET status = 'deleted',
                updated_at = $2,
                version = $3
            WHERE id = $1
        """,
            event.data['id'],
            event.created_at,
            event.version
        )


class ProjectionRunner:
    """
    Runs projections to keep read models in sync with event store.

    Features:
    - Catches up from last checkpoint
    - Handles failures with retries
    - Supports multiple projections
    """

    def __init__(
        self,
        event_store: EventStore,
        pool: asyncpg.Pool,
        projections: list[Projection]
    ):
        self.event_store = event_store
        self.pool = pool
        self.projections = {p.name: p for p in projections}
        self._running = False

    async def start(self):
        """Start the projection runner."""
        self._running = True

        # Catch up each projection
        for projection in self.projections.values():
            await self._catch_up(projection)

        # Subscribe to new events
        for projection in self.projections.values():
            for event_type in projection.handles():
                self.event_store.subscribe(
                    event_type,
                    lambda e, p=projection: self._handle_event(p, e)
                )

    async def _catch_up(self, projection: Projection):
        """Catch up a projection from its last checkpoint."""
        async with self.pool.acquire() as conn:
            # Get last processed event ID
            row = await conn.fetchrow("""
                SELECT last_event_id FROM projection_checkpoints
                WHERE projection_name = $1
            """, projection.name)

            last_id = row['last_event_id'] if row else 0

            # Process events in batches
            while True:
                events = await self.event_store.read_all(
                    from_id=last_id,
                    batch_size=100,
                    event_types=projection.handles()
                )

                if not events:
                    break

                for event in events:
                    await self._handle_event(projection, event)
                    last_id = event.id

                # Update checkpoint
                await conn.execute("""
                    INSERT INTO projection_checkpoints (projection_name, last_event_id, updated_at)
                    VALUES ($1, $2, NOW())
                    ON CONFLICT (projection_name)
                    DO UPDATE SET last_event_id = $2, updated_at = NOW()
                """, projection.name, last_id)

    async def _handle_event(self, projection: Projection, event: Event):
        """Handle a single event with retry logic."""
        max_retries = 3

        for attempt in range(max_retries):
            try:
                async with self.pool.acquire() as conn:
                    await projection.handle(event, conn)
                return
            except Exception as e:
                if attempt == max_retries - 1:
                    # Send to dead letter queue
                    await self._dead_letter(event, projection.name, str(e))
                else:
                    await asyncio.sleep(2 ** attempt)  # Exponential backoff

    async def _dead_letter(self, event: Event, projection: str, error: str):
        """Send failed event to dead letter queue for manual review."""
        async with self.pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO dead_letter_queue (event_id, projection_name, error, created_at)
                VALUES ($1, $2, $3, NOW())
            """, event.id, projection, error)
```

### 3. Domain Services Using Event Sourcing

```python
# company_os/domain/tasks/service.py

from typing import Optional
from uuid import UUID, uuid4
from dataclasses import dataclass

from company_os.core.events.store import EventStore, ConcurrencyError


@dataclass
class CreateTaskCommand:
    org_id: UUID
    title: str
    description: Optional[str] = None
    project_id: Optional[UUID] = None
    priority: str = "medium"
    user_id: Optional[UUID] = None  # Who's creating it


@dataclass
class AssignTaskCommand:
    task_id: UUID
    assignee_id: Optional[UUID] = None
    agent_session_id: Optional[str] = None
    user_id: UUID = None


class TaskService:
    """
    Task domain service using event sourcing.

    All state changes go through the event store.
    Read operations go to the read model (tasks table).
    """

    def __init__(self, event_store: EventStore, pool):
        self.event_store = event_store
        self.pool = pool

    async def create_task(self, cmd: CreateTaskCommand) -> UUID:
        """Create a new task."""
        task_id = uuid4()
        stream_id = f"task:{task_id}"

        await self.event_store.append(
            stream_id=stream_id,
            event_type="TaskCreated",
            data={
                "id": str(task_id),
                "org_id": str(cmd.org_id),
                "project_id": str(cmd.project_id) if cmd.project_id else None,
                "title": cmd.title,
                "description": cmd.description,
                "priority": cmd.priority,
                "status": "todo"
            },
            expected_version=-1,  # New stream
            metadata={"user_id": str(cmd.user_id) if cmd.user_id else None}
        )

        return task_id

    async def assign_task(self, cmd: AssignTaskCommand):
        """Assign a task to a user or agent."""
        stream_id = f"task:{cmd.task_id}"

        # Get current version
        events = await self.event_store.read_stream(stream_id)
        if not events:
            raise TaskNotFoundError(cmd.task_id)

        current_version = events[-1].version

        await self.event_store.append(
            stream_id=stream_id,
            event_type="TaskAssigned",
            data={
                "id": str(cmd.task_id),
                "assignee_id": str(cmd.assignee_id) if cmd.assignee_id else None,
                "agent_session_id": cmd.agent_session_id
            },
            expected_version=current_version,
            metadata={"user_id": str(cmd.user_id)}
        )

    async def change_status(
        self,
        task_id: UUID,
        new_status: str,
        user_id: UUID
    ):
        """Change task status with optimistic concurrency."""
        stream_id = f"task:{task_id}"

        events = await self.event_store.read_stream(stream_id)
        if not events:
            raise TaskNotFoundError(task_id)

        current_version = events[-1].version

        # Validate status transition
        current_state = self._rebuild_state(events)
        if not self._valid_transition(current_state['status'], new_status):
            raise InvalidStatusTransition(current_state['status'], new_status)

        await self.event_store.append(
            stream_id=stream_id,
            event_type="TaskStatusChanged",
            data={
                "id": str(task_id),
                "status": new_status,
                "previous_status": current_state['status']
            },
            expected_version=current_version,
            metadata={"user_id": str(user_id)}
        )

    def _rebuild_state(self, events) -> dict:
        """Rebuild current state from events."""
        state = {}
        for event in events:
            if event.event_type == "TaskCreated":
                state = event.data.copy()
            elif event.event_type == "TaskUpdated":
                state.update({k: v for k, v in event.data.items() if v is not None})
            elif event.event_type == "TaskAssigned":
                state['assignee_id'] = event.data.get('assignee_id')
                state['agent_session_id'] = event.data.get('agent_session_id')
            elif event.event_type == "TaskStatusChanged":
                state['status'] = event.data['status']
        return state

    def _valid_transition(self, from_status: str, to_status: str) -> bool:
        """Check if status transition is valid."""
        valid_transitions = {
            'todo': ['in_progress', 'cancelled'],
            'in_progress': ['todo', 'review', 'blocked', 'cancelled'],
            'review': ['in_progress', 'done', 'cancelled'],
            'blocked': ['in_progress', 'cancelled'],
            'done': ['todo'],  # Reopen
            'cancelled': ['todo']  # Reopen
        }
        return to_status in valid_transitions.get(from_status, [])


class TaskNotFoundError(Exception):
    pass

class InvalidStatusTransition(Exception):
    pass
```

---

## Key Benefits of This Design

### 1. **Data Consistency Guaranteed**
- Single write path through event store
- Read models can fail and be rebuilt
- No dual-write problems

### 2. **Full Audit Trail**
- Every change is an event
- Can replay to any point in time
- Perfect for compliance (SOC2, GDPR)

### 3. **Scalable Reads**
- Read models optimized for queries
- Can create new projections without changing writes
- Eventually consistent (typically < 100ms)

### 4. **Multi-Tenant Security**
- Row-level security on all read models
- Org isolation at database level
- Cannot accidentally leak data

### 5. **Agent-Friendly**
- Agents write events, don't touch read models
- Clear audit of what each agent did
- Easy to replay agent actions

---

## Migration Path from Current Design

1. **Week 1**: Create event store table and functions
2. **Week 2**: Create read model tables with RLS
3. **Week 3**: Build event store client and projections
4. **Week 4**: Migrate existing code to use event-based writes
5. **Week 5**: Add monitoring and dead letter queue
6. **Week 6**: Load test and optimize

---

**Next Document: LLM Integration Layer →**
