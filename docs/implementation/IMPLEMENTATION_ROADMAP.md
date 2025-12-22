# Company OS Implementation Roadmap

## Strategy: UWS as Intelligence Substrate

**Key Decision**: Use the existing Universal Workflow System (UWS) as the intelligence substrate for Company OS, rather than building a new LLM integration layer from scratch.

### What UWS Already Provides

| Component | Location | Status |
|-----------|----------|--------|
| **Agent Registry** | `.workflow/agents/registry.yaml` | ✅ Ready |
| **Agent Personas** | `docs/personas/*.md` | ✅ Ready |
| **Skills Catalog** | `.workflow/skills/catalog.yaml` | ✅ Ready |
| **Skill Definitions** | `.workflow/skills/definitions/*.md` | ✅ Ready |
| **Session Manager** | `scripts/lib/session_manager.sh` | ✅ Ready |
| **Checkpoint System** | `scripts/checkpoint.sh` | ✅ Ready |
| **State Management** | `.workflow/state.yaml` | ✅ Ready |
| **Handoff System** | `.workflow/handoff.md` | ✅ Ready |
| **Dashboard Server** | `scripts/dashboard_server.py` | ✅ Ready |
| **WebSocket Updates** | `dashboard/app.js` | ✅ Ready |

### What Needs to Be Added

| Component | Priority | Effort |
|-----------|----------|--------|
| Event Store (PostgreSQL) | P0 | 2 weeks |
| Authentication | P0 | 2 weeks |
| REST API Layer | P0 | 2 weeks |
| Multi-Tenant Support | P0 | 1 week |
| GitHub Integration | P1 | 1 week |
| Task Management | P1 | 1 week |

---

## Architecture: UWS + Company OS Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                     COMPANY OS (New)                             │
│                                                                  │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │ FastAPI       │  │ Auth Service  │  │ Task Service  │       │
│  │ REST API      │  │ (JWT/OAuth)   │  │               │       │
│  └───────┬───────┘  └───────────────┘  └───────────────┘       │
│          │                                                       │
│          ▼                                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    EVENT STORE                             │  │
│  │                   (PostgreSQL)                             │  │
│  │  All mutations → Events → Projections → Read Models        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
└──────────────────────────────┼───────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     UWS CORE (Existing)                          │
│                  [Intelligence Substrate]                        │
│                                                                  │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │ Agent Runtime │  │ Skills System │  │ Session Mgr   │       │
│  │ (Claude Code) │  │               │  │               │       │
│  └───────────────┘  └───────────────┘  └───────────────┘       │
│          │                   │                   │               │
│          ▼                   ▼                   ▼               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  .workflow/                                                │  │
│  │    agents/registry.yaml     (Agent definitions)           │  │
│  │    agents/sessions.yaml     (Active sessions)             │  │
│  │    skills/catalog.yaml      (Skill definitions)           │  │
│  │    state.yaml               (Workflow state)              │  │
│  │    handoff.md               (Context handoff)             │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │ Checkpoint    │  │ Recovery      │  │ Dashboard     │       │
│  │ System        │  │ System        │  │ Server        │       │
│  └───────────────┘  └───────────────┘  └───────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Foundation (Weeks 1-4)

### Week 1: Project Structure & Database

**Goal**: Set up the Company OS project structure alongside UWS

```
universal-workflow-system/
├── .workflow/                    # UWS (existing)
├── scripts/                      # UWS scripts (existing)
├── dashboard/                    # UWS dashboard (existing)
│
├── company_os/                   # NEW: Company OS Python package
│   ├── __init__.py
│   ├── core/
│   │   ├── events/              # Event store
│   │   │   ├── store.py
│   │   │   └── projections.py
│   │   ├── auth/                # Authentication
│   │   │   ├── service.py
│   │   │   ├── tokens.py
│   │   │   └── permissions.py
│   │   └── config.py
│   ├── domain/
│   │   ├── tasks/
│   │   ├── projects/
│   │   └── organizations/
│   ├── api/
│   │   ├── main.py              # FastAPI app
│   │   ├── routes/
│   │   └── security.py
│   └── integrations/
│       └── uws/                 # UWS integration
│           ├── adapter.py       # Bridges API to UWS
│           └── events.py        # Event handlers
│
├── migrations/                   # Database migrations
├── tests/                        # Existing + new tests
└── docker-compose.yml           # Development environment
```

**Tasks:**

1. **Create project structure**
   ```bash
   mkdir -p company_os/{core/{events,auth},domain/{tasks,projects,organizations},api/routes,integrations/uws}
   touch company_os/__init__.py
   touch company_os/core/__init__.py
   # ... etc
   ```

