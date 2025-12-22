# UWS + Vector DB: Enhanced Intelligence Substrate

## Vision

Combine UWS's workflow orchestration with vector embeddings to create **semantic memory** that enables agents to:

1. **Learn from history** - Find similar past tasks and their solutions
2. **Build knowledge** - Accumulate organizational knowledge over time
3. **Improve decisions** - Use context-aware retrieval for better outcomes
4. **Share intelligence** - Cross-agent knowledge transfer

---

## Architecture: Semantic Memory Layer

```
┌─────────────────────────────────────────────────────────────────┐
│                     AGENT EXECUTION                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Researcher  │  │ Architect   │  │ Implementer │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                      │
│         └────────────────┼────────────────┘                     │
│                          │                                       │
│                          ▼                                       │
│         ┌────────────────────────────────────┐                  │
│         │     SEMANTIC MEMORY LAYER          │                  │
│         │                                    │                  │
│         │  Query: "How did we solve auth?"   │                  │
│         │           ↓                        │                  │
│         │  [Embedding] → Vector Search       │                  │
│         │           ↓                        │                  │
│         │  Retrieved: [past_tasks, decisions,│                  │
│         │              code_patterns, docs]  │                  │
│         │           ↓                        │                  │
│         │  Inject into agent context         │                  │
│         └────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    KNOWLEDGE STORES                              │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │ TASK MEMORY    │  │ DECISION LOG   │  │ CODE PATTERNS  │    │
│  │                │  │                │  │                │    │
│  │ • Past tasks   │  │ • Why choices  │  │ • Solutions    │    │
│  │ • Solutions    │  │ • Trade-offs   │  │ • Anti-patterns│    │
│  │ • Outcomes     │  │ • Context      │  │ • Best practic │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │ HANDOFF MEMORY │  │ SKILL MEMORY   │  │ ERROR MEMORY   │    │
│  │                │  │                │  │                │    │
│  │ • Context      │  │ • Skill usage  │  │ • Past errors  │    │
│  │ • Blockers     │  │ • Effectiveness│  │ • Resolutions  │    │
│  │ • Next actions │  │ • Chains       │  │ • Root causes  │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
│                                                                  │
│                   PostgreSQL + pgvector                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Memory Types

### 1. Task Memory (Episodic)

**What it stores:**
- Task descriptions and requirements
- Agent execution traces (reasoning steps)
- Outcomes (success/failure, quality score)
- Human feedback and corrections

**Use cases:**
- "Find similar tasks we've done before"
- "What approach worked for this type of problem?"
- "Show me successful researcher outputs for literature reviews"

```python
# Schema
class TaskMemory:
    id: UUID
    task_description: str          # Original task
    embedding: Vector              # Semantic embedding
    agent_type: str                # Which agent worked on it
    execution_trace: list[dict]    # Step-by-step reasoning
    outcome: str                   # success/failure/partial
    quality_score: float           # 0-1 human rating
    human_feedback: str            # Corrections, improvements
    created_at: datetime
    metadata: dict                 # Tags, project, etc.
```

**Query example:**
```python
# Agent starts new literature review task
similar_tasks = await memory.search(
    query="literature review on transformer architectures",
    memory_type="task",
    filters={"agent_type": "researcher", "outcome": "success"},
    limit=5
)

# Inject into agent context
context = f"""
Here are similar successful tasks and their approaches:

{format_similar_tasks(similar_tasks)}

Use these as reference for your approach.
"""
```

### 2. Decision Memory (Architectural)

**What it stores:**
- Technical decisions made
- Alternatives considered
- Trade-offs evaluated
- Context that drove the decision

**Use cases:**
- "Why did we choose PostgreSQL over MongoDB?"
- "What authentication approach did we decide on?"
- "Find decisions related to scaling"

```python
# Schema
class DecisionMemory:
    id: UUID
    decision: str                  # What was decided
    embedding: Vector
    context: str                   # Why it was needed
    alternatives: list[str]        # What else was considered
    trade_offs: str                # Pros/cons
    rationale: str                 # Why this choice
    made_by: str                   # Human or agent
    created_at: datetime
    superseded_by: UUID            # If decision changed
