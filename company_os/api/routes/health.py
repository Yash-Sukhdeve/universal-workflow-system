"""
Health Check Routes.

System health and readiness endpoints.
"""

from fastapi import APIRouter, Depends

from ..state import get_app_state, AppState


router = APIRouter()


@router.get("/health")
async def health_check():
    """Basic health check."""
    return {"status": "healthy", "service": "company-os"}


@router.get("/ready")
async def readiness_check():
    """
    Readiness check - verifies all dependencies are available.
    """
    state = get_app_state()
    checks = {}

    # Check database connection
    try:
        async with state.pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        checks["database"] = "ok"
    except Exception as e:
        checks["database"] = f"error: {e}"

    # Check UWS availability
    try:
        uws_state = await state.uws_adapter.get_workflow_state()
        checks["uws"] = "ok" if uws_state else "no_state"
    except Exception as e:
        checks["uws"] = f"error: {e}"

    all_ok = all(v == "ok" for v in checks.values())

    return {
        "status": "ready" if all_ok else "degraded",
        "checks": checks
    }


@router.get("/status")
async def system_status():
    """
    Comprehensive system status including UWS state.
    """
    state = get_app_state()

    # Get UWS status
    try:
        uws_status = await state.uws_adapter.get_status()
    except Exception as e:
        uws_status = {"error": str(e)}

    return {
        "service": "company-os",
        "version": "0.1.0",
        "uws": uws_status
    }
