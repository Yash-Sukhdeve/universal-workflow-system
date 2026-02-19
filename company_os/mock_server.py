"""
Mock API Server for Dashboard Testing.

Simple mock server that responds to frontend API calls without requiring PostgreSQL.
"""

from fastapi import FastAPI, APIRouter, HTTPException, Depends, Form, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import uuid
import asyncio

app = FastAPI(title="Company OS Mock API")

# API Router with /api prefix to match frontend expectations
api = APIRouter(prefix="/api")

# CORS for dashboard
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer(auto_error=False)

# Mock data
MOCK_TOKEN = "mock-jwt-token-for-testing"
MOCK_USER = {
    "id": "user-001",
    "email": "test@example.com",
    "role": "admin",
    "organization_id": "org-001"
}

MOCK_TASKS = [
    {"id": "task-001", "title": "Implement WebSocket", "description": "Add real-time updates", "status": "completed", "priority": "high", "assigned_to": "researcher", "created_at": "2025-12-18T10:00:00Z", "updated_at": "2025-12-18T11:00:00Z"},
    {"id": "task-002", "title": "Build Dashboard", "description": "React frontend", "status": "in_progress", "priority": "high", "assigned_to": "implementer", "created_at": "2025-12-18T09:00:00Z", "updated_at": "2025-12-18T10:30:00Z"},
    {"id": "task-003", "title": "Write Tests", "description": "E2E tests with Playwright", "status": "pending", "priority": "medium", "assigned_to": None, "created_at": "2025-12-18T08:00:00Z", "updated_at": "2025-12-18T08:00:00Z"},
    {"id": "task-004", "title": "Deploy to Production", "description": "Docker + K8s", "status": "pending", "priority": "low", "assigned_to": "deployer", "created_at": "2025-12-17T15:00:00Z", "updated_at": "2025-12-17T15:00:00Z"},
]

MOCK_AGENTS = [
    {"name": "researcher", "status": "active", "capabilities": ["literature_review", "experimental_design", "statistical_validation"], "current_task": "Analyzing codebase", "activated_at": "2025-12-18T09:00:00Z"},
    {"name": "architect", "status": "inactive", "capabilities": ["system_design", "api_design", "architecture_patterns"], "current_task": None, "activated_at": None},
    {"name": "implementer", "status": "inactive", "capabilities": ["code_generation", "debugging", "testing"], "current_task": None, "activated_at": None},
    {"name": "experimenter", "status": "inactive", "capabilities": ["experimental_design", "data_collection", "analysis"], "current_task": None, "activated_at": None},
    {"name": "optimizer", "status": "inactive", "capabilities": ["performance_tuning", "refactoring", "profiling"], "current_task": None, "activated_at": None},
    {"name": "deployer", "status": "inactive", "capabilities": ["containerization", "ci_cd", "monitoring"], "current_task": None, "activated_at": None},
    {"name": "documenter", "status": "inactive", "capabilities": ["documentation", "api_docs", "user_guides"], "current_task": None, "activated_at": None},
]

MOCK_MEMORIES = [
    {"id": "mem-001", "content": "Implemented WebSocket with auto-reconnect", "type": "discovery", "relevance_score": 0.95, "created_at": "2025-12-18T11:30:00Z"},
    {"id": "mem-002", "content": "Dashboard uses Tailwind CSS 4", "type": "context", "relevance_score": 0.88, "created_at": "2025-12-18T10:00:00Z"},
    {"id": "mem-003", "content": "Decided to use event sourcing for audit trail", "type": "decision", "relevance_score": 0.92, "created_at": "2025-12-17T14:00:00Z"},
]


# Models
class LoginRequest(BaseModel):
    email: str = ""
    password: str = ""
    username: str = ""  # OAuth2 form compatibility

class RegisterRequest(BaseModel):
    email: str
    password: str
    organization_name: Optional[str] = None

class CreateTaskRequest(BaseModel):
    title: str
    description: str
    priority: str = "medium"
    assigned_to: Optional[str] = None

class StoreMemoryRequest(BaseModel):
    content: str
    type: str = "context"
    metadata: Optional[dict] = None


# Auth check
async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if not credentials:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return MOCK_USER


# Routes
@app.get("/")
async def root():
    return {"status": "ok"}

