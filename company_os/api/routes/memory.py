"""
Semantic Memory Routes.

Store and retrieve memories for agent learning.
"""

from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel

from ..state import get_app_state
from ..security import get_current_user_context, CurrentUser
from ...core.memory.service import MemoryType, AgentContextBuilder


router = APIRouter()


# Request/Response Models

class StoreMemoryRequest(BaseModel):
    """Store memory request."""
    memory_type: str  # task, decision, code_pattern, handoff, skill, error
    content: str
    metadata: Optional[dict] = None
    quality_score: float = 0.5


class SearchMemoryRequest(BaseModel):
    """Search memory request."""
    query: str
    memory_types: Optional[list[str]] = None
    filters: Optional[dict] = None
    limit: int = 10
    min_similarity: float = 0.5


class MemoryResponse(BaseModel):
    """Memory response."""
    id: str
    memory_type: str
    content: str
    quality_score: float
    usage_count: int
    metadata: dict
    created_at: str
    similarity: float


class ContextRequest(BaseModel):
    """Context build request."""
    agent_type: str
    task: str


class ContextResponse(BaseModel):
    """Context response."""
    enhanced_context: str
    memories_used: int


# Routes

@router.post("/store", status_code=status.HTTP_201_CREATED)
async def store_memory(
    request: StoreMemoryRequest,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Store a new memory.

    Automatically generates embedding for semantic search.
    """
    state = get_app_state()

    # Validate memory type
    try:
        memory_type = MemoryType(request.memory_type)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid memory_type. Must be one of: {[t.value for t in MemoryType]}"
        )

    try:
        memory_id = await state.memory_service.store(
            org_id=current_user.org_id,
            memory_type=memory_type,
            content=request.content,
            metadata=request.metadata,
            quality_score=request.quality_score
        )

        return {"memory_id": str(memory_id)}

    except Exception as e:
        # Log internal error but don't expose to client
        import logging
        logging.error(f"Failed to store memory: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to store memory"
        )


@router.post("/search", response_model=list[MemoryResponse])
async def search_memories(
    request: SearchMemoryRequest,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Search memories using semantic similarity.
    """
    state = get_app_state()

    # Parse memory types
    memory_types = None
    if request.memory_types:
        try:
            memory_types = [MemoryType(t) for t in request.memory_types]
        except ValueError as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid memory type: {e}"
            )

    try:
        memories = await state.memory_service.search(
            org_id=current_user.org_id,
            query=request.query,
            memory_types=memory_types,
            filters=request.filters,
            limit=request.limit,
            min_similarity=request.min_similarity
        )

        return [
            MemoryResponse(
                id=str(m.id),
                memory_type=m.memory_type.value,
                content=m.content,
                quality_score=m.quality_score,
                usage_count=m.usage_count,
                metadata=m.metadata,
                created_at=str(m.created_at),
                similarity=m.similarity
            )
            for m in memories
        ]

    except Exception as e:
        import logging
        logging.error(f"Failed to search memories: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to search memories"
        )


