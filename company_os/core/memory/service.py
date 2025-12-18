"""
Semantic Memory Service.

Vector-based memory for agent learning and context enhancement.
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4
import json

import asyncpg
import numpy as np


class MemoryType(str, Enum):
    """Types of memories stored."""
    TASK = "task"
    DECISION = "decision"
    CODE_PATTERN = "code_pattern"
    HANDOFF = "handoff"
    SKILL = "skill"
    ERROR = "error"


@dataclass
class Memory:
    """Memory record from semantic search."""
    id: UUID
    org_id: UUID
    memory_type: MemoryType
    content: str
    embedding: np.ndarray
    quality_score: float
    usage_count: int
    metadata: dict[str, Any]
    created_at: datetime
    similarity: float = 0.0  # Set during search


class EmbeddingService:
    """
    Generate embeddings using various providers.

    Supports:
    - OpenAI (text-embedding-3-small)
    - Sentence Transformers (local)
    """

    def __init__(
        self,
        provider: str = "openai",
        api_key: Optional[str] = None,
        model: str = "text-embedding-3-small"
    ):
        self.provider = provider
        self.api_key = api_key
        self.model = model
        self.dimensions = 1536
        self._client = None

    async def _get_client(self):
        """Lazy initialization of embedding client."""
        if self._client is None:
            if self.provider == "openai":
                try:
                    import openai
                    self._client = openai.AsyncOpenAI(api_key=self.api_key)
                except ImportError:
                    raise RuntimeError("openai package not installed")
            elif self.provider == "sentence-transformers":
                try:
                    from sentence_transformers import SentenceTransformer
                    self._client = SentenceTransformer("all-MiniLM-L6-v2")
                    self.dimensions = 384
                except ImportError:
                    raise RuntimeError("sentence-transformers package not installed")
        return self._client

    async def embed(self, text: str) -> np.ndarray:
        """
        Generate embedding for text.

        Args:
            text: Text to embed

        Returns:
            Numpy array of embedding vector
        """
        client = await self._get_client()

        if self.provider == "openai":
            response = await client.embeddings.create(
                model=self.model,
                input=text
            )
            return np.array(response.data[0].embedding)

        elif self.provider == "sentence-transformers":
            # sentence-transformers is synchronous
            embedding = client.encode(text)
            return np.array(embedding)

        else:
            raise ValueError(f"Unknown provider: {self.provider}")

    async def embed_batch(self, texts: list[str]) -> list[np.ndarray]:
        """Generate embeddings for multiple texts."""
        client = await self._get_client()

        if self.provider == "openai":
            response = await client.embeddings.create(
                model=self.model,
                input=texts
            )
            return [np.array(d.embedding) for d in response.data]

        elif self.provider == "sentence-transformers":
            embeddings = client.encode(texts)
            return [np.array(e) for e in embeddings]

        else:
            raise ValueError(f"Unknown provider: {self.provider}")


class SemanticMemoryService:
    """
    Semantic memory service using pgvector.

    Features:
    - Store memories with auto-embedding
    - Semantic search across memory types
    - Quality tracking and usage analytics
    - Memory consolidation and pruning
    """

    def __init__(
        self,
        pool: asyncpg.Pool,
        embedding_service: EmbeddingService
    ):
        self.pool = pool
        self.embedder = embedding_service

    async def store(
        self,
        org_id: UUID,
        memory_type: MemoryType,
        content: str,
        metadata: Optional[dict[str, Any]] = None,
        quality_score: float = 0.5
    ) -> UUID:
        """
        Store a new memory with automatic embedding.

        Args:
            org_id: Organization ID
            memory_type: Type of memory
            content: Text content
            metadata: Additional metadata
            quality_score: Initial quality (0-1)

        Returns:
            UUID of created memory
        """
        embedding = await self.embedder.embed(content)

        async with self.pool.acquire() as conn:
            memory_id = await conn.fetchval(
                """
                INSERT INTO memories
                (id, org_id, memory_type, content, embedding, quality_score, metadata)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                RETURNING id
                """,
                uuid4(),
                org_id,
                memory_type.value,
                content,
                embedding.tolist(),
                quality_score,
                json.dumps(metadata or {})
            )

        return memory_id

    async def search(
        self,
        org_id: UUID,
        query: str,
        memory_types: Optional[list[MemoryType]] = None,
        filters: Optional[dict[str, Any]] = None,
        limit: int = 10,
        min_similarity: float = 0.5
    ) -> list[Memory]:
        """
        Semantic search across memories.

        Args:
            org_id: Organization ID
            query: Natural language query
            memory_types: Filter by memory types
            filters: Additional metadata filters
            limit: Maximum results
            min_similarity: Minimum cosine similarity

        Returns:
            List of relevant memories sorted by similarity
        """
        query_embedding = await self.embedder.embed(query)

        # Build query with parameterized filters to prevent SQL injection
        params: list = [query_embedding.tolist(), org_id, min_similarity]
        param_idx = 4

        # Build type filter with parameterized values
        type_filter = ""
        if memory_types:
            type_placeholders = ", ".join(f"${param_idx + i}" for i in range(len(memory_types)))
            type_filter = f"AND memory_type = ANY(ARRAY[{type_placeholders}]::memory_type[])"
            params.extend([t.value for t in memory_types])
            param_idx += len(memory_types)

        # Build metadata filter with parameterized values (safe from injection)
        metadata_conditions = []
        if filters:
            for key, value in filters.items():
                # Validate key is alphanumeric to prevent injection via key names
                if not key.replace("_", "").isalnum():
                    raise ValueError(f"Invalid filter key: {key}")
                metadata_conditions.append(f"metadata->>'{key}' = ${param_idx}")
                params.append(str(value) if not isinstance(value, str) else value)
                param_idx += 1

        metadata_filter = ""
        if metadata_conditions:
            metadata_filter = "AND " + " AND ".join(metadata_conditions)

        params.append(limit)
        limit_param = f"${param_idx}"

        async with self.pool.acquire() as conn:
            rows = await conn.fetch(
                f"""
                SELECT
                    id,
                    org_id,
                    memory_type,
                    content,
                    embedding,
                    quality_score,
                    usage_count,
                    metadata,
                    created_at,
                    1 - (embedding <=> $1) as similarity
                FROM memories
                WHERE org_id = $2
                  AND 1 - (embedding <=> $1) >= $3
                  {type_filter}
                  {metadata_filter}
                ORDER BY embedding <=> $1
                LIMIT {limit_param}
                """,
                *params
            )

        memories = []
        for row in rows:
            memories.append(Memory(
                id=row["id"],
                org_id=row["org_id"],
                memory_type=MemoryType(row["memory_type"]),
                content=row["content"],
                embedding=np.array(row["embedding"]),
                quality_score=row["quality_score"],
                usage_count=row["usage_count"],
                metadata=json.loads(row["metadata"]) if isinstance(row["metadata"], str) else row["metadata"],
                created_at=row["created_at"],
                similarity=row["similarity"]
            ))

            # Update usage count
            await self._increment_usage(row["id"])

        return memories

    async def _increment_usage(self, memory_id: UUID) -> None:
        """Increment usage count for a memory."""
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE memories
                SET usage_count = usage_count + 1,
                    last_used_at = NOW()
                WHERE id = $1
                """,
                memory_id
            )

    async def search_similar_tasks(
        self,
        org_id: UUID,
        task_description: str,
        agent_type: Optional[str] = None,
        outcome_filter: Optional[str] = None,
        limit: int = 5
    ) -> list[Memory]:
        """Find similar past tasks."""
        filters = {}
        if agent_type:
            filters["agent_type"] = agent_type
        if outcome_filter:
            filters["outcome"] = outcome_filter

        return await self.search(
            org_id=org_id,
            query=task_description,
            memory_types=[MemoryType.TASK],
            filters=filters if filters else None,
            limit=limit
        )

    async def search_decisions(
        self,
        org_id: UUID,
        topic: str,
        limit: int = 5
    ) -> list[Memory]:
        """Find relevant past decisions."""
        return await self.search(
            org_id=org_id,
            query=topic,
            memory_types=[MemoryType.DECISION],
            limit=limit
        )

    async def search_code_patterns(
        self,
        org_id: UUID,
        description: str,
        language: Optional[str] = None,
        limit: int = 5
    ) -> list[Memory]:
        """Find relevant code patterns."""
        filters = {}
        if language:
            filters["language"] = language

        return await self.search(
            org_id=org_id,
            query=description,
            memory_types=[MemoryType.CODE_PATTERN],
            filters=filters if filters else None,
            limit=limit
        )

    async def search_errors(
        self,
        org_id: UUID,
        error_context: str,
        limit: int = 5
    ) -> list[Memory]:
        """Find similar past errors and their resolutions."""
        return await self.search(
            org_id=org_id,
            query=error_context,
            memory_types=[MemoryType.ERROR],
            limit=limit
        )

    async def update_quality(
        self,
        memory_id: UUID,
        quality_score: float,
        feedback: Optional[str] = None
    ) -> None:
        """Update memory quality score (from human feedback)."""
        async with self.pool.acquire() as conn:
            if feedback:
                await conn.execute(
                    """
                    UPDATE memories
                    SET quality_score = $1,
                        metadata = metadata || $2,
                        updated_at = NOW()
                    WHERE id = $3
                    """,
                    quality_score,
                    json.dumps({"feedback": feedback}),
                    memory_id
                )
            else:
                await conn.execute(
                    """
                    UPDATE memories
                    SET quality_score = $1, updated_at = NOW()
                    WHERE id = $2
                    """,
                    quality_score,
                    memory_id
                )

    async def consolidate(
        self,
        org_id: UUID,
        memory_type: MemoryType,
        similarity_threshold: float = 0.95
    ) -> int:
        """
        Consolidate highly similar memories.

        Merges memories >95% similar, keeping highest quality.

        Returns:
            Number of memories merged
        """
        merged_count = 0

        async with self.pool.acquire() as conn:
            # Find clusters of similar memories
            clusters = await conn.fetch(
                """
                SELECT
                    m1.id as id1,
                    m2.id as id2,
                    m1.quality_score as q1,
                    m2.quality_score as q2,
                    1 - (m1.embedding <=> m2.embedding) as similarity
                FROM memories m1
                JOIN memories m2 ON m1.id < m2.id
                WHERE m1.org_id = $1
                  AND m2.org_id = $1
                  AND m1.memory_type = $2
                  AND m2.memory_type = $2
                  AND 1 - (m1.embedding <=> m2.embedding) >= $3
                ORDER BY similarity DESC
                """,
                org_id,
                memory_type.value,
                similarity_threshold
            )

            # Process clusters (keep higher quality, delete other)
            deleted = set()
            for cluster in clusters:
                if cluster["id1"] in deleted or cluster["id2"] in deleted:
                    continue

                # Delete lower quality memory
                to_delete = cluster["id2"] if cluster["q1"] >= cluster["q2"] else cluster["id1"]
                await conn.execute(
                    "DELETE FROM memories WHERE id = $1",
                    to_delete
                )
                deleted.add(to_delete)
                merged_count += 1

        return merged_count

    async def prune_old(
        self,
        org_id: UUID,
        memory_type: MemoryType,
        max_age_days: int = 90,
        keep_high_quality: bool = True,
        quality_threshold: float = 0.8
    ) -> int:
        """
        Remove old, low-value memories.

        Returns:
            Number of memories deleted
        """
        # Validate inputs to prevent injection
        if not isinstance(max_age_days, int) or max_age_days < 0:
            raise ValueError("max_age_days must be a non-negative integer")
        if not isinstance(quality_threshold, (int, float)) or not 0 <= quality_threshold <= 1:
            raise ValueError("quality_threshold must be between 0 and 1")

        async with self.pool.acquire() as conn:
            if keep_high_quality:
                result = await conn.execute(
                    """
                    DELETE FROM memories
                    WHERE org_id = $1
                      AND memory_type = $2
                      AND created_at < NOW() - ($3::int * INTERVAL '1 day')
                      AND quality_score < $4
                    """,
                    org_id,
                    memory_type.value,
                    max_age_days,
                    quality_threshold
                )
            else:
                result = await conn.execute(
                    """
                    DELETE FROM memories
                    WHERE org_id = $1
                      AND memory_type = $2
                      AND created_at < NOW() - ($3::int * INTERVAL '1 day')
                    """,
                    org_id,
                    memory_type.value,
                    max_age_days
                )

            # Parse delete count from result
            return int(result.split()[-1]) if result else 0


