"""
Pytest Configuration for Company OS Integration Tests.

Provides common fixtures and setup for integration tests.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock
from datetime import datetime, timezone

from company_os.api.state import app_state
from company_os.core.auth.service import AuthService
from company_os.core.memory.service import SemanticMemoryService, EmbeddingService
from company_os.core.events.store import EventStore, EventPublisher
from company_os.core.events.projections import ProjectionManager


class AsyncContextManager:
    """Helper for mocking async context managers."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


@pytest.fixture(scope="function", autouse=True)
def setup_app_state():
    """
    Setup minimal app_state before each test.

    This runs automatically before each test to ensure app_state
    has required attributes, preventing AttributeError during
    FastAPI app creation.
    """
    # Create mock pool
    mock_pool = MagicMock()
    mock_conn = AsyncMock()
    mock_conn.execute = AsyncMock(return_value="SET")
    mock_conn.fetch = AsyncMock(return_value=[])
    mock_conn.fetchrow = AsyncMock(return_value=None)
    mock_pool.acquire.return_value = AsyncContextManager(mock_conn)

    # Create mock settings
    mock_settings = MagicMock()
    mock_settings.jwt_secret_key = "test-secret-key-for-testing-only"
    mock_settings.jwt_algorithm = "HS256"
    mock_settings.access_token_expire_minutes = 15
    mock_settings.refresh_token_expire_days = 7
    mock_settings.embedding_provider = "openai"
    mock_settings.embedding_model = "text-embedding-3-small"
    mock_settings.openai_api_key = "test-key"
    mock_settings.uws_root = "/tmp/test_uws"

    # Setup app_state with all required attributes
    app_state.pool = mock_pool
    app_state.auth_service = AuthService(mock_pool, mock_settings)

    # Mock event store
    app_state.event_store = AsyncMock(spec=EventStore)
    app_state.event_store.append = AsyncMock(return_value=[])
    app_state.event_store.get_stream_version = AsyncMock(return_value=-1)

    app_state.event_publisher = AsyncMock(spec=EventPublisher)

    # Mock projection manager
    app_state.projection_manager = AsyncMock(spec=ProjectionManager)
    app_state.projection_manager.apply_event = AsyncMock()

    # Mock memory service
    mock_embedding_service = MagicMock(spec=EmbeddingService)
    mock_embedding_service.generate_embedding = AsyncMock(return_value=[0.1] * 1536)
    app_state.memory_service = SemanticMemoryService(mock_pool, mock_embedding_service)

    # Mock UWS adapter
    app_state.uws_adapter = AsyncMock()
    app_state.uws_adapter.activate_agent = AsyncMock(return_value="session-123")

    yield app_state

    # Cleanup (optional - pytest will recreate for next test)
    # Could reset app_state attributes here if needed
