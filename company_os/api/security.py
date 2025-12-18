"""
API Security Dependencies.

FastAPI dependencies for authentication and authorization.
"""

from typing import Optional
from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from ..core.auth.service import AuthService, AuthenticationError, AuthorizationError
from ..core.auth.models import TokenPayload, Permission
from .state import get_app_state, AppState


# HTTP Bearer token scheme
bearer_scheme = HTTPBearer(auto_error=False)


async def get_auth_service() -> AuthService:
    """Get auth service from app state."""
    return get_app_state().auth_service


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    auth_service: AuthService = Depends(get_auth_service)
) -> TokenPayload:
    """
    Get current authenticated user from JWT token.

    Raises:
        HTTPException: If not authenticated or token invalid
    """
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        return await auth_service.verify_access_token(credentials.credentials)
    except AuthenticationError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    auth_service: AuthService = Depends(get_auth_service)
) -> Optional[TokenPayload]:
    """Get current user if authenticated, None otherwise."""
    if not credentials:
        return None

    try:
        return await auth_service.verify_access_token(credentials.credentials)
    except AuthenticationError:
        return None


def require_permission(permission: Permission):
    """
    Dependency factory for requiring specific permissions.

    Usage:
        @router.get("/admin", dependencies=[Depends(require_permission(Permission.ADMIN_FULL))])
    """
    async def check_permission(
        current_user: TokenPayload = Depends(get_current_user),
        auth_service: AuthService = Depends(get_auth_service)
    ) -> TokenPayload:
        try:
            auth_service.require_permission(current_user, permission)
            return current_user
        except AuthorizationError as e:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=str(e)
            )

    return check_permission


async def set_org_context(
    current_user: TokenPayload = Depends(get_current_user)
) -> UUID:
    """
    Set organization context for RLS policies.

    Returns the current organization ID.
    """
    state = get_app_state()

    # Set org context for RLS
    async with state.pool.acquire() as conn:
        await conn.execute(
            f"SET app.current_org_id = '{current_user.org_id}'"
        )

    return UUID(current_user.org_id)


class CurrentUser:
    """Wrapper for current user with organization context."""

    def __init__(self, token: TokenPayload):
        self.token = token
        self.user_id = UUID(token.sub)
        self.org_id = UUID(token.org_id)
        self.role = token.role
        self.permissions = token.permissions

    def has_permission(self, permission: Permission) -> bool:
        """Check if user has a specific permission."""
        return permission.value in self.permissions


async def get_current_user_context(
    current_user: TokenPayload = Depends(get_current_user)
) -> CurrentUser:
    """Get current user with convenience methods."""
    return CurrentUser(current_user)
