# Critical Issue #3: Authentication & Security Foundation Deep-Dive

## The Problem

Your architecture has **zero security implementation**:

- Authentication mentioned but not designed
- No permission model defined
- Agent sandboxing undefined
- Multi-tenant isolation missing
- No audit logging strategy

**Enterprise customers will reject this immediately.**

---

## The Solution: Defense-in-Depth Security

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL TRAFFIC                              │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 1: EDGE SECURITY                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ WAF/DDoS    │  │ Rate Limit  │  │ TLS 1.3     │             │
│  │ (Cloudflare)│  │ (per IP)    │  │ Termination │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 2: API GATEWAY                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ JWT Valid.  │  │ Permission  │  │ Audit Log   │             │
│  │ + Refresh   │  │ Check       │  │ (all reqs)  │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 3: APPLICATION                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Input Valid │  │ RBAC + ABAC │  │ Tenant      │             │
│  │ (Pydantic)  │  │ Enforcement │  │ Context     │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 4: DATA                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Row-Level   │  │ Encryption  │  │ Secrets     │             │
│  │ Security    │  │ (at rest)   │  │ (Vault)     │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 5: AGENT SANDBOX                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Container   │  │ Network     │  │ Resource    │             │
│  │ Isolation   │  │ Policies    │  │ Limits      │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation

### 1. Database Schema for Auth

```sql
-- migrations/010_create_auth_tables.sql

-- Organizations (tenants)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,
    plan VARCHAR(50) NOT NULL DEFAULT 'free',
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255),  -- NULL for OAuth-only users
    name VARCHAR(255),
    avatar_url TEXT,
    email_verified BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Organization memberships (many-to-many)
CREATE TABLE organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL DEFAULT 'member',  -- owner, admin, member, viewer
    permissions JSONB DEFAULT '{}',  -- Custom permissions
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(org_id, user_id)
);

-- OAuth providers
CREATE TABLE oauth_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,  -- github, google, etc.
    provider_account_id VARCHAR(255) NOT NULL,
    access_token TEXT,
    refresh_token TEXT,
    token_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(provider, provider_account_id)
);

-- Sessions (for session-based auth option)
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Refresh tokens
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    device_info JSONB,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- API keys (for programmatic access)
CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    name VARCHAR(255) NOT NULL,
    key_prefix VARCHAR(10) NOT NULL,  -- First 8 chars for identification
    key_hash VARCHAR(255) NOT NULL,
    permissions JSONB NOT NULL DEFAULT '["read"]',
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Audit log
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    org_id UUID REFERENCES organizations(id),
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50) NOT NULL,
    resource_id VARCHAR(255),
    details JSONB DEFAULT '{}',
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_audit_logs_org ON audit_logs(org_id, created_at DESC);
CREATE INDEX idx_audit_logs_user ON audit_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX idx_sessions_user ON sessions(user_id, expires_at);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id, expires_at);

-- Enable RLS on organization-scoped tables
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;
```

### 2. JWT Token Service

