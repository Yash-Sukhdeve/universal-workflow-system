"""
Unit Tests for Semantic Memory Service.

Tests embedding generation and memory search functionality.
"""

import pytest
import numpy as np
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

from company_os.core.memory.service import (
    MemoryType,
    Memory,
    EmbeddingService,
    SemanticMemoryService,
    AgentContextBuilder
)


class AsyncContextManagerMock:
    """Mock async context manager for connection pool and transactions."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


class TestMemoryType:
    """Tests for MemoryType enum."""

    def test_all_memory_types_exist(self):
        """Test all expected memory types are defined."""
        assert MemoryType.TASK.value == "task"
        assert MemoryType.DECISION.value == "decision"
        assert MemoryType.CODE_PATTERN.value == "code_pattern"
        assert MemoryType.HANDOFF.value == "handoff"
        assert MemoryType.SKILL.value == "skill"
        assert MemoryType.ERROR.value == "error"

    def test_memory_type_from_string(self):
        """Test creating MemoryType from string."""
        assert MemoryType("task") == MemoryType.TASK
        assert MemoryType("decision") == MemoryType.DECISION

    def test_invalid_memory_type(self):
        """Test invalid memory type raises ValueError."""
        with pytest.raises(ValueError):
            MemoryType("invalid_type")


class TestMemory:
    """Tests for Memory dataclass."""

    def test_memory_creation(self):
        """Test creating Memory instance."""
        memory = Memory(
            id=uuid4(),
            org_id=uuid4(),
            memory_type=MemoryType.TASK,
            content="Test memory content",
            embedding=np.array([0.1, 0.2, 0.3]),
            quality_score=0.8,
            usage_count=5,
            metadata={"agent": "researcher"},
            created_at=datetime.now(timezone.utc),
            similarity=0.95
        )

        assert memory.content == "Test memory content"
        assert memory.quality_score == 0.8
        assert memory.similarity == 0.95

    def test_memory_default_similarity(self):
        """Test Memory default similarity is 0.0."""
        memory = Memory(
            id=uuid4(),
            org_id=uuid4(),
            memory_type=MemoryType.DECISION,
            content="Decision content",
            embedding=np.zeros(10),
            quality_score=0.5,
            usage_count=0,
            metadata={},
            created_at=datetime.now(timezone.utc)
        )

        assert memory.similarity == 0.0


class TestEmbeddingService:
    """Tests for EmbeddingService."""

    def test_initialization_openai(self):
        """Test OpenAI provider initialization."""
        service = EmbeddingService(
            provider="openai",
            api_key="test-key",
            model="text-embedding-3-small"
        )

        assert service.provider == "openai"
        assert service.model == "text-embedding-3-small"
        assert service.dimensions == 1536

    def test_initialization_sentence_transformers(self):
        """Test sentence-transformers initialization."""
        service = EmbeddingService(
            provider="sentence-transformers"
        )

        assert service.provider == "sentence-transformers"
        # Dimensions updated on client init
        assert service.dimensions == 1536  # Default before init

    @pytest.mark.asyncio
    async def test_embed_openai(self):
        """Test embedding generation with OpenAI."""
        service = EmbeddingService(
            provider="openai",
            api_key="test-key"
        )

        # Mock the OpenAI client
        mock_response = MagicMock()
        mock_response.data = [MagicMock(embedding=[0.1] * 1536)]

        mock_client = AsyncMock()
        mock_client.embeddings.create = AsyncMock(return_value=mock_response)
        service._client = mock_client

        embedding = await service.embed("Test text")

        assert isinstance(embedding, np.ndarray)
        assert len(embedding) == 1536
        mock_client.embeddings.create.assert_called_once()

    @pytest.mark.asyncio
    async def test_embed_batch_openai(self):
        """Test batch embedding generation."""
        service = EmbeddingService(
            provider="openai",
            api_key="test-key"
        )

        mock_response = MagicMock()
        mock_response.data = [
            MagicMock(embedding=[0.1] * 1536),
            MagicMock(embedding=[0.2] * 1536)
        ]

        mock_client = AsyncMock()
        mock_client.embeddings.create = AsyncMock(return_value=mock_response)
        service._client = mock_client

        embeddings = await service.embed_batch(["Text 1", "Text 2"])

        assert len(embeddings) == 2
        assert all(isinstance(e, np.ndarray) for e in embeddings)


class TestSemanticMemoryService:
    """Tests for SemanticMemoryService."""

    @pytest.fixture
    def mock_pool(self):
        """Create mock database pool."""
        return MagicMock()

    @pytest.fixture
    def mock_embedder(self):
        """Create mock embedding service."""
        embedder = AsyncMock(spec=EmbeddingService)
        embedder.embed = AsyncMock(return_value=np.array([0.1] * 1536))
        return embedder

    @pytest.fixture
    def memory_service(self, mock_pool, mock_embedder):
        """Create SemanticMemoryService with mocks."""
        return SemanticMemoryService(mock_pool, mock_embedder)

    @pytest.mark.asyncio
    async def test_store_memory(self, memory_service, mock_pool, mock_embedder):
        """Test storing a new memory."""
        memory_id = uuid4()
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=memory_id)

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        result = await memory_service.store(
            org_id=org_id,
            memory_type=MemoryType.TASK,
            content="Test task content",
            metadata={"agent": "researcher"},
            quality_score=0.7
        )

        assert result == memory_id
        mock_embedder.embed.assert_called_once_with("Test task content")

    @pytest.mark.asyncio
    async def test_search_memories(self, memory_service, mock_pool, mock_embedder):
        """Test searching memories."""
        org_id = uuid4()
        memory_id = uuid4()
        now = datetime.now(timezone.utc)

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[
            {
                "id": memory_id,
                "org_id": org_id,
                "memory_type": "task",
                "content": "Similar task",
                "embedding": [0.1] * 1536,
                "quality_score": 0.8,
                "usage_count": 3,
                "metadata": {"agent": "researcher"},
                "created_at": now,
                "similarity": 0.92
            }
        ])
        mock_conn.execute = AsyncMock()  # For usage count update

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        results = await memory_service.search(
            org_id=org_id,
            query="Find similar tasks",
            memory_types=[MemoryType.TASK],
            limit=5
        )

        assert len(results) == 1
        assert results[0].content == "Similar task"
        assert results[0].similarity == 0.92

    @pytest.mark.asyncio
    async def test_search_with_filters(self, memory_service, mock_pool, mock_embedder):
        """Test search with metadata filters."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[])
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        await memory_service.search(
            org_id=org_id,
            query="test",
            filters={"agent_type": "researcher", "outcome": "success"}
        )

        # Verify search was executed
        mock_conn.fetch.assert_called_once()

    @pytest.mark.asyncio
    async def test_search_empty_results(self, memory_service, mock_pool, mock_embedder):
        """Test search returns empty list when no matches."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[])

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        results = await memory_service.search(
            org_id=org_id,
            query="no matches",
            min_similarity=0.99
        )

        assert results == []

    @pytest.mark.asyncio
    async def test_search_similar_tasks(self, memory_service, mock_pool, mock_embedder):
        """Test search_similar_tasks convenience method."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[])
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        await memory_service.search_similar_tasks(
            org_id=org_id,
            task_description="Build authentication system",
            agent_type="implementer",
            outcome_filter="success"
        )

        mock_embedder.embed.assert_called_once()

    @pytest.mark.asyncio
    async def test_update_quality(self, memory_service, mock_pool):
        """Test updating memory quality score."""
        memory_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        await memory_service.update_quality(
            memory_id=memory_id,
            quality_score=0.9,
            feedback="Excellent solution"
        )

        mock_conn.execute.assert_called_once()

    @pytest.mark.asyncio
    async def test_consolidate_memories(self, memory_service, mock_pool):
        """Test memory consolidation."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[
            {"id1": uuid4(), "id2": uuid4(), "q1": 0.8, "q2": 0.6}
        ])
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        merged = await memory_service.consolidate(
            org_id=org_id,
            memory_type=MemoryType.TASK,
            similarity_threshold=0.95
        )

        assert merged == 1

    @pytest.mark.asyncio
    async def test_prune_old_memories(self, memory_service, mock_pool):
        """Test pruning old memories."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.execute = AsyncMock(return_value="DELETE 5")

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        deleted = await memory_service.prune_old(
            org_id=org_id,
            memory_type=MemoryType.ERROR,
            max_age_days=30
        )

        assert deleted == 5


