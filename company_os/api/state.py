"""
Application State Module.

Separates app state from main to avoid circular imports.
"""

import asyncpg

from ..core.events.store import EventStore, EventPublisher
from ..core.events.projections import ProjectionManager
from ..core.auth.service import AuthService
from ..core.memory.service import SemanticMemoryService
from ..integrations.uws.adapter import UWSAdapter


class AppState:
    """Application-wide shared state."""
    pool: asyncpg.Pool
    event_store: EventStore
    event_publisher: EventPublisher
    projection_manager: ProjectionManager
    auth_service: AuthService
    memory_service: SemanticMemoryService
    uws_adapter: UWSAdapter


# Singleton app state
app_state = AppState()


def get_app_state() -> AppState:
    """Get application state for dependency injection."""
    return app_state
