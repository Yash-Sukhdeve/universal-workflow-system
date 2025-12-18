"""
Authentication Routes.

User registration, login, and token management.
"""

from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status, Request
from pydantic import BaseModel, EmailStr

from ..state import get_app_state
from ..security import get_current_user, get_auth_service
from ...core.auth.service import AuthService, AuthenticationError
from ...core.auth.models import TokenPayload


router = APIRouter()


# Request/Response Models

class RegisterRequest(BaseModel):
    """User registration request."""
    email: EmailStr
    name: str
    password: str
    org_name: Optional[str] = None


class LoginRequest(BaseModel):
    """User login request."""
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    """Token refresh request."""
    refresh_token: str


class TokenResponse(BaseModel):
    """Token pair response."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserResponse(BaseModel):
    """User info response."""
    id: str
    email: str
    name: str
    org_id: str
    role: str


# Routes

@router.post("/register", response_model=TokenResponse)
async def register(
    request: RegisterRequest,
    req: Request,
    auth_service: AuthService = Depends(get_auth_service)
):
    """
    Register a new user and create their default organization.

    Returns access and refresh tokens.
    """
    try:
        user, org = await auth_service.create_user(
            email=request.email,
            name=request.name,
            password=request.password,
            org_name=request.org_name
        )

        tokens = await auth_service.create_tokens(
            user=user,
            org=org,
            device_info=req.headers.get("user-agent"),
            ip_address=req.client.host if req.client else None
        )

        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            token_type=tokens.token_type,
            expires_in=tokens.expires_in
        )

    except Exception as e:
        # Check for unique constraint violation (email exists)
        error_str = str(e).lower()
        if "unique" in error_str or "duplicate" in error_str:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )
        # Log the actual error internally but don't expose to client
        import logging
        logging.error(f"Registration error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Registration failed. Please try again."
        )


@router.post("/login", response_model=TokenResponse)
async def login(
    request: LoginRequest,
    req: Request,
    auth_service: AuthService = Depends(get_auth_service)
):
    """
    Authenticate with email and password.

    Returns access and refresh tokens.
    """
    try:
        user, org = await auth_service.authenticate(
            email=request.email,
            password=request.password
        )

        tokens = await auth_service.create_tokens(
            user=user,
            org=org,
            device_info=req.headers.get("user-agent"),
            ip_address=req.client.host if req.client else None
        )

        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            token_type=tokens.token_type,
            expires_in=tokens.expires_in
        )

    except AuthenticationError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e)
        )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_tokens(
    request: RefreshRequest,
    req: Request,
    auth_service: AuthService = Depends(get_auth_service)
):
    """
    Refresh access token using refresh token.

    Implements token rotation: old refresh token is invalidated.
    """
    try:
        tokens = await auth_service.refresh_tokens(
            refresh_token=request.refresh_token,
            device_info=req.headers.get("user-agent"),
            ip_address=req.client.host if req.client else None
        )

        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            token_type=tokens.token_type,
            expires_in=tokens.expires_in
        )

    except AuthenticationError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e)
        )


@router.post("/logout")
async def logout(
    request: RefreshRequest,
    auth_service: AuthService = Depends(get_auth_service)
):
    """
    Logout by revoking the refresh token.
    """
    await auth_service.revoke_refresh_token(request.refresh_token)
    return {"message": "Logged out successfully"}


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(
    current_user: TokenPayload = Depends(get_current_user),
    auth_service: AuthService = Depends(get_auth_service)
):
    """
    Get current authenticated user info.
    """
    # Validate UUID from token - malformed tokens should fail auth
    try:
        user_id = UUID(current_user.sub)
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token: malformed user ID"
        )

    user = await auth_service.get_user_by_id(user_id)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    return UserResponse(
        id=str(user.id),
        email=user.email,
        name=user.name,
        org_id=current_user.org_id,
        role=current_user.role
    )


# GitHub OAuth routes (placeholder - needs GitHub app setup)

@router.get("/github")
async def github_auth():
    """
    Initiate GitHub OAuth flow.

    Redirects to GitHub authorization page.
    """
    # TODO: Implement GitHub OAuth
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="GitHub OAuth not yet configured"
    )


@router.get("/github/callback")
async def github_callback(code: str, state: Optional[str] = None):
    """
    Handle GitHub OAuth callback.

    Exchanges code for tokens and creates/links user.
    """
    # TODO: Implement GitHub OAuth callback
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="GitHub OAuth not yet configured"
    )