2. **Set up PostgreSQL with Event Store schema**
   - Use the schema from `CRITICAL_01_DATA_ARCHITECTURE.md`
   - Run migrations

3. **Create docker-compose for development**
   ```yaml
   version: '3.8'
   services:
     postgres:
       image: postgres:15
       environment:
         POSTGRES_DB: company_os
         POSTGRES_USER: company_os
         POSTGRES_PASSWORD: dev_password
       volumes:
         - postgres_data:/var/lib/postgresql/data
         - ./migrations:/docker-entrypoint-initdb.d
       ports:
         - "5432:5432"

     redis:
       image: redis:7-alpine
       ports:
         - "6379:6379"

     api:
       build: .
       volumes:
         - .:/app
       ports:
         - "8000:8000"
       depends_on:
         - postgres
         - redis
       environment:
         DATABASE_URL: postgresql://company_os:dev_password@postgres/company_os
         REDIS_URL: redis://redis:6379

   volumes:
     postgres_data:
   ```

**Deliverables:**
- [ ] Project structure created
- [ ] PostgreSQL running with event store schema
- [ ] Redis running
- [ ] Basic FastAPI app skeleton

### Week 2: Authentication System

**Goal**: Implement authentication (JWT + GitHub OAuth)

**Tasks:**

1. **Implement auth database schema**
   - Use schema from `CRITICAL_03_AUTH_SECURITY.md`

2. **Build token service**
   - JWT access tokens (15 min expiry)
   - Refresh token rotation

3. **Implement GitHub OAuth**
   - Authorization flow
   - User creation/linking

4. **Add API routes**
   ```
   POST /api/auth/register
   POST /api/auth/login
   GET  /api/auth/github
   GET  /api/auth/github/callback
   POST /api/auth/refresh
   POST /api/auth/logout
   ```

**Deliverables:**
- [ ] User registration with email/password
- [ ] Login with JWT tokens
- [ ] GitHub OAuth working
- [ ] Token refresh working
- [ ] Basic permission checking

### Week 3: UWS Integration Adapter

**Goal**: Create bridge between Company OS API and UWS agent system

```python
# company_os/integrations/uws/adapter.py

import subprocess
import json
from pathlib import Path
from typing import Optional, Dict, Any

class UWSAdapter:
    """
    Adapter to bridge Company OS API with UWS workflow system.

    Translates API calls into UWS commands.
    """

    def __init__(self, uws_root: str):
        self.root = Path(uws_root)
        self.scripts_dir = self.root / "scripts"
        self.workflow_dir = self.root / ".workflow"

    async def activate_agent(
        self,
        agent_type: str,
        task_description: str,
        org_id: str,
        task_id: str
    ) -> str:
        """Activate a UWS agent for a task."""
        # Create session using session_manager
        result = subprocess.run(
            [
                str(self.scripts_dir / "lib" / "session_manager.sh"),
                "create",
                agent_type,
                task_description
            ],
            capture_output=True,
            text=True,
            cwd=str(self.root)
        )

        session_id = result.stdout.strip()

        # Update session with org/task context
        await self._update_session_metadata(
            session_id,
            {"org_id": org_id, "task_id": task_id}
        )

        # Activate agent via UWS
        subprocess.run(
            [
                str(self.scripts_dir / "activate_agent.sh"),
                agent_type,
                "activate"
            ],
            cwd=str(self.root)
        )

        return session_id

    async def get_agent_sessions(self) -> list[Dict]:
        """Get all active agent sessions."""
        result = subprocess.run(
            [
                str(self.scripts_dir / "lib" / "session_manager.sh"),
                "list",
                "json"
            ],
            capture_output=True,
            text=True,
            cwd=str(self.root)
        )

        return json.loads(result.stdout)

    async def update_session_progress(
        self,
        session_id: str,
        progress: int,
        status: str = "active",
        task_update: Optional[str] = None
    ):
        """Update agent session progress."""
        cmd = [
            str(self.scripts_dir / "lib" / "session_manager.sh"),
            "update",
            session_id,
            str(progress),
            status
        ]
        if task_update:
            cmd.append(task_update)

        subprocess.run(cmd, cwd=str(self.root))

    async def end_session(
        self,
        session_id: str,
        result: str = "success"
    ):
        """End an agent session."""
        subprocess.run(
            [
                str(self.scripts_dir / "lib" / "session_manager.sh"),
                "end",
                session_id,
                result
            ],
            cwd=str(self.root)
        )

    async def get_available_agents(self) -> list[Dict]:
        """Get list of available agents from registry."""
        registry_path = self.workflow_dir / "agents" / "registry.yaml"

        import yaml
        with open(registry_path) as f:
            registry = yaml.safe_load(f)

        return [
            {
                "type": agent_type,
                "name": config.get("name", agent_type),
                "description": config.get("description", ""),
                "capabilities": config.get("capabilities", []),
                "icon": config.get("icon", "🤖")
            }
            for agent_type, config in registry.get("agents", {}).items()
        ]

    async def get_available_skills(self) -> list[Dict]:
        """Get list of available skills from catalog."""
        catalog_path = self.workflow_dir / "skills" / "catalog.yaml"

        import yaml
        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)

        return [
            {
                "name": skill_name,
                "description": config.get("description", ""),
                "category": config.get("category", "general")
            }
            for skill_name, config in catalog.get("skills", {}).items()
        ]

    async def create_checkpoint(self, message: str) -> str:
        """Create a workflow checkpoint."""
        result = subprocess.run(
            [
                str(self.scripts_dir / "checkpoint.sh"),
                "create",
                message
            ],
            capture_output=True,
            text=True,
            cwd=str(self.root)
        )

        # Parse checkpoint ID from output
        for line in result.stdout.split('\n'):
            if line.startswith('CP_'):
                return line.strip()

        return result.stdout.strip()

    async def _update_session_metadata(
        self,
        session_id: str,
        metadata: Dict[str, Any]
    ):
        """Update session metadata in sessions.yaml."""
        # This would update the YAML file with org_id, task_id, etc.
        pass
```