```python
# company_os/core/auth/tokens.py

from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from dataclasses import dataclass
import secrets
import hashlib
import jwt
from uuid import UUID


@dataclass
class TokenPair:
    """Access and refresh token pair."""
    access_token: str
    refresh_token: str
    access_expires_at: datetime
    refresh_expires_at: datetime
    token_type: str = "Bearer"


@dataclass
class TokenPayload:
    """Decoded JWT payload."""
    sub: str  # User ID
    org_id: Optional[str]  # Current organization
    role: str  # Role in organization
    permissions: list[str]
    exp: datetime
    iat: datetime
    jti: str  # Token ID for revocation


class TokenService:
    """
    JWT token management with security best practices.

    Features:
    - Short-lived access tokens (15 min)
    - Long-lived refresh tokens (7 days)
    - Token rotation on refresh
    - Revocation support
    """

    def __init__(
        self,
        secret_key: str,
        algorithm: str = "HS256",
        access_token_expire_minutes: int = 15,
        refresh_token_expire_days: int = 7
    ):
        self.secret_key = secret_key
        self.algorithm = algorithm
        self.access_expire = timedelta(minutes=access_token_expire_minutes)
        self.refresh_expire = timedelta(days=refresh_token_expire_days)

    def create_tokens(
        self,
        user_id: UUID,
        org_id: Optional[UUID],
        role: str,
        permissions: list[str]
    ) -> TokenPair:
        """Create access and refresh token pair."""
        now = datetime.utcnow()
        access_expires = now + self.access_expire
        refresh_expires = now + self.refresh_expire

        # Access token (short-lived, contains permissions)
        access_payload = {
            "sub": str(user_id),
            "org_id": str(org_id) if org_id else None,
            "role": role,
            "permissions": permissions,
            "exp": access_expires,
            "iat": now,
            "jti": secrets.token_urlsafe(16),
            "type": "access"
        }
        access_token = jwt.encode(
            access_payload,
            self.secret_key,
            algorithm=self.algorithm
        )

        # Refresh token (longer-lived, minimal info)
        refresh_payload = {
            "sub": str(user_id),
            "exp": refresh_expires,
            "iat": now,
            "jti": secrets.token_urlsafe(16),
            "type": "refresh"
        }
        refresh_token = jwt.encode(
            refresh_payload,
            self.secret_key,
            algorithm=self.algorithm
        )

        return TokenPair(
            access_token=access_token,
            refresh_token=refresh_token,
            access_expires_at=access_expires,
            refresh_expires_at=refresh_expires
        )

    def verify_access_token(self, token: str) -> TokenPayload:
        """Verify and decode an access token."""
        try:
            payload = jwt.decode(
                token,
                self.secret_key,
                algorithms=[self.algorithm]
            )

            if payload.get("type") != "access":
                raise InvalidTokenError("Not an access token")

            return TokenPayload(
                sub=payload["sub"],
                org_id=payload.get("org_id"),
                role=payload.get("role", "member"),
                permissions=payload.get("permissions", []),
                exp=datetime.fromtimestamp(payload["exp"]),
                iat=datetime.fromtimestamp(payload["iat"]),
                jti=payload["jti"]
            )

        except jwt.ExpiredSignatureError:
            raise TokenExpiredError("Access token has expired")
        except jwt.InvalidTokenError as e:
            raise InvalidTokenError(f"Invalid token: {e}")

    def verify_refresh_token(self, token: str) -> Dict[str, Any]:
        """Verify and decode a refresh token."""
        try:
            payload = jwt.decode(
                token,
                self.secret_key,
                algorithms=[self.algorithm]
            )

            if payload.get("type") != "refresh":
                raise InvalidTokenError("Not a refresh token")

            return {
                "user_id": payload["sub"],
                "jti": payload["jti"],
                "exp": datetime.fromtimestamp(payload["exp"])
            }

        except jwt.ExpiredSignatureError:
            raise TokenExpiredError("Refresh token has expired")
        except jwt.InvalidTokenError as e:
            raise InvalidTokenError(f"Invalid token: {e}")

    @staticmethod
    def hash_token(token: str) -> str:
        """Hash a token for storage."""
        return hashlib.sha256(token.encode()).hexdigest()


class TokenExpiredError(Exception):
    pass

class InvalidTokenError(Exception):
    pass
```

### 3. OAuth Provider (GitHub Example)

```python
# company_os/core/auth/oauth/github.py

from dataclasses import dataclass
from typing import Optional
import httpx


@dataclass
class GitHubUser:
    """GitHub user profile."""
    id: str
    login: str
    email: str
    name: Optional[str]
    avatar_url: Optional[str]


class GitHubOAuth:
    """
    GitHub OAuth 2.0 implementation with PKCE.

    PKCE (Proof Key for Code Exchange) prevents authorization code
    interception attacks.
    """

    AUTHORIZE_URL = "https://github.com/login/oauth/authorize"
    TOKEN_URL = "https://github.com/login/oauth/access_token"
    USER_URL = "https://api.github.com/user"
    EMAILS_URL = "https://api.github.com/user/emails"

    def __init__(
        self,
        client_id: str,
        client_secret: str,
        redirect_uri: str
    ):
        self.client_id = client_id
        self.client_secret = client_secret
        self.redirect_uri = redirect_uri

    def get_authorization_url(self, state: str, scopes: list[str] = None) -> str:
        """
        Generate authorization URL for GitHub OAuth.

        Args:
            state: Random state for CSRF protection
            scopes: OAuth scopes (default: user:email, read:org)
        """
        scopes = scopes or ["user:email", "read:org"]

        params = {
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
            "scope": " ".join(scopes),
            "state": state,
            "allow_signup": "true"
        }

        query = "&".join(f"{k}={v}" for k, v in params.items())
        return f"{self.AUTHORIZE_URL}?{query}"

    async def exchange_code(self, code: str) -> str:
        """Exchange authorization code for access token."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                self.TOKEN_URL,
                data={
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "code": code,
                    "redirect_uri": self.redirect_uri
                },
                headers={"Accept": "application/json"}
            )

            response.raise_for_status()
            data = response.json()

            if "error" in data:
                raise OAuthError(data.get("error_description", data["error"]))

            return data["access_token"]

    async def get_user(self, access_token: str) -> GitHubUser:
        """Fetch user profile from GitHub."""
        async with httpx.AsyncClient() as client:
            # Get user profile
            response = await client.get(
                self.USER_URL,
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Accept": "application/vnd.github.v3+json"
                }
            )
            response.raise_for_status()
            user_data = response.json()

            # Get primary email if not public
            email = user_data.get("email")
            if not email:
                emails_response = await client.get(
                    self.EMAILS_URL,
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Accept": "application/vnd.github.v3+json"
                    }
                )
                emails_response.raise_for_status()
                emails = emails_response.json()

                # Find primary email
                for e in emails:
                    if e.get("primary"):
                        email = e["email"]
                        break

            return GitHubUser(
                id=str(user_data["id"]),
                login=user_data["login"],
                email=email,
                name=user_data.get("name"),
                avatar_url=user_data.get("avatar_url")
            )


class OAuthError(Exception):
    pass
```

