"""
Unit tests for UWS Adapter.

Comprehensive tests for Company OS UWS integration adapter.
"""

import asyncio
import json
import subprocess
from datetime import datetime
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, Mock, mock_open, patch
from typing import Any

import pytest
import yaml

from company_os.integrations.uws.adapter import (
    AgentInfo,
    SessionInfo,
    SkillInfo,
    UWSAdapter,
)


@pytest.fixture
def uws_root(tmp_path: Path) -> Path:
    """Create temporary UWS root directory."""
    root = tmp_path / "uws"
    root.mkdir()
    (root / "scripts").mkdir()
    (root / ".workflow").mkdir()
    (root / ".workflow" / "agents").mkdir()
    (root / ".workflow" / "skills").mkdir()
    return root


@pytest.fixture
def adapter(uws_root: Path) -> UWSAdapter:
    """Create UWSAdapter instance."""
    return UWSAdapter(str(uws_root))


# Initialization Tests


def test_adapter_init_with_valid_path(uws_root: Path):
    """Test adapter initialization with valid UWS root path."""
    adapter = UWSAdapter(str(uws_root))

    assert adapter.root == uws_root
    assert adapter.scripts_dir == uws_root / "scripts"
    assert adapter.workflow_dir == uws_root / ".workflow"


def test_adapter_init_with_string_path(tmp_path: Path):
    """Test adapter initialization with string path."""
    root_str = str(tmp_path / "uws")
    adapter = UWSAdapter(root_str)

    assert adapter.root == Path(root_str)


# Script Execution Tests


@patch("subprocess.run")
def test_run_script_success(mock_run: Mock, adapter: UWSAdapter):
    """Test successful script execution."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=["test.sh"],
        returncode=0,
        stdout="success output",
        stderr=""
    )

    result = adapter._run_script("test.sh", ["arg1", "arg2"])

    assert result.returncode == 0
    assert result.stdout == "success output"
    mock_run.assert_called_once()

    # Verify script path and arguments
    call_args = mock_run.call_args[0][0]
    assert str(adapter.scripts_dir / "test.sh") in call_args
    assert "arg1" in call_args
    assert "arg2" in call_args


@patch("subprocess.run")
def test_run_script_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test script execution failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=["test.sh"],
        returncode=1,
        stdout="",
        stderr="error message"
    )

    result = adapter._run_script("test.sh", [])

    assert result.returncode == 1
    assert result.stderr == "error message"


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_run_script_async(mock_run: Mock, adapter: UWSAdapter):
    """Test asynchronous script execution."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=["test.sh"],
        returncode=0,
        stdout="async output",
        stderr=""
    )

    result = await adapter._run_script_async("test.sh", ["arg"])

    assert result.returncode == 0
    assert result.stdout == "async output"


# Agent Management Tests


@pytest.mark.asyncio
async def test_get_available_agents_success(adapter: UWSAdapter, uws_root: Path):
    """Test retrieving available agents from registry."""
    registry_data = {
        "agents": {
            "researcher": {
                "name": "Research Agent",
                "description": "Conducts research",
                "capabilities": ["research", "analysis"],
                "icon": "microscope"
            },
            "architect": {
                "name": "Architecture Agent",
                "description": "Designs systems",
                "capabilities": ["design", "architecture"],
                "icon": "blueprint"
            }
        }
    }

    registry_path = uws_root / ".workflow" / "agents" / "registry.yaml"
    with open(registry_path, "w") as f:
        yaml.dump(registry_data, f)

    agents = await adapter.get_available_agents()

    assert len(agents) == 2
    assert any(a.type == "researcher" for a in agents)
    assert any(a.type == "architect" for a in agents)

    researcher = next(a for a in agents if a.type == "researcher")
    assert researcher.name == "Research Agent"
    assert researcher.description == "Conducts research"
    assert researcher.capabilities == ["research", "analysis"]
    assert researcher.icon == "microscope"


@pytest.mark.asyncio
async def test_get_available_agents_missing_file(adapter: UWSAdapter):
    """Test retrieving agents when registry file doesn't exist."""
    agents = await adapter.get_available_agents()

    assert agents == []


