"""
Unit Tests for Event Projections.

Tests the projection system for transforming event streams into read models.
"""

import pytest
import json
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, call
from uuid import uuid4, UUID

from company_os.core.events.projections import (
    Projection,
    TaskReadModel,
    TaskProjection,
    ProjectionManager
)
from company_os.core.events.store import Event, EventStore


class AsyncContextManagerMock:
    """Mock async context manager for connection pool and transactions."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


class TestTaskReadModel:
    """Tests for TaskReadModel dataclass."""

    def test_task_read_model_creation(self, sample_org_id, sample_user_id):
        """Test creating a TaskReadModel instance."""
        task_id = uuid4()
        now = datetime.now(timezone.utc)

        model = TaskReadModel(
            id=task_id,
            org_id=UUID(sample_org_id),
            title="Test Task",
            description="A test task",
            status="pending",
            priority="high",
            project_id=None,
            assigned_agent=None,
            assigned_user_id=None,
            created_by=UUID(sample_user_id),
            created_at=now,
            updated_at=now,
            due_date=None,
            tags=["test", "unit"],
            metadata={"source": "test"}
        )

        assert model.id == task_id
        assert model.org_id == UUID(sample_org_id)
        assert model.title == "Test Task"
        assert model.status == "pending"
        assert model.priority == "high"
        assert len(model.tags) == 2
        assert model.metadata == {"source": "test"}


class TestTaskProjection:
    """Tests for TaskProjection class."""

    @pytest.fixture
    def mock_pool(self):
        """Create mock asyncpg pool."""
        pool = MagicMock()
        return pool

    @pytest.fixture
    def task_projection(self, mock_pool):
        """Create TaskProjection with mock pool."""
        return TaskProjection(mock_pool)

    def create_event(self, event_type, event_data, stream_id="task-123"):
        """Helper to create test events."""
        return Event(
            id=1,
            stream_id=stream_id,
            stream_version=0,
            event_type=event_type,
            event_data=event_data,
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

    @pytest.mark.asyncio
    async def test_handle_task_created(self, task_projection, mock_pool, sample_org_id, sample_user_id):
        """Test handling TaskCreated event creates task in read model."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskCreated",
            {
                "id": task_id,
                "org_id": sample_org_id,
                "title": "New Task",
                "description": "Task description",
                "priority": "high",
                "created_by": sample_user_id,
                "tags": ["feature", "backend"],
                "metadata": {"source": "api"}
            }
        )

        await task_projection.apply(event)

        # Verify INSERT was called with correct parameters
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert "INSERT INTO tasks_read_model" in call_args[0]
        assert call_args[1] == UUID(task_id)
        assert call_args[2] == UUID(sample_org_id)
        assert call_args[3] == "New Task"
        assert call_args[4] == "Task description"
        assert call_args[5] == "pending"  # Default status
        assert call_args[6] == "high"
        assert call_args[8] == UUID(sample_user_id)

    @pytest.mark.asyncio
    async def test_handle_task_created_minimal_data(self, task_projection, mock_pool, sample_org_id, sample_user_id):
        """Test handling TaskCreated with minimal required data."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskCreated",
            {
                "id": task_id,
                "org_id": sample_org_id,
                "title": "Minimal Task",
                "created_by": sample_user_id
            }
        )

        await task_projection.apply(event)

        # Verify INSERT was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert call_args[4] == ""  # Empty description
        assert call_args[6] == "medium"  # Default priority
        assert call_args[10] == []  # Empty tags
        assert call_args[11] == "{}"  # Empty metadata as JSON

    @pytest.mark.asyncio
    async def test_handle_task_updated(self, task_projection, mock_pool):
        """Test handling TaskUpdated event updates task fields."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskUpdated",
            {
                "id": task_id,
                "title": "Updated Title",
                "description": "Updated description",
                "priority": "critical"
            }
        )

        await task_projection.apply(event)

        # Verify UPDATE was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert "UPDATE tasks_read_model" in call_args[0]
        assert "title = $1" in call_args[0]
        assert "description = $2" in call_args[0]
        assert "priority = $3" in call_args[0]
        assert "updated_at = $4" in call_args[0]
        assert "WHERE id = $5" in call_args[0]

        # Check parameters
        assert call_args[1] == "Updated Title"
        assert call_args[2] == "Updated description"
        assert call_args[3] == "critical"
        assert isinstance(call_args[4], datetime)
        assert call_args[5] == UUID(task_id)

    @pytest.mark.asyncio
    async def test_handle_task_updated_partial_fields(self, task_projection, mock_pool):
        """Test handling TaskUpdated with only some fields."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskUpdated",
            {
                "id": task_id,
                "title": "Just Title Update"
            }
        )

        await task_projection.apply(event)

        # Verify UPDATE was called with only title
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert "title = $1" in call_args[0]
        assert "updated_at = $2" in call_args[0]
        assert call_args[1] == "Just Title Update"

    @pytest.mark.asyncio
    async def test_handle_task_updated_no_fields(self, task_projection, mock_pool):
        """Test handling TaskUpdated with no updateable fields does nothing."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskUpdated",
            {
                "id": task_id
                # No updateable fields
            }
        )

        await task_projection.apply(event)

        # Should not execute any UPDATE
        mock_conn.execute.assert_not_called()

    @pytest.mark.asyncio
    async def test_handle_task_assigned_to_agent(self, task_projection, mock_pool):
        """Test handling TaskAssigned event assigns to agent."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskAssigned",
            {
                "id": task_id,
                "agent_type": "implementer"
            }
        )

        await task_projection.apply(event)

        # Verify UPDATE was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert "UPDATE tasks_read_model" in call_args[0]
        assert "assigned_agent = $1" in call_args[0]
        assert call_args[1] == "implementer"
        assert call_args[2] is None  # No user_id
        assert call_args[4] == UUID(task_id)

    @pytest.mark.asyncio
    async def test_handle_task_assigned_to_user(self, task_projection, mock_pool, sample_user_id):
        """Test handling TaskAssigned event assigns to user."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskAssigned",
            {
                "id": task_id,
                "user_id": sample_user_id,
                "agent_type": "human"
            }
        )

        await task_projection.apply(event)

        # Verify UPDATE was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert call_args[1] == "human"
        assert call_args[2] == UUID(sample_user_id)

    @pytest.mark.asyncio
    async def test_handle_status_changed(self, task_projection, mock_pool):
        """Test handling TaskStatusChanged event updates status."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskStatusChanged",
            {
                "id": task_id,
                "status": "in_progress"
            }
        )

        await task_projection.apply(event)

        # Verify UPDATE was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert "UPDATE tasks_read_model" in call_args[0]
        assert "status = $1" in call_args[0]
        assert call_args[1] == "in_progress"
        assert call_args[3] == UUID(task_id)

    @pytest.mark.asyncio
    async def test_handle_task_completed(self, task_projection, mock_pool):
        """Test handling TaskCompleted event marks task complete."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskCompleted",
            {
                "id": task_id,
                "result": {
                    "success": True,
                    "output": "Task completed successfully"
                }
            }
        )

        await task_projection.apply(event)

        # Verify UPDATE was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert "UPDATE tasks_read_model" in call_args[0]
        assert "status = 'completed'" in call_args[0]
        assert "metadata = metadata || $2" in call_args[0]

        # Check metadata includes completion result
        metadata_json = call_args[2]
        metadata = json.loads(metadata_json)
        assert metadata["completion_result"]["success"] is True
        assert metadata["completion_result"]["output"] == "Task completed successfully"

    @pytest.mark.asyncio
    async def test_handle_task_completed_no_result(self, task_projection, mock_pool):
        """Test handling TaskCompleted without result data."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskCompleted",
            {
                "id": task_id
            }
        )

        await task_projection.apply(event)

        # Verify UPDATE was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        # Check metadata includes empty result
        metadata_json = call_args[2]
        metadata = json.loads(metadata_json)
        assert metadata["completion_result"] == {}

    @pytest.mark.asyncio
    async def test_handle_task_deleted(self, task_projection, mock_pool):
        """Test handling TaskDeleted event removes from read model."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        task_id = str(uuid4())
        event = self.create_event(
            "TaskDeleted",
            {
                "id": task_id
            }
        )

        await task_projection.apply(event)

        # Verify DELETE was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]

        assert "DELETE FROM tasks_read_model" in call_args[0]
        assert "WHERE id = $1" in call_args[0]
        assert call_args[1] == UUID(task_id)

    @pytest.mark.asyncio
    async def test_apply_unknown_event_type(self, task_projection, mock_pool):
        """Test applying unknown event type does nothing."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        event = self.create_event(
            "UnknownEvent",
            {"id": str(uuid4())}
        )

        await task_projection.apply(event)

        # Should not execute anything
        mock_conn.execute.assert_not_called()

    @pytest.mark.asyncio
    async def test_rebuild_projection(self, task_projection, mock_pool):
        """Test rebuilding projection from event stream."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        # Mock event store with sample events
        mock_event_store = AsyncMock(spec=EventStore)

        task_id = str(uuid4())
        org_id = str(uuid4())
        user_id = str(uuid4())

        events = [
            self.create_event(
                "TaskCreated",
                {
                    "id": task_id,
                    "org_id": org_id,
                    "title": "Test Task",
                    "created_by": user_id
                }
            ),
            self.create_event(
                "TaskStatusChanged",
                {
                    "id": task_id,
                    "status": "in_progress"
                }
            )
        ]

        # Mock async iterator for read_all
        async def async_event_iterator():
            for event in events:
                yield event

        mock_event_store.read_all = MagicMock(return_value=async_event_iterator())

        await task_projection.rebuild(mock_event_store)

        # Verify TRUNCATE was called
        truncate_call = mock_conn.execute.call_args_list[0]
        assert "TRUNCATE TABLE tasks_read_model" in truncate_call[0][0]

        # Verify events were replayed (INSERT + UPDATE)
        assert mock_conn.execute.call_count == 3  # TRUNCATE + 2 events

    @pytest.mark.asyncio
    async def test_rebuild_empty_event_stream(self, task_projection, mock_pool):
        """Test rebuilding with no events."""
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        # Mock event store with no events
        mock_event_store = AsyncMock(spec=EventStore)

        async def empty_iterator():
            return
            yield  # Make it a generator

        mock_event_store.read_all = MagicMock(return_value=empty_iterator())

        await task_projection.rebuild(mock_event_store)

        # Verify only TRUNCATE was called
        assert mock_conn.execute.call_count == 1
        truncate_call = mock_conn.execute.call_args_list[0]
        assert "TRUNCATE TABLE tasks_read_model" in truncate_call[0][0]