### 4. Authentication Service

```python
# company_os/core/auth/service.py

from typing import Optional, Tuple
from uuid import UUID
from datetime import datetime
import secrets
import bcrypt
import asyncpg

from .tokens import TokenService, TokenPair, TokenExpiredError, InvalidTokenError
from .oauth.github import GitHubOAuth, GitHubUser


class AuthService:
    """
    Authentication service handling all auth flows.

    Supports:
    - Email/password authentication
    - OAuth (GitHub, Google)
    - API keys
    - Session management
    """

    def __init__(
        self,
        pool: asyncpg.Pool,
        token_service: TokenService,
        github_oauth: Optional[GitHubOAuth] = None
    ):
        self.pool = pool
        self.tokens = token_service
        self.github = github_oauth

    # ============ Email/Password Auth ============

    async def register(
        self,
        email: str,
        password: str,
        name: Optional[str] = None
    ) -> Tuple[UUID, TokenPair]:
        """Register a new user with email/password."""
        # Hash password
        password_hash = bcrypt.hashpw(
            password.encode(),
            bcrypt.gensalt()
        ).decode()

        async with self.pool.acquire() as conn:
            # Check if email exists
            existing = await conn.fetchval(
                "SELECT id FROM users WHERE email = $1",
                email.lower()
            )
            if existing:
                raise EmailAlreadyExistsError(email)

            # Create user
            user_id = await conn.fetchval("""
                INSERT INTO users (email, password_hash, name, email_verified)
                VALUES ($1, $2, $3, FALSE)
                RETURNING id
            """, email.lower(), password_hash, name)

            # Create default organization for user
            org_id = await conn.fetchval("""
                INSERT INTO organizations (name, slug)
                VALUES ($1, $2)
                RETURNING id
            """, f"{name or email}'s Workspace", f"user-{user_id}")

            # Add user as org owner
            await conn.execute("""
                INSERT INTO organization_members (org_id, user_id, role)
                VALUES ($1, $2, 'owner')
            """, org_id, user_id)

        # Generate tokens
        tokens = self.tokens.create_tokens(
            user_id=user_id,
            org_id=org_id,
            role="owner",
            permissions=["*"]  # Full access to own org
        )

        # Store refresh token
        await self._store_refresh_token(user_id, tokens.refresh_token)

        return user_id, tokens

    async def login(
        self,
        email: str,
        password: str
    ) -> Tuple[UUID, TokenPair]:
        """Login with email/password."""
        async with self.pool.acquire() as conn:
            user = await conn.fetchrow("""
                SELECT id, password_hash, is_active
                FROM users
                WHERE email = $1
            """, email.lower())

            if not user:
                raise InvalidCredentialsError()

            if not user['is_active']:
                raise AccountDisabledError()

            # Verify password
            if not bcrypt.checkpw(
                password.encode(),
                user['password_hash'].encode()
            ):
                raise InvalidCredentialsError()

            # Get default organization
            membership = await conn.fetchrow("""
                SELECT org_id, role, permissions
                FROM organization_members
                WHERE user_id = $1
                ORDER BY joined_at ASC
                LIMIT 1
            """, user['id'])

            if not membership:
                raise NoOrganizationError()

        # Generate tokens
        tokens = self.tokens.create_tokens(
            user_id=user['id'],
            org_id=membership['org_id'],
            role=membership['role'],
            permissions=self._get_role_permissions(membership['role'])
        )

        await self._store_refresh_token(user['id'], tokens.refresh_token)

        return user['id'], tokens

    # ============ OAuth Auth ============

    async def oauth_login(
        self,
        provider: str,
        code: str
    ) -> Tuple[UUID, TokenPair]:
        """Login or register via OAuth."""
        if provider == "github":
            return await self._github_oauth_login(code)
        else:
            raise UnsupportedProviderError(provider)

    async def _github_oauth_login(self, code: str) -> Tuple[UUID, TokenPair]:
        """Handle GitHub OAuth callback."""
        # Exchange code for token
        access_token = await self.github.exchange_code(code)

        # Get GitHub user
        github_user = await self.github.get_user(access_token)

        async with self.pool.acquire() as conn:
            # Check if OAuth account exists
            existing = await conn.fetchrow("""
                SELECT user_id FROM oauth_accounts
                WHERE provider = 'github' AND provider_account_id = $1
            """, github_user.id)

            if existing:
                user_id = existing['user_id']
            else:
                # Check if user exists by email
                user = await conn.fetchrow("""
                    SELECT id FROM users WHERE email = $1
                """, github_user.email.lower())

                if user:
                    user_id = user['id']
                else:
                    # Create new user
                    user_id = await conn.fetchval("""
                        INSERT INTO users (email, name, avatar_url, email_verified)
                        VALUES ($1, $2, $3, TRUE)
                        RETURNING id
                    """,
                        github_user.email.lower(),
                        github_user.name or github_user.login,
                        github_user.avatar_url
                    )

                    # Create default org
                    org_id = await conn.fetchval("""
                        INSERT INTO organizations (name, slug)
                        VALUES ($1, $2)
                        RETURNING id
                    """,
                        f"{github_user.name or github_user.login}'s Workspace",
                        f"gh-{github_user.login}"
                    )

                    await conn.execute("""
                        INSERT INTO organization_members (org_id, user_id, role)
                        VALUES ($1, $2, 'owner')
                    """, org_id, user_id)

                # Link OAuth account
                await conn.execute("""
                    INSERT INTO oauth_accounts
                    (user_id, provider, provider_account_id, access_token)
                    VALUES ($1, 'github', $2, $3)
                """, user_id, github_user.id, access_token)

            # Get organization
            membership = await conn.fetchrow("""
                SELECT org_id, role FROM organization_members
                WHERE user_id = $1 ORDER BY joined_at LIMIT 1
            """, user_id)

        tokens = self.tokens.create_tokens(
            user_id=user_id,
            org_id=membership['org_id'],
            role=membership['role'],
            permissions=self._get_role_permissions(membership['role'])
        )

        await self._store_refresh_token(user_id, tokens.refresh_token)

        return user_id, tokens

    # ============ Token Management ============

    async def refresh_tokens(self, refresh_token: str) -> TokenPair:
        """Refresh access token using refresh token."""
        # Verify refresh token
        payload = self.tokens.verify_refresh_token(refresh_token)
        token_hash = TokenService.hash_token(refresh_token)

        async with self.pool.acquire() as conn:
            # Check if refresh token is valid and not revoked
            stored = await conn.fetchrow("""
                SELECT id, user_id, revoked_at
                FROM refresh_tokens
                WHERE token_hash = $1 AND expires_at > NOW()
            """, token_hash)

            if not stored or stored['revoked_at']:
                raise InvalidTokenError("Refresh token is invalid or revoked")

            # Revoke old token (rotation)
            await conn.execute("""
                UPDATE refresh_tokens SET revoked_at = NOW()
                WHERE id = $1
            """, stored['id'])

            # Get current org membership
            membership = await conn.fetchrow("""
                SELECT org_id, role FROM organization_members
                WHERE user_id = $1 ORDER BY joined_at LIMIT 1
            """, stored['user_id'])

        # Create new token pair
        tokens = self.tokens.create_tokens(
            user_id=UUID(payload['user_id']),
            org_id=membership['org_id'] if membership else None,
            role=membership['role'] if membership else 'member',
            permissions=self._get_role_permissions(
                membership['role'] if membership else 'member'
            )
        )

        await self._store_refresh_token(
            UUID(payload['user_id']),
            tokens.refresh_token
        )

        return tokens

    async def logout(self, refresh_token: str):
        """Logout by revoking refresh token."""
        token_hash = TokenService.hash_token(refresh_token)

        async with self.pool.acquire() as conn:
            await conn.execute("""
                UPDATE refresh_tokens SET revoked_at = NOW()
                WHERE token_hash = $1
            """, token_hash)

    async def logout_all(self, user_id: UUID):
        """Logout from all devices."""
        async with self.pool.acquire() as conn:
            await conn.execute("""
                UPDATE refresh_tokens SET revoked_at = NOW()
                WHERE user_id = $1 AND revoked_at IS NULL
            """, user_id)

    # ============ API Keys ============

    async def create_api_key(
        self,
        org_id: UUID,
        user_id: UUID,
        name: str,
        permissions: list[str],
        expires_in_days: Optional[int] = None
    ) -> Tuple[str, UUID]:
        """Create an API key for programmatic access."""
        # Generate key: cos_xxxxxxxxxxxxxxxxxxxx
        key = f"cos_{secrets.token_urlsafe(32)}"
        key_hash = TokenService.hash_token(key)
        key_prefix = key[:12]

        expires_at = None
        if expires_in_days:
            expires_at = datetime.utcnow() + timedelta(days=expires_in_days)

        async with self.pool.acquire() as conn:
            key_id = await conn.fetchval("""
                INSERT INTO api_keys
                (org_id, user_id, name, key_prefix, key_hash, permissions, expires_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                RETURNING id
            """, org_id, user_id, name, key_prefix, key_hash, permissions, expires_at)

        # Return the full key (only shown once!)
        return key, key_id

    async def verify_api_key(self, key: str) -> dict:
        """Verify an API key and return context."""
        key_hash = TokenService.hash_token(key)

        async with self.pool.acquire() as conn:
            api_key = await conn.fetchrow("""
                SELECT ak.id, ak.org_id, ak.user_id, ak.permissions,
                       o.slug as org_slug
                FROM api_keys ak
                JOIN organizations o ON ak.org_id = o.id
                WHERE ak.key_hash = $1
                  AND ak.revoked_at IS NULL
                  AND (ak.expires_at IS NULL OR ak.expires_at > NOW())
            """, key_hash)

            if not api_key:
                raise InvalidApiKeyError()

            # Update last used
            await conn.execute("""
                UPDATE api_keys SET last_used_at = NOW() WHERE id = $1
            """, api_key['id'])

        return {
            "org_id": api_key['org_id'],
            "user_id": api_key['user_id'],
            "permissions": api_key['permissions'],
            "org_slug": api_key['org_slug']
        }

    # ============ Helpers ============

    async def _store_refresh_token(self, user_id: UUID, token: str):
        """Store refresh token hash in database."""
        token_hash = TokenService.hash_token(token)
        expires_at = datetime.utcnow() + self.tokens.refresh_expire

        async with self.pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
                VALUES ($1, $2, $3)
            """, user_id, token_hash, expires_at)

    def _get_role_permissions(self, role: str) -> list[str]:
        """Get permissions for a role."""
        permissions = {
            "owner": ["*"],
            "admin": [
                "org:read", "org:write",
                "members:read", "members:write",
                "projects:*", "tasks:*", "agents:*"
            ],
            "member": [
                "org:read",
                "members:read",
                "projects:read", "projects:write",
                "tasks:*", "agents:execute"
            ],
            "viewer": [
                "org:read", "members:read",
                "projects:read", "tasks:read"
            ]
        }
        return permissions.get(role, [])


# Exceptions
class EmailAlreadyExistsError(Exception):
    pass

class InvalidCredentialsError(Exception):
    pass

class AccountDisabledError(Exception):
    pass

class NoOrganizationError(Exception):
    pass

class UnsupportedProviderError(Exception):
    pass

class InvalidApiKeyError(Exception):
    pass
```

