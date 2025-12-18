"""
Unit tests for Company OS Domain Models.

Tests all dataclasses, enums, and permission mappings from auth models.
"""

import unittest
from dataclasses import FrozenInstanceError
from datetime import datetime, timedelta
from uuid import uuid4, UUID

from company_os.core.auth.models import (
    User,
    Organization,
    OrgMembership,
    OAuthAccount,
    APIKey,
    RefreshToken,
    TokenPair,
    TokenPayload,
    UserRole,
    Permission,
    ROLE_PERMISSIONS,
)


class TestUserRole(unittest.TestCase):
    """Test UserRole enum."""

    def test_all_role_values(self):
        """Test that all expected roles exist."""
        self.assertEqual(UserRole.OWNER.value, "owner")
        self.assertEqual(UserRole.ADMIN.value, "admin")
        self.assertEqual(UserRole.MEMBER.value, "member")
        self.assertEqual(UserRole.VIEWER.value, "viewer")

    def test_role_count(self):
        """Test that we have exactly 4 roles."""
        self.assertEqual(len(UserRole), 4)

    def test_role_string_representation(self):
        """Test that roles can be converted to strings."""
        self.assertEqual(str(UserRole.OWNER), "UserRole.OWNER")
        self.assertEqual(str(UserRole.ADMIN), "UserRole.ADMIN")
        # Use .value for the string value
        self.assertEqual(UserRole.OWNER.value, "owner")
        self.assertEqual(UserRole.ADMIN.value, "admin")

    def test_role_comparison(self):
        """Test role equality comparison."""
        self.assertEqual(UserRole.OWNER, UserRole.OWNER)
        self.assertNotEqual(UserRole.OWNER, UserRole.ADMIN)

    def test_role_from_string(self):
        """Test creating role from string value."""
        role = UserRole("admin")
        self.assertEqual(role, UserRole.ADMIN)


class TestPermission(unittest.TestCase):
    """Test Permission enum."""

    def test_task_permissions_exist(self):
        """Test all task permissions are defined."""
        self.assertEqual(Permission.TASKS_CREATE.value, "tasks:create")
        self.assertEqual(Permission.TASKS_READ.value, "tasks:read")
        self.assertEqual(Permission.TASKS_UPDATE.value, "tasks:update")
        self.assertEqual(Permission.TASKS_DELETE.value, "tasks:delete")
        self.assertEqual(Permission.TASKS_ASSIGN.value, "tasks:assign")

    def test_agent_permissions_exist(self):
        """Test all agent permissions are defined."""
        self.assertEqual(Permission.AGENTS_ACTIVATE.value, "agents:activate")
        self.assertEqual(Permission.AGENTS_VIEW.value, "agents:view")
        self.assertEqual(Permission.AGENTS_CONFIGURE.value, "agents:configure")

    def test_project_permissions_exist(self):
        """Test all project permissions are defined."""
        self.assertEqual(Permission.PROJECTS_CREATE.value, "projects:create")
        self.assertEqual(Permission.PROJECTS_READ.value, "projects:read")
        self.assertEqual(Permission.PROJECTS_UPDATE.value, "projects:update")
        self.assertEqual(Permission.PROJECTS_DELETE.value, "projects:delete")

    def test_org_permissions_exist(self):
        """Test all organization permissions are defined."""
        self.assertEqual(Permission.ORG_MANAGE.value, "org:manage")
        self.assertEqual(Permission.ORG_BILLING.value, "org:billing")
        self.assertEqual(Permission.ORG_MEMBERS.value, "org:members")

    def test_admin_permissions_exist(self):
        """Test admin permissions are defined."""
        self.assertEqual(Permission.ADMIN_FULL.value, "admin:full")

    def test_permission_count(self):
        """Test that we have exactly 16 permissions."""
        self.assertEqual(len(Permission), 16)

    def test_permission_naming_convention(self):
        """Test that all permissions follow resource:action naming."""
        for perm in Permission:
            self.assertIn(":", perm.value, f"Permission {perm.value} doesn't follow resource:action format")