@pytest.mark.asyncio
async def test_get_available_agents_empty_registry(adapter: UWSAdapter, uws_root: Path):
    """Test retrieving agents from empty registry."""
    registry_path = uws_root / ".workflow" / "agents" / "registry.yaml"
    with open(registry_path, "w") as f:
        yaml.dump({}, f)

    agents = await adapter.get_available_agents()

    assert agents == []


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_activate_agent_success(mock_run: Mock, adapter: UWSAdapter, uws_root: Path):
    """Test successful agent activation."""
    # Mock session creation
    session_id = "session-123"
    mock_run.side_effect = [
        subprocess.CompletedProcess(
            args=[], returncode=0, stdout=session_id, stderr=""
        ),
        subprocess.CompletedProcess(
            args=[], returncode=0, stdout="Agent activated", stderr=""
        )
    ]

    # Create sessions file for metadata update
    sessions_path = uws_root / ".workflow" / "agents" / "sessions.yaml"
    sessions_data = {
        "sessions": [
            {"id": session_id, "agent_type": "researcher", "metadata": {}}
        ]
    }
    with open(sessions_path, "w") as f:
        yaml.dump(sessions_data, f)

    result_id = await adapter.activate_agent(
        "researcher",
        "Test task",
        "org-123",
        "task-456"
    )

    assert result_id == session_id
    assert mock_run.call_count == 2

    # Verify metadata was updated
    with open(sessions_path) as f:
        updated_sessions = yaml.safe_load(f)

    session = updated_sessions["sessions"][0]
    assert session["metadata"]["org_id"] == "org-123"
    assert session["metadata"]["task_id"] == "task-456"


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_activate_agent_session_creation_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test agent activation failure during session creation."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Failed to create session"
    )

    with pytest.raises(RuntimeError, match="Failed to create session"):
        await adapter.activate_agent("researcher", "Test task", "org-123", "task-456")


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_activate_agent_activation_failure(mock_run: Mock, adapter: UWSAdapter, uws_root: Path):
    """Test agent activation failure during activation step."""
    session_id = "session-123"

    # Session creation succeeds, activation fails
    mock_run.side_effect = [
        subprocess.CompletedProcess(
            args=[], returncode=0, stdout=session_id, stderr=""
        ),
        subprocess.CompletedProcess(
            args=[], returncode=1, stdout="", stderr="Failed to activate"
        )
    ]

    # Create sessions file
    sessions_path = uws_root / ".workflow" / "agents" / "sessions.yaml"
    sessions_data = {"sessions": [{"id": session_id, "metadata": {}}]}
    with open(sessions_path, "w") as f:
        yaml.dump(sessions_data, f)

    with pytest.raises(RuntimeError, match="Failed to activate agent"):
        await adapter.activate_agent("researcher", "Test task", "org-123", "task-456")


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_deactivate_agent_success(mock_run: Mock, adapter: UWSAdapter):
    """Test successful agent deactivation."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Agent deactivated", stderr=""
    )

    await adapter.deactivate_agent("researcher")

    mock_run.assert_called_once()
    call_args = mock_run.call_args[0][0]
    assert "activate_agent.sh" in call_args[0]
    assert "researcher" in call_args
    assert "deactivate" in call_args


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_deactivate_agent_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test agent deactivation failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Failed to deactivate"
    )

    with pytest.raises(RuntimeError, match="Failed to deactivate agent"):
        await adapter.deactivate_agent("researcher")


@pytest.mark.asyncio
async def test_get_active_agent_success(adapter: UWSAdapter, uws_root: Path):
    """Test getting active agent from state."""
    state_data = {
        "active_agent": "researcher",
        "phase": "phase_2_implementation"
    }

    state_path = uws_root / ".workflow" / "state.yaml"
    with open(state_path, "w") as f:
        yaml.dump(state_data, f)

    active_agent = await adapter.get_active_agent()

    assert active_agent == "researcher"


@pytest.mark.asyncio
async def test_get_active_agent_no_state_file(adapter: UWSAdapter):
    """Test getting active agent when state file doesn't exist."""
    active_agent = await adapter.get_active_agent()

    assert active_agent is None


@pytest.mark.asyncio
async def test_get_active_agent_no_active_agent(adapter: UWSAdapter, uws_root: Path):
    """Test getting active agent when none is active."""
    state_path = uws_root / ".workflow" / "state.yaml"
    with open(state_path, "w") as f:
        yaml.dump({"phase": "phase_1_planning"}, f)

    active_agent = await adapter.get_active_agent()

    assert active_agent is None