class TestProjectionManager:
    """Tests for ProjectionManager class."""

    @pytest.fixture
    def mock_pool(self):
        """Create mock asyncpg pool."""
        return MagicMock()

    @pytest.fixture
    def mock_event_store(self):
        """Create mock event store."""
        return AsyncMock(spec=EventStore)

    @pytest.fixture
    def projection_manager(self, mock_pool, mock_event_store):
        """Create ProjectionManager with mocks."""
        return ProjectionManager(mock_pool, mock_event_store)

    def test_register_projection(self, projection_manager, mock_pool):
        """Test registering a projection."""
        projection = TaskProjection(mock_pool)

        projection_manager.register(projection)

        assert len(projection_manager.projections) == 1
        assert projection_manager.projections[0] == projection

    def test_register_multiple_projections(self, projection_manager, mock_pool):
        """Test registering multiple projections."""
        projection1 = TaskProjection(mock_pool)
        projection2 = TaskProjection(mock_pool)

        projection_manager.register(projection1)
        projection_manager.register(projection2)

        assert len(projection_manager.projections) == 2

    @pytest.mark.asyncio
    async def test_apply_event_to_projections(self, projection_manager, mock_pool):
        """Test applying event to all registered projections."""
        # Register mock projections
        mock_projection1 = AsyncMock(spec=Projection)
        mock_projection2 = AsyncMock(spec=Projection)

        projection_manager.register(mock_projection1)
        projection_manager.register(mock_projection2)

        event = Event(
            id=1,
            stream_id="task-123",
            stream_version=0,
            event_type="TaskCreated",
            event_data={"id": str(uuid4())},
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

        await projection_manager.apply_event(event)

        # Both projections should receive the event
        mock_projection1.apply.assert_called_once_with(event)
        mock_projection2.apply.assert_called_once_with(event)

    @pytest.mark.asyncio
    async def test_apply_event_no_projections(self, projection_manager):
        """Test applying event with no registered projections."""
        event = Event(
            id=1,
            stream_id="task-123",
            stream_version=0,
            event_type="TaskCreated",
            event_data={},
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

        # Should not raise
        await projection_manager.apply_event(event)

    @pytest.mark.asyncio
    async def test_rebuild_all_projections(self, projection_manager, mock_event_store):
        """Test rebuilding all registered projections."""
        # Register mock projections
        mock_projection1 = AsyncMock(spec=Projection)
        mock_projection2 = AsyncMock(spec=Projection)

        projection_manager.register(mock_projection1)
        projection_manager.register(mock_projection2)

        await projection_manager.rebuild_all()

        # Both projections should be rebuilt with event store
        mock_projection1.rebuild.assert_called_once_with(mock_event_store)
        mock_projection2.rebuild.assert_called_once_with(mock_event_store)

    @pytest.mark.asyncio
    async def test_rebuild_all_no_projections(self, projection_manager):
        """Test rebuilding with no registered projections."""
        # Should not raise
        await projection_manager.rebuild_all()

    def test_get_projection(self, projection_manager, mock_pool):
        """Test retrieving a registered projection by index."""
        projection = TaskProjection(mock_pool)
        projection_manager.register(projection)

        retrieved = projection_manager.projections[0]

        assert retrieved == projection

    @pytest.mark.asyncio
    async def test_projection_manager_integration(self, mock_pool, mock_event_store):
        """Test full ProjectionManager workflow."""
        manager = ProjectionManager(mock_pool, mock_event_store)

        # Mock connection for TaskProjection
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        # Register TaskProjection
        task_projection = TaskProjection(mock_pool)
        manager.register(task_projection)

        # Create and apply event
        task_id = str(uuid4())
        org_id = str(uuid4())
        user_id = str(uuid4())

        event = Event(
            id=1,
            stream_id=f"task-{task_id}",
            stream_version=0,
            event_type="TaskCreated",
            event_data={
                "id": task_id,
                "org_id": org_id,
                "title": "Integration Test",
                "created_by": user_id
            },
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

        await manager.apply_event(event)

        # Verify the projection handled the event
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]
        assert "INSERT INTO tasks_read_model" in call_args[0]