class AgentContextBuilder:
    """
    Builds enhanced context for agents using semantic memory.

    Injects relevant historical context into agent prompts.
    """

    def __init__(self, memory: SemanticMemoryService):
        self.memory = memory

    async def build_context(
        self,
        org_id: UUID,
        agent_type: str,
        task_description: str,
        base_persona: str
    ) -> str:
        """
        Build enhanced context with relevant memories.

        Returns prompt with:
        - Base persona
        - Similar past tasks (with outcomes)
        - Relevant decisions
        - Applicable code patterns
        - Known errors to avoid
        """
        sections = [base_persona]

        # Find similar successful tasks
        similar_tasks = await self.memory.search_similar_tasks(
            org_id=org_id,
            task_description=task_description,
            agent_type=agent_type,
            outcome_filter="success",
            limit=3
        )

        if similar_tasks:
            sections.append(self._format_similar_tasks(similar_tasks))

        # Find relevant decisions
        decisions = await self.memory.search_decisions(
            org_id=org_id,
            topic=task_description,
            limit=3
        )

        if decisions:
            sections.append(self._format_decisions(decisions))

        # Find relevant code patterns for implementing agents
        if agent_type in ["implementer", "experimenter"]:
            patterns = await self.memory.search_code_patterns(
                org_id=org_id,
                description=task_description,
                limit=3
            )
            if patterns:
                sections.append(self._format_code_patterns(patterns))

        # Find known errors to avoid
        errors = await self.memory.search_errors(
            org_id=org_id,
            error_context=task_description,
            limit=3
        )

        if errors:
            sections.append(self._format_errors_to_avoid(errors))

        return "\n\n---\n\n".join(sections)

    def _format_similar_tasks(self, tasks: list[Memory]) -> str:
        result = "## Similar Successful Tasks\n\n"
        result += "Learn from these similar tasks we've completed:\n\n"

        for i, task in enumerate(tasks, 1):
            result += f"### Example {i} (Similarity: {task.similarity:.0%})\n"
            result += f"**Task:** {task.content[:200]}...\n"
            if task.metadata.get("approach"):
                result += f"**Approach:** {task.metadata['approach']}\n"
            if task.metadata.get("key_insight"):
                result += f"**Key Insight:** {task.metadata['key_insight']}\n"
            result += "\n"

        return result

    def _format_decisions(self, decisions: list[Memory]) -> str:
        result = "## Relevant Past Decisions\n\n"
        result += "Consider these related decisions we've made:\n\n"

        for decision in decisions:
            result += f"- **{decision.metadata.get('decision', 'Decision')}**\n"
            result += f"  Rationale: {decision.metadata.get('rationale', 'N/A')}\n"

        return result

    def _format_code_patterns(self, patterns: list[Memory]) -> str:
        result = "## Relevant Code Patterns\n\n"
        result += "Use these established patterns:\n\n"

        for pattern in patterns:
            result += f"### {pattern.metadata.get('pattern_name', 'Pattern')}\n"
            lang = pattern.metadata.get("language", "")
            result += f"```{lang}\n"
            result += f"{pattern.content[:500]}\n```\n\n"

        return result

    def _format_errors_to_avoid(self, errors: list[Memory]) -> str:
        result = "## Known Issues to Avoid\n\n"
        result += "Watch out for these known problems:\n\n"

        for error in errors:
            result += f"- **{error.metadata.get('error_type', 'Error')}**\n"
            result += f"  Prevention: {error.metadata.get('prevention', 'N/A')}\n"

        return result