# Session Management Tests


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_get_sessions_success(mock_run: Mock, adapter: UWSAdapter):
    """Test retrieving sessions list."""
    sessions_data = [
        {
            "id": "session-1",
            "agent_type": "researcher",
            "task": "Research task",
            "status": "active",
            "progress": 50,
            "started_at": "2025-12-17T10:00:00",
            "updated_at": "2025-12-17T10:30:00",
            "metadata": {"org_id": "org-123"}
        },
        {
            "id": "session-2",
            "agent_type": "architect",
            "task": "Design task",
            "status": "completed",
            "progress": 100,
            "started_at": "2025-12-17T09:00:00",
            "updated_at": "2025-12-17T09:45:00",
            "metadata": {}
        }
    ]

    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout=json.dumps(sessions_data), stderr=""
    )

    sessions = await adapter.get_sessions()

    assert len(sessions) == 2
    assert sessions[0].id == "session-1"
    assert sessions[0].agent_type == "researcher"
    assert sessions[0].task == "Research task"
    assert sessions[0].status == "active"
    assert sessions[0].progress == 50
    assert sessions[0].metadata == {"org_id": "org-123"}


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_get_sessions_script_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test retrieving sessions when script fails."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Error"
    )

    sessions = await adapter.get_sessions()

    assert sessions == []


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_get_sessions_invalid_json(mock_run: Mock, adapter: UWSAdapter):
    """Test retrieving sessions with invalid JSON response."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="invalid json", stderr=""
    )

    sessions = await adapter.get_sessions()

    assert sessions == []


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_get_sessions_missing_timestamps(mock_run: Mock, adapter: UWSAdapter):
    """Test retrieving sessions with missing timestamp fields."""
    sessions_data = [
        {
            "id": "session-1",
            "agent_type": "researcher",
            "task": "Research task",
            "status": "active",
            "progress": 50
            # Missing started_at and updated_at
        }
    ]

    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout=json.dumps(sessions_data), stderr=""
    )

    sessions = await adapter.get_sessions()

    assert len(sessions) == 1
    assert sessions[0].id == "session-1"
    # Should use default datetime.now()
    assert isinstance(sessions[0].started_at, datetime)
    assert isinstance(sessions[0].updated_at, datetime)


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_get_session_found(mock_run: Mock, adapter: UWSAdapter):
    """Test getting specific session by ID."""
    sessions_data = [
        {
            "id": "session-1",
            "agent_type": "researcher",
            "task": "Research task",
            "status": "active",
            "progress": 50,
            "started_at": "2025-12-17T10:00:00",
            "updated_at": "2025-12-17T10:30:00",
            "metadata": {}
        }
    ]

    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout=json.dumps(sessions_data), stderr=""
    )

    session = await adapter.get_session("session-1")

    assert session is not None
    assert session.id == "session-1"
    assert session.agent_type == "researcher"


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_get_session_not_found(mock_run: Mock, adapter: UWSAdapter):
    """Test getting non-existent session."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="[]", stderr=""
    )

    session = await adapter.get_session("nonexistent")

    assert session is None


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_update_session_progress_success(mock_run: Mock, adapter: UWSAdapter):
    """Test updating session progress."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Session updated", stderr=""
    )

    await adapter.update_session_progress("session-1", 75, "active")

    mock_run.assert_called_once()
    call_args = mock_run.call_args[0][0]
    assert "update" in call_args
    assert "session-1" in call_args
    assert "75" in call_args
    assert "active" in call_args


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_update_session_progress_with_task_update(mock_run: Mock, adapter: UWSAdapter):
    """Test updating session progress with task description update."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Session updated", stderr=""
    )

    await adapter.update_session_progress(
        "session-1", 75, "active", "Updated task description"
    )

    call_args = mock_run.call_args[0][0]
    assert "Updated task description" in call_args


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_update_session_progress_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test session progress update failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Update failed"
    )

    with pytest.raises(RuntimeError, match="Failed to update session"):
        await adapter.update_session_progress("session-1", 75, "active")


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_end_session_success(mock_run: Mock, adapter: UWSAdapter):
    """Test ending a session."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Session ended", stderr=""
    )

    await adapter.end_session("session-1", "success")

    call_args = mock_run.call_args[0][0]
    assert "end" in call_args
    assert "session-1" in call_args
    assert "success" in call_args


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_end_session_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test session end failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="End failed"
    )

    with pytest.raises(RuntimeError, match="Failed to end session"):
        await adapter.end_session("session-1", "success")


@pytest.mark.asyncio
async def test_update_session_metadata_success(adapter: UWSAdapter, uws_root: Path):
    """Test updating session metadata in sessions.yaml."""
    sessions_path = uws_root / ".workflow" / "agents" / "sessions.yaml"
    sessions_data = {
        "sessions": [
            {
                "id": "session-1",
                "agent_type": "researcher",
                "metadata": {"existing": "data"}
            }
        ]
    }

    with open(sessions_path, "w") as f:
        yaml.dump(sessions_data, f)

    await adapter._update_session_metadata(
        "session-1",
        {"org_id": "org-123", "task_id": "task-456"}
    )

    with open(sessions_path) as f:
        updated = yaml.safe_load(f)

    session = updated["sessions"][0]
    assert session["metadata"]["existing"] == "data"
    assert session["metadata"]["org_id"] == "org-123"
    assert session["metadata"]["task_id"] == "task-456"


@pytest.mark.asyncio
async def test_update_session_metadata_missing_file(adapter: UWSAdapter):
    """Test updating metadata when sessions file doesn't exist."""
    # Should not raise error, just return
    await adapter._update_session_metadata("session-1", {"key": "value"})