```

**Integration with UWS:**
- Architect agent saves decisions after design phase
- All agents can query before making new decisions
- Prevents contradictory decisions

### 3. Code Pattern Memory (Procedural)

**What it stores:**
- Code patterns and solutions
- Implementation approaches
- Anti-patterns to avoid
- Refactoring improvements

**Use cases:**
- "Show me how we implement API endpoints"
- "What's our pattern for error handling?"
- "Find similar implementations for auth middleware"

```python
# Schema
class CodePatternMemory:
    id: UUID
    pattern_name: str              # e.g., "API endpoint", "Error handler"
    description: str
    embedding: Vector
    code_example: str              # Actual code
    language: str                  # Python, TypeScript, etc.
    tags: list[str]                # Categories
    usage_count: int               # How often referenced
    quality_score: float           # From code reviews
```

### 4. Handoff Memory (Contextual)

**What it stores:**
- Session handoff notes
- Blockers and their resolutions
- Cross-session context
- Project state snapshots

**Use cases:**
- "What was I working on yesterday?"
- "What blockers did we encounter in this project?"
- "Resume context from last session"

**Integration with UWS:**
```python
# When handoff.md is written, embed it
async def on_handoff_created(handoff_content: str, session_id: str):
    embedding = await embed(handoff_content)

    await memory.store(
        memory_type="handoff",
        content=handoff_content,
        embedding=embedding,
        metadata={
            "session_id": session_id,
            "checkpoint_id": get_current_checkpoint(),
            "agent": get_active_agent()
        }
    )
```

### 5. Skill Memory (Procedural)

**What it stores:**
- Skill execution patterns
- Skill effectiveness by context
- Skill chain successes
- Skill parameter tuning

**Use cases:**
- "Which skills work best for code review?"
- "What skill chain is effective for ML pipeline tasks?"
- "How should I configure statistical_validation skill?"

**Integration with UWS Skills:**
```yaml
# .workflow/skills/catalog.yaml enhanced with memory
skills:
  literature_review:
    description: "Conduct systematic literature reviews"
    memory:
      track_effectiveness: true
      learn_from_outcomes: true
      similar_skill_fallback: ["web_search", "paper_analysis"]
```

### 6. Error Memory (Diagnostic)

**What it stores:**
- Errors encountered
- Root cause analyses
- Resolutions that worked
- Prevention strategies

**Use cases:**
- "Have we seen this error before?"
- "What fixed the database connection issue?"
- "Common errors in deployment tasks"

```python
# Schema
class ErrorMemory:
    id: UUID
    error_type: str                # Exception type
    error_message: str
    embedding: Vector              # Embed full context
    context: str                   # What was happening
    root_cause: str                # Why it happened
    resolution: str                # How it was fixed
    prevention: str                # How to avoid
    occurrences: int               # How many times seen
```

---

## Integration Points with UWS

### 1. Checkpoint Integration

When checkpoint is created, embed and store:

```python
# scripts/checkpoint.sh enhanced
async def create_checkpoint(message: str):
    # Existing checkpoint logic
    checkpoint_id = create_checkpoint_files(message)

    # NEW: Embed checkpoint state for semantic search
    state_content = read_state_yaml()
    handoff_content = read_handoff_md()

    await memory.store_checkpoint(
        checkpoint_id=checkpoint_id,
        state_embedding=await embed(json.dumps(state_content)),
        handoff_embedding=await embed(handoff_content),
        message=message
    )

    return checkpoint_id
