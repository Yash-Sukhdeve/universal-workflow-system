"""
Comprehensive Integration Tests for Memory API.

Tests semantic memory operations with pytest and httpx.
"""

import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4, UUID

from httpx import ASGITransport, AsyncClient

from company_os.api.main import create_app
from company_os.api.state import app_state
from company_os.core.auth.models import TokenPayload
from company_os.core.memory.service import (
    SemanticMemoryService,
    MemoryType,
    Memory,
    EmbeddingService,
    AgentContextBuilder
)


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
    pool.acquire.return_value = AsyncContextManager(conn)
    return pool


@pytest.fixture
def mock_embedding_service():
    """Create mock embedding service."""
    service = MagicMock(spec=EmbeddingService)
    service.generate_embedding = AsyncMock(return_value=[0.1] * 1536)
    return service


@pytest.fixture
def mock_memory_service(mock_pool, mock_embedding_service):
    """Create mock memory service."""
    return SemanticMemoryService(mock_pool, mock_embedding_service)


@pytest.fixture
def mock_app_state(mock_pool, mock_memory_service):
    """Setup mock application state."""
    app_state.pool = mock_pool
    app_state.memory_service = mock_memory_service
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
        permissions=["tasks:read", "tasks:create"],
        exp=datetime.now(timezone.utc) + timedelta(minutes=15),
        iat=datetime.now(timezone.utc),
        jti=str(uuid4())
    )


@pytest.fixture
def sample_memory(org_id):
    """Create sample memory object."""
    return Memory(
        id=uuid4(),
        org_id=org_id,
        memory_type=MemoryType.TASK,
        content="Implemented JWT authentication with token rotation",
        embedding=[0.1] * 1536,
        quality_score=0.85,
        usage_count=5,
        metadata={"agent_type": "implementer", "outcome": "success"},
        created_at=datetime.now(timezone.utc),
        similarity=0.92
    )


