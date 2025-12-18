"""
Company OS FastAPI Application.

Main entry point for the Company OS API.
"""

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import asyncpg

from ..core.config.settings import get_settings
from ..core.events.store import EventStore, EventPublisher
from ..core.events.projections import ProjectionManager, TaskProjection
from ..core.auth.service import AuthService
from ..core.memory.service import SemanticMemoryService, EmbeddingService
from ..integrations.uws.adapter import UWSAdapter
from .state import app_state, get_app_state, AppState
from .routes import auth, tasks, agents, memory, health


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Application lifespan manager."""
    settings = get_settings()

    # Create database pool
    app_state.pool = await asyncpg.create_pool(
        settings.database_url,
        min_size=5,
        max_size=settings.database_pool_size
    )

    # Initialize event store
    app_state.event_store = EventStore(app_state.pool)
    app_state.event_publisher = EventPublisher()

    # Initialize projections
    app_state.projection_manager = ProjectionManager(
        app_state.pool,
        app_state.event_store
    )
    app_state.projection_manager.register(TaskProjection(app_state.pool))

    # Initialize auth service
    app_state.auth_service = AuthService(app_state.pool, settings)

    # Initialize embedding and memory service
    embedding_service = EmbeddingService(
        provider=settings.embedding_provider,
        api_key=settings.openai_api_key,
        model=settings.embedding_model
    )
    app_state.memory_service = SemanticMemoryService(
        app_state.pool,
        embedding_service
    )

    # Initialize UWS adapter
    app_state.uws_adapter = UWSAdapter(settings.uws_root)

    yield

    # Cleanup
    await app_state.pool.close()


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    settings = get_settings()

    app = FastAPI(
        title="Company OS API",
        description="AI-Native Adaptive Intelligence Platform",
        version="0.1.0",
        lifespan=lifespan
    )

    # CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Include routers
    app.include_router(health.router, tags=["Health"])
    app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
    app.include_router(tasks.router, prefix="/api/tasks", tags=["Tasks"])
    app.include_router(agents.router, prefix="/api/agents", tags=["Agents"])
    app.include_router(memory.router, prefix="/api/memory", tags=["Memory"])

    return app


app = create_app()