```

### 2. Agent Activation Integration

When agent activates, retrieve relevant memory:

```python
# scripts/activate_agent.sh enhanced
async def activate_agent(agent_type: str, task: str):
    # Retrieve relevant context from memory
    relevant_memories = await memory.search(
        query=task,
        memory_types=["task", "decision", "code_pattern"],
        filters={"agent_type": agent_type},
        limit=10
    )

    # Inject into agent's persona context
    enhanced_context = build_context_with_memory(
        base_persona=load_persona(agent_type),
        memories=relevant_memories
    )

    # Activate with enhanced context
    activate_with_context(agent_type, enhanced_context)
```

### 3. Session Manager Integration

Track agent reasoning for future learning:

```python
# scripts/lib/session_manager.sh enhanced
async def update_session_with_trace(
    session_id: str,
    thought: str,
    action: str,
    result: str
):
    # Existing update logic
    update_session_progress(session_id, progress)

    # NEW: Store reasoning trace for learning
    await memory.store_trace(
        session_id=session_id,
        step={
            "thought": thought,
            "action": action,
            "result": result,
            "timestamp": now()
        }
    )
```

### 4. Skill Execution Integration

Learn from skill effectiveness:

```python
# When skill completes
async def on_skill_complete(
    skill_name: str,
    context: str,
    outcome: str,
    quality: float
):
    await memory.update_skill_effectiveness(
        skill_name=skill_name,
        context_embedding=await embed(context),
        outcome=outcome,
        quality=quality
    )

    # Learn skill chains that work well together
    if previous_skill:
        await memory.record_skill_chain(
            skills=[previous_skill, skill_name],
            context=context,
            effectiveness=quality
        )
```

---

## Implementation: Semantic Memory Service

```python
# company_os/core/memory/service.py

from typing import List, Dict, Any, Optional
from dataclasses import dataclass
from enum import Enum
import asyncpg
import numpy as np


class MemoryType(Enum):
    TASK = "task"
    DECISION = "decision"
    CODE_PATTERN = "code_pattern"
    HANDOFF = "handoff"
    SKILL = "skill"
    ERROR = "error"


@dataclass
class Memory:
    id: str
    memory_type: MemoryType
    content: str
    embedding: np.ndarray
    metadata: Dict[str, Any]
    created_at: str
    similarity: float = 0.0  # Set during search


