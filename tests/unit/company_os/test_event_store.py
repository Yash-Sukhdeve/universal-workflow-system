"""
Unit Tests for Event Store.

Tests the event sourcing implementation with optimistic concurrency.
"""

import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

from company_os.core.events.store import (
    Event,
    NewEvent,
    OptimisticConcurrencyError,
    EventStore,
    EventPublisher
)


class AsyncContextManagerMock:
    """Mock async context manager for connection pool and transactions."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


class TestEvent:
    """Tests for Event dataclass."""

    def test_event_creation(self):
        """Test creating an Event instance."""
        event = Event(
            id=1,
            stream_id="task-123",
            stream_version=0,
            event_type="TaskCreated",
            event_data={"title": "Test"},
            metadata={"user_id": "user-1"},
            created_at=datetime.now(timezone.utc)
        )

        assert event.id == 1
        assert event.stream_id == "task-123"
        assert event.stream_version == 0
        assert event.event_type == "TaskCreated"
        assert event.event_data == {"title": "Test"}

    def test_event_from_row(self):
        """Test creating Event from database row."""
        mock_row = {
            "id": 1,
            "stream_id": "task-456",
            "stream_version": 2,
            "event_type": "TaskUpdated",
            "event_data": {"title": "Updated"},
            "metadata": {},
            "created_at": datetime.now(timezone.utc)
        }

        event = Event.from_row(mock_row)

        assert event.id == 1
        assert event.stream_id == "task-456"
        assert event.stream_version == 2
        assert event.event_type == "TaskUpdated"

    def test_event_from_row_with_json_string(self):
        """Test from_row handles JSON string data."""
        mock_row = {
            "id": 1,
            "stream_id": "task-789",
            "stream_version": 0,
            "event_type": "TaskCreated",
            "event_data": '{"title": "JSON String"}',
            "metadata": '{"source": "test"}',
            "created_at": datetime.now(timezone.utc)
        }

        event = Event.from_row(mock_row)

        assert event.event_data == {"title": "JSON String"}
        assert event.metadata == {"source": "test"}


class TestNewEvent:
    """Tests for NewEvent dataclass."""

    def test_new_event_creation(self):
        """Test creating a NewEvent."""
        event = NewEvent(
            event_type="TaskCreated",
            event_data={"title": "New Task"}
        )

        assert event.event_type == "TaskCreated"
        assert event.event_data == {"title": "New Task"}
        assert event.metadata == {}

    def test_new_event_with_metadata(self):
        """Test NewEvent with metadata."""
        event = NewEvent(
            event_type="TaskUpdated",
            event_data={"status": "done"},
            metadata={"user_id": "user-1", "ip": "127.0.0.1"}
        )

        assert event.metadata == {"user_id": "user-1", "ip": "127.0.0.1"}


class TestOptimisticConcurrencyError:
    """Tests for OptimisticConcurrencyError."""

    def test_error_creation(self):
        """Test creating the error."""
        error = OptimisticConcurrencyError(
            stream_id="task-123",
            expected=5,
            actual=7
        )

        assert error.stream_id == "task-123"
        assert error.expected == 5
        assert error.actual == 7
        assert "task-123" in str(error)
        assert "5" in str(error)
        assert "7" in str(error)

    def test_error_is_exception(self):
        """Test that it's a proper exception."""
        error = OptimisticConcurrencyError("test", 1, 2)

        with pytest.raises(OptimisticConcurrencyError):
            raise error


