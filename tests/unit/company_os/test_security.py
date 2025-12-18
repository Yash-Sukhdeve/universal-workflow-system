"""
Unit Tests for API Security Module.

Tests FastAPI security dependencies for authentication and authorization.
"""

import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, Mock
from uuid import uuid4

from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from company_os.api.security import (
    get_auth_service,
    get_current_user,
    get_optional_user,
    get_current_user_context,
    require_permission,
    CurrentUser
)
from company_os.core.auth.service import AuthenticationError, AuthorizationError
from company_os.core.auth.models import (
    TokenPayload,
    Permission,
    UserRole
)


class TestCurrentUserClass:
    """Tests for CurrentUser wrapper class."""

    @pytest.fixture
    def sample_token_payload(self):
        """Create sample TokenPayload."""
        return TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="admin",
            permissions=["tasks:create", "tasks:read", "tasks:update", "tasks:delete"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

    def test_init_with_token_payload(self, sample_token_payload):
        """Test CurrentUser initialization with TokenPayload."""
        current_user = CurrentUser(sample_token_payload)

        assert str(current_user.user_id) == sample_token_payload.sub
        assert str(current_user.org_id) == sample_token_payload.org_id
        assert current_user.role == sample_token_payload.role
        assert current_user.permissions == sample_token_payload.permissions
        assert current_user.token == sample_token_payload

    def test_user_id_property(self, sample_token_payload):
        """Test user_id property returns UUID."""
        current_user = CurrentUser(sample_token_payload)

        assert str(current_user.user_id) == sample_token_payload.sub
        # Verify it's actually a UUID object
        assert hasattr(current_user.user_id, 'hex')

    def test_org_id_property(self, sample_token_payload):
        """Test org_id property returns UUID."""
        current_user = CurrentUser(sample_token_payload)

        assert str(current_user.org_id) == sample_token_payload.org_id
        # Verify it's actually a UUID object
        assert hasattr(current_user.org_id, 'hex')

    def test_role_property(self, sample_token_payload):
        """Test role property returns string."""
        current_user = CurrentUser(sample_token_payload)

        assert current_user.role == "admin"
        assert isinstance(current_user.role, str)

    def test_has_permission_granted(self, sample_token_payload):
        """Test has_permission returns True when permission exists."""
        current_user = CurrentUser(sample_token_payload)

        assert current_user.has_permission(Permission.TASKS_CREATE) is True
        assert current_user.has_permission(Permission.TASKS_READ) is True
        assert current_user.has_permission(Permission.TASKS_UPDATE) is True
        assert current_user.has_permission(Permission.TASKS_DELETE) is True

    def test_has_permission_denied(self, sample_token_payload):
        """Test has_permission returns False when permission missing."""
        current_user = CurrentUser(sample_token_payload)

        assert current_user.has_permission(Permission.ADMIN_FULL) is False
        assert current_user.has_permission(Permission.ORG_BILLING) is False
        assert current_user.has_permission(Permission.AGENTS_CONFIGURE) is False

    def test_has_permission_viewer_role(self):
        """Test has_permission for viewer role with limited permissions."""
        viewer_payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="viewer",
            permissions=["tasks:read", "projects:read"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )
        current_user = CurrentUser(viewer_payload)

        assert current_user.has_permission(Permission.TASKS_READ) is True
        assert current_user.has_permission(Permission.PROJECTS_READ) is True
        assert current_user.has_permission(Permission.TASKS_CREATE) is False
        assert current_user.has_permission(Permission.TASKS_UPDATE) is False


class TestGetAuthService:
    """Tests for get_auth_service dependency."""

    @pytest.mark.asyncio
    async def test_get_auth_service_returns_service(self):
        """Test get_auth_service returns AuthService from app state."""
        # Mock the app state
        mock_auth_service = MagicMock()

        # Patch get_app_state to return our mock
        with pytest.mock.patch('company_os.api.security.get_app_state') as mock_get_state:
            mock_state = MagicMock()
            mock_state.auth_service = mock_auth_service
            mock_get_state.return_value = mock_state

            result = await get_auth_service()

            assert result is mock_auth_service
            mock_get_state.assert_called_once()


class TestGetCurrentUser:
    """Tests for get_current_user dependency."""

    @pytest.fixture
    def mock_auth_service(self):
        """Create mock AuthService."""
        return AsyncMock()

    @pytest.fixture
    def valid_token_payload(self):
        """Create valid TokenPayload."""
        return TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="member",
            permissions=["tasks:read", "tasks:create"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

    @pytest.mark.asyncio
    async def test_get_current_user_with_valid_token(
        self, mock_auth_service, valid_token_payload
    ):
        """Test get_current_user returns payload with valid token."""
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="valid.jwt.token"
        )
        mock_auth_service.verify_access_token = AsyncMock(return_value=valid_token_payload)

        result = await get_current_user(credentials, mock_auth_service)

        assert result == valid_token_payload
        mock_auth_service.verify_access_token.assert_called_once_with("valid.jwt.token")

    @pytest.mark.asyncio
    async def test_get_current_user_with_no_credentials(self, mock_auth_service):
        """Test get_current_user raises 401 when no credentials provided."""
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(None, mock_auth_service)

        assert exc_info.value.status_code == status.HTTP_401_UNAUTHORIZED
        assert exc_info.value.detail == "Not authenticated"
        assert exc_info.value.headers == {"WWW-Authenticate": "Bearer"}

    @pytest.mark.asyncio
    async def test_get_current_user_with_invalid_token(self, mock_auth_service):
        """Test get_current_user raises 401 with invalid token."""
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="invalid.jwt.token"
        )
        mock_auth_service.verify_access_token = AsyncMock(
            side_effect=AuthenticationError("Token invalid")
        )

        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(credentials, mock_auth_service)

        assert exc_info.value.status_code == status.HTTP_401_UNAUTHORIZED
        assert "Token invalid" in exc_info.value.detail
        assert exc_info.value.headers == {"WWW-Authenticate": "Bearer"}

    @pytest.mark.asyncio
    async def test_get_current_user_with_expired_token(self, mock_auth_service):
        """Test get_current_user raises 401 with expired token."""
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="expired.jwt.token"
        )
        mock_auth_service.verify_access_token = AsyncMock(
            side_effect=AuthenticationError("Token has expired")
        )

        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(credentials, mock_auth_service)

        assert exc_info.value.status_code == status.HTTP_401_UNAUTHORIZED
        assert "expired" in exc_info.value.detail.lower()


