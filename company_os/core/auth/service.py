"""
Authentication Service.

Handles user authentication, token management, and authorization.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID, uuid4
import secrets
import hashlib

import asyncpg
from passlib.context import CryptContext
import jwt

from ..config.settings import Settings
from .models import (
    User, Organization, OrgMembership, OAuthAccount, APIKey,
    RefreshToken, TokenPair, TokenPayload, UserRole, Permission,
    ROLE_PERMISSIONS
)


class AuthenticationError(Exception):
    """Authentication failed."""
    pass


class AuthorizationError(Exception):
    """Authorization failed."""
    pass


class AuthService:
    """
    Authentication and authorization service.

    Features:
    - Password hashing with bcrypt
    - JWT access tokens (short-lived)
    - Refresh token rotation
    - GitHub OAuth integration
    - Role-based access control (RBAC)
    """

    def __init__(self, pool: asyncpg.Pool, settings: Settings):
        self.pool = pool
        self.settings = settings
        self.pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

    # Password handling

    def hash_password(self, password: str) -> str:
        """Hash a password using bcrypt."""
        return self.pwd_context.hash(password)

    def verify_password(self, plain_password: str, hashed_password: str) -> bool:
        """Verify a password against its hash."""
        return self.pwd_context.verify(plain_password, hashed_password)

    # User management

    async def create_user(
        self,
        email: str,
        name: str,
        password: Optional[str] = None,
        org_name: Optional[str] = None
    ) -> tuple[User, Organization]:
        """
        Create a new user and their default organization.

        Args:
            email: User's email
            name: User's display name
            password: Password (optional for OAuth users)
            org_name: Organization name (defaults to user's name)

        Returns:
            Tuple of (User, Organization)
        """
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                # Create user
                user_id = uuid4()
                now = datetime.now(timezone.utc)

                password_hash = self.hash_password(password) if password else None

                user_row = await conn.fetchrow(
                    """
                    INSERT INTO users
                    (id, email, name, password_hash, is_active, is_verified, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, true, false, $5, $5)
                    RETURNING id, email, name, password_hash, is_active, is_verified,
                              created_at, updated_at, last_login, avatar_url, preferences
                    """,
                    user_id, email, name, password_hash, now
                )

                # Create default organization
                org_id = uuid4()
                org_slug = self._generate_slug(org_name or name)

                org_row = await conn.fetchrow(
                    """
                    INSERT INTO organizations
                    (id, name, slug, plan, created_at, updated_at, settings, limits)
                    VALUES ($1, $2, $3, 'free', $4, $4, '{}', '{}')
                    RETURNING id, name, slug, plan, created_at, updated_at, settings, limits
                    """,
                    org_id, org_name or f"{name}'s Workspace", org_slug, now
                )

                # Add user as org owner
                await conn.execute(
                    """
                    INSERT INTO org_memberships
                    (user_id, org_id, role, joined_at)
                    VALUES ($1, $2, $3, $4)
                    """,
                    user_id, org_id, UserRole.OWNER.value, now
                )

                user = User(
                    id=user_row["id"],
                    email=user_row["email"],
                    name=user_row["name"],
                    password_hash=user_row["password_hash"],
                    is_active=user_row["is_active"],
                    is_verified=user_row["is_verified"],
                    created_at=user_row["created_at"],
                    updated_at=user_row["updated_at"],
                    last_login=user_row["last_login"],
                    avatar_url=user_row["avatar_url"],
                    preferences=user_row["preferences"] or {}
                )

                org = Organization(
                    id=org_row["id"],
                    name=org_row["name"],
                    slug=org_row["slug"],
                    plan=org_row["plan"],
                    created_at=org_row["created_at"],
                    updated_at=org_row["updated_at"],
                    settings=org_row["settings"] or {},
                    limits=org_row["limits"] or {}
                )

                return user, org

    async def get_user_by_email(self, email: str) -> Optional[User]:
        """Get user by email."""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT id, email, name, password_hash, is_active, is_verified,
                       created_at, updated_at, last_login, avatar_url, preferences
                FROM users WHERE email = $1
                """,
                email
            )

            if not row:
                return None

            return User(
                id=row["id"],
                email=row["email"],
                name=row["name"],
                password_hash=row["password_hash"],
                is_active=row["is_active"],
                is_verified=row["is_verified"],
                created_at=row["created_at"],
                updated_at=row["updated_at"],
                last_login=row["last_login"],
                avatar_url=row["avatar_url"],
                preferences=row["preferences"] or {}
            )

    async def get_user_by_id(self, user_id: UUID) -> Optional[User]:
        """Get user by ID."""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT id, email, name, password_hash, is_active, is_verified,
                       created_at, updated_at, last_login, avatar_url, preferences
                FROM users WHERE id = $1
                """,
                user_id
            )

            if not row:
                return None

            return User(
                id=row["id"],
                email=row["email"],
                name=row["name"],
                password_hash=row["password_hash"],
                is_active=row["is_active"],
                is_verified=row["is_verified"],
                created_at=row["created_at"],
                updated_at=row["updated_at"],
                last_login=row["last_login"],
                avatar_url=row["avatar_url"],
                preferences=row["preferences"] or {}
            )

    # Authentication

    async def authenticate(
        self,
        email: str,
        password: str
    ) -> tuple[User, Organization]:
        """
        Authenticate user with email and password.

        Returns:
            Tuple of (User, default Organization)

        Raises:
            AuthenticationError: If credentials invalid
        """
        user = await self.get_user_by_email(email)

        if not user or not user.password_hash:
            raise AuthenticationError("Invalid email or password")

        if not self.verify_password(password, user.password_hash):
            raise AuthenticationError("Invalid email or password")

        if not user.is_active:
            raise AuthenticationError("Account is disabled")

        # Get default organization
        org = await self._get_user_default_org(user.id)

        # Update last login
        await self._update_last_login(user.id)

        return user, org

    async def _get_user_default_org(self, user_id: UUID) -> Organization:
        """Get user's default (first) organization."""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT o.id, o.name, o.slug, o.plan, o.created_at,
                       o.updated_at, o.settings, o.limits
                FROM organizations o
                JOIN org_memberships m ON o.id = m.org_id
                WHERE m.user_id = $1
                ORDER BY m.joined_at ASC
                LIMIT 1
                """,
                user_id
            )

            if not row:
                raise AuthenticationError("User has no organization")

            return Organization(
                id=row["id"],
                name=row["name"],
                slug=row["slug"],
                plan=row["plan"],
                created_at=row["created_at"],
                updated_at=row["updated_at"],
                settings=row["settings"] or {},
                limits=row["limits"] or {}
            )

    async def _update_last_login(self, user_id: UUID) -> None:
        """Update user's last login timestamp."""
        async with self.pool.acquire() as conn:
            await conn.execute(
                "UPDATE users SET last_login = $1 WHERE id = $2",
                datetime.now(timezone.utc),
                user_id
            )

    # Token management

    async def create_tokens(
        self,
        user: User,
        org: Organization,
        device_info: Optional[str] = None,
        ip_address: Optional[str] = None
    ) -> TokenPair:
        """
        Create access and refresh token pair.

        Args:
            user: Authenticated user
            org: User's organization
            device_info: Optional device identifier
            ip_address: Optional IP address

        Returns:
            TokenPair with access and refresh tokens
        """
        # Get user role in organization
        role = await self._get_user_role(user.id, org.id)
        permissions = [p.value for p in ROLE_PERMISSIONS.get(role, set())]

        now = datetime.now(timezone.utc)
        jti = str(uuid4())

        # Create access token
        access_payload = {
            "sub": str(user.id),
            "org_id": str(org.id),
            "role": role.value,
            "permissions": permissions,
            "exp": now + timedelta(minutes=self.settings.access_token_expire_minutes),
            "iat": now,
            "jti": jti
        }

        access_token = jwt.encode(
            access_payload,
            self.settings.jwt_secret_key,
            algorithm=self.settings.jwt_algorithm
        )

        # Create refresh token
        refresh_token = secrets.token_urlsafe(32)
        refresh_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
        refresh_expires = now + timedelta(days=self.settings.refresh_token_expire_days)

        # Store refresh token
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO refresh_tokens
                (id, user_id, token_hash, device_info, ip_address, expires_at, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                """,
                uuid4(), user.id, refresh_hash, device_info, ip_address, refresh_expires, now
            )

        return TokenPair(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=self.settings.access_token_expire_minutes * 60
        )

    async def refresh_tokens(
        self,
        refresh_token: str,
        device_info: Optional[str] = None,
        ip_address: Optional[str] = None
    ) -> TokenPair:
        """
        Refresh tokens using a valid refresh token.

        Implements token rotation: old refresh token is invalidated.

        Args:
            refresh_token: Current refresh token
            device_info: Optional device identifier
            ip_address: Optional IP address

        Returns:
            New TokenPair

        Raises:
            AuthenticationError: If refresh token invalid
        """
        token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
        now = datetime.now(timezone.utc)

        async with self.pool.acquire() as conn:
            # Find and validate refresh token
            row = await conn.fetchrow(
                """
                SELECT id, user_id, expires_at, revoked_at
                FROM refresh_tokens
                WHERE token_hash = $1
                """,
                token_hash
            )

            if not row:
                raise AuthenticationError("Invalid refresh token")

            if row["revoked_at"]:
                raise AuthenticationError("Refresh token has been revoked")

            if row["expires_at"] < now:
                raise AuthenticationError("Refresh token has expired")

            # Revoke old token (rotation)
            await conn.execute(
                "UPDATE refresh_tokens SET revoked_at = $1 WHERE id = $2",
                now, row["id"]
            )

        # Get user and org
        user = await self.get_user_by_id(row["user_id"])
        if not user or not user.is_active:
            raise AuthenticationError("User not found or inactive")

        org = await self._get_user_default_org(user.id)

        # Create new tokens
        return await self.create_tokens(user, org, device_info, ip_address)

    async def verify_access_token(self, token: str) -> TokenPayload:
        """
        Verify and decode an access token.

        Args:
            token: JWT access token

        Returns:
            TokenPayload with user claims

        Raises:
            AuthenticationError: If token invalid
        """
        try:
            payload = jwt.decode(
                token,
                self.settings.jwt_secret_key,
                algorithms=[self.settings.jwt_algorithm]
            )

            return TokenPayload(
                sub=payload["sub"],
                org_id=payload["org_id"],
                role=payload["role"],
                permissions=payload["permissions"],
                exp=datetime.fromtimestamp(payload["exp"], tz=timezone.utc),
                iat=datetime.fromtimestamp(payload["iat"], tz=timezone.utc),
                jti=payload["jti"]
            )

        except jwt.ExpiredSignatureError:
            raise AuthenticationError("Token has expired")
        except jwt.InvalidTokenError as e:
            raise AuthenticationError(f"Invalid token: {e}")

    async def revoke_refresh_token(self, refresh_token: str) -> None:
        """Revoke a refresh token (logout)."""
        token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()

        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE refresh_tokens
                SET revoked_at = $1
                WHERE token_hash = $2 AND revoked_at IS NULL
                """,
                datetime.now(timezone.utc),
                token_hash
            )

    # Authorization

    async def _get_user_role(self, user_id: UUID, org_id: UUID) -> UserRole:
        """Get user's role in an organization."""
        async with self.pool.acquire() as conn:
            role = await conn.fetchval(
                """
                SELECT role FROM org_memberships
                WHERE user_id = $1 AND org_id = $2
                """,
                user_id, org_id
            )

            if not role:
                raise AuthorizationError("User not member of organization")

            return UserRole(role)

    def check_permission(
        self,
        token_payload: TokenPayload,
        required_permission: Permission
    ) -> bool:
        """Check if token has required permission."""
        return required_permission.value in token_payload.permissions

    def require_permission(
        self,
        token_payload: TokenPayload,
        required_permission: Permission
    ) -> None:
        """
        Require a specific permission.

        Raises:
            AuthorizationError: If permission not granted
        """
        if not self.check_permission(token_payload, required_permission):
            raise AuthorizationError(
                f"Permission denied: {required_permission.value} required"
            )

    # Utilities

    def _generate_slug(self, name: str) -> str:
        """Generate URL-safe slug from name."""
        slug = name.lower()
        slug = "".join(c if c.isalnum() else "-" for c in slug)
        slug = "-".join(filter(None, slug.split("-")))
        return f"{slug}-{secrets.token_hex(4)}"