class SemanticMemoryService:
    """
    Semantic memory service using pgvector.

    Provides:
    - Store memories with embeddings
    - Semantic search across memory types
    - Memory consolidation and pruning
    - Cross-agent knowledge sharing
    """

    def __init__(
        self,
        pool: asyncpg.Pool,
        embedding_service: 'EmbeddingService'
    ):
        self.pool = pool
        self.embedder = embedding_service

    async def store(
        self,
        memory_type: MemoryType,
        content: str,
        metadata: Dict[str, Any] = None
    ) -> str:
        """Store a new memory with automatic embedding."""
        # Generate embedding
        embedding = await self.embedder.embed(content)

        async with self.pool.acquire() as conn:
            memory_id = await conn.fetchval("""
                INSERT INTO memories
                (memory_type, content, embedding, metadata)
                VALUES ($1, $2, $3, $4)
                RETURNING id
            """,
                memory_type.value,
                content,
                embedding.tolist(),
                metadata or {}
            )

        return str(memory_id)

    async def search(
        self,
        query: str,
        memory_types: List[MemoryType] = None,
        filters: Dict[str, Any] = None,
        limit: int = 10,
        min_similarity: float = 0.5
    ) -> List[Memory]:
        """
        Semantic search across memories.

        Args:
            query: Natural language query
            memory_types: Filter by memory type(s)
            filters: Additional metadata filters
            limit: Max results
            min_similarity: Minimum cosine similarity threshold

        Returns:
            List of relevant memories sorted by similarity
        """
        # Embed query
        query_embedding = await self.embedder.embed(query)

        # Build query
        type_filter = ""
        if memory_types:
            types = ", ".join(f"'{t.value}'" for t in memory_types)
            type_filter = f"AND memory_type IN ({types})"

        metadata_filter = ""
        if filters:
            for key, value in filters.items():
                metadata_filter += f"AND metadata->>'{key}' = '{value}' "

        async with self.pool.acquire() as conn:
            rows = await conn.fetch(f"""
                SELECT
                    id,
                    memory_type,
                    content,
                    embedding,
                    metadata,
                    created_at,
                    1 - (embedding <=> $1) as similarity
                FROM memories
                WHERE 1 - (embedding <=> $1) >= $2
                {type_filter}
                {metadata_filter}
                ORDER BY embedding <=> $1
                LIMIT $3
            """,
                query_embedding.tolist(),
                min_similarity,
                limit
            )

        return [
            Memory(
                id=str(row['id']),
                memory_type=MemoryType(row['memory_type']),
                content=row['content'],
                embedding=np.array(row['embedding']),
                metadata=row['metadata'],
                created_at=str(row['created_at']),
                similarity=row['similarity']
            )
            for row in rows
        ]

    async def search_similar_tasks(
        self,
        task_description: str,
        agent_type: str = None,
        outcome_filter: str = None,
        limit: int = 5
    ) -> List[Memory]:
        """Find similar past tasks."""
        filters = {}
        if agent_type:
            filters["agent_type"] = agent_type
        if outcome_filter:
            filters["outcome"] = outcome_filter

        return await self.search(
            query=task_description,
            memory_types=[MemoryType.TASK],
            filters=filters,
            limit=limit
        )

    async def search_decisions(
        self,
        topic: str,
        limit: int = 5
    ) -> List[Memory]:
        """Find relevant past decisions."""
        return await self.search(
            query=topic,
            memory_types=[MemoryType.DECISION],
            limit=limit
        )

    async def search_code_patterns(
        self,
        description: str,
        language: str = None,
        limit: int = 5
    ) -> List[Memory]:
        """Find relevant code patterns."""
        filters = {}
        if language:
            filters["language"] = language

        return await self.search(
            query=description,
            memory_types=[MemoryType.CODE_PATTERN],
            filters=filters,
            limit=limit
        )

    async def search_errors(
        self,
        error_context: str,
        limit: int = 5
    ) -> List[Memory]:
        """Find similar past errors and their resolutions."""
        return await self.search(
            query=error_context,
            memory_types=[MemoryType.ERROR],
            limit=limit
        )

    async def consolidate(
        self,
        memory_type: MemoryType,
        similarity_threshold: float = 0.95
    ):
        """
        Consolidate similar memories to prevent redundancy.

        Merges memories that are >95% similar.
        """
        async with self.pool.acquire() as conn:
            # Find clusters of similar memories
            clusters = await conn.fetch("""
                SELECT
                    m1.id as id1,
                    m2.id as id2,
                    1 - (m1.embedding <=> m2.embedding) as similarity
                FROM memories m1
                JOIN memories m2 ON m1.id < m2.id
                WHERE m1.memory_type = $1
                  AND m2.memory_type = $1
                  AND 1 - (m1.embedding <=> m2.embedding) >= $2
            """,
                memory_type.value,
                similarity_threshold
            )

            # Merge clusters (keep highest quality)
            # ... implementation

    async def prune_old_memories(
        self,
        memory_type: MemoryType,
        max_age_days: int = 90,
        keep_high_quality: bool = True
    ):
        """Remove old, low-value memories."""
        quality_filter = ""
        if keep_high_quality:
            quality_filter = "AND (metadata->>'quality_score')::float < 0.8"

        async with self.pool.acquire() as conn:
            await conn.execute(f"""
                DELETE FROM memories
                WHERE memory_type = $1
                  AND created_at < NOW() - INTERVAL '{max_age_days} days'
                  {quality_filter}
            """, memory_type.value)