@router.post("/context", response_model=ContextResponse)
async def build_agent_context(
    request: ContextRequest,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Build enhanced context for an agent using semantic memory.

    Used by UWS scripts to get memory-enhanced prompts.
    """
    state = get_app_state()

    try:
        # Get base persona (placeholder - would load from registry)
        base_persona = f"You are a {request.agent_type} agent."

        context_builder = AgentContextBuilder(state.memory_service)
        enhanced_context = await context_builder.build_context(
            org_id=current_user.org_id,
            agent_type=request.agent_type,
            task_description=request.task,
            base_persona=base_persona
        )

        # Count sections used (rough estimate)
        sections = enhanced_context.split("---")
        memories_used = len(sections) - 1  # Subtract base persona

        return ContextResponse(
            enhanced_context=enhanced_context,
            memories_used=max(0, memories_used)
        )

    except Exception as e:
        import logging
        logging.error(f"Failed to build context: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build context"
        )


@router.get("/similar-tasks", response_model=list[MemoryResponse])
async def find_similar_tasks(
    task_description: str = Query(..., description="Task to find similar to"),
    agent_type: Optional[str] = Query(None, description="Filter by agent type"),
    outcome: Optional[str] = Query(None, description="Filter by outcome (success/failure)"),
    limit: int = Query(5, le=20),
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Find similar past tasks.

    Useful for learning from past experiences.
    """
    state = get_app_state()

    try:
        memories = await state.memory_service.search_similar_tasks(
            org_id=current_user.org_id,
            task_description=task_description,
            agent_type=agent_type,
            outcome_filter=outcome,
            limit=limit
        )

        return [
            MemoryResponse(
                id=str(m.id),
                memory_type=m.memory_type.value,
                content=m.content,
                quality_score=m.quality_score,
                usage_count=m.usage_count,
                metadata=m.metadata,
                created_at=str(m.created_at),
                similarity=m.similarity
            )
            for m in memories
        ]

    except Exception as e:
        import logging
        logging.error(f"Failed to find similar tasks: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to find similar tasks"
        )


@router.get("/decisions", response_model=list[MemoryResponse])
async def find_decisions(
    topic: str = Query(..., description="Topic to search decisions for"),
    limit: int = Query(5, le=20),
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Find relevant past decisions.

    Useful for maintaining consistency.
    """
    state = get_app_state()

    try:
        memories = await state.memory_service.search_decisions(
            org_id=current_user.org_id,
            topic=topic,
            limit=limit
        )

        return [
            MemoryResponse(
                id=str(m.id),
                memory_type=m.memory_type.value,
                content=m.content,
                quality_score=m.quality_score,
                usage_count=m.usage_count,
                metadata=m.metadata,
                created_at=str(m.created_at),
                similarity=m.similarity
            )
            for m in memories
        ]

    except Exception as e:
        import logging
        logging.error(f"Failed to find decisions: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to find decisions"
        )


@router.get("/code-patterns", response_model=list[MemoryResponse])
async def find_code_patterns(
    description: str = Query(..., description="What kind of code pattern"),
    language: Optional[str] = Query(None, description="Programming language"),
    limit: int = Query(5, le=20),
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Find relevant code patterns.

    Useful for consistent implementations.
    """
    state = get_app_state()

    try:
        memories = await state.memory_service.search_code_patterns(
            org_id=current_user.org_id,
            description=description,
            language=language,
            limit=limit
        )

        return [
            MemoryResponse(
                id=str(m.id),
                memory_type=m.memory_type.value,
                content=m.content,
                quality_score=m.quality_score,
                usage_count=m.usage_count,
                metadata=m.metadata,
                created_at=str(m.created_at),
                similarity=m.similarity
            )
            for m in memories
        ]

    except Exception as e:
        import logging
        logging.error(f"Failed to find code patterns: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to find code patterns"
        )


@router.get("/errors", response_model=list[MemoryResponse])
async def find_errors(
    context: str = Query(..., description="Error context to search"),
    limit: int = Query(5, le=20),
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Find similar past errors and their resolutions.

    Useful for avoiding known issues.
    """
    state = get_app_state()

    try:
        memories = await state.memory_service.search_errors(
            org_id=current_user.org_id,
            error_context=context,
            limit=limit
        )

        return [
            MemoryResponse(
                id=str(m.id),
                memory_type=m.memory_type.value,
                content=m.content,
                quality_score=m.quality_score,
                usage_count=m.usage_count,
                metadata=m.metadata,
                created_at=str(m.created_at),
                similarity=m.similarity
            )
            for m in memories
        ]

    except Exception as e:
        import logging
        logging.error(f"Failed to find errors: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to find errors"
        )


def parse_uuid(value: str, field_name: str = "id") -> UUID:
    """Parse and validate UUID, raising HTTPException on failure."""
    try:
        return UUID(value)
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{field_name} must be a valid UUID"
        )


@router.put("/{memory_id}/quality")
async def update_memory_quality(
    memory_id: str,
    quality_score: float = Query(..., ge=0, le=1),
    feedback: Optional[str] = None,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Update memory quality score (human feedback).
    """
    state = get_app_state()

    # Validate UUID format
    memory_uuid = parse_uuid(memory_id, "memory_id")

    try:
        await state.memory_service.update_quality(
            memory_id=memory_uuid,
            quality_score=quality_score,
            feedback=feedback
        )

        return {"message": "Quality updated", "quality_score": quality_score}

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update quality"
        )


@router.post("/consolidate")
async def consolidate_memories(
    memory_type: str = Query(..., description="Memory type to consolidate"),
    similarity_threshold: float = Query(0.95, ge=0.8, le=1.0),
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Consolidate similar memories.

    Merges memories above similarity threshold, keeping highest quality.
    """
    state = get_app_state()

    try:
        mt = MemoryType(memory_type)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid memory_type"
        )

    try:
        merged_count = await state.memory_service.consolidate(
            org_id=current_user.org_id,
            memory_type=mt,
            similarity_threshold=similarity_threshold
        )

        return {"merged_count": merged_count}

    except Exception as e:
        import logging
        logging.error(f"Failed to consolidate: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to consolidate memories"
        )


@router.post("/prune")
async def prune_old_memories(
    memory_type: str = Query(..., description="Memory type to prune"),
    max_age_days: int = Query(90, ge=7, le=365),
    keep_high_quality: bool = Query(True),
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Prune old, low-value memories.
    """
    state = get_app_state()

    try:
        mt = MemoryType(memory_type)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid memory_type"
        )

    try:
        deleted_count = await state.memory_service.prune_old(
            org_id=current_user.org_id,
            memory_type=mt,
            max_age_days=max_age_days,
            keep_high_quality=keep_high_quality
        )

        return {"deleted_count": deleted_count}

    except Exception as e:
        import logging
        logging.error(f"Failed to prune: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to prune memories"
        )