@app.get("/health")
async def health():
    return {"status": "healthy", "version": "0.1.0-mock"}


@api.post("/auth/login")
async def login(
    username: str = Form(default=""),
    password: str = Form(default=""),
):
    # Accept either form data (OAuth2 style) or JSON
    if username and password:
        return {
            "access_token": MOCK_TOKEN,
            "token_type": "bearer",
            "user": MOCK_USER
        }
    raise HTTPException(status_code=401, detail="Invalid credentials")


@api.post("/auth/register")
async def register(request: RegisterRequest):
    return {
        "access_token": MOCK_TOKEN,
        "token_type": "bearer",
        "user": {**MOCK_USER, "email": request.email}
    }


@api.get("/auth/me")
async def get_me(user: dict = Depends(get_current_user)):
    return user


@api.get("/tasks")
async def list_tasks(page: int = 1, per_page: int = 10, user: dict = Depends(get_current_user)):
    return {
        "items": MOCK_TASKS,
        "total": len(MOCK_TASKS),
        "page": page,
        "per_page": per_page
    }


@api.post("/tasks")
async def create_task(request: CreateTaskRequest, user: dict = Depends(get_current_user)):
    new_task = {
        "id": f"task-{uuid.uuid4().hex[:8]}",
        "title": request.title,
        "description": request.description,
        "status": "pending",
        "priority": request.priority,
        "assigned_to": request.assigned_to,
        "created_at": datetime.utcnow().isoformat() + "Z",
        "updated_at": datetime.utcnow().isoformat() + "Z",
    }
    MOCK_TASKS.insert(0, new_task)
    return new_task


@api.post("/tasks/{task_id}/complete")
async def complete_task(task_id: str, user: dict = Depends(get_current_user)):
    for task in MOCK_TASKS:
        if task["id"] == task_id:
            task["status"] = "completed"
            task["updated_at"] = datetime.utcnow().isoformat() + "Z"
            return task
    raise HTTPException(status_code=404, detail="Task not found")


@api.get("/agents")
async def list_agents(user: dict = Depends(get_current_user)):
    return MOCK_AGENTS


@api.post("/agents/{name}/activate")
async def activate_agent(name: str, user: dict = Depends(get_current_user)):
    for agent in MOCK_AGENTS:
        if agent["name"] == name:
            agent["status"] = "active"
            agent["activated_at"] = datetime.utcnow().isoformat() + "Z"
            return agent
    raise HTTPException(status_code=404, detail="Agent not found")


@api.post("/agents/{name}/deactivate")
async def deactivate_agent(name: str, user: dict = Depends(get_current_user)):
    for agent in MOCK_AGENTS:
        if agent["name"] == name:
            agent["status"] = "inactive"
            agent["current_task"] = None
            return agent
    raise HTTPException(status_code=404, detail="Agent not found")


@api.get("/memory/context")
async def get_memory_context(user: dict = Depends(get_current_user)):
    return {
        "recent_memories": MOCK_MEMORIES,
        "similar_tasks": MOCK_TASKS[:2],
        "decisions": [m for m in MOCK_MEMORIES if m["type"] == "decision"]
    }


@api.get("/memory/search")
async def search_memory(query: str, limit: int = 10, user: dict = Depends(get_current_user)):
    return [m for m in MOCK_MEMORIES if query.lower() in m["content"].lower()][:limit]


@api.post("/memory/store")
async def store_memory(request: StoreMemoryRequest, user: dict = Depends(get_current_user)):
    new_memory = {
        "id": f"mem-{uuid.uuid4().hex[:8]}",
        "content": request.content,
        "type": request.type,
        "relevance_score": 1.0,
        "created_at": datetime.utcnow().isoformat() + "Z",
        "metadata": request.metadata
    }
    MOCK_MEMORIES.insert(0, new_memory)
    return new_memory


# WebSocket connection manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                pass

manager = ConnectionManager()


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # Receive messages from client
            data = await websocket.receive_json()
            # Handle auth message
            if data.get("type") == "auth":
                await websocket.send_json({"type": "auth_success"})
            else:
                # Echo back or handle as needed
                await websocket.send_json({"type": "ack", "data": data})
    except WebSocketDisconnect:
        manager.disconnect(websocket)


# Include the API router
app.include_router(api)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