class TestAgentContextBuilder:
    """Tests for AgentContextBuilder."""

    @pytest.fixture
    def mock_memory_service(self):
        """Create mock memory service."""
        return AsyncMock(spec=SemanticMemoryService)

    @pytest.fixture
    def context_builder(self, mock_memory_service):
        """Create AgentContextBuilder with mock."""
        return AgentContextBuilder(mock_memory_service)

    @pytest.mark.asyncio
    async def test_build_context_basic(self, context_builder, mock_memory_service):
        """Test building basic context."""
        org_id = uuid4()

        # Mock returns empty for all searches
        mock_memory_service.search_similar_tasks = AsyncMock(return_value=[])
        mock_memory_service.search_decisions = AsyncMock(return_value=[])
        mock_memory_service.search_code_patterns = AsyncMock(return_value=[])
        mock_memory_service.search_errors = AsyncMock(return_value=[])

        context = await context_builder.build_context(
            org_id=org_id,
            agent_type="researcher",
            task_description="Research transformers",
            base_persona="You are a researcher."
        )

        assert "You are a researcher." in context

    @pytest.mark.asyncio
    async def test_build_context_with_similar_tasks(self, context_builder, mock_memory_service):
        """Test context includes similar tasks."""
        org_id = uuid4()

        similar_task = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.TASK,
            content="Previous research on attention mechanisms",
            embedding=np.zeros(10),
            quality_score=0.9,
            usage_count=5,
            metadata={"approach": "systematic review"},
            created_at=datetime.now(timezone.utc),
            similarity=0.88
        )

        mock_memory_service.search_similar_tasks = AsyncMock(return_value=[similar_task])
        mock_memory_service.search_decisions = AsyncMock(return_value=[])
        mock_memory_service.search_code_patterns = AsyncMock(return_value=[])
        mock_memory_service.search_errors = AsyncMock(return_value=[])

        context = await context_builder.build_context(
            org_id=org_id,
            agent_type="researcher",
            task_description="Research transformers",
            base_persona="You are a researcher."
        )

        assert "Similar Successful Tasks" in context
        assert "88%" in context  # Similarity percentage

    @pytest.mark.asyncio
    async def test_build_context_with_decisions(self, context_builder, mock_memory_service):
        """Test context includes relevant decisions."""
        org_id = uuid4()

        decision = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.DECISION,
            content="Use PostgreSQL for database",
            embedding=np.zeros(10),
            quality_score=1.0,
            usage_count=10,
            metadata={"decision": "PostgreSQL", "rationale": "ACID compliance"},
            created_at=datetime.now(timezone.utc),
            similarity=0.75
        )

        mock_memory_service.search_similar_tasks = AsyncMock(return_value=[])
        mock_memory_service.search_decisions = AsyncMock(return_value=[decision])
        mock_memory_service.search_code_patterns = AsyncMock(return_value=[])
        mock_memory_service.search_errors = AsyncMock(return_value=[])

        context = await context_builder.build_context(
            org_id=org_id,
            agent_type="architect",
            task_description="Design database schema",
            base_persona="You are an architect."
        )

        assert "Relevant Past Decisions" in context
        assert "PostgreSQL" in context

    @pytest.mark.asyncio
    async def test_build_context_implementer_gets_code_patterns(
        self, context_builder, mock_memory_service
    ):
        """Test implementer agent gets code patterns."""
        org_id = uuid4()

        pattern = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.CODE_PATTERN,
            content="async def handler(request):\n    pass",
            embedding=np.zeros(10),
            quality_score=0.95,
            usage_count=20,
            metadata={"pattern_name": "API Handler", "language": "python"},
            created_at=datetime.now(timezone.utc),
            similarity=0.82
        )

        mock_memory_service.search_similar_tasks = AsyncMock(return_value=[])
        mock_memory_service.search_decisions = AsyncMock(return_value=[])
        mock_memory_service.search_code_patterns = AsyncMock(return_value=[pattern])
        mock_memory_service.search_errors = AsyncMock(return_value=[])

        context = await context_builder.build_context(
            org_id=org_id,
            agent_type="implementer",
            task_description="Create API endpoint",
            base_persona="You are an implementer."
        )

        assert "Relevant Code Patterns" in context
        assert "API Handler" in context

    @pytest.mark.asyncio
    async def test_build_context_with_errors_to_avoid(self, context_builder, mock_memory_service):
        """Test context includes errors to avoid."""
        org_id = uuid4()

        error = Memory(
            id=uuid4(),
            org_id=org_id,
            memory_type=MemoryType.ERROR,
            content="Connection timeout on database",
            embedding=np.zeros(10),
            quality_score=1.0,
            usage_count=3,
            metadata={"error_type": "TimeoutError", "prevention": "Add connection pooling"},
            created_at=datetime.now(timezone.utc),
            similarity=0.70
        )

        mock_memory_service.search_similar_tasks = AsyncMock(return_value=[])
        mock_memory_service.search_decisions = AsyncMock(return_value=[])
        mock_memory_service.search_code_patterns = AsyncMock(return_value=[])
        mock_memory_service.search_errors = AsyncMock(return_value=[error])

        context = await context_builder.build_context(
            org_id=org_id,
            agent_type="implementer",
            task_description="Setup database connection",
            base_persona="You are an implementer."
        )

        assert "Known Issues to Avoid" in context
        assert "TimeoutError" in context