class EmbeddingService:
    """Generate embeddings using OpenAI or local models."""

    def __init__(self, provider: str = "openai", api_key: str = None):
        self.provider = provider
        self.api_key = api_key

        if provider == "openai":
            import openai
            self.client = openai.AsyncOpenAI(api_key=api_key)
            self.model = "text-embedding-3-small"
            self.dimensions = 1536

    async def embed(self, text: str) -> np.ndarray:
        """Generate embedding for text."""
        if self.provider == "openai":
            response = await self.client.embeddings.create(
                model=self.model,
                input=text
            )
            return np.array(response.data[0].embedding)

        # Add other providers (sentence-transformers, etc.)
```

---

## Enhanced Agent Context Builder

```python
# company_os/agents/context.py

from typing import Dict, Any, List
from company_os.core.memory.service import SemanticMemoryService, MemoryType


class AgentContextBuilder:
    """
    Builds enhanced context for agents using semantic memory.

    Injects relevant historical context into agent prompts.
    """

    def __init__(self, memory: SemanticMemoryService):
        self.memory = memory

    async def build_context(
        self,
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
            task_description=task_description,
            agent_type=agent_type,
            outcome_filter="success",
            limit=3
        )

        if similar_tasks:
            sections.append(self._format_similar_tasks(similar_tasks))

        # Find relevant decisions
        decisions = await self.memory.search_decisions(
            topic=task_description,
            limit=3
        )

        if decisions:
            sections.append(self._format_decisions(decisions))

        # Find relevant code patterns
        if agent_type in ["implementer", "experimenter"]:
            patterns = await self.memory.search_code_patterns(
                description=task_description,
                limit=3
            )
            if patterns:
                sections.append(self._format_code_patterns(patterns))

        # Find known errors to avoid
        errors = await self.memory.search_errors(
            error_context=task_description,
            limit=3
        )

        if errors:
            sections.append(self._format_errors_to_avoid(errors))

        return "\n\n---\n\n".join(sections)

    def _format_similar_tasks(self, tasks: List) -> str:
        result = "## Similar Successful Tasks\n\n"
        result += "Learn from these similar tasks we've completed:\n\n"

        for i, task in enumerate(tasks, 1):
            result += f"### Example {i} (Similarity: {task.similarity:.0%})\n"
            result += f"**Task:** {task.content[:200]}...\n"
            if task.metadata.get('approach'):
                result += f"**Approach:** {task.metadata['approach']}\n"
            if task.metadata.get('key_insight'):
                result += f"**Key Insight:** {task.metadata['key_insight']}\n"
            result += "\n"

        return result

    def _format_decisions(self, decisions: List) -> str:
        result = "## Relevant Past Decisions\n\n"
        result += "Consider these related decisions we've made:\n\n"

        for decision in decisions:
            result += f"- **{decision.metadata.get('decision', 'Decision')}**\n"
            result += f"  Rationale: {decision.metadata.get('rationale', 'N/A')}\n"

        return result

    def _format_code_patterns(self, patterns: List) -> str:
        result = "## Relevant Code Patterns\n\n"
        result += "Use these established patterns:\n\n"

        for pattern in patterns:
            result += f"### {pattern.metadata.get('pattern_name', 'Pattern')}\n"
            result += f"```{pattern.metadata.get('language', '')}\n"
            result += f"{pattern.content[:500]}\n```\n\n"

        return result

    def _format_errors_to_avoid(self, errors: List) -> str:
        result = "## Known Issues to Avoid\n\n"
        result += "Watch out for these known problems:\n\n"

        for error in errors:
            result += f"- **{error.metadata.get('error_type', 'Error')}**\n"
            result += f"  Prevention: {error.metadata.get('prevention', 'N/A')}\n"

        return result
```

---

## Database Schema for Memory

```sql
-- migrations/020_create_memory_tables.sql

-- Enable pgvector
CREATE EXTENSION IF NOT EXISTS vector;

