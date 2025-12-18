"""
Task Management Routes.

CRUD operations for tasks with event sourcing.
"""

from typing import Optional
from uuid import UUID, uuid4
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel, Field

from ..state import get_app_state
from ..security import get_current_user_context, CurrentUser
from ...core.events.store import NewEvent
from ...core.auth.models import Permission


router = APIRouter()


def parse_uuid(value: str, field_name: str = "id") -> UUID:
    """Parse and validate UUID, raising HTTPException on failure."""
    try:
        return UUID(value)
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{field_name} must be a valid UUID"
        )


# Request/Response Models

class CreateTaskRequest(BaseModel):
    """Create task request."""
    title: str
    description: Optional[str] = None
    priority: str = "medium"  # low, medium, high, critical
    project_id: Optional[str] = None
    due_date: Optional[datetime] = None
    tags: list[str] = Field(default_factory=list)  # Avoid mutable default


class UpdateTaskRequest(BaseModel):
    """Update task request."""
    title: Optional[str] = None
    description: Optional[str] = None
    priority: Optional[str] = None
    due_date: Optional[datetime] = None
    tags: Optional[list[str]] = None


class AssignTaskRequest(BaseModel):
    """Assign task to agent or user."""
    agent_type: Optional[str] = None
    user_id: Optional[str] = None


class TaskResponse(BaseModel):
    """Task response."""
    id: str
    title: str
    description: Optional[str]
    status: str
    priority: str
    project_id: Optional[str]
    assigned_agent: Optional[str]
    assigned_user_id: Optional[str]
    created_by: str
    created_at: datetime
    updated_at: datetime
    due_date: Optional[datetime]
    tags: list[str]


# Routes

