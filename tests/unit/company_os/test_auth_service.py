"""
Unit Tests for Authentication Service.

Tests user management, tokens, and authorization.
"""

import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

from company_os.core.auth.service import (
    AuthService,
    AuthenticationError,
    AuthorizationError
)
from company_os.core.auth.models import (
    User,
    Organization,
    UserRole,
    Permission,
    TokenPayload,
    ROLE_PERMISSIONS
)


class AsyncContextManagerMock:
    """Mock async context manager for connection pool and transactions."""
    def __init__(self, return_value=None):
        self.return_value = return_value

    async def __aenter__(self):
        return self.return_value

    async def __aexit__(self, *args):
        pass


class TestPasswordHashing:
    """Tests for password hashing functionality."""

    @pytest.fixture
    def auth_service(self):
        """Create AuthService with mocked dependencies."""
        mock_pool = MagicMock()
        mock_settings = MagicMock()
        mock_settings.jwt_secret_key = "test-secret"
        mock_settings.jwt_algorithm = "HS256"
        mock_settings.access_token_expire_minutes = 15
        mock_settings.refresh_token_expire_days = 7
        return AuthService(mock_pool, mock_settings)

    def test_hash_password(self, auth_service):
        """Test password hashing produces hash."""
        password = "secure_password_123"
        hashed = auth_service.hash_password(password)

        assert hashed != password
        assert len(hashed) > 0
        assert hashed.startswith("$2b$")  # bcrypt prefix

    def test_verify_password_correct(self, auth_service):
        """Test correct password verification."""
        password = "my_secure_password"
        hashed = auth_service.hash_password(password)

        assert auth_service.verify_password(password, hashed) is True

    def test_verify_password_incorrect(self, auth_service):
        """Test incorrect password verification."""
        password = "my_secure_password"
        hashed = auth_service.hash_password(password)

        assert auth_service.verify_password("wrong_password", hashed) is False

    def test_different_passwords_different_hashes(self, auth_service):
        """Test same password produces different hashes (salt)."""
        password = "same_password"
        hash1 = auth_service.hash_password(password)
        hash2 = auth_service.hash_password(password)

        assert hash1 != hash2  # Different salts
        # But both should verify
        assert auth_service.verify_password(password, hash1)
        assert auth_service.verify_password(password, hash2)


class TestUserManagement:
    """Tests for user creation and retrieval."""

    @pytest.fixture
    def mock_pool(self):
        """Create mock database pool."""
        pool = MagicMock()
        return pool

    @pytest.fixture
    def mock_settings(self):
        """Create mock settings."""
        settings = MagicMock()
        settings.jwt_secret_key = "test-secret-key-12345"
        settings.jwt_algorithm = "HS256"
        settings.access_token_expire_minutes = 15
        settings.refresh_token_expire_days = 7
        return settings

    @pytest.fixture
    def auth_service(self, mock_pool, mock_settings):
        """Create AuthService with mocks."""
        return AuthService(mock_pool, mock_settings)

    @pytest.mark.asyncio
    async def test_create_user(self, auth_service, mock_pool):
        """Test creating a new user."""
        user_id = uuid4()
        org_id = uuid4()
        now = datetime.now(timezone.utc)

        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(side_effect=[
            # First call - user creation
            {
                "id": user_id,
                "email": "test@example.com",
                "name": "Test User",
                "password_hash": "hashed",
                "is_active": True,
                "is_verified": False,
                "created_at": now,
                "updated_at": now,
                "last_login": None,
                "avatar_url": None,
                "preferences": {}
            },
            # Second call - org creation
            {
                "id": org_id,
                "name": "Test User's Workspace",
                "slug": "test-user-abc123",
                "plan": "free",
                "created_at": now,
                "updated_at": now,
                "settings": {},
                "limits": {}
            }
        ])
        mock_conn.execute = AsyncMock()

        # Setup proper async context managers
        # transaction() returns a context manager, not a coroutine
        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)
        mock_conn.transaction = MagicMock(return_value=AsyncContextManagerMock(None))

        user, org = await auth_service.create_user(
            email="test@example.com",
            name="Test User",
            password="password123"
        )

        assert user.email == "test@example.com"
        assert user.name == "Test User"
        assert org.plan == "free"

    @pytest.mark.asyncio
    async def test_get_user_by_email(self, auth_service, mock_pool):
        """Test retrieving user by email."""
        user_id = uuid4()
        now = datetime.now(timezone.utc)

        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": user_id,
            "email": "test@example.com",
            "name": "Test User",
            "password_hash": "hashed",
            "is_active": True,
            "is_verified": True,
            "created_at": now,
            "updated_at": now,
            "last_login": now,
            "avatar_url": None,
            "preferences": {"theme": "dark"}
        })

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        user = await auth_service.get_user_by_email("test@example.com")

        assert user is not None
        assert user.email == "test@example.com"
        assert user.preferences == {"theme": "dark"}

    @pytest.mark.asyncio
    async def test_get_user_by_email_not_found(self, auth_service, mock_pool):
        """Test retrieving non-existent user returns None."""
        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value=None)

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        user = await auth_service.get_user_by_email("nonexistent@example.com")

        assert user is None

    @pytest.mark.asyncio
    async def test_get_user_by_id(self, auth_service, mock_pool):
        """Test retrieving user by ID."""
        user_id = uuid4()
        now = datetime.now(timezone.utc)

        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": user_id,
            "email": "test@example.com",
            "name": "Test User",
            "password_hash": "hashed",
            "is_active": True,
            "is_verified": True,
            "created_at": now,
            "updated_at": now,
            "last_login": None,
            "avatar_url": "https://example.com/avatar.png",
            "preferences": {}
        })

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        user = await auth_service.get_user_by_id(user_id)

        assert user is not None
        assert user.id == user_id
        assert user.avatar_url == "https://example.com/avatar.png"