class TestRolePermissions(unittest.TestCase):
    """Test ROLE_PERMISSIONS mapping."""

    def test_owner_has_all_permissions(self):
        """Test that OWNER role has all permissions."""
        owner_perms = ROLE_PERMISSIONS[UserRole.OWNER]
        all_perms = set(Permission)
        self.assertEqual(owner_perms, all_perms)
        self.assertEqual(len(owner_perms), 16)

    def test_admin_has_expected_permissions(self):
        """Test that ADMIN role has expected permissions."""
        admin_perms = ROLE_PERMISSIONS[UserRole.ADMIN]

        # Admin should have these permissions
        expected = {
            Permission.TASKS_CREATE, Permission.TASKS_READ, Permission.TASKS_UPDATE,
            Permission.TASKS_DELETE, Permission.TASKS_ASSIGN,
            Permission.AGENTS_ACTIVATE, Permission.AGENTS_VIEW, Permission.AGENTS_CONFIGURE,
            Permission.PROJECTS_CREATE, Permission.PROJECTS_READ, Permission.PROJECTS_UPDATE,
            Permission.PROJECTS_DELETE,
            Permission.ORG_MEMBERS,
        }
        self.assertEqual(admin_perms, expected)
        self.assertEqual(len(admin_perms), 13)

    def test_admin_lacks_owner_permissions(self):
        """Test that ADMIN doesn't have owner-only permissions."""
        admin_perms = ROLE_PERMISSIONS[UserRole.ADMIN]

        # Admin should NOT have these
        self.assertNotIn(Permission.ORG_MANAGE, admin_perms)
        self.assertNotIn(Permission.ORG_BILLING, admin_perms)
        self.assertNotIn(Permission.ADMIN_FULL, admin_perms)

    def test_member_has_limited_permissions(self):
        """Test that MEMBER role has limited permissions."""
        member_perms = ROLE_PERMISSIONS[UserRole.MEMBER]

        expected = {
            Permission.TASKS_CREATE, Permission.TASKS_READ, Permission.TASKS_UPDATE,
            Permission.TASKS_ASSIGN,
            Permission.AGENTS_ACTIVATE, Permission.AGENTS_VIEW,
            Permission.PROJECTS_READ,
        }
        self.assertEqual(member_perms, expected)
        self.assertEqual(len(member_perms), 7)

    def test_member_cannot_delete(self):
        """Test that MEMBER cannot delete tasks or projects."""
        member_perms = ROLE_PERMISSIONS[UserRole.MEMBER]

        self.assertNotIn(Permission.TASKS_DELETE, member_perms)
        self.assertNotIn(Permission.PROJECTS_DELETE, member_perms)
        self.assertNotIn(Permission.PROJECTS_CREATE, member_perms)

    def test_viewer_has_read_only_permissions(self):
        """Test that VIEWER role is read-only."""
        viewer_perms = ROLE_PERMISSIONS[UserRole.VIEWER]

        expected = {
            Permission.TASKS_READ,
            Permission.AGENTS_VIEW,
            Permission.PROJECTS_READ,
        }
        self.assertEqual(viewer_perms, expected)
        self.assertEqual(len(viewer_perms), 3)

    def test_viewer_cannot_write(self):
        """Test that VIEWER has no write permissions."""
        viewer_perms = ROLE_PERMISSIONS[UserRole.VIEWER]

        # No create, update, or delete permissions
        self.assertNotIn(Permission.TASKS_CREATE, viewer_perms)
        self.assertNotIn(Permission.TASKS_UPDATE, viewer_perms)
        self.assertNotIn(Permission.TASKS_DELETE, viewer_perms)
        self.assertNotIn(Permission.PROJECTS_CREATE, viewer_perms)
        self.assertNotIn(Permission.PROJECTS_UPDATE, viewer_perms)

    def test_all_roles_have_permission_sets(self):
        """Test that all roles have permission mappings."""
        for role in UserRole:
            self.assertIn(role, ROLE_PERMISSIONS)
            self.assertIsInstance(ROLE_PERMISSIONS[role], set)

    def test_permission_hierarchy(self):
        """Test that permission sets follow a hierarchy (owner > admin > member > viewer)."""
        owner_perms = ROLE_PERMISSIONS[UserRole.OWNER]
        admin_perms = ROLE_PERMISSIONS[UserRole.ADMIN]
        member_perms = ROLE_PERMISSIONS[UserRole.MEMBER]
        viewer_perms = ROLE_PERMISSIONS[UserRole.VIEWER]

        # Admin permissions should be subset of owner
        self.assertTrue(admin_perms.issubset(owner_perms))

        # Member permissions should be subset of admin
        self.assertTrue(member_perms.issubset(admin_perms))

        # Viewer permissions should be subset of member
        self.assertTrue(viewer_perms.issubset(member_perms))