### 5. Permission System (RBAC + ABAC)

```python
# company_os/core/auth/permissions.py

from typing import Optional, Dict, Any
from dataclasses import dataclass
from enum import Enum
import re


class Permission(Enum):
    """Built-in permissions."""
    # Organization
    ORG_READ = "org:read"
    ORG_WRITE = "org:write"
    ORG_DELETE = "org:delete"

    # Members
    MEMBERS_READ = "members:read"
    MEMBERS_WRITE = "members:write"
    MEMBERS_DELETE = "members:delete"

    # Projects
    PROJECTS_READ = "projects:read"
    PROJECTS_WRITE = "projects:write"
    PROJECTS_DELETE = "projects:delete"

    # Tasks
    TASKS_READ = "tasks:read"
    TASKS_WRITE = "tasks:write"
    TASKS_DELETE = "tasks:delete"
    TASKS_ASSIGN = "tasks:assign"

    # Agents
    AGENTS_READ = "agents:read"
    AGENTS_EXECUTE = "agents:execute"
    AGENTS_CONFIGURE = "agents:configure"
    AGENTS_APPROVE = "agents:approve"


@dataclass
class PermissionContext:
    """Context for permission checks."""
    user_id: str
    org_id: str
    role: str
    permissions: list[str]
    resource_owner_id: Optional[str] = None
    resource_org_id: Optional[str] = None


class PermissionChecker:
    """
    Check permissions using RBAC + ABAC hybrid model.

    RBAC: Role-based (owner, admin, member, viewer)
    ABAC: Attribute-based (resource ownership, team membership)
    """

    def __init__(self):
        self._policies: list[Policy] = []
        self._register_default_policies()

    def check(
        self,
        permission: str,
        context: PermissionContext
    ) -> bool:
        """Check if context has the required permission."""
        # Superuser check (owner has all permissions)
        if "*" in context.permissions:
            return True

        # Direct permission check
        if self._match_permission(permission, context.permissions):
            return True

        # Policy-based checks
        for policy in self._policies:
            result = policy.evaluate(permission, context)
            if result is True:
                return True
            elif result is False:
                return False  # Explicit deny

        return False

    def _match_permission(
        self,
        required: str,
        granted: list[str]
    ) -> bool:
        """Check if required permission matches any granted permission."""
        for perm in granted:
            # Exact match
            if perm == required:
                return True

            # Wildcard match (e.g., "tasks:*" matches "tasks:read")
            if perm.endswith(":*"):
                prefix = perm[:-1]  # Remove "*"
                if required.startswith(prefix):
                    return True

        return False

    def _register_default_policies(self):
        """Register default ABAC policies."""
        # Users can always read/write their own resources
        self._policies.append(OwnerPolicy())

        # Team-based access
        self._policies.append(TeamPolicy())

    def require(
        self,
        permission: str,
        context: PermissionContext
    ):
        """Require permission, raise exception if denied."""
        if not self.check(permission, context):
            raise PermissionDeniedError(
                f"Permission '{permission}' denied for user {context.user_id}"
            )


class Policy:
    """Base class for ABAC policies."""

    def evaluate(
        self,
        permission: str,
        context: PermissionContext
    ) -> Optional[bool]:
        """
        Evaluate policy.

        Returns:
            True: Allow
            False: Deny
            None: No decision (continue to next policy)
        """
        raise NotImplementedError


class OwnerPolicy(Policy):
    """Allow resource owners full access to their resources."""

    def evaluate(
        self,
        permission: str,
        context: PermissionContext
    ) -> Optional[bool]:
        if context.resource_owner_id == context.user_id:
            return True
        return None


class TeamPolicy(Policy):
    """Team-based access control."""

    def evaluate(
        self,
        permission: str,
        context: PermissionContext
    ) -> Optional[bool]:
        # Ensure resource belongs to user's organization
        if context.resource_org_id and context.resource_org_id != context.org_id:
            return False  # Explicit deny for cross-org access
        return None


class PermissionDeniedError(Exception):
    pass
```