class TestStoreMemory:
    """Tests for POST /api/memory/store."""

    @pytest.mark.asyncio
    async def test_store_memory_success(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test successfully storing a memory."""
        memory_id = uuid4()

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(app_state.memory_service, "store", new_callable=AsyncMock) as mock_store:
                mock_auth.return_value = mock_token_payload
                mock_store.return_value = memory_id

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/store",
                        json={
                            "memory_type": "task",
                            "content": "Implemented user authentication system",
                            "metadata": {"agent_type": "implementer", "outcome": "success"},
                            "quality_score": 0.8
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 201
                data = response.json()
                assert "memory_id" in data
                assert data["memory_id"] == str(memory_id)

                # Verify store was called correctly
                mock_store.assert_called_once()
                call_kwargs = mock_store.call_args.kwargs
                assert call_kwargs["memory_type"] == MemoryType.TASK
                assert call_kwargs["content"] == "Implemented user authentication system"
                assert call_kwargs["quality_score"] == 0.8
                assert call_kwargs["org_id"] == UUID(mock_token_payload.org_id)

    @pytest.mark.asyncio
    async def test_store_memory_all_types(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test storing memories of all types."""
        memory_types = ["task", "decision", "code_pattern", "handoff", "skill", "error"]

        for mem_type in memory_types:
            memory_id = uuid4()

            with patch("company_os.api.security.get_current_user") as mock_auth:
                with patch.object(app_state.memory_service, "store", new_callable=AsyncMock) as mock_store:
                    mock_auth.return_value = mock_token_payload
                    mock_store.return_value = memory_id

                    async with AsyncClient(
                        transport=ASGITransport(app=fastapi_app),
                        base_url="http://test"
                    ) as client:
                        response = await client.post(
                            "/api/memory/store",
                            json={
                                "memory_type": mem_type,
                                "content": f"Test {mem_type} memory",
                                "quality_score": 0.7
                            },
                            headers={"Authorization": "Bearer test.token"}
                        )

                    assert response.status_code == 201

    @pytest.mark.asyncio
    async def test_store_memory_invalid_type(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test storing memory with invalid type."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/store",
                    json={
                        "memory_type": "invalid_type",
                        "content": "Some content",
                        "quality_score": 0.5
                    },
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code == 400
            assert "Invalid memory_type" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_store_memory_missing_content(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test storing memory without content."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/store",
                    json={
                        "memory_type": "task",
                        "quality_score": 0.5
                    },
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code == 422  # Validation error

    @pytest.mark.asyncio
    async def test_store_memory_unauthorized(self, fastapi_app):
        """Test storing memory without authentication."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/memory/store",
                json={
                    "memory_type": "task",
                    "content": "Unauthorized memory",
                    "quality_score": 0.5
                }
            )

        assert response.status_code in [401, 403]


class TestSearchMemories:
    """Tests for POST /api/memory/search."""

    @pytest.mark.asyncio
    async def test_search_memories_success(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_memory
    ):
        """Test searching memories successfully."""
        memories = [sample_memory]

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(app_state.memory_service, "search", new_callable=AsyncMock) as mock_search:
                mock_auth.return_value = mock_token_payload
                mock_search.return_value = memories

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/search",
                        json={
                            "query": "authentication implementation",
                            "memory_types": ["task"],
                            "limit": 10,
                            "min_similarity": 0.7
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "task"
                assert data[0]["similarity"] == 0.92
                assert data[0]["quality_score"] == 0.85

    @pytest.mark.asyncio
    async def test_search_memories_multiple_types(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test searching across multiple memory types."""
        task_memory = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.TASK,
            content="Task memory",
            embedding=[0.1] * 1536,
            quality_score=0.8,
            usage_count=1,
            metadata={},
            created_at=datetime.now(timezone.utc),
            similarity=0.9
        )

        decision_memory = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.DECISION,
            content="Decision memory",
            embedding=[0.2] * 1536,
            quality_score=0.7,
            usage_count=2,
            metadata={},
            created_at=datetime.now(timezone.utc),
            similarity=0.85
        )

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(app_state.memory_service, "search", new_callable=AsyncMock) as mock_search:
                mock_auth.return_value = mock_token_payload
                mock_search.return_value = [task_memory, decision_memory]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/search",
                        json={
                            "query": "test query",
                            "memory_types": ["task", "decision"],
                            "limit": 10
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 2

    @pytest.mark.asyncio
    async def test_search_memories_with_filters(
        self, fastapi_app, mock_app_state, mock_token_payload, sample_memory
    ):
        """Test searching memories with metadata filters."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(app_state.memory_service, "search", new_callable=AsyncMock) as mock_search:
                mock_auth.return_value = mock_token_payload
                mock_search.return_value = [sample_memory]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/search",
                        json={
                            "query": "authentication",
                            "filters": {"agent_type": "implementer", "outcome": "success"},
                            "limit": 5
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                # Verify filters were passed to service
                call_kwargs = mock_search.call_args.kwargs
                assert call_kwargs["filters"] == {"agent_type": "implementer", "outcome": "success"}

    @pytest.mark.asyncio
    async def test_search_memories_invalid_type(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test searching with invalid memory type."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/search",
                    json={
                        "query": "test",
                        "memory_types": ["invalid_type"],
                        "limit": 10
                    },
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_search_memories_missing_query(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test searching without query parameter."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/search",
                    json={"limit": 10},
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code == 422


class TestBuildAgentContext:
    """Tests for POST /api/memory/context."""

    @pytest.mark.asyncio
    async def test_build_context_success(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test building agent context with memories."""
        enhanced_context = """You are a implementer agent.

---

## Similar Successful Tasks

Learn from these similar tasks we've completed:

### Example 1 (Similarity: 95%)
**Task:** Implemented user authentication system
**Approach:** Used JWT tokens with refresh token rotation
**Key Insight:** Always validate tokens server-side

---

## Relevant Past Decisions

Consider these related decisions we've made:

- **Use FastAPI for API layer**
  Rationale: Better async support and automatic OpenAPI docs"""

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(AgentContextBuilder, "build_context", new_callable=AsyncMock) as mock_build:
                mock_auth.return_value = mock_token_payload
                mock_build.return_value = enhanced_context

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/context",
                        json={
                            "agent_type": "implementer",
                            "task": "Implement OAuth2 authentication"
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert "enhanced_context" in data
                assert "memories_used" in data
                assert "Similar Successful Tasks" in data["enhanced_context"]
                assert data["memories_used"] >= 0

    @pytest.mark.asyncio
    async def test_build_context_missing_fields(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test building context with missing required fields."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/context",
                    json={"agent_type": "implementer"},
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code == 422


class TestFindSimilarTasks:
    """Tests for GET /api/memory/similar-tasks."""

    @pytest.mark.asyncio
    async def test_find_similar_tasks_success(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test finding similar past tasks."""
        memory = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.TASK,
            content="Implemented rate limiting middleware",
            embedding=[0.1] * 1536,
            quality_score=0.9,
            usage_count=2,
            metadata={"agent_type": "implementer", "outcome": "success"},
            created_at=datetime.now(timezone.utc),
            similarity=0.88
        )

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(
                app_state.memory_service,
                "search_similar_tasks",
                new_callable=AsyncMock
            ) as mock_search:
                mock_auth.return_value = mock_token_payload
                mock_search.return_value = [memory]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/memory/similar-tasks",
                        params={
                            "task_description": "Add rate limiting to API",
                            "agent_type": "implementer",
                            "outcome": "success",
                            "limit": 5
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "task"
                assert data[0]["content"] == "Implemented rate limiting middleware"

    @pytest.mark.asyncio
    async def test_find_similar_tasks_with_filters(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test finding similar tasks with agent and outcome filters."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(
                app_state.memory_service,
                "search_similar_tasks",
                new_callable=AsyncMock
            ) as mock_search:
                mock_auth.return_value = mock_token_payload
                mock_search.return_value = []

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/memory/similar-tasks",
                        params={
                            "task_description": "Test task",
                            "agent_type": "researcher",
                            "outcome": "success"
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                # Verify filters were passed
                call_kwargs = mock_search.call_args.kwargs
                assert call_kwargs["agent_type"] == "researcher"
                assert call_kwargs["outcome_filter"] == "success"


class TestFindDecisions:
    """Tests for GET /api/memory/decisions."""

    @pytest.mark.asyncio
    async def test_find_decisions_success(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test finding relevant past decisions."""
        memory = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.DECISION,
            content="Use PostgreSQL for persistence",
            embedding=[0.1] * 1536,
            quality_score=0.95,
            usage_count=8,
            metadata={"decision": "Database choice"},
            created_at=datetime.now(timezone.utc),
            similarity=0.91
        )

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(
                app_state.memory_service,
                "search_decisions",
                new_callable=AsyncMock
            ) as mock_search:
                mock_auth.return_value = mock_token_payload
                mock_search.return_value = [memory]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/memory/decisions",
                        params={"topic": "database selection", "limit": 5},
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "decision"
                assert "PostgreSQL" in data[0]["content"]


class TestFindCodePatterns:
    """Tests for GET /api/memory/code-patterns."""

    @pytest.mark.asyncio
    async def test_find_code_patterns_success(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test finding relevant code patterns."""
        memory = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.CODE_PATTERN,
            content="async def endpoint():\n    async with pool.acquire() as conn:\n        ...",
            embedding=[0.1] * 1536,
            quality_score=0.88,
            usage_count=12,
            metadata={"pattern_name": "Database connection", "language": "python"},
            created_at=datetime.now(timezone.utc),
            similarity=0.93
        )

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(
                app_state.memory_service,
                "search_code_patterns",
                new_callable=AsyncMock
            ) as mock_search:
                mock_auth.return_value = mock_token_payload
                mock_search.return_value = [memory]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/memory/code-patterns",
                        params={
                            "description": "database connection handling",
                            "language": "python",
                            "limit": 5
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "code_pattern"
                assert "async def" in data[0]["content"]


class TestFindErrors:
    """Tests for GET /api/memory/errors."""

    @pytest.mark.asyncio
    async def test_find_errors_success(
        self, fastapi_app, mock_app_state, mock_token_payload, org_id
    ):
        """Test finding similar past errors."""
        memory = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.ERROR,
            content="Connection pool exhaustion when not releasing connections",
            embedding=[0.1] * 1536,
            quality_score=0.85,
            usage_count=4,
            metadata={
                "error_type": "ConnectionPoolError",
                "prevention": "Always use context managers"
            },
            created_at=datetime.now(timezone.utc),
            similarity=0.89
        )

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(
                app_state.memory_service,
                "search_errors",
                new_callable=AsyncMock
            ) as mock_search:
                mock_auth.return_value = mock_token_payload
                mock_search.return_value = [memory]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/memory/errors",
                        params={"context": "database connection issues", "limit": 5},
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "error"
                assert "Connection pool" in data[0]["content"]


class TestUpdateMemoryQuality:
    """Tests for PUT /api/memory/{id}/quality."""

    @pytest.mark.asyncio
    async def test_update_quality_success(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test updating memory quality score."""
        memory_id = uuid4()

        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(
                app_state.memory_service,
                "update_quality",
                new_callable=AsyncMock
            ) as mock_update:
                mock_auth.return_value = mock_token_payload

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.put(
                        f"/api/memory/{memory_id}/quality",
                        params={
                            "quality_score": 0.95,
                            "feedback": "Very helpful for similar tasks"
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["message"] == "Quality updated"
                assert data["quality_score"] == 0.95

                # Verify update was called correctly
                mock_update.assert_called_once()
                call_kwargs = mock_update.call_args.kwargs
                assert call_kwargs["memory_id"] == memory_id
                assert call_kwargs["quality_score"] == 0.95

    @pytest.mark.asyncio
    async def test_update_quality_invalid_score(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test updating quality with out-of-range score."""
        memory_id = uuid4()

        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.put(
                    f"/api/memory/{memory_id}/quality",
                    params={"quality_score": 1.5},  # Invalid: > 1.0
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_update_quality_invalid_uuid(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test updating quality with invalid UUID."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.put(
                    "/api/memory/not-a-uuid/quality",
                    params={"quality_score": 0.95},
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code in [422, 500]


class TestConsolidateMemories:
    """Tests for POST /api/memory/consolidate."""

    @pytest.mark.asyncio
    async def test_consolidate_success(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test consolidating similar memories."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(
                app_state.memory_service,
                "consolidate",
                new_callable=AsyncMock
            ) as mock_consolidate:
                mock_auth.return_value = mock_token_payload
                mock_consolidate.return_value = 5

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/consolidate",
                        params={
                            "memory_type": "task",
                            "similarity_threshold": 0.96
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["merged_count"] == 5

                # Verify parameters
                call_kwargs = mock_consolidate.call_args.kwargs
                assert call_kwargs["memory_type"] == MemoryType.TASK
                assert call_kwargs["similarity_threshold"] == 0.96

    @pytest.mark.asyncio
    async def test_consolidate_invalid_type(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test consolidation with invalid memory type."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/consolidate",
                    params={
                        "memory_type": "invalid_type",
                        "similarity_threshold": 0.95
                    },
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code == 400


class TestPruneMemories:
    """Tests for POST /api/memory/prune."""

    @pytest.mark.asyncio
    async def test_prune_success(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test pruning old memories."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            with patch.object(
                app_state.memory_service,
                "prune_old",
                new_callable=AsyncMock
            ) as mock_prune:
                mock_auth.return_value = mock_token_payload
                mock_prune.return_value = 12

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/prune",
                        params={
                            "memory_type": "task",
                            "max_age_days": 90,
                            "keep_high_quality": True
                        },
                        headers={"Authorization": "Bearer test.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["deleted_count"] == 12

                # Verify parameters
                call_kwargs = mock_prune.call_args.kwargs
                assert call_kwargs["memory_type"] == MemoryType.TASK
                assert call_kwargs["max_age_days"] == 90
                assert call_kwargs["keep_high_quality"] is True

    @pytest.mark.asyncio
    async def test_prune_invalid_type(
        self, fastapi_app, mock_app_state, mock_token_payload
    ):
        """Test pruning with invalid memory type."""
        with patch("company_os.api.security.get_current_user") as mock_auth:
            mock_auth.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/prune",
                    params={
                        "memory_type": "invalid_type",
                        "max_age_days": 90
                    },
                    headers={"Authorization": "Bearer test.token"}
                )

            assert response.status_code == 400