class TestUser(unittest.TestCase):
    """Test User dataclass."""

    def test_user_creation(self):
        """Test creating a user with all fields."""
        user_id = uuid4()
        now = datetime.utcnow()

        user = User(
            id=user_id,
            email="test@example.com",
            name="Test User",
            password_hash="hashed_password_123",
            is_active=True,
            is_verified=False,
            created_at=now,
            updated_at=now,
        )

        self.assertEqual(user.id, user_id)
        self.assertEqual(user.email, "test@example.com")
        self.assertEqual(user.name, "Test User")
        self.assertEqual(user.password_hash, "hashed_password_123")
        self.assertTrue(user.is_active)
        self.assertFalse(user.is_verified)
        self.assertEqual(user.created_at, now)
        self.assertEqual(user.updated_at, now)

    def test_user_optional_fields(self):
        """Test user with optional fields."""
        user_id = uuid4()
        now = datetime.utcnow()
        last_login = now - timedelta(hours=1)

        user = User(
            id=user_id,
            email="test@example.com",
            name="Test User",
            password_hash=None,
            is_active=True,
            is_verified=True,
            created_at=now,
            updated_at=now,
            last_login=last_login,
            avatar_url="https://example.com/avatar.png",
            preferences={"theme": "dark", "notifications": True},
        )

        self.assertIsNone(user.password_hash)
        self.assertEqual(user.last_login, last_login)
        self.assertEqual(user.avatar_url, "https://example.com/avatar.png")
        self.assertEqual(user.preferences["theme"], "dark")
        self.assertTrue(user.preferences["notifications"])

    def test_user_default_preferences(self):
        """Test that preferences default to empty dict."""
        user = User(
            id=uuid4(),
            email="test@example.com",
            name="Test User",
            password_hash="hash",
            is_active=True,
            is_verified=False,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )

        self.assertEqual(user.preferences, {})

    def test_user_field_types(self):
        """Test that user fields have correct types."""
        user_id = uuid4()
        now = datetime.utcnow()

        user = User(
            id=user_id,
            email="test@example.com",
            name="Test User",
            password_hash="hash",
            is_active=True,
            is_verified=False,
            created_at=now,
            updated_at=now,
        )

        self.assertIsInstance(user.id, UUID)
        self.assertIsInstance(user.email, str)
        self.assertIsInstance(user.name, str)
        self.assertIsInstance(user.is_active, bool)
        self.assertIsInstance(user.is_verified, bool)
        self.assertIsInstance(user.created_at, datetime)
        self.assertIsInstance(user.updated_at, datetime)
        self.assertIsInstance(user.preferences, dict)


class TestOrganization(unittest.TestCase):
    """Test Organization dataclass."""

    def test_organization_creation(self):
        """Test creating an organization."""
        org_id = uuid4()
        now = datetime.utcnow()

        org = Organization(
            id=org_id,
            name="Test Org",
            slug="test-org",
            plan="pro",
            created_at=now,
            updated_at=now,
        )

        self.assertEqual(org.id, org_id)
        self.assertEqual(org.name, "Test Org")
        self.assertEqual(org.slug, "test-org")
        self.assertEqual(org.plan, "pro")
        self.assertEqual(org.created_at, now)
        self.assertEqual(org.updated_at, now)

    def test_organization_plans(self):
        """Test different organization plans."""
        plans = ["free", "starter", "pro", "enterprise"]

        for plan in plans:
            org = Organization(
                id=uuid4(),
                name="Test Org",
                slug="test-org",
                plan=plan,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            )
            self.assertEqual(org.plan, plan)

    def test_organization_with_settings(self):
        """Test organization with settings."""
        settings = {
            "max_agents": 10,
            "max_projects": 50,
            "features": ["ai", "analytics"],
        }

        org = Organization(
            id=uuid4(),
            name="Test Org",
            slug="test-org",
            plan="enterprise",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
            settings=settings,
        )

        self.assertEqual(org.settings["max_agents"], 10)
        self.assertEqual(org.settings["max_projects"], 50)
        self.assertIn("ai", org.settings["features"])

    def test_organization_with_limits(self):
        """Test organization with usage limits."""
        limits = {
            "api_calls_per_month": 100000,
            "storage_gb": 100,
            "seats": 25,
        }

        org = Organization(
            id=uuid4(),
            name="Test Org",
            slug="test-org",
            plan="pro",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
            limits=limits,
        )

        self.assertEqual(org.limits["api_calls_per_month"], 100000)
        self.assertEqual(org.limits["storage_gb"], 100)
        self.assertEqual(org.limits["seats"], 25)

    def test_organization_default_collections(self):
        """Test that settings and limits default to empty dicts."""
        org = Organization(
            id=uuid4(),
            name="Test Org",
            slug="test-org",
            plan="free",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )

        self.assertEqual(org.settings, {})
        self.assertEqual(org.limits, {})


