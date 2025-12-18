"""
Agent Management Routes.

Control and monitor UWS agents via API.
"""

from typing import Optional
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel

from ..state import get_app_state
from ..security import get_current_user_context, CurrentUser


router = APIRouter()


# Request/Response Models

class AgentInfo(BaseModel):
    """Agent information."""
    type: str
    name: str
    description: str
    capabilities: list[str]
    icon: str


class SkillInfo(BaseModel):
    """Skill information."""
    name: str
    description: str
    category: str


class SessionResponse(BaseModel):
    """Agent session response."""
    id: str
    agent_type: str
    task: str
    status: str
    progress: int
    started_at: datetime
    updated_at: datetime
    metadata: dict


class ActivateAgentRequest(BaseModel):
    """Activate agent request."""
    agent_type: str
    task_description: str
    task_id: Optional[str] = None


class UpdateSessionRequest(BaseModel):
    """Update session request."""
    progress: Optional[int] = None
    status: Optional[str] = None
    task_update: Optional[str] = None


class WorkflowStatusResponse(BaseModel):
    """Workflow status response."""
    state: dict
    active_sessions: list[dict]
    enabled_skills: list[str]
    current_phase: Optional[str]
    current_checkpoint: Optional[str]


# Routes

@router.get("", response_model=list[AgentInfo])
async def list_agents(
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    List available agents from UWS registry.
    """
    state = get_app_state()

    try:
        agents = await state.uws_adapter.get_available_agents()
        return [
            AgentInfo(
                type=a.type,
                name=a.name,
                description=a.description,
                capabilities=a.capabilities,
                icon=a.icon
            )
            for a in agents
        ]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get agents: {e}"
        )


@router.post("/activate", response_model=SessionResponse)
async def activate_agent(
    request: ActivateAgentRequest,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Activate an agent for a task.

    Creates a new agent session via UWS.
    """
    state = get_app_state()

    try:
        session_id = await state.uws_adapter.activate_agent(
            agent_type=request.agent_type,
            task_description=request.task_description,
            org_id=str(current_user.org_id),
            task_id=request.task_id or ""
        )

        session = await state.uws_adapter.get_session(session_id)
        if not session:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Session created but not found"
            )

        return SessionResponse(
            id=session.id,
            agent_type=session.agent_type,
            task=session.task,
            status=session.status,
            progress=session.progress,
            started_at=session.started_at,
            updated_at=session.updated_at,
            metadata=session.metadata
        )

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to activate agent: {e}"
        )


@router.get("/sessions", response_model=list[SessionResponse])
async def list_sessions(
    status_filter: Optional[str] = Query(None, alias="status"),
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    List all agent sessions.
    """
    state = get_app_state()

    try:
        sessions = await state.uws_adapter.get_sessions()

        if status_filter:
            sessions = [s for s in sessions if s.status == status_filter]

        return [
            SessionResponse(
                id=s.id,
                agent_type=s.agent_type,
                task=s.task,
                status=s.status,
                progress=s.progress,
                started_at=s.started_at,
                updated_at=s.updated_at,
                metadata=s.metadata
            )
            for s in sessions
        ]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get sessions: {e}"
        )


@router.get("/sessions/{session_id}", response_model=SessionResponse)
async def get_session(
    session_id: str,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Get a specific agent session.
    """
    state = get_app_state()

    try:
        session = await state.uws_adapter.get_session(session_id)
        if not session:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Session not found"
            )

        return SessionResponse(
            id=session.id,
            agent_type=session.agent_type,
            task=session.task,
            status=session.status,
            progress=session.progress,
            started_at=session.started_at,
            updated_at=session.updated_at,
            metadata=session.metadata
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get session: {e}"
        )


@router.put("/sessions/{session_id}", response_model=SessionResponse)
async def update_session(
    session_id: str,
    request: UpdateSessionRequest,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Update an agent session's progress.
    """
    state = get_app_state()

    try:
        await state.uws_adapter.update_session_progress(
            session_id=session_id,
            progress=request.progress or 0,
            status=request.status or "active",
            task_update=request.task_update
        )

        return await get_session(session_id, current_user)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update session: {e}"
        )


@router.delete("/sessions/{session_id}")
async def end_session(
    session_id: str,
    result: str = "success",
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    End an agent session.
    """
    state = get_app_state()

    try:
        await state.uws_adapter.end_session(session_id, result)
        return {"message": "Session ended", "result": result}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to end session: {e}"
        )


# Skills Routes

@router.get("/skills", response_model=list[SkillInfo])
async def list_skills(
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    List available skills from UWS catalog.
    """
    state = get_app_state()

    try:
        skills = await state.uws_adapter.get_available_skills()
        return [
            SkillInfo(
                name=s.name,
                description=s.description,
                category=s.category
            )
            for s in skills
        ]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get skills: {e}"
        )


@router.get("/skills/enabled", response_model=list[str])
async def list_enabled_skills(
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    List currently enabled skills.
    """
    state = get_app_state()

    try:
        return await state.uws_adapter.get_enabled_skills()
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get enabled skills: {e}"
        )


@router.post("/skills/{skill_name}/enable")
async def enable_skill(
    skill_name: str,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Enable a skill.
    """
    state = get_app_state()

    try:
        await state.uws_adapter.enable_skill(skill_name)
        return {"message": f"Skill '{skill_name}' enabled"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to enable skill: {e}"
        )


@router.post("/skills/{skill_name}/disable")
async def disable_skill(
    skill_name: str,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Disable a skill.
    """
    state = get_app_state()

    try:
        await state.uws_adapter.disable_skill(skill_name)
        return {"message": f"Skill '{skill_name}' disabled"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to disable skill: {e}"
        )


# Workflow Routes

@router.get("/workflow/status", response_model=WorkflowStatusResponse)
async def get_workflow_status(
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Get comprehensive workflow status.
    """
    state = get_app_state()

    try:
        status = await state.uws_adapter.get_status()
        return WorkflowStatusResponse(
            state=status.get("state", {}),
            active_sessions=status.get("active_sessions", []),
            enabled_skills=status.get("enabled_skills", []),
            current_phase=status.get("current_phase"),
            current_checkpoint=status.get("current_checkpoint")
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get workflow status: {e}"
        )


@router.post("/workflow/checkpoint")
async def create_checkpoint(
    message: str,
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Create a workflow checkpoint.
    """
    state = get_app_state()

    try:
        checkpoint_id = await state.uws_adapter.create_checkpoint(message)
        return {"checkpoint_id": checkpoint_id, "message": message}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create checkpoint: {e}"
        )


@router.get("/workflow/checkpoints")
async def list_checkpoints(
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    List all workflow checkpoints.
    """
    state = get_app_state()

    try:
        return await state.uws_adapter.list_checkpoints()
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list checkpoints: {e}"
        )


@router.post("/workflow/recover")
async def recover_context(
    current_user: CurrentUser = Depends(get_current_user_context)
):
    """
    Recover context after session break.
    """
    state = get_app_state()

    try:
        result = await state.uws_adapter.recover_context()
        return result
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to recover context: {e}"
        )