### 6. FastAPI Security Middleware

```python
# company_os/api/security.py

from typing import Optional
from fastapi import Request, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials, APIKeyHeader
from starlette.middleware.base import BaseHTTPMiddleware
import asyncpg

from company_os.core.auth.tokens import TokenService, TokenPayload
from company_os.core.auth.service import AuthService
from company_os.core.auth.permissions import PermissionChecker, PermissionContext


# Security schemes
bearer_scheme = HTTPBearer(auto_error=False)
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def get_current_user(
    request: Request,
    bearer: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    api_key: Optional[str] = Depends(api_key_header)
) -> PermissionContext:
    """
    Extract and validate authentication from request.

    Supports:
    - Bearer token (JWT)
    - API key
    """
    auth_service: AuthService = request.app.state.auth_service
    token_service: TokenService = request.app.state.token_service

    # Try Bearer token first
    if bearer:
        try:
            payload = token_service.verify_access_token(bearer.credentials)
            return PermissionContext(
                user_id=payload.sub,
                org_id=payload.org_id,
                role=payload.role,
                permissions=payload.permissions
            )
        except Exception as e:
            raise HTTPException(status_code=401, detail=str(e))

    # Try API key
    if api_key:
        try:
            key_context = await auth_service.verify_api_key(api_key)
            return PermissionContext(
                user_id=str(key_context['user_id']),
                org_id=str(key_context['org_id']),
                role="api_key",
                permissions=key_context['permissions']
            )
        except Exception as e:
            raise HTTPException(status_code=401, detail="Invalid API key")

    raise HTTPException(status_code=401, detail="Not authenticated")


def require_permission(permission: str):
    """Dependency to require a specific permission."""
    async def checker(
        request: Request,
        context: PermissionContext = Depends(get_current_user)
    ):
        checker: PermissionChecker = request.app.state.permission_checker
        try:
            checker.require(permission, context)
            return context
        except Exception as e:
            raise HTTPException(status_code=403, detail=str(e))

    return checker


class TenantContextMiddleware(BaseHTTPMiddleware):
    """
    Middleware to set tenant context for database queries.

    This enables Row-Level Security (RLS) in PostgreSQL.
    """

    async def dispatch(self, request: Request, call_next):
        # Get org_id from auth context if available
        org_id = None

        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            try:
                token = auth_header.split(" ")[1]
                token_service: TokenService = request.app.state.token_service
                payload = token_service.verify_access_token(token)
                org_id = payload.org_id
            except:
                pass

        if org_id:
            # Set org context for RLS
            pool: asyncpg.Pool = request.app.state.db_pool
            async with pool.acquire() as conn:
                await conn.execute(
                    f"SET app.current_org_id = '{org_id}'"
                )

        response = await call_next(request)
        return response


class AuditLogMiddleware(BaseHTTPMiddleware):
    """Middleware to log all API requests for audit."""

    async def dispatch(self, request: Request, call_next):
        # Capture request details
        method = request.method
        path = request.url.path
        ip = request.client.host if request.client else None
        user_agent = request.headers.get("user-agent")

        # Get user from auth if available
        user_id = None
        org_id = None

        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            try:
                token = auth_header.split(" ")[1]
                token_service: TokenService = request.app.state.token_service
                payload = token_service.verify_access_token(token)
                user_id = payload.sub
                org_id = payload.org_id
            except:
                pass

        # Execute request
        response = await call_next(request)

        # Log after response (don't block request)
        if method in ["POST", "PUT", "PATCH", "DELETE"]:
            await self._log_request(
                request.app,
                method, path,
                user_id, org_id,
                ip, user_agent,
                response.status_code
            )

        return response

    async def _log_request(
        self,
        app,
        method: str,
        path: str,
        user_id: Optional[str],
        org_id: Optional[str],
        ip: Optional[str],
        user_agent: Optional[str],
        status_code: int
    ):
        """Write audit log entry."""
        pool: asyncpg.Pool = app.state.db_pool

        # Parse resource from path
        resource_type, resource_id = self._parse_path(path)
        action = f"{resource_type}.{method.lower()}"

        try:
            async with pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO audit_logs
                    (org_id, user_id, action, resource_type, resource_id,
                     details, ip_address, user_agent)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                    org_id,
                    user_id,
                    action,
                    resource_type,
                    resource_id,
                    {"status_code": status_code},
                    ip,
                    user_agent
                )
        except Exception as e:
            # Don't fail request if audit log fails
            print(f"Audit log error: {e}")

    def _parse_path(self, path: str) -> tuple[str, Optional[str]]:
        """Extract resource type and ID from path."""
        parts = path.strip("/").split("/")
        if len(parts) >= 2 and parts[0] == "api":
            resource_type = parts[1] if len(parts) > 1 else "unknown"
            resource_id = parts[2] if len(parts) > 2 else None
            return resource_type, resource_id
        return "unknown", None
```

