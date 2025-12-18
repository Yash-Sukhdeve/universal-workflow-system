"""
API Routes Package.

All route modules are imported here for registration in main.py.
"""

from . import auth, tasks, agents, memory, health

__all__ = ["auth", "tasks", "agents", "memory", "health"]