@router.post("", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    request: CreateTaskRequest,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Create a new task.

    Stores TaskCreated event and updates read model.
    """
    state = get_app_state()

    # Validate priority
    if request.priority not in ["low", "medium", "high", "critical"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid priority. Must be: low, medium, high, critical"
        )

    task_id = uuid4()
    stream_id = f"task-{task_id}"

    # Create event
    event_data = {
        "id": str(task_id),
        "org_id": str(current_user.org_id),
        "title": request.title,
        "description": request.description,
        "priority": request.priority,
        "project_id": request.project_id,
        "due_date": request.due_date.isoformat() if request.due_date else None,
        "tags": request.tags,
        "created_by": str(current_user.user_id)
    }

    event = NewEvent(
        event_type="TaskCreated",
        event_data=event_data,
        metadata={"user_id": str(current_user.user_id)}
    )

    # Append to event store
    events = await state.event_store.append(
        stream_id=stream_id,
        events=[event],
        org_id=current_user.org_id
    )

    # Apply to projections
    for e in events:
        await state.projection_manager.apply_event(e)

    return TaskResponse(
        id=str(task_id),
        title=request.title,
        description=request.description,
        status="pending",
        priority=request.priority,
        project_id=request.project_id,
        assigned_agent=None,
        assigned_user_id=None,
        created_by=str(current_user.user_id),
        created_at=events[0].created_at,
        updated_at=events[0].created_at,
        due_date=request.due_date,
        tags=request.tags
    )


@router.get("", response_model=list[TaskResponse])
async def list_tasks(
    status: Optional[str] = Query(None, description="Filter by status"),
    priority: Optional[str] = Query(None, description="Filter by priority"),
    assigned_agent: Optional[str] = Query(None, description="Filter by assigned agent"),
    limit: int = Query(50, le=100, description="Maximum results"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    List tasks for the current organization.
    """
    state = get_app_state()

    # Build query
    query = """
        SELECT id, title, description, status, priority, project_id,
               assigned_agent, assigned_user_id, created_by,
               created_at, updated_at, due_date, tags
        FROM tasks_read_model
        WHERE org_id = $1
    """
    params = [current_user.org_id]
    param_count = 2

    if status:
        query += f" AND status = ${param_count}"
        params.append(status)
        param_count += 1

    if priority:
        query += f" AND priority = ${param_count}"
        params.append(priority)
        param_count += 1

    if assigned_agent:
        query += f" AND assigned_agent = ${param_count}"
        params.append(assigned_agent)
        param_count += 1

    query += f" ORDER BY created_at DESC LIMIT ${param_count} OFFSET ${param_count + 1}"
    params.extend([limit, offset])

    async with state.pool.acquire() as conn:
        # Set org context for RLS using parameterized query to prevent injection
        await conn.execute(
            "SELECT set_config('app.current_org_id', $1, true)",
            str(current_user.org_id)
        )
        rows = await conn.fetch(query, *params)

    return [
        TaskResponse(
            id=str(row["id"]),
            title=row["title"],
            description=row["description"],
            status=row["status"],
            priority=row["priority"],
            project_id=str(row["project_id"]) if row["project_id"] else None,
            assigned_agent=row["assigned_agent"],
            assigned_user_id=str(row["assigned_user_id"]) if row["assigned_user_id"] else None,
            created_by=str(row["created_by"]),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            due_date=row["due_date"],
            tags=row["tags"] or []
        )
        for row in rows
    ]


@router.get("/{task_id}", response_model=TaskResponse)
async def get_task(
    task_id: str,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Get a specific task by ID.
    """
    state = get_app_state()

    # Validate UUID format
    task_uuid = parse_uuid(task_id, "task_id")

    async with state.pool.acquire() as conn:
        # Set org context for RLS using parameterized query
        await conn.execute(
            "SELECT set_config('app.current_org_id', $1, true)",
            str(current_user.org_id)
        )
        row = await conn.fetchrow(
            """
            SELECT id, title, description, status, priority, project_id,
                   assigned_agent, assigned_user_id, created_by,
                   created_at, updated_at, due_date, tags
            FROM tasks_read_model
            WHERE id = $1 AND org_id = $2
            """,
            task_uuid,
            current_user.org_id
        )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Task not found"
        )

    return TaskResponse(
        id=str(row["id"]),
        title=row["title"],
        description=row["description"],
        status=row["status"],
        priority=row["priority"],
        project_id=str(row["project_id"]) if row["project_id"] else None,
        assigned_agent=row["assigned_agent"],
        assigned_user_id=str(row["assigned_user_id"]) if row["assigned_user_id"] else None,
        created_by=str(row["created_by"]),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
        due_date=row["due_date"],
        tags=row["tags"] or []
    )


@router.put("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: str,
    request: UpdateTaskRequest,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Update a task.

    Stores TaskUpdated event.
    """
    state = get_app_state()
    stream_id = f"task-{task_id}"

    # Get current version
    current_version = await state.event_store.get_stream_version(stream_id)
    if current_version < 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Task not found"
        )

    # Build event data with only changed fields
    event_data = {"id": task_id}
    if request.title is not None:
        event_data["title"] = request.title
    if request.description is not None:
        event_data["description"] = request.description
    if request.priority is not None:
        event_data["priority"] = request.priority
    if request.due_date is not None:
        event_data["due_date"] = request.due_date.isoformat()
    if request.tags is not None:
        event_data["tags"] = request.tags

    event = NewEvent(
        event_type="TaskUpdated",
        event_data=event_data,
        metadata={"user_id": str(current_user.user_id)}
    )

    events = await state.event_store.append(
        stream_id=stream_id,
        events=[event],
        expected_version=current_version,
        org_id=current_user.org_id
    )

    for e in events:
        await state.projection_manager.apply_event(e)

    return await get_task(task_id, current_user)


@router.post("/{task_id}/assign", response_model=TaskResponse)
async def assign_task(
    task_id: str,
    request: AssignTaskRequest,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Assign a task to an agent or user.

    If assigning to an agent, activates the agent via UWS.
    """
    state = get_app_state()
    stream_id = f"task-{task_id}"

    # Validate assignment
    if not request.agent_type and not request.user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Must specify agent_type or user_id"
        )

    # Get current version
    current_version = await state.event_store.get_stream_version(stream_id)
    if current_version < 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Task not found"
        )

    # Get task info for agent activation
    task = await get_task(task_id, current_user)

    event_data = {
        "id": task_id,
        "agent_type": request.agent_type,
        "user_id": request.user_id
    }

    # If assigning to agent, activate via UWS
    if request.agent_type:
        try:
            session_id = await state.uws_adapter.activate_agent(
                agent_type=request.agent_type,
                task_description=task.title,
                org_id=str(current_user.org_id),
                task_id=task_id
            )
            event_data["session_id"] = session_id
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to activate agent: {e}"
            )

    event = NewEvent(
        event_type="TaskAssigned",
        event_data=event_data,
        metadata={"user_id": str(current_user.user_id)}
    )

    events = await state.event_store.append(
        stream_id=stream_id,
        events=[event],
        expected_version=current_version,
        org_id=current_user.org_id
    )

    for e in events:
        await state.projection_manager.apply_event(e)

    # Also update status to in_progress
    await _update_task_status(task_id, "in_progress", current_user)

    return await get_task(task_id, current_user)


@router.post("/{task_id}/complete")
async def complete_task(
    task_id: str,
    result: Optional[dict] = None,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Mark a task as completed.
    """
    return await _update_task_status(task_id, "completed", current_user, result)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(
    task_id: str,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Delete a task.
    """
    state = get_app_state()
    stream_id = f"task-{task_id}"

    current_version = await state.event_store.get_stream_version(stream_id)
    if current_version < 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Task not found"
        )

    event = NewEvent(
        event_type="TaskDeleted",
        event_data={"id": task_id},
        metadata={"user_id": str(current_user.user_id)}
    )

    events = await state.event_store.append(
        stream_id=stream_id,
        events=[event],
        expected_version=current_version,
        org_id=current_user.org_id
    )

    for e in events:
        await state.projection_manager.apply_event(e)


async def _update_task_status(
    task_id: str,
    new_status: str,
    current_user: CurrentUser,
    result: Optional[dict] = None
) -> TaskResponse:
    """Internal helper to update task status."""
    state = get_app_state()
    stream_id = f"task-{task_id}"

    current_version = await state.event_store.get_stream_version(stream_id)
    if current_version < 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Task not found"
        )

    event_type = "TaskCompleted" if new_status == "completed" else "TaskStatusChanged"
    event_data = {"id": task_id, "status": new_status}
    if result:
        event_data["result"] = result

    event = NewEvent(
        event_type=event_type,
        event_data=event_data,
        metadata={"user_id": str(current_user.user_id)}
    )

    events = await state.event_store.append(
        stream_id=stream_id,
        events=[event],
        expected_version=current_version,
        org_id=current_user.org_id
    )

    for e in events:
        await state.projection_manager.apply_event(e)

    return await get_task(task_id, current_user)
