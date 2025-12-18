"""
Authentication Models.

Domain models for authentication and authorization.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional
from uuid import UUID
from enum import Enum


class UserRole(str, Enum):
    """User roles within an organization."""
    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"
    VIEWER = "viewer"


class Permission(str, Enum):
    """Granular permissions."""
    # Task permissions
    TASKS_CREATE = "tasks:create"
    TASKS_READ = "tasks:read"
    TASKS_UPDATE = "tasks:update"
    TASKS_DELETE = "tasks:delete"
    TASKS_ASSIGN = "tasks:assign"

    # Agent permissions
    AGENTS_ACTIVATE = "agents:activate"
    AGENTS_VIEW = "agents:view"
    AGENTS_CONFIGURE = "agents:configure"

    # Project permissions
    PROJECTS_CREATE = "projects:create"
    PROJECTS_READ = "projects:read"
    PROJECTS_UPDATE = "projects:update"
    PROJECTS_DELETE = "projects:delete"

    # Organization permissions
    ORG_MANAGE = "org:manage"
    ORG_BILLING = "org:billing"
    ORG_MEMBERS = "org:members"

    # Admin permissions
    ADMIN_FULL = "admin:full"


# Role permission mappings
ROLE_PERMISSIONS: dict[UserRole, set[Permission]] = {
    UserRole.OWNER: set(Permission),  # All permissions
    UserRole.ADMIN: {
        Permission.TASKS_CREATE, Permission.TASKS_READ, Permission.TASKS_UPDATE,
        Permission.TASKS_DELETE, Permission.TASKS_ASSIGN,
        Permission.AGENTS_ACTIVATE, Permission.AGENTS_VIEW, Permission.AGENTS_CONFIGURE,
        Permission.PROJECTS_CREATE, Permission.PROJECTS_READ, Permission.PROJECTS_UPDATE,
        Permission.PROJECTS_DELETE,
        Permission.ORG_MEMBERS,
    },
    UserRole.MEMBER: {
        Permission.TASKS_CREATE, Permission.TASKS_READ, Permission.TASKS_UPDATE,
        Permission.TASKS_ASSIGN,
        Permission.AGENTS_ACTIVATE, Permission.AGENTS_VIEW,
        Permission.PROJECTS_READ,
    },
    UserRole.VIEWER: {
        Permission.TASKS_READ,
        Permission.AGENTS_VIEW,
        Permission.PROJECTS_READ,
    },
}


@dataclass
class User:
    """User entity."""
    id: UUID
    email: str
    name: str
    password_hash: Optional[str]
    is_active: bool
    is_verified: bool
    created_at: datetime
    updated_at: datetime
    last_login: Optional[datetime] = None
    avatar_url: Optional[str] = None
    preferences: dict = field(default_factory=dict)


@dataclass
class Organization:
    """Organization entity."""
    id: UUID
    name: str
    slug: str
    plan: str  # free, starter, pro, enterprise
    created_at: datetime
    updated_at: datetime
    settings: dict = field(default_factory=dict)
    limits: dict = field(default_factory=dict)


@dataclass
class OrgMembership:
    """User membership in an organization."""
    user_id: UUID
    org_id: UUID
    role: UserRole
    joined_at: datetime
    invited_by: Optional[UUID] = None


@dataclass
class OAuthAccount:
    """Linked OAuth account."""
    id: UUID
    user_id: UUID
    provider: str  # github, google, etc.
    provider_user_id: str
    provider_username: Optional[str]
    access_token: str
    refresh_token: Optional[str]
    token_expires_at: Optional[datetime]
    created_at: datetime
    updated_at: datetime


@dataclass
class APIKey:
    """API key for programmatic access."""
    id: UUID
    org_id: UUID
    user_id: UUID
    name: str
    key_hash: str
    key_prefix: str  # First 8 chars for identification
    permissions: list[str]
    last_used_at: Optional[datetime]
    expires_at: Optional[datetime]
    created_at: datetime
    is_active: bool = True


@dataclass
class RefreshToken:
    """Refresh token for token rotation."""
    id: UUID
    user_id: UUID
    token_hash: str
    device_info: Optional[str]
    ip_address: Optional[str]
    expires_at: datetime
    created_at: datetime
    revoked_at: Optional[datetime] = None


@dataclass
class TokenPair:
    """Access and refresh token pair."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = 900  # 15 minutes in seconds


@dataclass
class TokenPayload:
    """JWT token payload."""
    sub: str  # User ID
    org_id: str
    role: str
    permissions: list[str]
    exp: datetime
    iat: datetime
    jti: str  # Unique token ID