**Tasks:**

1. **Create UWS adapter**
   - Wrap UWS shell scripts in Python
   - Handle async execution

2. **Add API routes for agents**
   ```
   GET  /api/agents              # List available agents
   POST /api/agents/activate     # Activate an agent
   GET  /api/agents/sessions     # List active sessions
   GET  /api/agents/sessions/:id # Get session details
   PUT  /api/agents/sessions/:id # Update session
   DELETE /api/agents/sessions/:id # End session
   ```

3. **Connect WebSocket to API events**
   - Bridge dashboard WebSocket to API events

**Deliverables:**
- [ ] UWS adapter working
- [ ] Agent activation via API
- [ ] Session management via API
- [ ] Skills listing via API

### Week 4: Task Management & Event Sourcing

**Goal**: Task CRUD with event sourcing

**Tasks:**

1. **Implement event store client**
   - Use code from `CRITICAL_01_DATA_ARCHITECTURE.md`

2. **Create task domain service**
   - CreateTask command
   - UpdateTask command
   - AssignTask command (to agent)
   - StatusChange command

3. **Build projections**
   - TaskProjection for read model
   - AgentSessionProjection

4. **Add task API routes**
   ```
   GET    /api/tasks              # List tasks
   POST   /api/tasks              # Create task
   GET    /api/tasks/:id          # Get task
   PUT    /api/tasks/:id          # Update task
   POST   /api/tasks/:id/assign   # Assign to agent
   DELETE /api/tasks/:id          # Delete task
   ```

5. **Connect tasks to agents**
   - When task assigned to agent → activate agent session
   - When agent completes → update task status

**Deliverables:**
- [ ] Event store working
- [ ] Task CRUD via API
- [ ] Tasks assigned to agents
- [ ] Agent completion updates tasks

---

## Phase 2: Integration (Weeks 5-8)

### Week 5: GitHub Integration

**Goal**: Sync GitHub Issues with Company OS Tasks

**Tasks:**

1. **GitHub OAuth app setup**
   - Repository permissions
   - Webhook registration

2. **Issue sync**
   ```
   GitHub Issue Created → Company OS Task Created
   GitHub Issue Updated → Company OS Task Updated
   Company OS Task Updated → GitHub Issue Updated
   ```

3. **PR tracking**
   - Link PRs to tasks
   - Status updates from PR state

**API Routes:**
```
GET  /api/integrations/github/repos
POST /api/integrations/github/sync
POST /api/webhooks/github  # Webhook receiver
```

### Week 6: Project & Organization Management

**Goal**: Multi-project, multi-org support

**Tasks:**

1. **Organization management**
   - Create/update organizations
   - Member management
   - Role assignment

2. **Project management**
   - Create projects within org
   - Project settings
   - Project-level permissions

3. **Row-level security enforcement**
   - All queries scoped to org
   - RLS policies active

### Week 7: Dashboard Enhancement

**Goal**: Upgrade existing dashboard for Company OS