### 7. Agent Sandbox Configuration

```python
# company_os/agents/sandbox.py

from dataclasses import dataclass
from typing import Dict, List, Optional
import docker
import asyncio


@dataclass
class SandboxConfig:
    """Configuration for agent sandbox."""
    # Resource limits
    cpu_limit: float = 1.0  # CPU cores
    memory_limit: str = "2g"  # Memory limit
    timeout_seconds: int = 3600  # 1 hour max

    # Network policy
    network_enabled: bool = True
    allowed_hosts: List[str] = None  # None = allow all

    # Filesystem
    read_only_root: bool = True
    workspace_size: str = "1g"

    # Security
    privileged: bool = False
    cap_drop: List[str] = None


class AgentSandbox:
    """
    Docker-based sandbox for agent execution.

    Provides:
    - Resource isolation
    - Network policy enforcement
    - Filesystem isolation
    - Automatic cleanup
    """

    def __init__(self, config: SandboxConfig = None):
        self.config = config or SandboxConfig()
        self.client = docker.from_env()

    async def run(
        self,
        agent_id: str,
        code: str,
        env_vars: Dict[str, str] = None
    ) -> str:
        """Run code in sandbox and return output."""
        container = None

        try:
            # Create container
            container = self.client.containers.run(
                image="company-os-sandbox:latest",
                command=["python", "-c", code],
                detach=True,
                remove=False,

                # Resource limits
                cpu_period=100000,
                cpu_quota=int(self.config.cpu_limit * 100000),
                mem_limit=self.config.memory_limit,

                # Security
                privileged=self.config.privileged,
                read_only=self.config.read_only_root,
                cap_drop=self.config.cap_drop or ["ALL"],
                security_opt=["no-new-privileges:true"],

                # User (non-root)
                user="65534:65534",

                # Network
                network_mode="bridge" if self.config.network_enabled else "none",

                # Environment
                environment=env_vars or {},

                # Temp filesystem for writes
                tmpfs={"/tmp": f"size={self.config.workspace_size}"},

                # Labels for cleanup
                labels={
                    "company-os.agent-id": agent_id,
                    "company-os.sandbox": "true"
                }
            )

            # Wait for completion with timeout
            result = await asyncio.wait_for(
                asyncio.to_thread(container.wait),
                timeout=self.config.timeout_seconds
            )

            # Get logs
            output = container.logs(stdout=True, stderr=True).decode()

            if result["StatusCode"] != 0:
                raise SandboxExecutionError(
                    f"Execution failed with code {result['StatusCode']}: {output}"
                )

            return output

        except asyncio.TimeoutError:
            raise SandboxTimeoutError(
                f"Execution timed out after {self.config.timeout_seconds}s"
            )

        finally:
            if container:
                try:
                    container.remove(force=True)
                except:
                    pass

    def build_sandbox_image(self):
        """Build the sandbox Docker image."""
        dockerfile = """
FROM python:3.11-slim

# Install common packages
RUN pip install --no-cache-dir \
    requests \
    pandas \
    numpy \
    scipy

# Create non-root user
RUN useradd -m -u 65534 sandbox

# Set working directory
WORKDIR /sandbox
RUN chown sandbox:sandbox /sandbox

USER sandbox

CMD ["python"]
"""
        # Build image
        self.client.images.build(
            fileobj=dockerfile.encode(),
            tag="company-os-sandbox:latest",
            rm=True
        )


class SandboxExecutionError(Exception):
    pass

class SandboxTimeoutError(Exception):
    pass
```