class TestOrgMembership(unittest.TestCase):
    """Test OrgMembership dataclass."""

    def test_membership_creation(self):
        """Test creating an organization membership."""
        user_id = uuid4()
        org_id = uuid4()
        now = datetime.utcnow()

        membership = OrgMembership(
            user_id=user_id,
            org_id=org_id,
            role=UserRole.MEMBER,
            joined_at=now,
        )

        self.assertEqual(membership.user_id, user_id)
        self.assertEqual(membership.org_id, org_id)
        self.assertEqual(membership.role, UserRole.MEMBER)
        self.assertEqual(membership.joined_at, now)
        self.assertIsNone(membership.invited_by)

    def test_membership_with_invitation(self):
        """Test membership with inviter information."""
        user_id = uuid4()
        org_id = uuid4()
        inviter_id = uuid4()
        now = datetime.utcnow()

        membership = OrgMembership(
            user_id=user_id,
            org_id=org_id,
            role=UserRole.MEMBER,
            joined_at=now,
            invited_by=inviter_id,
        )

        self.assertEqual(membership.invited_by, inviter_id)

    def test_membership_all_roles(self):
        """Test creating memberships with different roles."""
        for role in UserRole:
            membership = OrgMembership(
                user_id=uuid4(),
                org_id=uuid4(),
                role=role,
                joined_at=datetime.utcnow(),
            )
            self.assertEqual(membership.role, role)


class TestOAuthAccount(unittest.TestCase):
    """Test OAuthAccount dataclass."""

    def test_oauth_account_creation(self):
        """Test creating an OAuth account."""
        account_id = uuid4()
        user_id = uuid4()
        now = datetime.utcnow()
        expires = now + timedelta(hours=1)

        oauth = OAuthAccount(
            id=account_id,
            user_id=user_id,
            provider="github",
            provider_user_id="12345",
            provider_username="testuser",
            access_token="access_token_xyz",
            refresh_token="refresh_token_abc",
            token_expires_at=expires,
            created_at=now,
            updated_at=now,
        )

        self.assertEqual(oauth.id, account_id)
        self.assertEqual(oauth.user_id, user_id)
        self.assertEqual(oauth.provider, "github")
        self.assertEqual(oauth.provider_user_id, "12345")
        self.assertEqual(oauth.provider_username, "testuser")
        self.assertEqual(oauth.access_token, "access_token_xyz")
        self.assertEqual(oauth.refresh_token, "refresh_token_abc")
        self.assertEqual(oauth.token_expires_at, expires)

    def test_oauth_different_providers(self):
        """Test OAuth accounts for different providers."""
        providers = ["github", "google", "microsoft", "gitlab"]

        for provider in providers:
            oauth = OAuthAccount(
                id=uuid4(),
                user_id=uuid4(),
                provider=provider,
                provider_user_id="12345",
                provider_username=None,
                access_token="token",
                refresh_token=None,
                token_expires_at=None,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            )
            self.assertEqual(oauth.provider, provider)

    def test_oauth_optional_fields(self):
        """Test OAuth account with optional fields as None."""
        oauth = OAuthAccount(
            id=uuid4(),
            user_id=uuid4(),
            provider="github",
            provider_user_id="12345",
            provider_username=None,
            access_token="token",
            refresh_token=None,
            token_expires_at=None,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )

        self.assertIsNone(oauth.provider_username)
        self.assertIsNone(oauth.refresh_token)
        self.assertIsNone(oauth.token_expires_at)


