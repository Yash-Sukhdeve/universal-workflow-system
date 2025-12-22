-- Read Models Schema
-- Denormalized projections from event store for fast queries

-- Projects read model
CREATE TABLE IF NOT EXISTS projects_read_model (
    id UUID PRIMARY KEY,
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'active',  -- active, archived, completed
    settings JSONB DEFAULT '{}',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- Enable RLS
ALTER TABLE projects_read_model ENABLE ROW LEVEL SECURITY;

CREATE POLICY projects_org_isolation ON projects_read_model
    USING (org_id = current_setting('app.current_org_id', true)::uuid);

CREATE INDEX IF NOT EXISTS idx_projects_org ON projects_read_model(org_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects_read_model(status);

-- Tasks read model
CREATE TABLE IF NOT EXISTS tasks_read_model (
    id UUID PRIMARY KEY,
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_id UUID REFERENCES projects_read_model(id) ON DELETE SET NULL,

    title VARCHAR(500) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',  -- pending, in_progress, completed, cancelled
    priority VARCHAR(20) NOT NULL DEFAULT 'medium',  -- low, medium, high, critical

    -- Assignment
    assigned_agent VARCHAR(50),  -- researcher, architect, implementer, etc.
    assigned_user_id UUID REFERENCES users(id),

    -- Tracking
    created_by UUID NOT NULL REFERENCES users(id),
    due_date TIMESTAMPTZ,
    tags VARCHAR(50)[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- Enable RLS
ALTER TABLE tasks_read_model ENABLE ROW LEVEL SECURITY;

CREATE POLICY tasks_org_isolation ON tasks_read_model
    USING (org_id = current_setting('app.current_org_id', true)::uuid);

CREATE INDEX IF NOT EXISTS idx_tasks_org ON tasks_read_model(org_id);
CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks_read_model(project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks_read_model(status);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_agent ON tasks_read_model(assigned_agent);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_user ON tasks_read_model(assigned_user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks_read_model(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_tags ON tasks_read_model USING GIN(tags);

-- Agent sessions read model (mirrors UWS sessions)
CREATE TABLE IF NOT EXISTS agent_sessions_read_model (
    id VARCHAR(50) PRIMARY KEY,
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    task_id UUID REFERENCES tasks_read_model(id) ON DELETE SET NULL,

    agent_type VARCHAR(50) NOT NULL,
    task_description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'active',  -- active, paused, completed, failed
    progress INT DEFAULT 0 CHECK (progress >= 0 AND progress <= 100),

    -- Execution tracking
    started_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    result VARCHAR(50),  -- success, failure, timeout

    -- Context
    thought_stream JSONB DEFAULT '[]',  -- Recent thoughts/actions
    metadata JSONB DEFAULT '{}'
);

-- Enable RLS
ALTER TABLE agent_sessions_read_model ENABLE ROW LEVEL SECURITY;

CREATE POLICY sessions_org_isolation ON agent_sessions_read_model
    USING (org_id = current_setting('app.current_org_id', true)::uuid);

CREATE INDEX IF NOT EXISTS idx_sessions_org ON agent_sessions_read_model(org_id);
CREATE INDEX IF NOT EXISTS idx_sessions_task ON agent_sessions_read_model(task_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON agent_sessions_read_model(status);
CREATE INDEX IF NOT EXISTS idx_sessions_agent ON agent_sessions_read_model(agent_type);

-- Approval requests (human-in-the-loop)
CREATE TABLE IF NOT EXISTS approval_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    session_id VARCHAR(50) REFERENCES agent_sessions_read_model(id) ON DELETE CASCADE,
    task_id UUID REFERENCES tasks_read_model(id) ON DELETE SET NULL,

    request_type VARCHAR(50) NOT NULL,  -- action, commit, deploy, etc.
    description TEXT NOT NULL,
    context JSONB DEFAULT '{}',

    status VARCHAR(50) NOT NULL DEFAULT 'pending',  -- pending, approved, rejected
    decided_by UUID REFERENCES users(id),
    decided_at TIMESTAMPTZ,
    decision_reason TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE approval_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY approvals_org_isolation ON approval_requests
    USING (org_id = current_setting('app.current_org_id', true)::uuid);

CREATE INDEX IF NOT EXISTS idx_approvals_org ON approval_requests(org_id);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON approval_requests(status);
CREATE INDEX IF NOT EXISTS idx_approvals_session ON approval_requests(session_id);

-- Metrics snapshots (for dashboards)
CREATE TABLE IF NOT EXISTS metrics_snapshots (
    id BIGSERIAL PRIMARY KEY,
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    snapshot_date DATE NOT NULL,
    metrics_type VARCHAR(50) NOT NULL,  -- daily, weekly, monthly
    metrics JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(org_id, snapshot_date, metrics_type)
);

CREATE INDEX IF NOT EXISTS idx_metrics_org_date ON metrics_snapshots(org_id, snapshot_date DESC);

-- View for task statistics
CREATE OR REPLACE VIEW task_statistics AS
SELECT
    org_id,
    COUNT(*) as total_tasks,
    COUNT(*) FILTER (WHERE status = 'pending') as pending_tasks,
    COUNT(*) FILTER (WHERE status = 'in_progress') as in_progress_tasks,
    COUNT(*) FILTER (WHERE status = 'completed') as completed_tasks,
    COUNT(*) FILTER (WHERE status = 'cancelled') as cancelled_tasks,
    COUNT(*) FILTER (WHERE assigned_agent IS NOT NULL) as agent_assigned_tasks,
    COUNT(*) FILTER (WHERE assigned_user_id IS NOT NULL) as user_assigned_tasks
FROM tasks_read_model
GROUP BY org_id;

-- View for agent performance
CREATE OR REPLACE VIEW agent_performance AS
SELECT
    org_id,
    agent_type,
    COUNT(*) as total_sessions,
    COUNT(*) FILTER (WHERE result = 'success') as successful_sessions,
    COUNT(*) FILTER (WHERE result = 'failure') as failed_sessions,
    AVG(progress) FILTER (WHERE status = 'completed') as avg_completion_progress,
    AVG(EXTRACT(EPOCH FROM (completed_at - started_at))) FILTER (WHERE completed_at IS NOT NULL) as avg_duration_seconds
FROM agent_sessions_read_model
GROUP BY org_id, agent_type;

COMMENT ON TABLE tasks_read_model IS 'Denormalized task view projected from events';
COMMENT ON TABLE agent_sessions_read_model IS 'Agent session tracking synced with UWS';
COMMENT ON TABLE approval_requests IS 'Human-in-the-loop approval queue';