@pytest.mark.asyncio
async def test_update_session_metadata_session_not_found(adapter: UWSAdapter, uws_root: Path):
    """Test updating metadata for non-existent session."""
    sessions_path = uws_root / ".workflow" / "agents" / "sessions.yaml"
    sessions_data = {"sessions": [{"id": "other-session", "metadata": {}}]}

    with open(sessions_path, "w") as f:
        yaml.dump(sessions_data, f)

    await adapter._update_session_metadata("nonexistent", {"key": "value"})

    # Should not modify file
    with open(sessions_path) as f:
        unchanged = yaml.safe_load(f)

    assert len(unchanged["sessions"]) == 1
    assert unchanged["sessions"][0]["id"] == "other-session"


# Skills Management Tests


@pytest.mark.asyncio
async def test_get_available_skills_success(adapter: UWSAdapter, uws_root: Path):
    """Test retrieving available skills from catalog."""
    catalog_data = {
        "skills": {
            "code_review": {
                "description": "Review code quality",
                "category": "development"
            },
            "research": {
                "description": "Conduct research",
                "category": "analysis"
            }
        }
    }

    catalog_path = uws_root / ".workflow" / "skills" / "catalog.yaml"
    with open(catalog_path, "w") as f:
        yaml.dump(catalog_data, f)

    skills = await adapter.get_available_skills()

    assert len(skills) == 2
    assert any(s.name == "code_review" for s in skills)
    assert any(s.name == "research" for s in skills)

    code_review = next(s for s in skills if s.name == "code_review")
    assert code_review.description == "Review code quality"
    assert code_review.category == "development"


@pytest.mark.asyncio
async def test_get_available_skills_missing_file(adapter: UWSAdapter):
    """Test retrieving skills when catalog doesn't exist."""
    skills = await adapter.get_available_skills()

    assert skills == []


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_enable_skill_success(mock_run: Mock, adapter: UWSAdapter):
    """Test enabling a skill."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Skill enabled", stderr=""
    )

    await adapter.enable_skill("code_review")

    call_args = mock_run.call_args[0][0]
    assert "enable_skill.sh" in call_args[0]
    assert "code_review" in call_args
    assert "enable" in call_args


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_enable_skill_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test skill enable failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Enable failed"
    )

    with pytest.raises(RuntimeError, match="Failed to enable skill"):
        await adapter.enable_skill("code_review")


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_disable_skill_success(mock_run: Mock, adapter: UWSAdapter):
    """Test disabling a skill."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Skill disabled", stderr=""
    )

    await adapter.disable_skill("code_review")

    call_args = mock_run.call_args[0][0]
    assert "disable" in call_args


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_disable_skill_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test skill disable failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Disable failed"
    )

    with pytest.raises(RuntimeError, match="Failed to disable skill"):
        await adapter.disable_skill("code_review")


@pytest.mark.asyncio
async def test_get_enabled_skills_success(adapter: UWSAdapter, uws_root: Path):
    """Test getting enabled skills from state."""
    state_data = {
        "enabled_skills": ["code_review", "research", "testing"]
    }

    state_path = uws_root / ".workflow" / "state.yaml"
    with open(state_path, "w") as f:
        yaml.dump(state_data, f)

    skills = await adapter.get_enabled_skills()

    assert skills == ["code_review", "research", "testing"]