class TestAPIKey(unittest.TestCase):
    """Test APIKey dataclass."""

    def test_api_key_creation(self):
        """Test creating an API key."""
        key_id = uuid4()
        org_id = uuid4()
        user_id = uuid4()
        now = datetime.utcnow()

        api_key = APIKey(
            id=key_id,
            org_id=org_id,
            user_id=user_id,
            name="Production API Key",
            key_hash="hashed_key_xyz",
            key_prefix="uws_abcd",
            permissions=["tasks:read", "tasks:create"],
            last_used_at=None,
            expires_at=None,
            created_at=now,
            is_active=True,
        )

        self.assertEqual(api_key.id, key_id)
        self.assertEqual(api_key.org_id, org_id)
        self.assertEqual(api_key.user_id, user_id)
        self.assertEqual(api_key.name, "Production API Key")
        self.assertEqual(api_key.key_hash, "hashed_key_xyz")
        self.assertEqual(api_key.key_prefix, "uws_abcd")
        self.assertEqual(len(api_key.permissions), 2)
        self.assertTrue(api_key.is_active)

    def test_api_key_with_usage(self):
        """Test API key with usage information."""
        now = datetime.utcnow()
        last_used = now - timedelta(hours=2)

        api_key = APIKey(
            id=uuid4(),
            org_id=uuid4(),
            user_id=uuid4(),
            name="Test Key",
            key_hash="hash",
            key_prefix="uws_test",
            permissions=["tasks:read"],
            last_used_at=last_used,
            expires_at=None,
            created_at=now,
        )

        self.assertEqual(api_key.last_used_at, last_used)

    def test_api_key_with_expiration(self):
        """Test API key with expiration."""
        now = datetime.utcnow()
        expires = now + timedelta(days=30)

        api_key = APIKey(
            id=uuid4(),
            org_id=uuid4(),
            user_id=uuid4(),
            name="Temporary Key",
            key_hash="hash",
            key_prefix="uws_temp",
            permissions=["projects:read"],
            last_used_at=None,
            expires_at=expires,
            created_at=now,
        )

        self.assertEqual(api_key.expires_at, expires)

    def test_api_key_inactive(self):
        """Test creating an inactive API key."""
        api_key = APIKey(
            id=uuid4(),
            org_id=uuid4(),
            user_id=uuid4(),
            name="Revoked Key",
            key_hash="hash",
            key_prefix="uws_old",
            permissions=[],
            last_used_at=None,
            expires_at=None,
            created_at=datetime.utcnow(),
            is_active=False,
        )

        self.assertFalse(api_key.is_active)

    def test_api_key_default_active(self):
        """Test that API keys are active by default."""
        api_key = APIKey(
            id=uuid4(),
            org_id=uuid4(),
            user_id=uuid4(),
            name="New Key",
            key_hash="hash",
            key_prefix="uws_new",
            permissions=["tasks:read"],
            last_used_at=None,
            expires_at=None,
            created_at=datetime.utcnow(),
        )

        self.assertTrue(api_key.is_active)


class TestRefreshToken(unittest.TestCase):
    """Test RefreshToken dataclass."""

    def test_refresh_token_creation(self):
        """Test creating a refresh token."""
        token_id = uuid4()
        user_id = uuid4()
        now = datetime.utcnow()
        expires = now + timedelta(days=30)

        token = RefreshToken(
            id=token_id,
            user_id=user_id,
            token_hash="hashed_token_xyz",
            device_info="Chrome on macOS",
            ip_address="192.168.1.1",
            expires_at=expires,
            created_at=now,
        )

        self.assertEqual(token.id, token_id)
        self.assertEqual(token.user_id, user_id)
        self.assertEqual(token.token_hash, "hashed_token_xyz")
        self.assertEqual(token.device_info, "Chrome on macOS")
        self.assertEqual(token.ip_address, "192.168.1.1")
        self.assertEqual(token.expires_at, expires)
        self.assertEqual(token.created_at, now)
        self.assertIsNone(token.revoked_at)

    def test_refresh_token_optional_fields(self):
        """Test refresh token with optional fields as None."""
        token = RefreshToken(
            id=uuid4(),
            user_id=uuid4(),
            token_hash="hash",
            device_info=None,
            ip_address=None,
            expires_at=datetime.utcnow() + timedelta(days=30),
            created_at=datetime.utcnow(),
        )

        self.assertIsNone(token.device_info)
        self.assertIsNone(token.ip_address)

    def test_refresh_token_revoked(self):
        """Test revoking a refresh token."""
        now = datetime.utcnow()
        revoked = now + timedelta(hours=1)

        token = RefreshToken(
            id=uuid4(),
            user_id=uuid4(),
            token_hash="hash",
            device_info="Mobile App",
            ip_address="10.0.0.1",
            expires_at=now + timedelta(days=30),
            created_at=now,
            revoked_at=revoked,
        )

        self.assertEqual(token.revoked_at, revoked)
        self.assertIsNotNone(token.revoked_at)