**Tasks:**

1. **Authentication UI**
   - Login/register forms
   - GitHub OAuth button
   - Session management

2. **Project view**
   - Project list
   - Project details
   - Task board (kanban)

3. **Agent enhancement**
   - Keep existing agent cards
   - Add task context
   - Show approval requests

### Week 8: Human-in-the-Loop Controls

**Goal**: Implement approval workflows

**Tasks:**

1. **Approval request system**
   - Agents request approval for high-risk actions
   - Notifications to humans
   - Approval/rejection flow

2. **Autonomy configuration**
   - Per-agent autonomy levels
   - Per-action approval requirements
   - Emergency stop capability

3. **Intervention UI**
   - Approval queue
   - One-click approve/reject
   - Override controls

---

## Phase 3: Production Ready (Weeks 9-12)

### Week 9: Security Hardening

- [ ] Implement agent sandboxing (Docker)
- [ ] Add rate limiting
- [ ] Set up secrets management (Vault or env)
- [ ] Security audit of all endpoints
- [ ] Input validation everywhere

### Week 10: Observability

- [ ] Structured logging (JSON)
- [ ] Prometheus metrics
- [ ] Grafana dashboards
- [ ] Alerting rules
- [ ] Error tracking (Sentry)

### Week 11: Testing & Documentation

- [ ] Unit tests (80% coverage)
- [ ] Integration tests
- [ ] API documentation (OpenAPI)
- [ ] User documentation
- [ ] Deployment guide

### Week 12: Deployment

- [ ] Production Docker setup
- [ ] CI/CD pipeline
- [ ] Database backups
- [ ] SSL/TLS configuration
- [ ] Domain setup

---

## Milestone Checklist

### MVP (Week 4)
- [ ] Users can register/login
- [ ] Users can create tasks
- [ ] Tasks can be assigned to agents
- [ ] Agents execute via UWS
- [ ] Task status updates automatically
- [ ] Dashboard shows agent activity

### Beta (Week 8)
- [ ] GitHub integration working
- [ ] Multiple projects supported
- [ ] Human approval workflows
- [ ] Team collaboration
- [ ] Basic permissions

### Production (Week 12)
- [ ] Security hardened
- [ ] Monitoring in place
- [ ] Documentation complete
- [ ] Backups configured
- [ ] Ready for customers

---

## Technical Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Intelligence Layer | UWS Core | Already built, proven, integrates with Claude Code |
| Database | PostgreSQL Only | Simplicity, JSONB for events, pgvector for embeddings |
| API Framework | FastAPI | Async, Python (matches UWS scripts), great docs |
| Auth | JWT + OAuth | Industry standard, stateless |
| Real-time | WebSocket (existing) | Already works in dashboard |
| State Management | Event Sourcing | Full audit trail, replay capability |
| Agent Runtime | Claude Code + UWS | Existing integration, skill system |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| UWS shell scripts don't scale | Rewrite critical paths in Python if needed |
| WebSocket single server | Add Redis pub/sub when >100 users |
| Event store performance | Add read replicas, optimize indexes |
| Agent runaway costs | Add rate limits, budget caps per org |

---

## Resource Requirements

### Development
- 1 Full-stack developer
- 1 DevOps engineer (part-time)

### Infrastructure (MVP)
- PostgreSQL: 1 vCPU, 2GB RAM, 20GB SSD
- Redis: 1 vCPU, 1GB RAM
- API Server: 2 vCPU, 4GB RAM
- **Estimated cost**: $100-200/month

### Infrastructure (Production)
- PostgreSQL: 2 vCPU, 8GB RAM, 100GB SSD (managed)
- Redis: 2 vCPU, 4GB RAM (managed)
- API Servers: 2x (2 vCPU, 4GB RAM)
- **Estimated cost**: $500-800/month

---

## Success Criteria

### Week 4 (MVP)
- User can sign up and create a task
- Task can be assigned to researcher agent
- Agent executes and provides results
- Task status automatically updates to "done"
- Total time: < 5 minutes for demo

### Week 8 (Beta)
- 10 beta users actively using system
- GitHub integration working for 3+ repos
- No critical bugs in 1 week
- Agent success rate > 80%

### Week 12 (Launch)
- 50+ active users
- < 500ms API response time (p95)
- 99% uptime over 1 month
- Zero security incidents
- First paying customer

---

## Next Steps

1. **Today**: Review this roadmap
2. **Tomorrow**: Create project structure
3. **This Week**: Week 1 tasks (database, docker)
4. **Next Week**: Authentication system

**Ready to start?**
