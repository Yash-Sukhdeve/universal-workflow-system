"""
Integration Tests for Memory API.

Tests the semantic memory routes using FastAPI AsyncClient.
"""

import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4, UUID

from httpx import ASGITransport, AsyncClient

from company_os.api.main import create_app
from company_os.api.state import app_state
from company_os.core.memory.service import (
    SemanticMemoryService,
    MemoryType,
    Memory,
    EmbeddingService,
    AgentContextBuilder
)
from company_os.core.auth.models import TokenPayload


class AsyncContextManagerMock:
    """Mock async context manager."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


class TestMemoryAPI:
    """Tests for Memory API endpoints."""

    @pytest.fixture
    def fastapi_app(self):
        """Create FastAPI app for testing."""
        return create_app()

    @pytest.fixture
    def mock_app_state(self):
        """Create mock application state."""
        mock_pool = MagicMock()
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        mock_embedding_service = MagicMock(spec=EmbeddingService)
        app_state.pool = mock_pool
        app_state.memory_service = SemanticMemoryService(
            mock_pool,
            mock_embedding_service
        )
        return app_state

    @pytest.fixture
    def mock_token_payload(self):
        """Create mock token payload for authenticated requests."""
        return TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="member",
            permissions=["tasks:read", "tasks:create"],
            exp=datetime.now(timezone.utc),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

    @pytest.mark.asyncio
    async def test_store_memory_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test storing a new memory."""
        memory_id = uuid4()

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(app_state.memory_service, "store", new_callable=AsyncMock) as mock_store:
                mock_store.return_value = memory_id

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/store",
                        json={
                            "memory_type": "task",
                            "content": "Implemented user authentication with JWT tokens",
                            "metadata": {"agent_type": "implementer", "outcome": "success"},
                            "quality_score": 0.8
                        },
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 201
                data = response.json()
                assert "memory_id" in data
                assert data["memory_id"] == str(memory_id)

                # Verify store was called with correct parameters
                mock_store.assert_called_once()
                call_args = mock_store.call_args
                assert call_args.kwargs["memory_type"] == MemoryType.TASK
                assert call_args.kwargs["content"] == "Implemented user authentication with JWT tokens"
                assert call_args.kwargs["quality_score"] == 0.8

    @pytest.mark.asyncio
    async def test_store_memory_invalid_type(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test storing memory with invalid memory type."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

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
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            assert response.status_code == 400
            assert "Invalid memory_type" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_store_memory_unauthorized(self, fastapi_app, mock_app_state):
        """Test storing memory without authentication."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/memory/store",
                json={
                    "memory_type": "task",
                    "content": "Some content",
                    "quality_score": 0.5
                }
            )

        assert response.status_code in [401, 403]

    @pytest.mark.asyncio
    async def test_search_memories_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test searching memories."""
        memory1 = Memory(
            id=uuid4(),
            org_id=UUID(mock_token_payload.org_id),
            memory_type=MemoryType.TASK,
            content="Implemented JWT authentication",
            embedding=[0.1] * 1536,
            quality_score=0.85,
            usage_count=5,
            metadata={"agent_type": "implementer"},
            created_at=datetime.now(timezone.utc),
            similarity=0.92
        )

        memory2 = Memory(
            id=uuid4(),
            org_id=UUID(mock_token_payload.org_id),
            memory_type=MemoryType.DECISION,
            content="Decided to use FastAPI for the API layer",
            embedding=[0.2] * 1536,
            quality_score=0.75,
            usage_count=3,
            metadata={"decision": "API framework choice"},
            created_at=datetime.now(timezone.utc),
            similarity=0.87
        )

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(app_state.memory_service, "search", new_callable=AsyncMock) as mock_search:
                mock_search.return_value = [memory1, memory2]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/memory/search",
                        json={
                            "query": "authentication implementation",
                            "memory_types": ["task", "decision"],
                            "limit": 10,
                            "min_similarity": 0.7
                        },
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 2
                assert data[0]["memory_type"] == "task"
                assert data[0]["similarity"] == 0.92
                assert data[1]["memory_type"] == "decision"
                assert data[1]["similarity"] == 0.87

    @pytest.mark.asyncio
    async def test_search_memories_invalid_type(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test searching with invalid memory type."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/search",
                    json={
                        "query": "test query",
                        "memory_types": ["invalid_type"],
                        "limit": 10
                    },
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            assert response.status_code == 400
            assert "Invalid memory type" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_build_agent_context_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test building agent context with memories."""
        enhanced_context = """You are a implementer agent.

---

## Similar Successful Tasks

Learn from these similar tasks we've completed:

### Example 1 (Similarity: 95%)
**Task:** Implemented user authentication system...
**Approach:** Used JWT tokens with refresh token rotation
**Key Insight:** Always validate tokens server-side

---

## Relevant Past Decisions

Consider these related decisions we've made:

- **Use FastAPI for API layer**
  Rationale: Better async support and automatic OpenAPI docs"""

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(AgentContextBuilder, "build_context", new_callable=AsyncMock) as mock_build:
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
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert "enhanced_context" in data
                assert "memories_used" in data
                assert data["memories_used"] >= 0
                assert "Similar Successful Tasks" in data["enhanced_context"]

    @pytest.mark.asyncio
    async def test_find_similar_tasks_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test finding similar past tasks."""
        memory = Memory(
            id=uuid4(),
            org_id=UUID(mock_token_payload.org_id),
            memory_type=MemoryType.TASK,
            content="Implemented rate limiting middleware",
            embedding=[0.1] * 1536,
            quality_score=0.9,
            usage_count=2,
            metadata={"agent_type": "implementer", "outcome": "success"},
            created_at=datetime.now(timezone.utc),
            similarity=0.88
        )

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(
                app_state.memory_service,
                "search_similar_tasks",
                new_callable=AsyncMock
            ) as mock_search:
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
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "task"
                assert data[0]["content"] == "Implemented rate limiting middleware"

    @pytest.mark.asyncio
    async def test_find_decisions_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test finding relevant past decisions."""
        memory = Memory(
            id=uuid4(),
            org_id=UUID(mock_token_payload.org_id),
            memory_type=MemoryType.DECISION,
            content="Use PostgreSQL for persistence",
            embedding=[0.1] * 1536,
            quality_score=0.95,
            usage_count=8,
            metadata={"decision": "Database choice", "rationale": "Better ACID guarantees"},
            created_at=datetime.now(timezone.utc),
            similarity=0.91
        )

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(
                app_state.memory_service,
                "search_decisions",
                new_callable=AsyncMock
            ) as mock_search:
                mock_search.return_value = [memory]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/memory/decisions",
                        params={
                            "topic": "database selection",
                            "limit": 5
                        },
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "decision"
                assert "PostgreSQL" in data[0]["content"]

    @pytest.mark.asyncio
    async def test_find_code_patterns_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test finding relevant code patterns."""
        memory = Memory(
            id=uuid4(),
            org_id=UUID(mock_token_payload.org_id),
            memory_type=MemoryType.CODE_PATTERN,
            content="async def endpoint():\n    async with pool.acquire() as conn:\n        ...",
            embedding=[0.1] * 1536,
            quality_score=0.88,
            usage_count=12,
            metadata={"pattern_name": "Database connection pattern", "language": "python"},
            created_at=datetime.now(timezone.utc),
            similarity=0.93
        )

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(
                app_state.memory_service,
                "search_code_patterns",
                new_callable=AsyncMock
            ) as mock_search:
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
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "code_pattern"
                assert "async def" in data[0]["content"]

    @pytest.mark.asyncio
    async def test_find_errors_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test finding similar past errors."""
        memory = Memory(
            id=uuid4(),
            org_id=UUID(mock_token_payload.org_id),
            memory_type=MemoryType.ERROR,
            content="Connection pool exhaustion when not releasing connections",
            embedding=[0.1] * 1536,
            quality_score=0.85,
            usage_count=4,
            metadata={
                "error_type": "ConnectionPoolError",
                "prevention": "Always use context managers for pool.acquire()"
            },
            created_at=datetime.now(timezone.utc),
            similarity=0.89
        )

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(
                app_state.memory_service,
                "search_errors",
                new_callable=AsyncMock
            ) as mock_search:
                mock_search.return_value = [memory]

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/memory/errors",
                        params={
                            "context": "database connection issues",
                            "limit": 5
                        },
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert len(data) == 1
                assert data[0]["memory_type"] == "error"
                assert "Connection pool" in data[0]["content"]

    @pytest.mark.asyncio
    async def test_update_memory_quality_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test updating memory quality score."""
        memory_id = uuid4()

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(
                app_state.memory_service,
                "update_quality",
                new_callable=AsyncMock
            ) as mock_update:
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
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["message"] == "Quality updated"
                assert data["quality_score"] == 0.95

                # Verify update_quality was called correctly
                mock_update.assert_called_once()
                call_args = mock_update.call_args
                assert call_args.kwargs["memory_id"] == memory_id
                assert call_args.kwargs["quality_score"] == 0.95
                assert call_args.kwargs["feedback"] == "Very helpful for similar tasks"

    @pytest.mark.asyncio
    async def test_update_memory_quality_invalid_uuid(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test updating quality with invalid UUID."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.put(
                    "/api/memory/not-a-uuid/quality",
                    params={"quality_score": 0.95},
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            # Should either be 422 (validation error) or 500 (UUID parsing error)
            assert response.status_code in [422, 500]

    @pytest.mark.asyncio
    async def test_consolidate_memories_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test consolidating similar memories."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(
                app_state.memory_service,
                "consolidate",
                new_callable=AsyncMock
            ) as mock_consolidate:
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
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["merged_count"] == 5

                # Verify consolidate was called with correct parameters
                mock_consolidate.assert_called_once()
                call_args = mock_consolidate.call_args
                assert call_args.kwargs["memory_type"] == MemoryType.TASK
                assert call_args.kwargs["similarity_threshold"] == 0.96

    @pytest.mark.asyncio
    async def test_consolidate_invalid_memory_type(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test consolidation with invalid memory type."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

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
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            assert response.status_code == 400
            assert "Invalid memory_type" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_prune_old_memories_success(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test pruning old memories."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            with patch.object(
                app_state.memory_service,
                "prune_old",
                new_callable=AsyncMock
            ) as mock_prune:
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
                        headers={"Authorization": "Bearer fake.token.here"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["deleted_count"] == 12

                # Verify prune_old was called with correct parameters
                mock_prune.assert_called_once()
                call_args = mock_prune.call_args
                assert call_args.kwargs["memory_type"] == MemoryType.TASK
                assert call_args.kwargs["max_age_days"] == 90
                assert call_args.kwargs["keep_high_quality"] is True

    @pytest.mark.asyncio
    async def test_prune_invalid_memory_type(self, fastapi_app, mock_app_state, mock_token_payload):
        """Test pruning with invalid memory type."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

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
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            assert response.status_code == 400
            assert "Invalid memory_type" in response.json()["detail"]


class TestMemoryValidation:
    """Tests for memory input validation."""

    @pytest.fixture
    def fastapi_app(self):
        """Create FastAPI app for testing."""
        return create_app()

    @pytest.fixture
    def mock_token_payload(self):
        """Create mock token payload for authenticated requests."""
        return TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="member",
            permissions=["tasks:read"],
            exp=datetime.now(timezone.utc),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

    @pytest.mark.asyncio
    async def test_store_memory_missing_content(self, fastapi_app, mock_token_payload):
        """Test storing memory with missing content field."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

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
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            assert response.status_code == 422  # Validation error

    @pytest.mark.asyncio
    async def test_search_memory_missing_query(self, fastapi_app, mock_token_payload):
        """Test searching memory with missing query field."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/search",
                    json={
                        "limit": 10
                    },
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            assert response.status_code == 422  # Validation error

    @pytest.mark.asyncio
    async def test_build_context_missing_fields(self, fastapi_app, mock_token_payload):
        """Test building context with missing required fields."""
        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/memory/context",
                    json={
                        "agent_type": "implementer"
                        # Missing "task" field
                    },
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            assert response.status_code == 422  # Validation error

    @pytest.mark.asyncio
    async def test_quality_score_out_of_range(self, fastapi_app, mock_token_payload):
        """Test updating quality with out-of-range score."""
        memory_id = uuid4()

        with patch("company_os.api.security.get_current_user") as mock_get_user:
            mock_get_user.return_value = mock_token_payload

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.put(
                    f"/api/memory/{memory_id}/quality",
                    params={
                        "quality_score": 1.5  # Invalid: should be 0-1
                    },
                    headers={"Authorization": "Bearer fake.token.here"}
                )

            assert response.status_code == 422  # Validation error
