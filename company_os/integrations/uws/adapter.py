"""
UWS Integration Adapter.

Bridges Company OS API with UWS workflow system scripts.
"""

import subprocess
import json
import asyncio
import re
import shlex
from pathlib import Path
from typing import Any, Optional
from dataclasses import dataclass
from datetime import datetime

import yaml


# Input validation patterns
SAFE_ARG_PATTERN = re.compile(r'^[a-zA-Z0-9_\-\.\s:/@]+$')
MAX_ARG_LENGTH = 1000


def validate_shell_arg(arg: str, arg_name: str = "argument") -> str:
    """
    Validate and sanitize shell command arguments to prevent injection.

    Args:
        arg: The argument to validate
        arg_name: Name of the argument for error messages

    Returns:
        Sanitized argument string

    Raises:
        ValueError: If argument contains dangerous characters
    """
    if not arg:
        return ""

    if len(arg) > MAX_ARG_LENGTH:
        raise ValueError(f"{arg_name} exceeds maximum length of {MAX_ARG_LENGTH}")

    # Check for shell metacharacters that could enable injection
    dangerous_chars = ['$', '`', '|', '&', ';', '>', '<', '(', ')', '{', '}', '[', ']', '!', '\\', '\n', '\r']
    for char in dangerous_chars:
        if char in arg:
            raise ValueError(f"{arg_name} contains invalid character: {repr(char)}")

    return arg


@dataclass
class AgentInfo:
    """Agent information from registry."""
    type: str
    name: str
    description: str
    capabilities: list[str]
    icon: str


@dataclass
class SkillInfo:
    """Skill information from catalog."""
    name: str
    description: str
    category: str


@dataclass
class SessionInfo:
    """Agent session information."""
    id: str
    agent_type: str
    task: str
    status: str
    progress: int
    started_at: datetime
    updated_at: datetime
    metadata: dict[str, Any]


