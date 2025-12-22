"""
Pytest Configuration and Fixtures for Company OS.

Provides shared fixtures for unit, integration, and system tests.
"""

import asyncio
import os
from typing import AsyncGenerator, Generator
from uuid import uuid4

import pytest
import pytest_asyncio
import asyncpg
from unittest.mock import AsyncMock, MagicMock, patch

# Set test environment
os.environ.setdefault("ENVIRONMENT", "testing")
os.environ.setdefault("DATABASE_URL", "postgresql://test:test@localhost:5432/test_company_os")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-for-testing-only")
os.environ.setdefault("OPENAI_API_KEY", "test-key")


@pytest.fixture(scope="session")
def event_loop() -> Generator[asyncio.AbstractEventLoop, None, None]:
    """Create event loop for async tests."""
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def mock_pool() -> MagicMock:
    """Create a mock database pool."""
    pool = MagicMock(spec=asyncpg.Pool)

    # Mock acquire context manager
    mock_conn = AsyncMock()
    mock_conn.fetchval = AsyncMock(return_value=None)
    mock_conn.fetchrow = AsyncMock(return_value=None)
    mock_conn.fetch = AsyncMock(return_value=[])
    mock_conn.execute = AsyncMock(return_value="DELETE 0")

    # Mock transaction context manager - critical for event store tests
    mock_conn.transaction = MagicMock(return_value=AsyncContextManager(None))

    pool.acquire = MagicMock(return_value=AsyncContextManager(mock_conn))

    return pool


class AsyncContextManager:
    """Helper for mocking async context managers."""
    def __init__(self, obj):
        self.obj = obj

    async def __aenter__(self):
        return self.obj

    async def __aexit__(self, *args):
        pass


@pytest.fixture
def mock_settings():
    """Create mock settings for testing."""
    from company_os.core.config.settings import Settings

    return Settings(
        database_url="postgresql://test:test@localhost:5432/test",
        jwt_secret_key="test-secret-key",
        access_token_expire_minutes=15,
        refresh_token_expire_days=7,
        uws_root="/tmp/test_uws"
    )


@pytest.fixture
def sample_user_id() -> str:
    """Generate a sample user ID."""
    return str(uuid4())


@pytest.fixture
def sample_org_id() -> str:
    """Generate a sample organization ID."""
    return str(uuid4())


@pytest.fixture
def sample_task_data(sample_org_id: str, sample_user_id: str) -> dict:
    """Generate sample task data."""
    return {
        "id": str(uuid4()),
        "org_id": sample_org_id,
        "title": "Test Task",
        "description": "A test task for testing",
        "priority": "medium",
        "created_by": sample_user_id,
        "tags": ["test", "automated"]
    }


@pytest.fixture
def sample_event_data(sample_task_data: dict) -> dict:
    """Generate sample event data."""
    return {
        "stream_id": f"task-{sample_task_data['id']}",
        "event_type": "TaskCreated",
        "event_data": sample_task_data
    }


# Markers for test categories
def pytest_configure(config):
    """Configure custom markers."""
    config.addinivalue_line("markers", "unit: Unit tests")
    config.addinivalue_line("markers", "integration: Integration tests")
    config.addinivalue_line("markers", "system: System/E2E tests")
    config.addinivalue_line("markers", "slow: Slow running tests")
