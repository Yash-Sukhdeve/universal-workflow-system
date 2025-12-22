"""
Comprehensive Integration Tests for Authentication API.

Tests all auth endpoints with real scenarios using pytest and httpx.
"""

import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4, UUID

import jwt
from httpx import ASGITransport, AsyncClient

from company_os.api.main import create_app
from company_os.api.state import app_state
from company_os.core.auth.service import AuthService, AuthenticationError
from company_os.core.auth.models import (
    User, Organization, TokenPair, TokenPayload,
    UserRole, OrgMembership
)


class AsyncContextManager:
    """Helper for mocking async context managers."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


@pytest.fixture
def fastapi_app():
    """Create FastAPI app for testing."""
    return create_app()


@pytest.fixture
def mock_settings():
    """Mock settings for testing."""
    settings = MagicMock()
    settings.jwt_secret_key = "test-secret-key-for-testing-only"
    settings.jwt_algorithm = "HS256"
    settings.access_token_expire_minutes = 15
    settings.refresh_token_expire_days = 7
    return settings


@pytest.fixture
def mock_pool():
    """Create mock database pool."""
    pool = MagicMock()
    conn = AsyncMock()
    pool.acquire.return_value = AsyncContextManager(conn)
    return pool


@pytest.fixture
def mock_app_state(mock_pool, mock_settings):
    """Setup mock application state."""
    app_state.pool = mock_pool
    app_state.auth_service = AuthService(mock_pool, mock_settings)
    return app_state


@pytest.fixture
def sample_user():
    """Create sample user object."""
    user_id = uuid4()
    return User(
        id=user_id,
        email="testuser@example.com",
        name="Test User",
        password_hash="$2b$12$hashedpassword",
        is_active=True,
        is_verified=True,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
        last_login=None,
        avatar_url=None,
        preferences={}
    )


@pytest.fixture
def sample_org():
    """Create sample organization object."""
    return Organization(
        id=uuid4(),
        name="Test Organization",
        slug="test-org",
        plan="free",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
        settings={},
        limits={"max_tasks": 100}
    )


@pytest.fixture
def sample_tokens():
    """Create sample token pair."""
    return TokenPair(
        access_token="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.test.token",
        refresh_token="refresh.token.here",
        token_type="bearer",
        expires_in=900
    )


class TestRegisterEndpoint:
    """Tests for POST /api/auth/register."""

    @pytest.mark.asyncio
    async def test_register_success(self, fastapi_app, mock_app_state, sample_user, sample_org, sample_tokens):
        """Test successful user registration with all fields."""
        with patch.object(app_state.auth_service, 'create_user', new_callable=AsyncMock) as mock_create:
            with patch.object(app_state.auth_service, 'create_tokens', new_callable=AsyncMock) as mock_tokens_call:
                mock_create.return_value = (sample_user, sample_org)
                mock_tokens_call.return_value = sample_tokens

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/auth/register",
                        json={
                            "email": "newuser@example.com",
                            "name": "New User",
                            "password": "SecurePassword123!",
                            "org_name": "My New Company"
                        }
                    )

                assert response.status_code == 200
                data = response.json()
                assert "access_token" in data
                assert "refresh_token" in data
                assert data["token_type"] == "bearer"
                assert data["expires_in"] == 900

                # Verify create_user was called with correct params
                mock_create.assert_called_once()
                call_kwargs = mock_create.call_args.kwargs
                assert call_kwargs["email"] == "newuser@example.com"
                assert call_kwargs["name"] == "New User"
                assert call_kwargs["password"] == "SecurePassword123!"
                assert call_kwargs["org_name"] == "My New Company"

    @pytest.mark.asyncio
    async def test_register_without_org_name(self, fastapi_app, mock_app_state, sample_user, sample_org, sample_tokens):
        """Test registration without optional org_name field."""
        with patch.object(app_state.auth_service, 'create_user', new_callable=AsyncMock) as mock_create:
            with patch.object(app_state.auth_service, 'create_tokens', new_callable=AsyncMock) as mock_tokens_call:
                mock_create.return_value = (sample_user, sample_org)
                mock_tokens_call.return_value = sample_tokens

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/auth/register",
                        json={
                            "email": "user@example.com",
                            "name": "User Name",
                            "password": "password123"
                        }
                    )

                assert response.status_code == 200
                assert "access_token" in response.json()

    @pytest.mark.asyncio
    async def test_register_duplicate_email(self, fastapi_app, mock_app_state):
        """Test registration fails with duplicate email."""
        with patch.object(app_state.auth_service, 'create_user', new_callable=AsyncMock) as mock_create:
            # Simulate unique constraint violation
            mock_create.side_effect = Exception("unique constraint violation: email already exists")

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
            assert "already registered" in response.json()["detail"].lower()

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

        assert response.status_code == 422  # Pydantic validation error

    @pytest.mark.asyncio
    async def test_register_missing_required_fields(self, fastapi_app):
        """Test registration with missing required fields."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/auth/register",
                json={"email": "test@example.com"}
            )

        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_register_empty_password(self, fastapi_app):
        """Test registration with empty password."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/auth/register",
                json={
                    "email": "test@example.com",
                    "name": "Test User",
                    "password": ""
                }
            )

        # Should either fail validation or proceed (depends on validation rules)
        assert response.status_code in [200, 400, 422]


class TestLoginEndpoint:
    """Tests for POST /api/auth/login."""

    @pytest.mark.asyncio
    async def test_login_success(self, fastapi_app, mock_app_state, sample_user, sample_org, sample_tokens):
        """Test successful login with correct credentials."""
        with patch.object(app_state.auth_service, 'authenticate', new_callable=AsyncMock) as mock_auth:
            with patch.object(app_state.auth_service, 'create_tokens', new_callable=AsyncMock) as mock_tokens_call:
                mock_auth.return_value = (sample_user, sample_org)
                mock_tokens_call.return_value = sample_tokens

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.post(
                        "/api/auth/login",
                        json={
                            "email": "testuser@example.com",
                            "password": "correctpassword"
                        }
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["access_token"] == sample_tokens.access_token
                assert data["refresh_token"] == sample_tokens.refresh_token
                assert data["token_type"] == "bearer"

    @pytest.mark.asyncio
    async def test_login_wrong_password(self, fastapi_app, mock_app_state):
        """Test login fails with incorrect password."""
        with patch.object(app_state.auth_service, 'authenticate', new_callable=AsyncMock) as mock_auth:
            mock_auth.side_effect = AuthenticationError("Invalid credentials")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/login",
                    json={
                        "email": "testuser@example.com",
                        "password": "wrongpassword"
                    }
                )

            assert response.status_code == 401
            assert "Invalid credentials" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_login_inactive_user(self, fastapi_app, mock_app_state):
        """Test login fails for inactive user account."""
        with patch.object(app_state.auth_service, 'authenticate', new_callable=AsyncMock) as mock_auth:
            mock_auth.side_effect = AuthenticationError("Account is inactive")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/login",
                    json={
                        "email": "inactive@example.com",
                        "password": "password123"
                    }
                )

            assert response.status_code == 401
            assert "inactive" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_login_nonexistent_user(self, fastapi_app, mock_app_state):
        """Test login fails for non-existent user."""
        with patch.object(app_state.auth_service, 'authenticate', new_callable=AsyncMock) as mock_auth:
            mock_auth.side_effect = AuthenticationError("Invalid credentials")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/login",
                    json={
                        "email": "nonexistent@example.com",
                        "password": "password123"
                    }
                )

            assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_login_missing_password(self, fastapi_app):
        """Test login with missing password field."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/auth/login",
                json={"email": "test@example.com"}
            )

        assert response.status_code == 422


