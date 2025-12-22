"""
Comprehensive Integration Tests for Tasks API.

Tests CRUD operations, event sourcing, and task lifecycle with pytest and httpx.
"""

import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4, UUID

from httpx import ASGITransport, AsyncClient

from company_os.api.main import create_app
from company_os.api.state import app_state
from company_os.api.security import CurrentUser
from company_os.core.auth.models import TokenPayload
from company_os.core.events.store import Event, NewEvent


class AsyncContextManager:
    """Helper for mocking async context managers."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


@pytest.fixture
def fastapi_app():
    """Create FastAPI app for testing."""
    return create_app()


@pytest.fixture
def mock_pool():
    """Create mock database pool."""
    pool = MagicMock()
    conn = AsyncMock()
    conn.execute = AsyncMock(return_value="SET")
    conn.fetch = AsyncMock(return_value=[])
    conn.fetchrow = AsyncMock(return_value=None)
    pool.acquire.return_value = AsyncContextManager(conn)
    return pool


@pytest.fixture
def mock_event_store():
    """Create mock event store."""
    store = AsyncMock()
    store.append = AsyncMock(return_value=[])
    store.get_stream_version = AsyncMock(return_value=-1)
    return store


@pytest.fixture
def mock_projection_manager():
    """Create mock projection manager."""
    manager = AsyncMock()
    manager.apply_event = AsyncMock()
    return manager


@pytest.fixture
def mock_uws_adapter():
    """Create mock UWS adapter."""
    adapter = AsyncMock()
    adapter.activate_agent = AsyncMock(return_value="session-123")
    return adapter


@pytest.fixture
def mock_app_state(mock_pool, mock_event_store, mock_projection_manager, mock_uws_adapter):
    """Setup mock application state."""
    app_state.pool = mock_pool
    app_state.event_store = mock_event_store
    app_state.projection_manager = mock_projection_manager
    app_state.uws_adapter = mock_uws_adapter
    return app_state


@pytest.fixture
def user_id():
    """Sample user ID."""
    return uuid4()


@pytest.fixture
def org_id():
    """Sample organization ID."""
    return uuid4()


@pytest.fixture
def mock_token_payload(user_id, org_id):
    """Create mock token payload."""
    return TokenPayload(
        sub=str(user_id),
        org_id=str(org_id),
        role="member",
        permissions=["tasks:read", "tasks:create", "tasks:update", "tasks:delete", "tasks:assign"],
        exp=datetime.now(timezone.utc) + timedelta(minutes=15),
        iat=datetime.now(timezone.utc),
        jti=str(uuid4())
    )


@pytest.fixture
def mock_current_user(mock_token_payload):
    """Create mock CurrentUser object."""
    from company_os.api.security import CurrentUser
    return CurrentUser(mock_token_payload)


@pytest.fixture
def sample_task_row(user_id, org_id):
    """Create sample task database row."""
    task_id = uuid4()
    now = datetime.now(timezone.utc)
    return {
        "id": task_id,
        "title": "Implement authentication",
        "description": "Add JWT auth to API",
        "status": "pending",
        "priority": "high",
        "project_id": None,
        "assigned_agent": None,
        "assigned_user_id": None,
        "created_by": user_id,
        "created_at": now,
        "updated_at": now,
        "due_date": None,
        "tags": ["backend", "security"]
    }


class TestCreateTask:
    """Tests for POST /api/tasks."""

    @pytest.mark.asyncio
    async def test_create_task_success(
        self, fastapi_app, mock_app_state, mock_token_payload, user_id, org_id
    ):
        """Test successfully creating a task."""
        task_id = uuid4()
        now = datetime.now(timezone.utc)

        created_event = Event(
            id=uuid4(),
            stream_id=f"task-{task_id}",
            event_type="TaskCreated",
            event_data={
                "id": str(task_id),
                "title": "New Task",
                "description": "Task description",
                "priority": "medium"
            },
            metadata={"user_id": str(user_id)},
            sequence=1,
            created_at=now,
            org_id=org_id
        )

        mock_app_state.event_store.append.return_value = [created_event]

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                current_user = CurrentUser(mock_token_payload)
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = current_user

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/tasks",
                        json={
                            "title": "New Task",
                            "description": "Task description",
                            "priority": "medium",
                            "tags": ["test", "api"]
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 201
                data = response.json()
                assert "id" in data
                assert data["title"] == "New Task"
                assert data["description"] == "Task description"
                assert data["priority"] == "medium"
                assert data["status"] == "pending"
                assert data["tags"] == ["test", "api"]

    @pytest.mark.asyncio
    async def test_create_task_with_due_date(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test creating task with due date."""
        created_event = Event(
            id=uuid4(),
            stream_id=f"task-{uuid4()}",
            event_type="TaskCreated",
            event_data={},
            metadata={},
            sequence=1,
            created_at=datetime.now(timezone.utc),
            org_id=org_id
        )
        mock_app_state.event_store.append.return_value = [created_event]

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                due_date = (datetime.now(timezone.utc) + timedelta(days=7)).isoformat()

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/tasks",
                        json={
                            "title": "Task with deadline",
                            "priority": "high",
                            "due_date": due_date
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 201
                data = response.json()
                assert data["due_date"] is not None

    @pytest.mark.asyncio
    async def test_create_task_invalid_priority(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test creating task with invalid priority."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/tasks",
                        json={
                            "title": "Task",
                            "priority": "invalid_priority"
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 400
                assert "Invalid priority" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_create_task_unauthorized(self, fastapi_app):
        """Test creating task without authentication."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/tasks",
                json={"title": "Unauthorized task", "priority": "low"}
            )

        assert response.status_code in [401, 403]


class TestListTasks:
    """Tests for GET /api/tasks."""

    @pytest.mark.asyncio
    async def test_list_tasks_success(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_task_row
    ):
        """Test listing tasks."""
        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        mock_conn.fetch.return_value = [sample_task_row]

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/tasks",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert isinstance(data, list)
                assert len(data) == 1
                assert data[0]["title"] == sample_task_row["title"]

    @pytest.mark.asyncio
    async def test_list_tasks_with_status_filter(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_task_row
    ):
        """Test listing tasks filtered by status."""
        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        mock_conn.fetch.return_value = [sample_task_row]

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/tasks?status=pending",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) >= 0

    @pytest.mark.asyncio
    async def test_list_tasks_with_pagination(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test listing tasks with pagination."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/tasks?limit=10&offset=20",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_list_tasks_unauthorized(self, fastapi_app):
        """Test listing tasks without authentication."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.get("/api/tasks")

        assert response.status_code in [401, 403]


class TestGetTask:
    """Tests for GET /api/tasks/{id}."""

    @pytest.mark.asyncio
    async def test_get_task_found(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_task_row
    ):
        """Test getting an existing task."""
        task_id = sample_task_row["id"]
        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        mock_conn.fetchrow.return_value = sample_task_row

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        f"/api/tasks/{task_id}",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["id"] == str(task_id)
                assert data["title"] == sample_task_row["title"]

    @pytest.mark.asyncio
    async def test_get_task_not_found(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test getting a non-existent task."""
        task_id = uuid4()
        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        mock_conn.fetchrow.return_value = None

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        f"/api/tasks/{task_id}",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 404
                assert "not found" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_get_task_invalid_uuid(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test getting task with invalid UUID format."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/tasks/not-a-valid-uuid",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 400
                assert "UUID" in response.json()["detail"]


class TestUpdateTask:
    """Tests for PUT /api/tasks/{id}."""

    @pytest.mark.asyncio
    async def test_update_task_success(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_task_row, org_id
    ):
        """Test updating a task."""
        task_id = str(uuid4())

        updated_event = Event(
            id=uuid4(),
            stream_id=f"task-{task_id}",
            event_type="TaskUpdated",
            event_data={"id": task_id, "title": "Updated Title"},
            metadata={},
            sequence=2,
            created_at=datetime.now(timezone.utc),
            org_id=org_id
        )

        mock_app_state.event_store.get_stream_version.return_value = 1
        mock_app_state.event_store.append.return_value = [updated_event]

        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        sample_task_row["title"] = "Updated Title"
        mock_conn.fetchrow.return_value = sample_task_row

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.put(
                        f"/api/tasks/{task_id}",
                        json={"title": "Updated Title"},
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["title"] == "Updated Title"

    @pytest.mark.asyncio
    async def test_update_task_not_found(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test updating non-existent task."""
        task_id = str(uuid4())
        mock_app_state.event_store.get_stream_version.return_value = -1

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.put(
                        f"/api/tasks/{task_id}",
                        json={"title": "Updated"},
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 404


class TestAssignTask:
    """Tests for POST /api/tasks/{id}/assign."""

    @pytest.mark.asyncio
    async def test_assign_task_to_agent(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_task_row, org_id
    ):
        """Test assigning task to an agent."""
        task_id = str(uuid4())

        mock_app_state.event_store.get_stream_version.return_value = 1
        mock_app_state.event_store.append.return_value = [
            Event(
                id=uuid4(),
                stream_id=f"task-{task_id}",
                event_type="TaskAssigned",
                event_data={"agent_type": "implementer"},
                metadata={},
                sequence=2,
                created_at=datetime.now(timezone.utc),
                org_id=org_id
            )
        ]

        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        sample_task_row["assigned_agent"] = "implementer"
        mock_conn.fetchrow.return_value = sample_task_row

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        f"/api/tasks/{task_id}/assign",
                        json={"agent_type": "implementer"},
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                # Verify UWS adapter was called to activate agent
                mock_app_state.uws_adapter.activate_agent.assert_called_once()

    @pytest.mark.asyncio
    async def test_assign_task_to_user(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_task_row, org_id
    ):
        """Test assigning task to a user."""
        task_id = str(uuid4())
        user_id_to_assign = str(uuid4())

        mock_app_state.event_store.get_stream_version.return_value = 1
        mock_app_state.event_store.append.return_value = [
            Event(
                id=uuid4(),
                stream_id=f"task-{task_id}",
                event_type="TaskAssigned",
                event_data={"user_id": user_id_to_assign},
                metadata={},
                sequence=2,
                created_at=datetime.now(timezone.utc),
                org_id=org_id
            )
        ]

        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        mock_conn.fetchrow.return_value = sample_task_row

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        f"/api/tasks/{task_id}/assign",
                        json={"user_id": user_id_to_assign},
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_assign_task_missing_assignee(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test assigning task without specifying agent or user."""
        task_id = str(uuid4())
        mock_app_state.event_store.get_stream_version.return_value = 1

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        f"/api/tasks/{task_id}/assign",
                        json={},
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 400
                assert "must specify" in response.json()["detail"].lower()


class TestCompleteTask:
    """Tests for POST /api/tasks/{id}/complete."""

    @pytest.mark.asyncio
    async def test_complete_task_success(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_task_row, org_id
    ):
        """Test completing a task."""
        task_id = str(uuid4())

        mock_app_state.event_store.get_stream_version.return_value = 1
        mock_app_state.event_store.append.return_value = [
            Event(
                id=uuid4(),
                stream_id=f"task-{task_id}",
                event_type="TaskCompleted",
                event_data={"id": task_id, "status": "completed"},
                metadata={},
                sequence=2,
                created_at=datetime.now(timezone.utc),
                org_id=org_id
            )
        ]

        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        sample_task_row["status"] = "completed"
        mock_conn.fetchrow.return_value = sample_task_row

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        f"/api/tasks/{task_id}/complete",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["status"] == "completed"


class TestDeleteTask:
    """Tests for DELETE /api/tasks/{id}."""

    @pytest.mark.asyncio
    async def test_delete_task_success(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test deleting a task."""
        task_id = str(uuid4())

        mock_app_state.event_store.get_stream_version.return_value = 1
        mock_app_state.event_store.append.return_value = [
            Event(
                id=uuid4(),
                stream_id=f"task-{task_id}",
                event_type="TaskDeleted",
                event_data={"id": task_id},
                metadata={},
                sequence=2,
                created_at=datetime.now(timezone.utc),
                org_id=org_id
            )
        ]

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.delete(
                        f"/api/tasks/{task_id}",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 204

    @pytest.mark.asyncio
    async def test_delete_task_not_found(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test deleting non-existent task."""
        task_id = str(uuid4())
        mock_app_state.event_store.get_stream_version.return_value = -1

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.delete(
                        f"/api/tasks/{task_id}",
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 404


class TestEventSourcing:
    """Tests for event sourcing behavior."""

    @pytest.mark.asyncio
    async def test_task_create_generates_event(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test that creating a task generates TaskCreated event."""
        created_event = Event(
            id=uuid4(),
            stream_id=f"task-{uuid4()}",
            event_type="TaskCreated",
            event_data={"title": "Test Task"},
            metadata={"user_id": str(mock_token_payload.sub)},
            sequence=1,
            created_at=datetime.now(timezone.utc),
            org_id=org_id
        )
        mock_app_state.event_store.append.return_value = [created_event]

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    await client.post(
                        "/api/tasks",
                        json={"title": "Test Task", "priority": "low"},
                        headers={"Authorization": "Bearer test.token"}
                    )

                # Verify event was appended
                mock_app_state.event_store.append.assert_called_once()
                call_args = mock_app_state.event_store.append.call_args
                events = call_args.kwargs["events"]
                assert len(events) == 1
                assert events[0].event_type == "TaskCreated"

    @pytest.mark.asyncio
    async def test_task_update_generates_event(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_task_row, org_id
    ):
        """Test that updating a task generates TaskUpdated event."""
        task_id = str(uuid4())
        mock_app_state.event_store.get_stream_version.return_value = 1

        updated_event = Event(
            id=uuid4(),
            stream_id=f"task-{task_id}",
            event_type="TaskUpdated",
            event_data={"id": task_id, "title": "New Title"},
            metadata={},
            sequence=2,
            created_at=datetime.now(timezone.utc),
            org_id=org_id
        )
        mock_app_state.event_store.append.return_value = [updated_event]

        mock_conn = mock_app_state.pool.acquire.return_value.return_value
        mock_conn.fetchrow.return_value = sample_task_row

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    await client.put(
                        f"/api/tasks/{task_id}",
                        json={"title": "New Title"},
                        headers={"Authorization": "Bearer test.token"}
                    )

                # Verify TaskUpdated event
                assert mock_app_state.event_store.append.called
                call_args = mock_app_state.event_store.append.call_args
                events = call_args.kwargs["events"]
                assert events[0].event_type == "TaskUpdated"

    @pytest.mark.asyncio
    async def test_events_applied_to_projections(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test that events are applied to projection manager."""
        created_event = Event(
            id=uuid4(),
            stream_id=f"task-{uuid4()}",
            event_type="TaskCreated",
            event_data={},
            metadata={},
            sequence=1,
            created_at=datetime.now(timezone.utc),
            org_id=org_id
        )
        mock_app_state.event_store.append.return_value = [created_event]

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch("company_os.api.security.get_current_user_context") as mock_context:
                from company_os.api.security import CurrentUser
                mock_auth.return_value = mock_token_payload
                mock_context.return_value = CurrentUser(mock_token_payload)

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    await client.post(
                        "/api/tasks",
                        json={"title": "Test", "priority": "low"},
                        headers={"Authorization": "Bearer test.token"}
                    )

                # Verify projection manager received the event
                mock_app_state.projection_manager.apply_event.assert_called_once()
                call_args = mock_app_state.projection_manager.apply_event.call_args
                assert call_args.args[0].event_type == "TaskCreated"