class TestTokenPair(unittest.TestCase):
    """Test TokenPair dataclass."""

    def test_token_pair_creation(self):
        """Test creating a token pair."""
        pair = TokenPair(
            access_token="access_token_xyz",
            refresh_token="refresh_token_abc",
        )

        self.assertEqual(pair.access_token, "access_token_xyz")
        self.assertEqual(pair.refresh_token, "refresh_token_abc")
        self.assertEqual(pair.token_type, "bearer")
        self.assertEqual(pair.expires_in, 900)

    def test_token_pair_custom_values(self):
        """Test token pair with custom token type and expiration."""
        pair = TokenPair(
            access_token="token1",
            refresh_token="token2",
            token_type="Bearer",
            expires_in=3600,
        )

        self.assertEqual(pair.token_type, "Bearer")
        self.assertEqual(pair.expires_in, 3600)

    def test_token_pair_defaults(self):
        """Test token pair default values."""
        pair = TokenPair(
            access_token="access",
            refresh_token="refresh",
        )

        # Defaults: bearer and 900 seconds (15 minutes)
        self.assertEqual(pair.token_type, "bearer")
        self.assertEqual(pair.expires_in, 900)


class TestTokenPayload(unittest.TestCase):
    """Test TokenPayload dataclass."""

    def test_token_payload_creation(self):
        """Test creating a token payload."""
        user_id = str(uuid4())
        org_id = str(uuid4())
        token_id = str(uuid4())
        now = datetime.utcnow()
        exp = now + timedelta(minutes=15)

        payload = TokenPayload(
            sub=user_id,
            org_id=org_id,
            role="admin",
            permissions=["tasks:read", "tasks:create", "projects:read"],
            exp=exp,
            iat=now,
            jti=token_id,
        )

        self.assertEqual(payload.sub, user_id)
        self.assertEqual(payload.org_id, org_id)
        self.assertEqual(payload.role, "admin")
        self.assertEqual(len(payload.permissions), 3)
        self.assertEqual(payload.exp, exp)
        self.assertEqual(payload.iat, now)
        self.assertEqual(payload.jti, token_id)

    def test_token_payload_different_roles(self):
        """Test token payloads for different roles."""
        roles = ["owner", "admin", "member", "viewer"]

        for role in roles:
            payload = TokenPayload(
                sub=str(uuid4()),
                org_id=str(uuid4()),
                role=role,
                permissions=[],
                exp=datetime.utcnow() + timedelta(minutes=15),
                iat=datetime.utcnow(),
                jti=str(uuid4()),
            )
            self.assertEqual(payload.role, role)

    def test_token_payload_permissions_list(self):
        """Test that permissions are stored as a list."""
        payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="member",
            permissions=["tasks:read", "tasks:create"],
            exp=datetime.utcnow() + timedelta(minutes=15),
            iat=datetime.utcnow(),
            jti=str(uuid4()),
        )

        self.assertIsInstance(payload.permissions, list)
        self.assertIn("tasks:read", payload.permissions)
        self.assertIn("tasks:create", payload.permissions)

    def test_token_payload_expiration(self):
        """Test token payload expiration calculation."""
        now = datetime.utcnow()
        exp = now + timedelta(minutes=15)

        payload = TokenPayload(
            sub=str(uuid4()),
            org_id=str(uuid4()),
            role="viewer",
            permissions=["tasks:read"],
            exp=exp,
            iat=now,
            jti=str(uuid4()),
        )

        # Token should expire in approximately 15 minutes
        time_diff = (payload.exp - payload.iat).total_seconds()
        self.assertAlmostEqual(time_diff, 900, delta=1)


if __name__ == "__main__":
    unittest.main()