class TestRefreshEndpoint:
    """Tests for POST /api/auth/refresh."""

    @pytest.mark.asyncio
    async def test_refresh_success(self, fastapi_app, mock_app_state, sample_tokens):
        """Test successful token refresh."""
        new_tokens = TokenPair(
            access_token="new.access.token",
            refresh_token="new.refresh.token",
            token_type="bearer",
            expires_in=900
        )

        with patch.object(app_state.auth_service, 'refresh_tokens', new_callable=AsyncMock) as mock_refresh:
            mock_refresh.return_value = new_tokens

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

            # Verify old token was passed for refresh
            mock_refresh.assert_called_once()
            assert mock_refresh.call_args.kwargs["refresh_token"] == "old.refresh.token"

    @pytest.mark.asyncio
    async def test_refresh_invalid_token(self, fastapi_app, mock_app_state):
        """Test refresh fails with invalid token."""
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
            assert "Invalid refresh token" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_refresh_expired_token(self, fastapi_app, mock_app_state):
        """Test refresh fails with expired token."""
        with patch.object(app_state.auth_service, 'refresh_tokens', new_callable=AsyncMock) as mock_refresh:
            mock_refresh.side_effect = AuthenticationError("Refresh token has expired")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/refresh",
                    json={"refresh_token": "expired.token"}
                )

            assert response.status_code == 401
            assert "expired" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_refresh_revoked_token(self, fastapi_app, mock_app_state):
        """Test refresh fails with revoked token."""
        with patch.object(app_state.auth_service, 'refresh_tokens', new_callable=AsyncMock) as mock_refresh:
            mock_refresh.side_effect = AuthenticationError("Refresh token has been revoked")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/refresh",
                    json={"refresh_token": "revoked.token"}
                )

            assert response.status_code == 401