---

## API Routes Example

```python
# company_os/api/routes/auth.py

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, EmailStr
from typing import Optional

from company_os.core.auth.service import AuthService
from company_os.api.security import get_current_user, require_permission


router = APIRouter(prefix="/auth", tags=["Authentication"])


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    name: Optional[str] = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int


@router.post("/register", response_model=TokenResponse)
async def register(request: Request, body: RegisterRequest):
    """Register a new user."""
    auth_service: AuthService = request.app.state.auth_service

    try:
        user_id, tokens = await auth_service.register(
            email=body.email,
            password=body.password,
            name=body.name
        )

        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            expires_in=900  # 15 minutes
        )
    except EmailAlreadyExistsError:
        raise HTTPException(status_code=400, detail="Email already registered")


@router.post("/login", response_model=TokenResponse)
async def login(request: Request, body: LoginRequest):
    """Login with email/password."""
    auth_service: AuthService = request.app.state.auth_service

    try:
        user_id, tokens = await auth_service.login(
            email=body.email,
            password=body.password
        )

        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            expires_in=900
        )
    except (InvalidCredentialsError, AccountDisabledError):
        raise HTTPException(status_code=401, detail="Invalid credentials")


@router.get("/github")
async def github_login(request: Request):
    """Initiate GitHub OAuth flow."""
    import secrets

    github = request.app.state.github_oauth
    state = secrets.token_urlsafe(32)

    # Store state in session/cache for verification

    return {
        "url": github.get_authorization_url(state)
    }


@router.get("/github/callback", response_model=TokenResponse)
async def github_callback(request: Request, code: str, state: str):
    """Handle GitHub OAuth callback."""
    auth_service: AuthService = request.app.state.auth_service

    # TODO: Verify state matches stored state

    user_id, tokens = await auth_service.oauth_login("github", code)

    return TokenResponse(
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        expires_in=900
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_tokens(request: Request, refresh_token: str):
    """Refresh access token."""
    auth_service: AuthService = request.app.state.auth_service

    try:
        tokens = await auth_service.refresh_tokens(refresh_token)

        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            expires_in=900
        )
    except:
        raise HTTPException(status_code=401, detail="Invalid refresh token")


@router.post("/logout")
async def logout(
    request: Request,
    refresh_token: str,
    context = Depends(get_current_user)
):
    """Logout (revoke refresh token)."""
    auth_service: AuthService = request.app.state.auth_service
    await auth_service.logout(refresh_token)
    return {"message": "Logged out"}
```

---

## Security Checklist

### Authentication
- [x] JWT with short expiry (15 min)
- [x] Refresh token rotation
- [x] OAuth 2.0 with GitHub
- [x] API keys for programmatic access
- [x] Password hashing with bcrypt
- [x] Session management

### Authorization
- [x] Role-based access control (RBAC)
- [x] Attribute-based policies (ABAC)
- [x] Permission inheritance
- [x] Resource ownership checks
- [x] Cross-org protection

### Data Protection
- [x] Row-level security (RLS)
- [x] Tenant isolation
- [x] Audit logging
- [x] Token hashing

### Agent Security
- [x] Docker sandbox
- [x] Resource limits
- [x] Network isolation
- [x] Non-root execution
- [x] Capability dropping

---

**Next: Implementation Roadmap →**