class TestAuthentication:
    """Tests for authentication flow."""

    @pytest.fixture
    def mock_pool(self):
        return MagicMock()

    @pytest.fixture
    def mock_settings(self):
        settings = MagicMock()
        settings.jwt_secret_key = "test-secret-key-12345"
        settings.jwt_algorithm = "HS256"
        settings.access_token_expire_minutes = 15
        settings.refresh_token_expire_days = 7
        return settings

    @pytest.fixture
    def auth_service(self, mock_pool, mock_settings):
        return AuthService(mock_pool, mock_settings)

    @pytest.mark.asyncio
    async def test_authenticate_success(self, auth_service, mock_pool):
        """Test successful authentication."""
        user_id = uuid4()
        org_id = uuid4()
        now = datetime.now(timezone.utc)
        password_hash = auth_service.hash_password("correct_password")

        mock_conn = AsyncMock()
        # First call - get user
        mock_conn.fetchrow = AsyncMock(side_effect=[
            {
                "id": user_id,
                "email": "test@example.com",
                "name": "Test User",
                "password_hash": password_hash,
                "is_active": True,
                "is_verified": True,
                "created_at": now,
                "updated_at": now,
                "last_login": None,
                "avatar_url": None,
                "preferences": {}
            },
            # Second call - get org
            {
                "id": org_id,
                "name": "Test Org",
                "slug": "test-org",
                "plan": "free",
                "created_at": now,
                "updated_at": now,
                "settings": {},
                "limits": {}
            }
        ])
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        user, org = await auth_service.authenticate(
            email="test@example.com",
            password="correct_password"
        )

        assert user.email == "test@example.com"
        assert org.id == org_id

    @pytest.mark.asyncio
    async def test_authenticate_wrong_password(self, auth_service, mock_pool):
        """Test authentication fails with wrong password."""
        user_id = uuid4()
        now = datetime.now(timezone.utc)
        password_hash = auth_service.hash_password("correct_password")

        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": user_id,
            "email": "test@example.com",
            "name": "Test User",
            "password_hash": password_hash,
            "is_active": True,
            "is_verified": True,
            "created_at": now,
            "updated_at": now,
            "last_login": None,
            "avatar_url": None,
            "preferences": {}
        })

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        with pytest.raises(AuthenticationError) as exc_info:
            await auth_service.authenticate(
                email="test@example.com",
                password="wrong_password"
            )

        assert "Invalid" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_authenticate_user_not_found(self, auth_service, mock_pool):
        """Test authentication fails for non-existent user."""
        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value=None)

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        with pytest.raises(AuthenticationError):
            await auth_service.authenticate(
                email="nonexistent@example.com",
                password="any_password"
            )

    @pytest.mark.asyncio
    async def test_authenticate_inactive_user(self, auth_service, mock_pool):
        """Test authentication fails for inactive user."""
        user_id = uuid4()
        now = datetime.now(timezone.utc)
        password_hash = auth_service.hash_password("password")

        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": user_id,
            "email": "test@example.com",
            "name": "Test User",
            "password_hash": password_hash,
            "is_active": False,  # Inactive!
            "is_verified": True,
            "created_at": now,
            "updated_at": now,
            "last_login": None,
            "avatar_url": None,
            "preferences": {}
        })

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        with pytest.raises(AuthenticationError) as exc_info:
            await auth_service.authenticate(
                email="test@example.com",
                password="password"
            )

        assert "disabled" in str(exc_info.value)