@pytest.mark.asyncio
async def test_get_enabled_skills_no_state_file(adapter: UWSAdapter):
    """Test getting enabled skills when state file doesn't exist."""
    skills = await adapter.get_enabled_skills()

    assert skills == []


# Checkpoint Management Tests


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_create_checkpoint_success(mock_run: Mock, adapter: UWSAdapter):
    """Test creating a checkpoint."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[],
        returncode=0,
        stdout="Created checkpoint CP_2_005\nCheckpoint created successfully",
        stderr=""
    )

    checkpoint_id = await adapter.create_checkpoint("Test checkpoint")

    assert checkpoint_id == "CP_2_005"
    call_args = mock_run.call_args[0][0]
    assert "checkpoint.sh" in call_args[0]
    assert "create" in call_args
    assert "Test checkpoint" in call_args


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_create_checkpoint_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test checkpoint creation failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Failed to create"
    )

    with pytest.raises(RuntimeError, match="Failed to create checkpoint"):
        await adapter.create_checkpoint("Test checkpoint")


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_create_checkpoint_no_id_in_output(mock_run: Mock, adapter: UWSAdapter):
    """Test checkpoint creation when ID not found in output."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Some output without checkpoint ID", stderr=""
    )

    checkpoint_id = await adapter.create_checkpoint("Test checkpoint")

    # Should return full output if no ID pattern found
    assert "Some output" in checkpoint_id


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_list_checkpoints_success(mock_run: Mock, adapter: UWSAdapter):
    """Test listing checkpoints."""
    output = """2025-12-17T10:00:00 | CP_2_001 | Initial checkpoint
2025-12-17T11:00:00 | CP_2_002 | Second checkpoint
2025-12-17T12:00:00 | CP_2_003 | Third checkpoint"""

    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout=output, stderr=""
    )

    checkpoints = await adapter.list_checkpoints()

    assert len(checkpoints) == 3
    assert checkpoints[0]["id"] == "CP_2_001"
    assert checkpoints[0]["message"] == "Initial checkpoint"
    assert checkpoints[1]["id"] == "CP_2_002"
    assert checkpoints[2]["id"] == "CP_2_003"


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_list_checkpoints_empty(mock_run: Mock, adapter: UWSAdapter):
    """Test listing checkpoints when none exist."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="No checkpoints found", stderr=""
    )

    checkpoints = await adapter.list_checkpoints()

    assert checkpoints == []


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_list_checkpoints_script_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test listing checkpoints when script fails."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Error"
    )

    checkpoints = await adapter.list_checkpoints()

    assert checkpoints == []


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_restore_checkpoint_success(mock_run: Mock, adapter: UWSAdapter):
    """Test restoring a checkpoint."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Checkpoint restored", stderr=""
    )

    await adapter.restore_checkpoint("CP_2_001")

    call_args = mock_run.call_args[0][0]
    assert "checkpoint.sh" in call_args[0]
    assert "restore" in call_args
    assert "CP_2_001" in call_args


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_restore_checkpoint_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test checkpoint restore failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Restore failed"
    )

    with pytest.raises(RuntimeError, match="Failed to restore checkpoint"):
        await adapter.restore_checkpoint("CP_2_001")


# Workflow State Tests


@pytest.mark.asyncio
async def test_get_workflow_state_success(adapter: UWSAdapter, uws_root: Path):
    """Test getting workflow state."""
    state_data = {
        "phase": "phase_2_implementation",
        "checkpoint": "CP_2_003",
        "active_agent": "researcher",
        "enabled_skills": ["code_review"],
        "health": {"score": 95}
    }

    state_path = uws_root / ".workflow" / "state.yaml"
    with open(state_path, "w") as f:
        yaml.dump(state_data, f)

    state = await adapter.get_workflow_state()

    assert state["phase"] == "phase_2_implementation"
    assert state["checkpoint"] == "CP_2_003"
    assert state["active_agent"] == "researcher"
    assert state["health"]["score"] == 95


@pytest.mark.asyncio
async def test_get_workflow_state_missing_file(adapter: UWSAdapter):
    """Test getting workflow state when file doesn't exist."""
    state = await adapter.get_workflow_state()

    assert state == {}


@pytest.mark.asyncio
async def test_get_handoff_notes_success(adapter: UWSAdapter, uws_root: Path):
    """Test getting handoff notes."""
    notes_content = """# Handoff Notes

## Current Status
Working on implementation

## Next Actions
- Complete tests
- Deploy to staging"""

    handoff_path = uws_root / ".workflow" / "handoff.md"
    with open(handoff_path, "w") as f:
        f.write(notes_content)

    notes = await adapter.get_handoff_notes()

    assert "Current Status" in notes
    assert "Complete tests" in notes