class TestEventStore:
    """Tests for EventStore class."""

    @pytest.fixture
    def mock_pool(self):
        """Create mock asyncpg pool."""
        pool = MagicMock()
        return pool

    @pytest.fixture
    def event_store(self, mock_pool):
        """Create EventStore with mock pool."""
        return EventStore(mock_pool)

    @pytest.mark.asyncio
    async def test_append_single_event(self, event_store, mock_pool):
        """Test appending a single event."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=-1)  # Empty stream
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": 1,
            "stream_id": "task-123",
            "stream_version": 0,
            "event_type": "TaskCreated",
            "event_data": {"title": "Test"},
            "metadata": {},
            "created_at": datetime.now(timezone.utc)
        })

        # Setup proper async context managers
        # transaction() returns a context manager, not a coroutine
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)
        mock_conn.transaction = MagicMock(return_value=AsyncContextManagerMock(None))

        new_event = NewEvent(
            event_type="TaskCreated",
            event_data={"title": "Test"}
        )

        events = await event_store.append(
            stream_id="task-123",
            events=[new_event]
        )

        assert len(events) == 1
        assert events[0].event_type == "TaskCreated"
        assert events[0].stream_version == 0

    @pytest.mark.asyncio
    async def test_append_empty_events(self, event_store):
        """Test appending empty event list returns empty."""
        events = await event_store.append(
            stream_id="task-123",
            events=[]
        )

        assert events == []

    @pytest.mark.asyncio
    async def test_append_with_version_check(self, event_store, mock_pool):
        """Test append with expected version."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=5)  # Current version is 5
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": 10,
            "stream_id": "task-123",
            "stream_version": 6,
            "event_type": "TaskUpdated",
            "event_data": {"status": "done"},
            "metadata": {},
            "created_at": datetime.now(timezone.utc)
        })

        # Setup proper async context managers
        # transaction() returns a context manager, not a coroutine
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)
        mock_conn.transaction = MagicMock(return_value=AsyncContextManagerMock(None))

        new_event = NewEvent(
            event_type="TaskUpdated",
            event_data={"status": "done"}
        )

        events = await event_store.append(
            stream_id="task-123",
            events=[new_event],
            expected_version=5  # Matches current version
        )

        assert len(events) == 1
        assert events[0].stream_version == 6

    @pytest.mark.asyncio
    async def test_append_version_conflict(self, event_store, mock_pool):
        """Test append raises error on version conflict."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=7)  # Current version is 7

        # Setup proper async context managers
        # transaction() returns a context manager, not a coroutine
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)
        mock_conn.transaction = MagicMock(return_value=AsyncContextManagerMock(None))

        new_event = NewEvent(
            event_type="TaskUpdated",
            event_data={"status": "done"}
        )

        with pytest.raises(OptimisticConcurrencyError) as exc_info:
            await event_store.append(
                stream_id="task-123",
                events=[new_event],
                expected_version=5  # Expected 5, but actual is 7
            )

        assert exc_info.value.expected == 5
        assert exc_info.value.actual == 7

    @pytest.mark.asyncio
    async def test_read_stream(self, event_store, mock_pool):
        """Test reading events from a stream."""
        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[
            {
                "id": 1,
                "stream_id": "task-123",
                "stream_version": 0,
                "event_type": "TaskCreated",
                "event_data": {"title": "Test"},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            },
            {
                "id": 2,
                "stream_id": "task-123",
                "stream_version": 1,
                "event_type": "TaskUpdated",
                "event_data": {"title": "Updated"},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            }
        ])

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        events = await event_store.read_stream("task-123")

        assert len(events) == 2
        assert events[0].stream_version == 0
        assert events[1].stream_version == 1

    @pytest.mark.asyncio
    async def test_read_stream_with_from_version(self, event_store, mock_pool):
        """Test reading stream starting from specific version."""
        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[])

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        await event_store.read_stream("task-123", from_version=5)

        # Verify the query included from_version
        call_args = mock_conn.fetch.call_args
        assert 5 in call_args[0]  # from_version should be in params

    @pytest.mark.asyncio
    async def test_get_stream_version(self, event_store, mock_pool):
        """Test getting current stream version."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=10)

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        version = await event_store.get_stream_version("task-123")

        assert version == 10

    @pytest.mark.asyncio
    async def test_get_stream_version_nonexistent(self, event_store, mock_pool):
        """Test getting version of non-existent stream returns -1."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=-1)

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        version = await event_store.get_stream_version("nonexistent")

        assert version == -1

    @pytest.mark.asyncio
    async def test_stream_exists_true(self, event_store, mock_pool):
        """Test stream_exists returns True for existing stream."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=5)

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        exists = await event_store.stream_exists("task-123")

        assert exists is True

    @pytest.mark.asyncio
    async def test_stream_exists_false(self, event_store, mock_pool):
        """Test stream_exists returns False for non-existent stream."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=-1)

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        exists = await event_store.stream_exists("nonexistent")

        assert exists is False

    @pytest.mark.asyncio
    async def test_append_multiple_events(self, event_store, mock_pool):
        """Test appending multiple events at once."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=-1)  # Empty stream

        # Return different events for each insert
        mock_conn.fetchrow = AsyncMock(side_effect=[
            {
                "id": 1,
                "stream_id": "task-123",
                "stream_version": 0,
                "event_type": "TaskCreated",
                "event_data": {"title": "Test"},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            },
            {
                "id": 2,
                "stream_id": "task-123",
                "stream_version": 1,
                "event_type": "TaskUpdated",
                "event_data": {"title": "Updated"},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            },
            {
                "id": 3,
                "stream_id": "task-123",
                "stream_version": 2,
                "event_type": "TaskCompleted",
                "event_data": {"result": "success"},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            }
        ])

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)
        mock_conn.transaction = MagicMock(return_value=AsyncContextManagerMock(None))

        new_events = [
            NewEvent(event_type="TaskCreated", event_data={"title": "Test"}),
            NewEvent(event_type="TaskUpdated", event_data={"title": "Updated"}),
            NewEvent(event_type="TaskCompleted", event_data={"result": "success"})
        ]

        events = await event_store.append(
            stream_id="task-123",
            events=new_events
        )

        assert len(events) == 3
        assert events[0].stream_version == 0
        assert events[1].stream_version == 1
        assert events[2].stream_version == 2

    @pytest.mark.asyncio
    async def test_append_with_org_id(self, event_store, mock_pool):
        """Test appending events with org_id for multi-tenancy."""
        from uuid import uuid4
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=-1)
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": 1,
            "stream_id": "task-123",
            "stream_version": 0,
            "event_type": "TaskCreated",
            "event_data": {"title": "Test"},
            "metadata": {},
            "created_at": datetime.now(timezone.utc)
        })

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)
        mock_conn.transaction = MagicMock(return_value=AsyncContextManagerMock(None))

        new_event = NewEvent(
            event_type="TaskCreated",
            event_data={"title": "Test"}
        )

        await event_store.append(
            stream_id="task-123",
            events=[new_event],
            org_id=org_id
        )

        # Verify org_id was passed to INSERT
        call_args = mock_conn.fetchrow.call_args[0]
        assert org_id in call_args

    @pytest.mark.asyncio
    async def test_read_stream_with_to_version(self, event_store, mock_pool):
        """Test reading stream with both from and to version."""
        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[
            {
                "id": 5,
                "stream_id": "task-123",
                "stream_version": 5,
                "event_type": "TaskUpdated",
                "event_data": {"status": "in_progress"},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            },
            {
                "id": 6,
                "stream_id": "task-123",
                "stream_version": 6,
                "event_type": "TaskUpdated",
                "event_data": {"status": "review"},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            }
        ])

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        events = await event_store.read_stream(
            "task-123",
            from_version=5,
            to_version=6
        )

        assert len(events) == 2
        assert events[0].stream_version == 5
        assert events[1].stream_version == 6

    @pytest.mark.asyncio
    async def test_read_stream_with_limit(self, event_store, mock_pool):
        """Test reading stream respects limit parameter."""
        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[
            {"id": i, "stream_id": "task-123", "stream_version": i,
             "event_type": "Event", "event_data": {}, "metadata": {},
             "created_at": datetime.now(timezone.utc)}
            for i in range(10)
        ])

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        events = await event_store.read_stream("task-123", limit=10)

        assert len(events) == 10
        # Verify limit was in query
        call_args = mock_conn.fetch.call_args[0]
        assert 10 in call_args

    @pytest.mark.asyncio
    async def test_read_all_with_event_types_filter(self, event_store, mock_pool):
        """Test read_all with event type filtering."""
        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[
            {
                "id": 1,
                "stream_id": "task-123",
                "stream_version": 0,
                "event_type": "TaskCreated",
                "event_data": {},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            },
            {
                "id": 5,
                "stream_id": "task-456",
                "stream_version": 0,
                "event_type": "TaskCreated",
                "event_data": {},
                "metadata": {},
                "created_at": datetime.now(timezone.utc)
            }
        ])

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        events = []
        async for event in event_store.read_all(
            from_position=0,
            event_types=["TaskCreated", "TaskUpdated"]
        ):
            events.append(event)

        assert len(events) == 2
        assert all(e.event_type == "TaskCreated" for e in events)

    @pytest.mark.asyncio
    async def test_read_all_pagination(self, event_store, mock_pool):
        """Test read_all handles pagination correctly."""
        mock_conn = AsyncMock()

        # First batch returns 2 events, second batch returns empty
        mock_conn.fetch = AsyncMock(side_effect=[
            [
                {"id": 1, "stream_id": "task-1", "stream_version": 0,
                 "event_type": "Event", "event_data": {}, "metadata": {},
                 "created_at": datetime.now(timezone.utc)},
                {"id": 2, "stream_id": "task-2", "stream_version": 0,
                 "event_type": "Event", "event_data": {}, "metadata": {},
                 "created_at": datetime.now(timezone.utc)}
            ],
            []  # Empty result to stop iteration
        ])

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        events = []
        async for event in event_store.read_all(batch_size=2):
            events.append(event)

        assert len(events) == 2