class UWSAdapter:
    """
    Adapter to bridge Company OS API with UWS workflow system.

    Translates API calls into UWS shell commands and YAML file operations.
    """

    def __init__(self, uws_root: str):
        self.root = Path(uws_root)
        self.scripts_dir = self.root / "scripts"
        self.workflow_dir = self.root / ".workflow"

    def _run_script(
        self,
        script: str,
        args: list[str],
        timeout: int = 30
    ) -> subprocess.CompletedProcess:
        """Run a UWS script with arguments."""
        script_path = self.scripts_dir / script

        return subprocess.run(
            [str(script_path)] + args,
            capture_output=True,
            text=True,
            cwd=str(self.root),
            timeout=timeout
        )

    async def _run_script_async(
        self,
        script: str,
        args: list[str],
        timeout: int = 30
    ) -> subprocess.CompletedProcess:
        """Run a UWS script asynchronously."""
        return await asyncio.to_thread(
            self._run_script, script, args, timeout
        )

    # Agent Management

    async def get_available_agents(self) -> list[AgentInfo]:
        """Get list of available agents from registry."""
        registry_path = self.workflow_dir / "agents" / "registry.yaml"

        if not registry_path.exists():
            return []

        with open(registry_path) as f:
            registry = yaml.safe_load(f)

        agents = []
        for agent_type, config in registry.get("agents", {}).items():
            agents.append(AgentInfo(
                type=agent_type,
                name=config.get("name", agent_type),
                description=config.get("description", ""),
                capabilities=config.get("capabilities", []),
                icon=config.get("icon", "")
            ))

        return agents

    async def activate_agent(
        self,
        agent_type: str,
        task_description: str,
        org_id: str,
        task_id: str
    ) -> str:
        """
        Activate a UWS agent for a task.

        Args:
            agent_type: Type of agent (researcher, architect, etc.)
            task_description: Description of task to perform
            org_id: Organization ID
            task_id: Task ID for tracking

        Returns:
            Session ID

        Raises:
            ValueError: If input validation fails
            RuntimeError: If agent activation fails
        """
        # Validate all inputs to prevent command injection
        safe_agent_type = validate_shell_arg(agent_type, "agent_type")
        safe_task = validate_shell_arg(task_description, "task_description")
        safe_org_id = validate_shell_arg(org_id, "org_id")
        safe_task_id = validate_shell_arg(task_id, "task_id")

        # Create session using session_manager
        result = await self._run_script_async(
            "lib/session_manager.sh",
            ["create", safe_agent_type, safe_task]
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to create session: {result.stderr}")

        session_id = result.stdout.strip()

        # Update session with org/task context
        await self._update_session_metadata(
            session_id,
            {"org_id": safe_org_id, "task_id": safe_task_id}
        )

        # Activate agent via UWS
        result = await self._run_script_async(
            "activate_agent.sh",
            [safe_agent_type, "activate"]
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to activate agent: {result.stderr}")

        return session_id

    async def deactivate_agent(self, agent_type: str) -> None:
        """Deactivate an agent."""
        result = await self._run_script_async(
            "activate_agent.sh",
            [agent_type, "deactivate"]
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to deactivate agent: {result.stderr}")

    async def get_active_agent(self) -> Optional[str]:
        """Get currently active agent type."""
        state_path = self.workflow_dir / "state.yaml"

        if not state_path.exists():
            return None

        with open(state_path) as f:
            state = yaml.safe_load(f)

        return state.get("active_agent")

    # Session Management

    async def get_sessions(self) -> list[SessionInfo]:
        """Get all agent sessions."""
        result = await self._run_script_async(
            "lib/session_manager.sh",
            ["list", "json"]
        )

        if result.returncode != 0:
            return []

        try:
            sessions_data = json.loads(result.stdout)
        except json.JSONDecodeError:
            return []

        sessions = []
        for s in sessions_data:
            sessions.append(SessionInfo(
                id=s.get("id", ""),
                agent_type=s.get("agent_type", ""),
                task=s.get("task", ""),
                status=s.get("status", "unknown"),
                progress=s.get("progress", 0),
                started_at=datetime.fromisoformat(s["started_at"]) if s.get("started_at") else datetime.now(),
                updated_at=datetime.fromisoformat(s["updated_at"]) if s.get("updated_at") else datetime.now(),
                metadata=s.get("metadata", {})
            ))

        return sessions

    async def get_session(self, session_id: str) -> Optional[SessionInfo]:
        """Get a specific session."""
        sessions = await self.get_sessions()
        for session in sessions:
            if session.id == session_id:
                return session
        return None

    async def update_session_progress(
        self,
        session_id: str,
        progress: int,
        status: str = "active",
        task_update: Optional[str] = None
    ) -> None:
        """Update agent session progress."""
        args = ["update", session_id, str(progress), status]
        if task_update:
            args.append(task_update)

        result = await self._run_script_async(
            "lib/session_manager.sh",
            args
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to update session: {result.stderr}")

    async def end_session(
        self,
        session_id: str,
        result: str = "success"
    ) -> None:
        """End an agent session."""
        cmd_result = await self._run_script_async(
            "lib/session_manager.sh",
            ["end", session_id, result]
        )

        if cmd_result.returncode != 0:
            raise RuntimeError(f"Failed to end session: {cmd_result.stderr}")

    async def _update_session_metadata(
        self,
        session_id: str,
        metadata: dict[str, Any]
    ) -> None:
        """Update session metadata in sessions.yaml."""
        sessions_path = self.workflow_dir / "agents" / "sessions.yaml"

        if not sessions_path.exists():
            return

        with open(sessions_path) as f:
            sessions = yaml.safe_load(f) or {"sessions": []}

        for session in sessions.get("sessions", []):
            if session.get("id") == session_id:
                if "metadata" not in session:
                    session["metadata"] = {}
                session["metadata"].update(metadata)
                break

        with open(sessions_path, "w") as f:
            yaml.dump(sessions, f, default_flow_style=False)

    # Skills Management

    async def get_available_skills(self) -> list[SkillInfo]:
        """Get list of available skills from catalog."""
        catalog_path = self.workflow_dir / "skills" / "catalog.yaml"

        if not catalog_path.exists():
            return []

        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)

        skills = []
        for skill_name, config in catalog.get("skills", {}).items():
            skills.append(SkillInfo(
                name=skill_name,
                description=config.get("description", ""),
                category=config.get("category", "general")
            ))

        return skills

    async def enable_skill(self, skill_name: str) -> None:
        """Enable a skill."""
        result = await self._run_script_async(
            "enable_skill.sh",
            [skill_name, "enable"]
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to enable skill: {result.stderr}")

    async def disable_skill(self, skill_name: str) -> None:
        """Disable a skill."""
        result = await self._run_script_async(
            "enable_skill.sh",
            [skill_name, "disable"]
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to disable skill: {result.stderr}")

    async def get_enabled_skills(self) -> list[str]:
        """Get list of currently enabled skills."""
        state_path = self.workflow_dir / "state.yaml"

        if not state_path.exists():
            return []

        with open(state_path) as f:
            state = yaml.safe_load(f)

        return state.get("enabled_skills", [])

    # Checkpoint Management

    async def create_checkpoint(self, message: str) -> str:
        """Create a workflow checkpoint."""
        safe_message = validate_shell_arg(message, "checkpoint_message")

        result = await self._run_script_async(
            "checkpoint.sh",
            ["create", safe_message]
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to create checkpoint: {result.stderr}")

        # Parse checkpoint ID from output
        for line in result.stdout.split("\n"):
            if "CP_" in line:
                # Extract CP_X_XXX pattern
                import re
                match = re.search(r"CP_\d+_\d+", line)
                if match:
                    return match.group()

        return result.stdout.strip()

    async def list_checkpoints(self) -> list[dict]:
        """List all checkpoints."""
        result = await self._run_script_async(
            "checkpoint.sh",
            ["list"]
        )

        if result.returncode != 0:
            return []

        checkpoints = []
        for line in result.stdout.split("\n"):
            if "|" in line and "CP_" in line:
                parts = line.split("|")
                if len(parts) >= 3:
                    checkpoints.append({
                        "timestamp": parts[0].strip(),
                        "id": parts[1].strip(),
                        "message": parts[2].strip()
                    })

        return checkpoints

    async def restore_checkpoint(self, checkpoint_id: str) -> None:
        """Restore a checkpoint."""
        result = await self._run_script_async(
            "checkpoint.sh",
            ["restore", checkpoint_id]
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to restore checkpoint: {result.stderr}")

    # Workflow State

    async def get_workflow_state(self) -> dict[str, Any]:
        """Get current workflow state."""
        state_path = self.workflow_dir / "state.yaml"

        if not state_path.exists():
            return {}

        with open(state_path) as f:
            return yaml.safe_load(f) or {}

    async def get_handoff_notes(self) -> str:
        """Get current handoff notes."""
        handoff_path = self.workflow_dir / "handoff.md"

        if not handoff_path.exists():
            return ""

        with open(handoff_path) as f:
            return f.read()

    async def update_handoff_notes(self, content: str) -> None:
        """Update handoff notes."""
        handoff_path = self.workflow_dir / "handoff.md"

        with open(handoff_path, "w") as f:
            f.write(content)

    # Context Recovery

    async def recover_context(self) -> dict[str, Any]:
        """
        Recover context after session break.

        Returns recovery summary.
        """
        result = await self._run_script_async(
            "recover_context.sh",
            []
        )

        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "errors": result.stderr,
            "state": await self.get_workflow_state(),
            "handoff": await self.get_handoff_notes()
        }

    # Status

    async def get_status(self) -> dict[str, Any]:
        """Get comprehensive workflow status."""
        result = await self._run_script_async(
            "status.sh",
            []
        )

        state = await self.get_workflow_state()
        sessions = await self.get_sessions()
        skills = await self.get_enabled_skills()

        return {
            "state": state,
            "active_sessions": [
                {
                    "id": s.id,
                    "agent": s.agent_type,
                    "progress": s.progress,
                    "status": s.status
                }
                for s in sessions if s.status == "active"
            ],
            "enabled_skills": skills,
            "current_phase": state.get("phase"),
            "current_checkpoint": state.get("checkpoint"),
            "status_output": result.stdout
        }