class TestGetOptionalUser:
    """Tests for get_optional_user dependency."""

    @pytest.fixture
    def mock_auth_service(self):
        """Create mock AuthService."""
        return AsyncMock()

    @pytest.fixture
    def valid_token_payload(self):
        """Create valid TokenPayload."""
        return TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="owner",
            permissions=["admin:full"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

    @pytest.mark.asyncio
    async def test_get_optional_user_with_valid_token(
        self, mock_auth_service, valid_token_payload
    ):
        """Test get_optional_user returns payload when authenticated."""
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="valid.jwt.token"
        )
        mock_auth_service.verify_access_token = AsyncMock(return_value=valid_token_payload)

        result = await get_optional_user(credentials, mock_auth_service)

        assert result == valid_token_payload
        mock_auth_service.verify_access_token.assert_called_once_with("valid.jwt.token")

    @pytest.mark.asyncio
    async def test_get_optional_user_with_no_credentials(self, mock_auth_service):
        """Test get_optional_user returns None when no credentials."""
        result = await get_optional_user(None, mock_auth_service)

        assert result is None
        mock_auth_service.verify_access_token.assert_not_called()

    @pytest.mark.asyncio
    async def test_get_optional_user_with_invalid_token(self, mock_auth_service):
        """Test get_optional_user returns None with invalid token."""
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="invalid.jwt.token"
        )
        mock_auth_service.verify_access_token = AsyncMock(
            side_effect=AuthenticationError("Invalid token")
        )

        result = await get_optional_user(credentials, mock_auth_service)

        assert result is None

    @pytest.mark.asyncio
    async def test_get_optional_user_with_expired_token(self, mock_auth_service):
        """Test get_optional_user returns None with expired token."""
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="expired.jwt.token"
        )
        mock_auth_service.verify_access_token = AsyncMock(
            side_effect=AuthenticationError("Token expired")
        )

        result = await get_optional_user(credentials, mock_auth_service)

        assert result is None