class TestEventPublisher:
    """Tests for EventPublisher class."""

    def test_subscribe_to_event_type(self):
        """Test subscribing to specific event type."""
        publisher = EventPublisher()
        handler = AsyncMock()

        publisher.subscribe("TaskCreated", handler)

        assert "TaskCreated" in publisher._subscribers
        assert handler in publisher._subscribers["TaskCreated"]

    def test_subscribe_all(self):
        """Test subscribing to all events."""
        publisher = EventPublisher()
        handler = AsyncMock()

        publisher.subscribe_all(handler)

        assert "*" in publisher._subscribers
        assert handler in publisher._subscribers["*"]

    @pytest.mark.asyncio
    async def test_publish_to_specific_subscriber(self):
        """Test publishing calls specific subscriber."""
        publisher = EventPublisher()
        handler = AsyncMock()
        publisher.subscribe("TaskCreated", handler)

        event = Event(
            id=1,
            stream_id="task-123",
            stream_version=0,
            event_type="TaskCreated",
            event_data={},
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

        await publisher.publish(event)

        handler.assert_called_once_with(event)

    @pytest.mark.asyncio
    async def test_publish_to_wildcard_subscriber(self):
        """Test publishing calls wildcard subscriber."""
        publisher = EventPublisher()
        handler = AsyncMock()
        publisher.subscribe_all(handler)

        event = Event(
            id=1,
            stream_id="task-123",
            stream_version=0,
            event_type="AnyEvent",
            event_data={},
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

        await publisher.publish(event)

        handler.assert_called_once_with(event)

    @pytest.mark.asyncio
    async def test_publish_to_multiple_subscribers(self):
        """Test publishing calls all matching subscribers."""
        publisher = EventPublisher()
        specific_handler = AsyncMock()
        wildcard_handler = AsyncMock()

        publisher.subscribe("TaskCreated", specific_handler)
        publisher.subscribe_all(wildcard_handler)

        event = Event(
            id=1,
            stream_id="task-123",
            stream_version=0,
            event_type="TaskCreated",
            event_data={},
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

        await publisher.publish(event)

        specific_handler.assert_called_once_with(event)
        wildcard_handler.assert_called_once_with(event)

    @pytest.mark.asyncio
    async def test_publish_no_matching_subscriber(self):
        """Test publishing with no matching subscriber doesn't error."""
        publisher = EventPublisher()

        event = Event(
            id=1,
            stream_id="task-123",
            stream_version=0,
            event_type="UnhandledEvent",
            event_data={},
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

        # Should not raise
        await publisher.publish(event)