@pytest.mark.asyncio
async def test_get_handoff_notes_missing_file(adapter: UWSAdapter):
    """Test getting handoff notes when file doesn't exist."""
    notes = await adapter.get_handoff_notes()

    assert notes == ""


@pytest.mark.asyncio
async def test_update_handoff_notes_success(adapter: UWSAdapter, uws_root: Path):
    """Test updating handoff notes."""
    new_content = "# Updated Handoff Notes\n\nNew content here"

    await adapter.update_handoff_notes(new_content)

    handoff_path = uws_root / ".workflow" / "handoff.md"
    with open(handoff_path) as f:
        content = f.read()

    assert content == new_content


# Context Recovery Tests


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_recover_context_success(mock_run: Mock, adapter: UWSAdapter, uws_root: Path):
    """Test successful context recovery."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=0, stdout="Context recovered", stderr=""
    )

    # Create state and handoff files
    state_path = uws_root / ".workflow" / "state.yaml"
    with open(state_path, "w") as f:
        yaml.dump({"phase": "phase_2_implementation"}, f)

    handoff_path = uws_root / ".workflow" / "handoff.md"
    with open(handoff_path, "w") as f:
        f.write("Current work in progress")

    result = await adapter.recover_context()

    assert result["success"] is True
    assert result["output"] == "Context recovered"
    assert result["state"]["phase"] == "phase_2_implementation"
    assert "work in progress" in result["handoff"]


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_recover_context_failure(mock_run: Mock, adapter: UWSAdapter):
    """Test context recovery failure."""
    mock_run.return_value = subprocess.CompletedProcess(
        args=[], returncode=1, stdout="", stderr="Recovery failed"
    )

    result = await adapter.recover_context()

    assert result["success"] is False
    assert result["errors"] == "Recovery failed"


# Status Tests


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_get_status_comprehensive(mock_run: Mock, adapter: UWSAdapter, uws_root: Path):
    """Test getting comprehensive workflow status."""
    # Mock status.sh script
    mock_run.side_effect = [
        subprocess.CompletedProcess(
            args=[], returncode=0, stdout="Status output", stderr=""
        ),
        subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout=json.dumps([
                {
                    "id": "session-1",
                    "agent_type": "researcher",
                    "task": "Research",
                    "status": "active",
                    "progress": 60,
                    "started_at": "2025-12-17T10:00:00",
                    "updated_at": "2025-12-17T10:30:00",
                    "metadata": {}
                }
            ]),
            stderr=""
        )
    ]

    # Create state file
    state_data = {
        "phase": "phase_2_implementation",
        "checkpoint": "CP_2_003",
        "enabled_skills": ["code_review", "testing"]
    }
    state_path = uws_root / ".workflow" / "state.yaml"
    with open(state_path, "w") as f:
        yaml.dump(state_data, f)

    status = await adapter.get_status()

    assert status["state"]["phase"] == "phase_2_implementation"
    assert status["current_phase"] == "phase_2_implementation"
    assert status["current_checkpoint"] == "CP_2_003"
    assert len(status["active_sessions"]) == 1
    assert status["active_sessions"][0]["agent"] == "researcher"
    assert status["enabled_skills"] == ["code_review", "testing"]
    assert status["status_output"] == "Status output"


@pytest.mark.asyncio
@patch("subprocess.run")
async def test_get_status_no_active_sessions(mock_run: Mock, adapter: UWSAdapter, uws_root: Path):
    """Test getting status with no active sessions."""
    mock_run.side_effect = [
        subprocess.CompletedProcess(
            args=[], returncode=0, stdout="Status output", stderr=""
        ),
        subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout=json.dumps([
                {
                    "id": "session-1",
                    "agent_type": "researcher",
                    "task": "Research",
                    "status": "completed",
                    "progress": 100,
                    "started_at": "2025-12-17T10:00:00",
                    "updated_at": "2025-12-17T10:30:00",
                    "metadata": {}
                }
            ]),
            stderr=""
        )
    ]

    state_path = uws_root / ".workflow" / "state.yaml"
    with open(state_path, "w") as f:
        yaml.dump({}, f)

    status = await adapter.get_status()

    assert len(status["active_sessions"]) == 0
