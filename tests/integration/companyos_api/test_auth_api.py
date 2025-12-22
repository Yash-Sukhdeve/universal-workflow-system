"""
Integration Tests for Authentication API.

Tests the auth routes using FastAPI TestClient.
"""

import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

from fastapi.testclient import TestClient
from httpx import ASGITransport, AsyncClient

from company_os.api.main import create_app
from company_os.api.state import app_state
from company_os.core.auth.service import AuthService
from company_os.core.auth.models import User, Organization, TokenPair


class AsyncContextManagerMock:
    """Mock async context manager."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


class TestAuthAPI:
    """Tests for authentication API endpoints."""

    @pytest.fixture
    def fastapi_app(self):
        """Create FastAPI app for testing."""
        return create_app()

    @pytest.fixture
    def mock_app_state(self):
        """Create mock application state."""
        mock_pool = MagicMock()
        mock_conn = AsyncMock()
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        mock_settings = MagicMock()
        mock_settings.jwt_secret_key = "test-secret-key"
        mock_settings.jwt_algorithm = "HS256"
        mock_settings.access_token_expire_minutes = 15
        mock_settings.refresh_token_expire_days = 7

        app_state.pool = mock_pool
        app_state.auth_service = AuthService(mock_pool, mock_settings)
        return app_state

    @pytest.mark.asyncio
    async def test_register_success(self, fastapi_app, mock_app_state):
        """Test successful user registration."""
        user_id = uuid4()
        org_id = uuid4()
        now = datetime.now(timezone.utc)

        # Mock the auth_service.create_user method
        mock_user = User(
            id=user_id,
            email="newuser@example.com",
            name="New User",
            password_hash="hashed",
            is_active=True,
            is_verified=False,
            created_at=now,
            updated_at=now,
            last_login=None,
            avatar_url=None,
            preferences={}
        )
        mock_org = Organization(
            id=org_id,
            name="New User's Workspace",
            slug="new-user-workspace",
            plan="free",
            created_at=now,
            updated_at=now,
            settings={},
            limits={}
        )

        mock_tokens = TokenPair(
            access_token="mock.access.token",
            refresh_token="mock.refresh.token",
            token_type="bearer",
            expires_in=900
        )

        with patch.object(app_state.auth_service, 'create_user', new_callable=AsyncMock) as mock_create:
            with patch.object(app_state.auth_service, 'create_tokens', new_callable=AsyncMock) as mock_tokens_call:
                mock_create.return_value = (mock_user, mock_org)
                mock_tokens_call.return_value = mock_tokens

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/auth/register",
                        json={
                            "email": "newuser@example.com",
                            "name": "New User",
                            "password": "securepassword123"
                        }
                    )

                assert response.status_code == 200
                data = response.json()
                assert "access_token" in data
                assert "refresh_token" in data
                assert data["token_type"] == "bearer"

    @pytest.mark.asyncio
    async def test_register_duplicate_email(self, fastapi_app, mock_app_state):
        """Test registration with existing email."""
        with patch.object(app_state.auth_service, 'create_user', new_callable=AsyncMock) as mock_create:
            mock_create.side_effect = Exception("unique constraint violation")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/register",
                    json={
                        "email": "existing@example.com",
                        "name": "Existing User",
                        "password": "password123"
                    }
                )

            assert response.status_code == 400
            assert "already registered" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_login_success(self, fastapi_app, mock_app_state):
        """Test successful login."""
        user_id = uuid4()
        org_id = uuid4()
        now = datetime.now(timezone.utc)

        mock_user = User(
            id=user_id,
            email="user@example.com",
            name="Test User",
            password_hash="hashed",
            is_active=True,
            is_verified=True,
            created_at=now,
            updated_at=now,
            last_login=now,
            avatar_url=None,
            preferences={}
        )
        mock_org = Organization(
            id=org_id,
            name="Test Org",
            slug="test-org",
            plan="free",
            created_at=now,
            updated_at=now,
            settings={},
            limits={}
        )
        mock_tokens = TokenPair(
            access_token="valid.access.token",
            refresh_token="valid.refresh.token",
            token_type="bearer",
            expires_in=900
        )

        with patch.object(app_state.auth_service, 'authenticate', new_callable=AsyncMock) as mock_auth:
            with patch.object(app_state.auth_service, 'create_tokens', new_callable=AsyncMock) as mock_tokens_call:
                mock_auth.return_value = (mock_user, mock_org)
                mock_tokens_call.return_value = mock_tokens

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/auth/login",
                        json={
                            "email": "user@example.com",
                            "password": "correctpassword"
                        }
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["access_token"] == "valid.access.token"

    @pytest.mark.asyncio
    async def test_login_invalid_credentials(self, fastapi_app, mock_app_state):
        """Test login with wrong password."""
        from company_os.core.auth.service import AuthenticationError

        with patch.object(app_state.auth_service, 'authenticate', new_callable=AsyncMock) as mock_auth:
            mock_auth.side_effect = AuthenticationError("Invalid credentials")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/login",
                    json={
                        "email": "user@example.com",
                        "password": "wrongpassword"
                    }
                )

            assert response.status_code == 401
            assert "Invalid credentials" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_refresh_tokens_success(self, fastapi_app, mock_app_state):
        """Test token refresh."""
        mock_tokens = TokenPair(
            access_token="new.access.token",
            refresh_token="new.refresh.token",
            token_type="bearer",
            expires_in=900
        )

        with patch.object(app_state.auth_service, 'refresh_tokens', new_callable=AsyncMock) as mock_refresh:
            mock_refresh.return_value = mock_tokens

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/refresh",
                    json={"refresh_token": "old.refresh.token"}
                )

            assert response.status_code == 200
            data = response.json()
            assert data["access_token"] == "new.access.token"
            assert data["refresh_token"] == "new.refresh.token"

    @pytest.mark.asyncio
    async def test_refresh_tokens_invalid(self, fastapi_app, mock_app_state):
        """Test refresh with invalid token."""
        from company_os.core.auth.service import AuthenticationError

        with patch.object(app_state.auth_service, 'refresh_tokens', new_callable=AsyncMock) as mock_refresh:
            mock_refresh.side_effect = AuthenticationError("Invalid refresh token")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/refresh",
                    json={"refresh_token": "invalid.token"}
                )

            assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_logout_success(self, fastapi_app, mock_app_state):
        """Test logout."""
        with patch.object(app_state.auth_service, 'revoke_refresh_token', new_callable=AsyncMock) as mock_revoke:
            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/logout",
                    json={"refresh_token": "token.to.revoke"}
                )

            assert response.status_code == 200
            assert response.json()["message"] == "Logged out successfully"
            mock_revoke.assert_called_once_with("token.to.revoke")

    @pytest.mark.asyncio
    async def test_get_current_user_unauthorized(self, fastapi_app, mock_app_state):
        """Test accessing /me without authentication."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.get("/api/auth/me")

        # Should return 401 or 403 without auth header
        assert response.status_code in [401, 403]

    @pytest.mark.asyncio
    async def test_github_oauth_not_implemented(self, fastapi_app, mock_app_state):
        """Test GitHub OAuth returns not implemented."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.get("/api/auth/github")

        assert response.status_code == 501
        assert "not yet configured" in response.json()["detail"]


class TestAuthValidation:
    """Tests for auth input validation."""

    @pytest.fixture
    def fastapi_app(self):
        """Create FastAPI app for testing."""
        return create_app()

    @pytest.mark.asyncio
    async def test_register_invalid_email(self, fastapi_app):
        """Test registration with invalid email format."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/auth/register",
                json={
                    "email": "not-an-email",
                    "name": "Test User",
                    "password": "password123"
                }
            )

        assert response.status_code == 422  # Validation error

    @pytest.mark.asyncio
    async def test_register_missing_fields(self, fastapi_app):
        """Test registration with missing required fields."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/auth/register",
                json={"email": "test@example.com"}
            )

        assert response.status_code == 422  # Validation error

    @pytest.mark.asyncio
    async def test_login_missing_password(self, fastapi_app):
        """Test login with missing password."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/auth/login",
                json={"email": "test@example.com"}
            )

        assert response.status_code == 422