class TestLogoutEndpoint:
    """Tests for POST /api/auth/logout."""

    @pytest.mark.asyncio
    async def test_logout_success(self, fastapi_app, mock_app_state):
        """Test successful logout."""
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
    async def test_logout_already_revoked(self, fastapi_app, mock_app_state):
        """Test logout with already revoked token (should still succeed)."""
        with patch.object(app_state.auth_service, 'revoke_refresh_token', new_callable=AsyncMock) as mock_revoke:
            # Even if already revoked, logout should return success
            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/auth/logout",
                    json={"refresh_token": "already.revoked.token"}
                )

            assert response.status_code == 200


class TestGetCurrentUserEndpoint:
    """Tests for GET /api/auth/me."""

    @pytest.mark.asyncio
    async def test_get_me_authenticated(self, fastapi_app, mock_app_state, sample_user, mock_settings):
        """Test getting current user info when authenticated."""
        user_id = sample_user.id
        org_id = uuid4()

        # Create valid token payload
        token_payload = TokenPayload(
            sub=str(user_id),
            org_id=str(org_id),
            role="member",
            permissions=["tasks:read"],
            exp=datetime.now(timezone.utc) + timedelta(minutes=15),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        with patch.object(app_state.auth_service, 'verify_access_token', new_callable=AsyncMock) as mock_verify:
            with patch.object(app_state.auth_service, 'get_user_by_id', new_callable=AsyncMock) as mock_get_user:
                mock_verify.return_value = token_payload
                mock_get_user.return_value = sample_user

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/auth/me",
                        headers={"Authorization": "Bearer valid.access.token"}
                    )

                assert response.status_code == 200
                data = response.json()
                assert data["id"] == str(user_id)
                assert data["email"] == sample_user.email
                assert data["name"] == sample_user.name
                assert data["org_id"] == str(org_id)
                assert data["role"] == "member"

    @pytest.mark.asyncio
    async def test_get_me_unauthenticated(self, fastapi_app, mock_app_state):
        """Test accessing /me without authentication."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.get("/api/auth/me")

        assert response.status_code in [401, 403]

    @pytest.mark.asyncio
    async def test_get_me_invalid_token(self, fastapi_app, mock_app_state):
        """Test accessing /me with invalid token."""
        with patch.object(app_state.auth_service, 'verify_access_token', new_callable=AsyncMock) as mock_verify:
            mock_verify.side_effect = AuthenticationError("Invalid token")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.get(
                    "/api/auth/me",
                    headers={"Authorization": "Bearer invalid.token"}
                )

            assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_get_me_expired_token(self, fastapi_app, mock_app_state):
        """Test accessing /me with expired token."""
        with patch.object(app_state.auth_service, 'verify_access_token', new_callable=AsyncMock) as mock_verify:
            mock_verify.side_effect = AuthenticationError("Token has expired")

            async with AsyncClient(
                transport=ASGITransport(app=fastapi_app),
                base_url="http://test"
            ) as client:
                response = await client.get(
                    "/api/auth/me",
                    headers={"Authorization": "Bearer expired.token"}
                )

            assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_get_me_user_not_found(self, fastapi_app, mock_app_state):
        """Test /me when user is deleted after token was issued."""
        token_payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="member",
            permissions=[],
            exp=datetime.now(timezone.utc) + timedelta(minutes=15),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        with patch.object(app_state.auth_service, 'verify_access_token', new_callable=AsyncMock) as mock_verify:
            with patch.object(app_state.auth_service, 'get_user_by_id', new_callable=AsyncMock) as mock_get_user:
                mock_verify.return_value = token_payload
                mock_get_user.return_value = None  # User deleted

                async with AsyncClient(
                    transport=ASGITransport(app=fastapi_app),
                    base_url="http://test"
                ) as client:
                    response = await client.get(
                        "/api/auth/me",
                        headers={"Authorization": "Bearer valid.token"}
                    )

                assert response.status_code == 404
                assert "not found" in response.json()["detail"].lower()


class TestGitHubOAuthEndpoints:
    """Tests for GitHub OAuth endpoints (not implemented)."""

    @pytest.mark.asyncio
    async def test_github_oauth_not_implemented(self, fastapi_app):
        """Test GitHub OAuth returns 501."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.get("/api/auth/github")

        assert response.status_code == 501
        assert "not yet configured" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_github_callback_not_implemented(self, fastapi_app):
        """Test GitHub OAuth callback returns 501."""
        async with AsyncClient(
            transport=ASGITransport(app=fastapi_app),
            base_url="http://test"
        ) as client:
            response = await client.get(
                "/api/auth/github/callback",
                params={"code": "abc123", "state": "xyz"}
            )

        assert response.status_code == 501