class TestTokenManagement:
    """Tests for JWT token creation and verification."""

    @pytest.fixture
    def mock_pool(self):
        return MagicMock()

    @pytest.fixture
    def mock_settings(self):
        settings = MagicMock()
        settings.jwt_secret_key = "test-secret-key-for-jwt-signing"
        settings.jwt_algorithm = "HS256"
        settings.access_token_expire_minutes = 15
        settings.refresh_token_expire_days = 7
        return settings

    @pytest.fixture
    def auth_service(self, mock_pool, mock_settings):
        return AuthService(mock_pool, mock_settings)

    @pytest.fixture
    def sample_user(self):
        return User(
            id=uuid4(),
            email="test@example.com",
            name="Test User",
            password_hash="hashed",
            is_active=True,
            is_verified=True,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc)
        )

    @pytest.fixture
    def sample_org(self):
        return Organization(
            id=uuid4(),
            name="Test Org",
            slug="test-org",
            plan="free",
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc)
        )

    @pytest.mark.asyncio
    async def test_create_tokens(self, auth_service, mock_pool, sample_user, sample_org):
        """Test token creation."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value="owner")  # User role
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        tokens = await auth_service.create_tokens(sample_user, sample_org)

        assert tokens.access_token is not None
        assert tokens.refresh_token is not None
        assert tokens.token_type == "bearer"
        assert tokens.expires_in == 15 * 60  # 15 minutes in seconds

    @pytest.mark.asyncio
    async def test_verify_access_token(self, auth_service, mock_pool, sample_user, sample_org):
        """Test access token verification."""
        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value="owner")
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        tokens = await auth_service.create_tokens(sample_user, sample_org)

        payload = await auth_service.verify_access_token(tokens.access_token)

        assert payload.sub == str(sample_user.id)
        assert payload.org_id == str(sample_org.id)

    @pytest.mark.asyncio
    async def test_verify_invalid_token(self, auth_service):
        """Test verification fails for invalid token."""
        with pytest.raises(AuthenticationError):
            await auth_service.verify_access_token("invalid-token")

    @pytest.mark.asyncio
    async def test_verify_expired_token(self, auth_service, mock_pool, sample_user, sample_org):
        """Test verification fails for expired token."""
        # Create service with very short expiry
        auth_service.settings.access_token_expire_minutes = -1  # Already expired

        mock_conn = AsyncMock()
        mock_conn.fetchval = AsyncMock(return_value="owner")
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        tokens = await auth_service.create_tokens(sample_user, sample_org)

        with pytest.raises(AuthenticationError) as exc_info:
            await auth_service.verify_access_token(tokens.access_token)

        assert "expired" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_refresh_tokens_success(self, auth_service, mock_pool, sample_user, sample_org):
        """Test successful token refresh with rotation."""
        refresh_token_id = uuid4()
        user_id = sample_user.id
        now = datetime.now(timezone.utc)

        mock_conn = AsyncMock()
        # First fetchrow - find refresh token
        # Second fetchrow - get user
        # Third fetchrow - get org
        mock_conn.fetchrow = AsyncMock(side_effect=[
            {
                "id": refresh_token_id,
                "user_id": user_id,
                "expires_at": now + timedelta(days=7),
                "revoked_at": None
            },
            {
                "id": user_id,
                "email": sample_user.email,
                "name": sample_user.name,
                "password_hash": "hashed",
                "is_active": True,
                "is_verified": True,
                "created_at": now,
                "updated_at": now,
                "last_login": None,
                "avatar_url": None,
                "preferences": {}
            },
            {
                "id": sample_org.id,
                "name": sample_org.name,
                "slug": sample_org.slug,
                "plan": "free",
                "created_at": now,
                "updated_at": now,
                "settings": {},
                "limits": {}
            }
        ])
        mock_conn.fetchval = AsyncMock(return_value="owner")
        mock_conn.execute = AsyncMock()

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        new_tokens = await auth_service.refresh_tokens(
            refresh_token="valid_refresh_token",
            device_info="test-device",
            ip_address="127.0.0.1"
        )

        assert new_tokens.access_token is not None
        assert new_tokens.refresh_token is not None
        # Verify old token was revoked
        assert mock_conn.execute.call_count >= 2  # Revoke old + store new

    @pytest.mark.asyncio
    async def test_refresh_tokens_invalid_token(self, auth_service, mock_pool):
        """Test refresh fails with invalid token."""
        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value=None)  # Token not found

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        with pytest.raises(AuthenticationError) as exc_info:
            await auth_service.refresh_tokens("invalid_token")

        assert "Invalid refresh token" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_refresh_tokens_revoked_token(self, auth_service, mock_pool):
        """Test refresh fails with revoked token."""
        refresh_token_id = uuid4()
        now = datetime.now(timezone.utc)

        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": refresh_token_id,
            "user_id": uuid4(),
            "expires_at": now + timedelta(days=7),
            "revoked_at": now - timedelta(hours=1)  # Already revoked
        })

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        with pytest.raises(AuthenticationError) as exc_info:
            await auth_service.refresh_tokens("revoked_token")

        assert "revoked" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_refresh_tokens_expired_token(self, auth_service, mock_pool):
        """Test refresh fails with expired token."""
        refresh_token_id = uuid4()
        now = datetime.now(timezone.utc)

        mock_conn = AsyncMock()
        mock_conn.fetchrow = AsyncMock(return_value={
            "id": refresh_token_id,
            "user_id": uuid4(),
            "expires_at": now - timedelta(days=1),  # Expired
            "revoked_at": None
        })

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        with pytest.raises(AuthenticationError) as exc_info:
            await auth_service.refresh_tokens("expired_token")

        assert "expired" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_revoke_refresh_token(self, auth_service, mock_pool):
        """Test revoking a refresh token (logout)."""
        mock_conn = AsyncMock()
        mock_conn.execute = AsyncMock(return_value="UPDATE 1")

        mock_pool.acquire.return_value = AsyncContextManagerMock(mock_conn)

        await auth_service.revoke_refresh_token("token_to_revoke")

        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]
        assert "UPDATE refresh_tokens" in call_args[0]
        assert "revoked_at" in call_args[0]


class TestAuthorization:
    """Tests for permission checking."""

    @pytest.fixture
    def mock_pool(self):
        return MagicMock()

    @pytest.fixture
    def mock_settings(self):
        settings = MagicMock()
        settings.jwt_secret_key = "test-secret"
        settings.jwt_algorithm = "HS256"
        settings.access_token_expire_minutes = 15
        settings.refresh_token_expire_days = 7
        return settings

    @pytest.fixture
    def auth_service(self, mock_pool, mock_settings):
        return AuthService(mock_pool, mock_settings)

    def test_check_permission_granted(self, auth_service):
        """Test permission check returns True when granted."""
        payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="admin",
            permissions=["tasks:create", "tasks:read", "tasks:update"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        assert auth_service.check_permission(payload, Permission.TASKS_CREATE) is True
        assert auth_service.check_permission(payload, Permission.TASKS_READ) is True

    def test_check_permission_denied(self, auth_service):
        """Test permission check returns False when not granted."""
        payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="viewer",
            permissions=["tasks:read"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        assert auth_service.check_permission(payload, Permission.TASKS_CREATE) is False
        assert auth_service.check_permission(payload, Permission.ADMIN_FULL) is False

    def test_require_permission_success(self, auth_service):
        """Test require_permission passes when granted."""
        payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="admin",
            permissions=["tasks:delete"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        # Should not raise
        auth_service.require_permission(payload, Permission.TASKS_DELETE)

    def test_require_permission_failure(self, auth_service):
        """Test require_permission raises when denied."""
        payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="viewer",
            permissions=["tasks:read"],
            exp=datetime.now(timezone.utc) + timedelta(hours=1),
            iat=datetime.now(timezone.utc),
            jti=str(uuid4())
        )

        with pytest.raises(AuthorizationError) as exc_info:
            auth_service.require_permission(payload, Permission.TASKS_DELETE)

        assert "Permission denied" in str(exc_info.value)


class TestRolePermissionMappings:
    """Tests for role-permission mapping configuration."""

    def test_owner_has_all_permissions(self):
        """Test owner role has all permissions."""
        owner_perms = ROLE_PERMISSIONS[UserRole.OWNER]
        assert owner_perms == set(Permission)

    def test_admin_has_expected_permissions(self):
        """Test admin role has expected permissions."""
        admin_perms = ROLE_PERMISSIONS[UserRole.ADMIN]

        assert Permission.TASKS_CREATE in admin_perms
        assert Permission.TASKS_DELETE in admin_perms
        assert Permission.AGENTS_CONFIGURE in admin_perms
        assert Permission.ADMIN_FULL not in admin_perms

    def test_member_has_limited_permissions(self):
        """Test member role has limited permissions."""
        member_perms = ROLE_PERMISSIONS[UserRole.MEMBER]

        assert Permission.TASKS_CREATE in member_perms
        assert Permission.TASKS_READ in member_perms
        assert Permission.TASKS_DELETE not in member_perms
        assert Permission.ORG_MANAGE not in member_perms

    def test_viewer_has_read_only(self):
        """Test viewer role has read-only permissions."""
        viewer_perms = ROLE_PERMISSIONS[UserRole.VIEWER]

        assert Permission.TASKS_READ in viewer_perms
        assert Permission.PROJECTS_READ in viewer_perms
        assert Permission.TASKS_CREATE not in viewer_perms
        assert Permission.TASKS_UPDATE not in viewer_perms
