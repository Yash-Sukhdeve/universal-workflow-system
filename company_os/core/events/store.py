"""
Event Store Implementation.

PostgreSQL-based event sourcing with optimistic concurrency control.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Optional, AsyncIterator, Callable
from uuid import UUID, uuid4
import json

import asyncpg


@dataclass
class Event:
    """Immutable event record."""
    id: int
    stream_id: str
    stream_version: int
    event_type: str
    event_data: dict[str, Any]
    metadata: dict[str, Any]
    created_at: datetime

    @classmethod
    def from_row(cls, row: asyncpg.Record) -> "Event":
        """Create Event from database row."""
        return cls(
            id=row["id"],
            stream_id=row["stream_id"],
            stream_version=row["stream_version"],
            event_type=row["event_type"],
            event_data=json.loads(row["event_data"]) if isinstance(row["event_data"], str) else row["event_data"],
            metadata=json.loads(row["metadata"]) if isinstance(row["metadata"], str) else row["metadata"],
            created_at=row["created_at"]
        )


@dataclass
class NewEvent:
    """Event to be appended."""
    event_type: str
    event_data: dict[str, Any]
    metadata: dict[str, Any] = field(default_factory=dict)


class OptimisticConcurrencyError(Exception):
    """Raised when concurrent modification detected."""
    def __init__(self, stream_id: str, expected: int, actual: int):
        self.stream_id = stream_id
        self.expected = expected
        self.actual = actual
        super().__init__(
            f"Concurrency conflict on stream '{stream_id}': "
            f"expected version {expected}, found {actual}"
        )


class EventStore:
    """
    PostgreSQL-based event store with optimistic concurrency control.

    Features:
    - Append-only event storage
    - Stream-based organization
    - Optimistic locking via version numbers
    - Subscription support for projections
    """

    def __init__(self, pool: asyncpg.Pool):
        self.pool = pool

    async def append(
        self,
        stream_id: str,
        events: list[NewEvent],
        expected_version: int = -1,
        org_id: Optional[UUID] = None
    ) -> list[Event]:
        """
        Append events to a stream with optimistic concurrency.

        Args:
            stream_id: Unique stream identifier
            events: Events to append
            expected_version: Expected current version (-1 for new streams)
            org_id: Organization ID for multi-tenancy

        Returns:
            List of appended events with assigned IDs

        Raises:
            OptimisticConcurrencyError: If version mismatch
        """
        if not events:
            return []

        async with self.pool.acquire() as conn:
            async with conn.transaction():
                # Get current stream version
                current_version = await conn.fetchval(
                    """
                    SELECT COALESCE(MAX(stream_version), -1)
                    FROM events
                    WHERE stream_id = $1
                    """,
                    stream_id
                )

                # Check concurrency
                if expected_version != -1 and current_version != expected_version:
                    raise OptimisticConcurrencyError(
                        stream_id, expected_version, current_version
                    )

                # Append events
                appended = []
                version = current_version + 1

                for event in events:
                    row = await conn.fetchrow(
                        """
                        INSERT INTO events
                        (stream_id, stream_version, event_type, event_data, metadata, org_id)
                        VALUES ($1, $2, $3, $4, $5, $6)
                        RETURNING id, stream_id, stream_version, event_type,
                                  event_data, metadata, created_at
                        """,
                        stream_id,
                        version,
                        event.event_type,
                        json.dumps(event.event_data),
                        json.dumps(event.metadata),
                        org_id
                    )
                    appended.append(Event.from_row(row))
                    version += 1

                return appended

    async def read_stream(
        self,
        stream_id: str,
        from_version: int = 0,
        to_version: Optional[int] = None,
        limit: int = 1000
    ) -> list[Event]:
        """
        Read events from a stream.

        Args:
            stream_id: Stream to read
            from_version: Start version (inclusive)
            to_version: End version (inclusive), None for all
            limit: Maximum events to return

        Returns:
            List of events in version order
        """
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

        query += " ORDER BY stream_version ASC LIMIT $" + str(len(params) + 1)
        params.append(limit)

        async with self.pool.acquire() as conn:
            rows = await conn.fetch(query, *params)
            return [Event.from_row(row) for row in rows]

    async def read_all(
        self,
        from_position: int = 0,
        batch_size: int = 100,
        event_types: Optional[list[str]] = None
    ) -> AsyncIterator[Event]:
        """
        Read all events across streams (for projections).

        Args:
            from_position: Global event ID to start from
            batch_size: Number of events per fetch
            event_types: Filter by event types

        Yields:
            Events in global order
        """
        position = from_position

        while True:
            query = """
                SELECT id, stream_id, stream_version, event_type,
                       event_data, metadata, created_at
                FROM events
                WHERE id > $1
            """
            params = [position]

            if event_types:
                query += " AND event_type = ANY($2)"
                params.append(event_types)

            query += " ORDER BY id ASC LIMIT $" + str(len(params) + 1)
            params.append(batch_size)

            async with self.pool.acquire() as conn:
                rows = await conn.fetch(query, *params)

            if not rows:
                break

            for row in rows:
                event = Event.from_row(row)
                yield event
                position = event.id

    async def get_stream_version(self, stream_id: str) -> int:
        """Get current version of a stream (-1 if doesn't exist)."""
        async with self.pool.acquire() as conn:
            version = await conn.fetchval(
                """
                SELECT COALESCE(MAX(stream_version), -1)
                FROM events
                WHERE stream_id = $1
                """,
                stream_id
            )
            return version

    async def stream_exists(self, stream_id: str) -> bool:
        """Check if a stream exists."""
        return await self.get_stream_version(stream_id) >= 0


class EventPublisher:
    """Publishes events to subscribers (for real-time projections)."""

    def __init__(self):
        self._subscribers: dict[str, list[Callable]] = {}

    def subscribe(self, event_type: str, handler: Callable):
        """Subscribe to an event type."""
        if event_type not in self._subscribers:
            self._subscribers[event_type] = []
        self._subscribers[event_type].append(handler)

    def subscribe_all(self, handler: Callable):
        """Subscribe to all events."""
        self.subscribe("*", handler)

    async def publish(self, event: Event):
        """Publish an event to subscribers."""
        # Type-specific subscribers
        for handler in self._subscribers.get(event.event_type, []):
            await handler(event)

        # Wildcard subscribers
        for handler in self._subscribers.get("*", []):
            await handler(event)