class TestGetCurrentUserContext:
    """Tests for get_current_user_context dependency."""

    @pytest.mark.asyncio
    async def test_get_current_user_context_returns_current_user(self):
        """Test get_current_user_context returns CurrentUser wrapper."""
        token_payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="admin",
            permissions=["tasks:create", "projects:read"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        result = await get_current_user_context(token_payload)

        assert isinstance(result, CurrentUser)
        assert result.token == token_payload
        assert str(result.user_id) == token_payload.sub
        assert str(result.org_id) == token_payload.org_id
        assert result.role == token_payload.role

    @pytest.mark.asyncio
    async def test_get_current_user_context_preserves_permissions(self):
        """Test get_current_user_context preserves permissions."""
        token_payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="member",
            permissions=["tasks:read", "tasks:create", "agents:view"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        result = await get_current_user_context(token_payload)

        assert result.has_permission(Permission.TASKS_READ) is True
        assert result.has_permission(Permission.TASKS_CREATE) is True
        assert result.has_permission(Permission.AGENTS_VIEW) is True
        assert result.has_permission(Permission.ADMIN_FULL) is False


class TestRequirePermissionFactory:
    """Tests for require_permission dependency factory."""

    @pytest.fixture
    def mock_auth_service(self):
        """Create mock AuthService."""
        return MagicMock()

    @pytest.fixture
    def token_with_permissions(self):
        """Create TokenPayload with specific permissions."""
        return TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="admin",
            permissions=["tasks:create", "tasks:update", "tasks:delete"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

    @pytest.mark.asyncio
    async def test_require_permission_granted(
        self, mock_auth_service, token_with_permissions
    ):
        """Test require_permission allows access when permission granted."""
        mock_auth_service.require_permission = MagicMock()  # Does not raise

        check_permission = require_permission(Permission.TASKS_CREATE)
        result = await check_permission(token_with_permissions, mock_auth_service)

        assert result == token_with_permissions
        mock_auth_service.require_permission.assert_called_once_with(
            token_with_permissions, Permission.TASKS_CREATE
        )

    @pytest.mark.asyncio
    async def test_require_permission_denied(
        self, mock_auth_service, token_with_permissions
    ):
        """Test require_permission raises 403 when permission denied."""
        mock_auth_service.require_permission = MagicMock(
            side_effect=AuthorizationError("Permission denied: admin:full")
        )

        check_permission = require_permission(Permission.ADMIN_FULL)

        with pytest.raises(HTTPException) as exc_info:
            await check_permission(token_with_permissions, mock_auth_service)

        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
        assert "Permission denied" in exc_info.value.detail
        assert "admin:full" in exc_info.value.detail

    @pytest.mark.asyncio
    async def test_require_permission_multiple_permissions(self, mock_auth_service):
        """Test require_permission with multiple different permissions."""
        token = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="member",
            permissions=["tasks:read", "projects:read"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        # Test allowed permission
        mock_auth_service.require_permission = MagicMock()
        check_read = require_permission(Permission.TASKS_READ)
        result = await check_read(token, mock_auth_service)
        assert result == token

        # Test denied permission
        mock_auth_service.require_permission = MagicMock(
            side_effect=AuthorizationError("Permission denied: tasks:delete")
        )
        check_delete = require_permission(Permission.TASKS_DELETE)

        with pytest.raises(HTTPException) as exc_info:
            await check_delete(token, mock_auth_service)

        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN

    @pytest.mark.asyncio
    async def test_require_permission_returns_callable(self):
        """Test require_permission factory returns callable dependency."""
        permission_checker = require_permission(Permission.ORG_MANAGE)

        # Verify it's a coroutine function
        assert callable(permission_checker)
        assert hasattr(permission_checker, '__call__')

    @pytest.mark.asyncio
    async def test_require_permission_admin_full(self, mock_auth_service):
        """Test require_permission with ADMIN_FULL permission."""
        owner_token = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="owner",
            permissions=["admin:full", "org:manage", "org:billing"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        mock_auth_service.require_permission = MagicMock()
        check_admin = require_permission(Permission.ADMIN_FULL)
        result = await check_admin(owner_token, mock_auth_service)

        assert result == owner_token
        mock_auth_service.require_permission.assert_called_once_with(
            owner_token, Permission.ADMIN_FULL
        )


class TestIntegrationScenarios:
    """Integration tests for common security scenarios."""

    @pytest.mark.asyncio
    async def test_authenticated_user_with_sufficient_permissions(self):
        """Test full flow: authenticated user with required permission."""
        # Setup
        user_id = uuid4()
        org_id = uuid4()
        token_payload = TokenPayload(
            sub=str(user_id),
            org_id=str(org_id),
            role="admin",
            permissions=["projects:create", "projects:update", "projects:delete"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="valid.token"
        )

        mock_auth_service = AsyncMock()
        mock_auth_service.verify_access_token = AsyncMock(return_value=token_payload)
        mock_auth_service.require_permission = MagicMock()

        # Get current user
        current_user_token = await get_current_user(credentials, mock_auth_service)
        assert current_user_token == token_payload

        # Check permission
        check_perm = require_permission(Permission.PROJECTS_CREATE)
        result = await check_perm(current_user_token, mock_auth_service)
        assert result == token_payload

        # Get user context
        user_context = await get_current_user_context(current_user_token)
        assert isinstance(user_context, CurrentUser)
        assert user_context.has_permission(Permission.PROJECTS_CREATE) is True

    @pytest.mark.asyncio
    async def test_unauthenticated_user_denied_access(self):
        """Test full flow: unauthenticated user is denied."""
        mock_auth_service = AsyncMock()

        # No credentials provided
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(None, mock_auth_service)

        assert exc_info.value.status_code == status.HTTP_401_UNAUTHORIZED

    @pytest.mark.asyncio
    async def test_authenticated_user_insufficient_permissions(self):
        """Test full flow: authenticated user lacks required permission."""
        token_payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="viewer",
            permissions=["tasks:read"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="valid.token"
        )

        mock_auth_service = AsyncMock()
        mock_auth_service.verify_access_token = AsyncMock(return_value=token_payload)
        mock_auth_service.require_permission = MagicMock(
            side_effect=AuthorizationError("Permission denied: tasks:delete")
        )

        # Get current user succeeds
        current_user_token = await get_current_user(credentials, mock_auth_service)
        assert current_user_token == token_payload

        # But permission check fails
        check_perm = require_permission(Permission.TASKS_DELETE)
        with pytest.raises(HTTPException) as exc_info:
            await check_perm(current_user_token, mock_auth_service)

        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
        assert "Permission denied" in exc_info.value.detail