class TestMemoryEdgeCases:
    """Tests for edge cases and error handling."""

    @pytest.fixture
    def mock_pool(self):
        """Create mock database pool."""
        return MagicMock()

    @pytest.fixture
    def mock_embedder(self):
        """Create mock embedding service."""
        embedder = AsyncMock(spec=EmbeddingService)
        embedder.embed = AsyncMock(return_value=np.array([0.1] * 1536))
        return embedder

    @pytest.fixture
    def memory_service(self, mock_pool, mock_embedder):
        """Create SemanticMemoryService with mocks."""
        return SemanticMemoryService(mock_pool, mock_embedder)

    @pytest.mark.asyncio
    async def test_search_with_invalid_filter_key(self, memory_service, mock_pool, mock_embedder):
        """Test search rejects invalid filter keys (SQL injection prevention)."""
        org_id = uuid4()

        with pytest.raises(ValueError) as exc_info:
            await memory_service.search(
                org_id=org_id,
                query="test",
                filters={"'; DROP TABLE--": "malicious"}
            )

        assert "Invalid filter key" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_search_with_special_chars_in_filter_value(self, memory_service, mock_pool, mock_embedder):
        """Test search handles special characters in filter values safely."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[])
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        # Should not raise - special chars in values are safe
        await memory_service.search(
            org_id=org_id,
            query="test",
            filters={"agent_type": "researcher'; DROP TABLE--"}
        )

        # Verify query was executed (parameterized, so safe)
        mock_conn.fetch.assert_called_once()

    @pytest.mark.asyncio
    async def test_store_with_empty_content(self, memory_service, mock_pool, mock_embedder):
        """Test storing memory with empty content."""
        org_id = uuid4()
        memory_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value=memory_id)

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        result = await memory_service.store(
            org_id=org_id,
            memory_type=MemoryType.TASK,
            content="",  # Empty content
            quality_score=0.5
        )

        assert result == memory_id
        mock_embedder.embed.assert_called_once_with("")

    @pytest.mark.asyncio
    async def test_search_with_multiple_memory_types(self, memory_service, mock_pool, mock_embedder):
        """Test search with multiple memory types filter."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[])
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        await memory_service.search(
            org_id=org_id,
            query="test",
            memory_types=[MemoryType.TASK, MemoryType.DECISION, MemoryType.ERROR],
            limit=20
        )

        # Verify query was executed
        mock_conn.fetch.assert_called_once()
        call_args = mock_conn.fetch.call_args[0]
        # Should include type filter parameters
        assert "task" in call_args
        assert "decision" in call_args
        assert "error" in call_args

    @pytest.mark.asyncio
    async def test_update_quality_without_feedback(self, memory_service, mock_pool):
        """Test updating quality without feedback."""
        memory_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        await memory_service.update_quality(
            memory_id=memory_id,
            quality_score=0.95
            # No feedback provided
        )

        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]
        # Should not include feedback in update
        assert "feedback" not in call_args[0] or call_args[0].count("$") == 2

    @pytest.mark.asyncio
    async def test_consolidate_with_no_duplicates(self, memory_service, mock_pool):
        """Test consolidation when no similar memories exist."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[])  # No clusters found

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        merged = await memory_service.consolidate(
            org_id=org_id,
            memory_type=MemoryType.TASK,
            similarity_threshold=0.95
        )

        assert merged == 0

    @pytest.mark.asyncio
    async def test_consolidate_keeps_higher_quality(self, memory_service, mock_pool):
        """Test consolidation keeps memory with higher quality score."""
        org_id = uuid4()
        high_quality_id = uuid4()
        low_quality_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[
            {
                "id1": high_quality_id,
                "id2": low_quality_id,
                "q1": 0.9,  # Higher quality
                "q2": 0.3,  # Lower quality
                "similarity": 0.98
            }
        ])
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        merged = await memory_service.consolidate(
            org_id=org_id,
            memory_type=MemoryType.DECISION,
            similarity_threshold=0.95
        )

        assert merged == 1
        # Verify the lower quality one was deleted
        delete_call = mock_conn.execute.call_args[0]
        assert "DELETE" in delete_call[0]
        assert low_quality_id in delete_call

    @pytest.mark.asyncio
    async def test_prune_old_with_invalid_max_age(self, memory_service, mock_pool):
        """Test prune_old rejects invalid max_age_days parameter."""
        org_id = uuid4()

        with pytest.raises(ValueError) as exc_info:
            await memory_service.prune_old(
                org_id=org_id,
                memory_type=MemoryType.ERROR,
                max_age_days=-5  # Invalid
            )

        assert "non-negative integer" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_prune_old_with_invalid_quality_threshold(self, memory_service, mock_pool):
        """Test prune_old rejects invalid quality_threshold parameter."""
        org_id = uuid4()

        with pytest.raises(ValueError) as exc_info:
            await memory_service.prune_old(
                org_id=org_id,
                memory_type=MemoryType.ERROR,
                max_age_days=30,
                quality_threshold=1.5  # Invalid (> 1.0)
            )

        assert "between 0 and 1" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_prune_old_keeps_high_quality(self, memory_service, mock_pool):
        """Test prune keeps high quality memories when flag is set."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.execute = AsyncMock(return_value="DELETE 3")

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        deleted = await memory_service.prune_old(
            org_id=org_id,
            memory_type=MemoryType.TASK,
            max_age_days=90,
            keep_high_quality=True,
            quality_threshold=0.8
        )

        assert deleted == 3
        # Verify quality filter was included
        call_args = mock_conn.execute.call_args[0]
        assert "quality_score" in call_args[0]

    @pytest.mark.asyncio
    async def test_prune_old_without_quality_filter(self, memory_service, mock_pool):
        """Test prune deletes all old memories when keep_high_quality=False."""
        org_id = uuid4()

        mock_conn = AsyncMock()
        mock_conn.execute = AsyncMock(return_value="DELETE 10")

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        deleted = await memory_service.prune_old(
            org_id=org_id,
            memory_type=MemoryType.HANDOFF,
            max_age_days=30,
            keep_high_quality=False
        )

        assert deleted == 10

    @pytest.mark.asyncio
    async def test_search_increments_usage_count(self, memory_service, mock_pool, mock_embedder):
        """Test search increments usage_count for returned memories."""
        org_id = uuid4()
        memory_id = uuid4()
        now = datetime.now(timezone.utc)

        mock_conn = AsyncMock()
        mock_conn.fetch = AsyncMock(return_value=[
            {
                "id": memory_id,
                "org_id": org_id,
                "memory_type": "task",
                "content": "Test",
                "embedding": [0.1] * 1536,
                "quality_score": 0.8,
                "usage_count": 5,
                "metadata": {},
                "created_at": now,
                "similarity": 0.9
            }
        ])
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        results = await memory_service.search(
            org_id=org_id,
            query="test"
        )

        assert len(results) == 1
        # Verify usage count was updated
        update_call = mock_conn.execute.call_args[0]
        assert "usage_count" in update_call[0]
        assert memory_id in update_call