-- Memory types enum
CREATE TYPE memory_type AS ENUM (
    'task',
    'decision',
    'code_pattern',
    'handoff',
    'skill',
    'error'
);

-- Main memories table
CREATE TABLE memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID REFERENCES organizations(id),

    memory_type memory_type NOT NULL,
    content TEXT NOT NULL,
    embedding vector(1536) NOT NULL,

    -- Quality and usage tracking
    quality_score FLOAT DEFAULT 0.5,
    usage_count INT DEFAULT 0,
    last_used_at TIMESTAMPTZ,

    -- Metadata (flexible JSON)
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE memories ENABLE ROW LEVEL SECURITY;

CREATE POLICY memories_org_isolation ON memories
    USING (org_id = current_setting('app.current_org_id')::uuid);

-- Vector similarity search index
CREATE INDEX idx_memories_embedding ON memories
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Other indexes
CREATE INDEX idx_memories_type ON memories(memory_type);
CREATE INDEX idx_memories_created ON memories(created_at DESC);
CREATE INDEX idx_memories_metadata ON memories USING GIN(metadata);

-- Memory links (for related memories)
CREATE TABLE memory_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID REFERENCES memories(id) ON DELETE CASCADE,
    target_id UUID REFERENCES memories(id) ON DELETE CASCADE,
    link_type VARCHAR(50) NOT NULL,  -- 'related', 'supersedes', 'derives_from'
    strength FLOAT DEFAULT 1.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(source_id, target_id, link_type)
);

-- Skill effectiveness tracking
CREATE TABLE skill_effectiveness (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    skill_name VARCHAR(100) NOT NULL,
    context_embedding vector(1536),
    success_rate FLOAT NOT NULL,
    avg_quality FLOAT NOT NULL,
    sample_count INT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(skill_name)
);

-- Skill chains (which skills work well together)
CREATE TABLE skill_chains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    skills VARCHAR(100)[] NOT NULL,
    context_embedding vector(1536),
    effectiveness FLOAT NOT NULL,
    usage_count INT DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## Use Cases

### 1. New Researcher Task

```python
# When researcher agent starts a literature review
task = "Review papers on attention mechanisms in transformers"

# System automatically:
# 1. Searches for similar past research tasks
similar = await memory.search_similar_tasks(task, agent_type="researcher")

# 2. Finds relevant decisions (e.g., "we focus on 2023+ papers")
decisions = await memory.search_decisions("literature review methodology")

# 3. Injects into agent context
enhanced_prompt = f"""
{researcher_persona}

## Relevant History

Similar tasks we've completed successfully:
{format_tasks(similar)}

Established approaches:
{format_decisions(decisions)}

Now, your task: {task}
"""
```

### 2. Architect Making Design Decision

```python
# When architect needs to decide on database schema
question = "Should we use single table or separate tables for events?"

# System automatically:
# 1. Finds past database decisions
past_decisions = await memory.search_decisions("database schema design")

# 2. Finds relevant code patterns
patterns = await memory.search_code_patterns("event sourcing schema")

# 3. Prevents contradictory decisions
# If past decision exists, flag it for review
```

### 3. Implementer Writing Code

```python
# When implementer needs to write API endpoint
task = "Create POST /api/tasks endpoint"

# System automatically:
# 1. Finds established API patterns
patterns = await memory.search_code_patterns("API endpoint POST", language="python")

# 2. Finds known errors in similar code
errors = await memory.search_errors("API endpoint errors")

# 3. Suggests consistent implementation
```

### 4. Session Recovery

```python
# When recovering from session break
async def recover_context(session_id: str):
    # Find recent handoff memories
    handoffs = await memory.search(
        query=f"session {session_id}",
        memory_types=[MemoryType.HANDOFF],
        limit=5
    )

    # Build recovery context
    return f"""
    Session Recovery Context:

    Last known state:
    {handoffs[0].content if handoffs else 'No previous context'}

    Related work:
    {format_related_handoffs(handoffs[1:])}
    """
```

