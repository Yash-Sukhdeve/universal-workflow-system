"""
Event Projections.

Transforms event streams into read models.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Optional
from uuid import UUID
import json

import asyncpg

from .store import Event, EventStore


class Projection(ABC):
    """Base class for event projections."""

    @abstractmethod
    async def apply(self, event: Event) -> None:
        """Apply an event to update the read model."""
        pass

    @abstractmethod
    async def rebuild(self, event_store: EventStore) -> None:
        """Rebuild the entire projection from event history."""
        pass


@dataclass
class TaskReadModel:
    """Task read model for queries."""
    id: UUID
    org_id: UUID
    title: str
    description: str
    status: str  # pending, in_progress, completed, cancelled
    priority: str  # low, medium, high, critical
    project_id: Optional[UUID]
    assigned_agent: Optional[str]
    assigned_user_id: Optional[UUID]
    created_by: UUID
    created_at: datetime
    updated_at: datetime
    due_date: Optional[datetime]
    tags: list[str]
    metadata: dict[str, Any]


class TaskProjection(Projection):
    """Projects task events into read model."""

    EVENT_HANDLERS = {
        "TaskCreated": "_handle_created",
        "TaskUpdated": "_handle_updated",
        "TaskAssigned": "_handle_assigned",
        "TaskStatusChanged": "_handle_status_changed",
        "TaskCompleted": "_handle_completed",
        "TaskDeleted": "_handle_deleted",
    }

    def __init__(self, pool: asyncpg.Pool):
        self.pool = pool

    async def apply(self, event: Event) -> None:
        """Apply a task event."""
        handler_name = self.EVENT_HANDLERS.get(event.event_type)
        if handler_name:
            handler = getattr(self, handler_name)
            await handler(event)

    async def rebuild(self, event_store: EventStore) -> None:
        """Rebuild task read model from all events."""
        async with self.pool.acquire() as conn:
            # Clear existing read model
            await conn.execute("TRUNCATE TABLE tasks_read_model")

            # Replay all task events
            async for event in event_store.read_all(
                event_types=list(self.EVENT_HANDLERS.keys())
            ):
                await self.apply(event)

    async def _handle_created(self, event: Event) -> None:
        """Handle TaskCreated event."""
        data = event.event_data
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO tasks_read_model
                (id, org_id, title, description, status, priority, project_id,
                 created_by, created_at, updated_at, due_date, tags, metadata)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9, $10, $11, $12)
                """,
                UUID(data["id"]),
                UUID(data["org_id"]),
                data["title"],
                data.get("description", ""),
                "pending",
                data.get("priority", "medium"),
                UUID(data["project_id"]) if data.get("project_id") else None,
                UUID(data["created_by"]),
                event.created_at,
                data.get("due_date"),
                data.get("tags", []),
                json.dumps(data.get("metadata", {}))
            )

    async def _handle_updated(self, event: Event) -> None:
        """Handle TaskUpdated event."""
        data = event.event_data
        updates = []
        params = []
        param_count = 1

        for field in ["title", "description", "priority", "due_date", "tags"]:
            if field in data:
                updates.append(f"{field} = ${param_count}")
                params.append(data[field])
                param_count += 1

        if updates:
            updates.append(f"updated_at = ${param_count}")
            params.append(event.created_at)
            param_count += 1

            params.append(UUID(data["id"]))

            async with self.pool.acquire() as conn:
                await conn.execute(
                    f"""
                    UPDATE tasks_read_model
                    SET {', '.join(updates)}
                    WHERE id = ${param_count}
                    """,
                    *params
                )

    async def _handle_assigned(self, event: Event) -> None:
        """Handle TaskAssigned event."""
        data = event.event_data
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE tasks_read_model
                SET assigned_agent = $1,
                    assigned_user_id = $2,
                    updated_at = $3
                WHERE id = $4
                """,
                data.get("agent_type"),
                UUID(data["user_id"]) if data.get("user_id") else None,
                event.created_at,
                UUID(data["id"])
            )

    async def _handle_status_changed(self, event: Event) -> None:
        """Handle TaskStatusChanged event."""
        data = event.event_data
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE tasks_read_model
                SET status = $1, updated_at = $2
                WHERE id = $3
                """,
                data["status"],
                event.created_at,
                UUID(data["id"])
            )

    async def _handle_completed(self, event: Event) -> None:
        """Handle TaskCompleted event."""
        data = event.event_data
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE tasks_read_model
                SET status = 'completed',
                    updated_at = $1,
                    metadata = metadata || $2
                WHERE id = $3
                """,
                event.created_at,
                json.dumps({"completion_result": data.get("result", {})}),
                UUID(data["id"])
            )

    async def _handle_deleted(self, event: Event) -> None:
        """Handle TaskDeleted event."""
        data = event.event_data
        async with self.pool.acquire() as conn:
            await conn.execute(
                "DELETE FROM tasks_read_model WHERE id = $1",
                UUID(data["id"])
            )


class ProjectionManager:
    """Manages all projections."""

    def __init__(self, pool: asyncpg.Pool, event_store: EventStore):
        self.pool = pool
        self.event_store = event_store
        self.projections: list[Projection] = []

    def register(self, projection: Projection) -> None:
        """Register a projection."""
        self.projections.append(projection)

    async def apply_event(self, event: Event) -> None:
        """Apply event to all projections."""
        for projection in self.projections:
            await projection.apply(event)

    async def rebuild_all(self) -> None:
        """Rebuild all projections from event history."""
        for projection in self.projections:
            await projection.rebuild(self.event_store)