---

## Learning Loop

```
┌──────────────────────────────────────────────────────────────┐
│                     LEARNING LOOP                             │
│                                                               │
│  1. CAPTURE                                                   │
│     Agent executes task                                       │
│     └─→ Store task + trace + outcome                         │
│                                                               │
│  2. EVALUATE                                                  │
│     Human reviews output                                      │
│     └─→ Store quality score + feedback                       │
│                                                               │
│  3. CONSOLIDATE                                               │
│     Periodic batch process                                    │
│     └─→ Merge similar memories                               │
│     └─→ Extract patterns                                     │
│     └─→ Update skill effectiveness                           │
│                                                               │
│  4. RETRIEVE                                                  │
│     Next similar task                                         │
│     └─→ Inject learned context                               │
│     └─→ Better performance                                   │
│                                                               │
│  [Repeat]                                                     │
└──────────────────────────────────────────────────────────────┘
```

---

## Integration with Existing UWS

### Modified activate_agent.sh

```bash
# Enhanced agent activation with memory
activate_agent() {
    local agent="$1"
    local task="${2:-}"

    # NEW: Get memory-enhanced context via API
    local enhanced_context
    enhanced_context=$(curl -s "http://localhost:8000/api/memory/context" \
        -H "Content-Type: application/json" \
        -d "{
            \"agent_type\": \"$agent\",
            \"task\": \"$task\"
        }")

    # Write enhanced persona to temp file
    echo "$enhanced_context" > ".workflow/agents/${agent}_enhanced_persona.md"

    # Continue with existing activation...
}
```

### Modified session_manager.sh

```bash
# Store execution trace on session update
update_session_progress() {
    local session_id="$1"
    local progress="$2"
    local thought="${3:-}"

    # Existing progress update...

    # NEW: Store thought trace for learning
    if [[ -n "$thought" ]]; then
        curl -s "http://localhost:8000/api/memory/trace" \
            -H "Content-Type: application/json" \
            -d "{
                \"session_id\": \"$session_id\",
                \"thought\": \"$thought\",
                \"progress\": $progress
            }"
    fi
}
```

### Modified checkpoint.sh

```bash
# Store checkpoint in semantic memory
create_checkpoint() {
    local message="$1"

    # Existing checkpoint creation...

    # NEW: Embed checkpoint for semantic search
    curl -s "http://localhost:8000/api/memory/checkpoint" \
        -H "Content-Type: application/json" \
        -d "{
            \"checkpoint_id\": \"$checkpoint_id\",
            \"message\": \"$message\",
            \"state\": $(cat .workflow/state.yaml | python3 -c 'import sys,json,yaml; print(json.dumps(yaml.safe_load(sys.stdin)))'),
            \"handoff\": $(cat .workflow/handoff.md | jq -Rs .)
        }"
}
```

---

## Benefits

### 1. **Continuous Learning**
- Every task improves future performance
- Mistakes are captured and prevented
- Best practices emerge organically

### 2. **Knowledge Persistence**
- Survives session breaks
- Transfers across agents
- Accumulates organizational wisdom

### 3. **Context-Aware Execution**
- Agents don't repeat mistakes
- Consistent with past decisions
- Builds on proven patterns

### 4. **Reduced Token Usage**
- Only inject relevant context
- Compressed historical knowledge
- Efficient retrieval vs. full history

### 5. **Auditable Intelligence**
- Can explain why decisions were made
- Traceable learning path
- Transparent reasoning

---

## Next Steps

1. **Week 1**: Implement EmbeddingService + Memory schema
2. **Week 2**: Create SemanticMemoryService
3. **Week 3**: Integrate with UWS scripts
4. **Week 4**: Build learning loop + consolidation

This creates a **truly intelligent** system that improves over time!
