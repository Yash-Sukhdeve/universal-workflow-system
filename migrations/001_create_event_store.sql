-- Event Store Schema
-- PostgreSQL-based event sourcing with optimistic concurrency control

-- Events table (append-only log)
CREATE TABLE IF NOT EXISTS events (
    id BIGSERIAL PRIMARY KEY,
    stream_id VARCHAR(255) NOT NULL,
    stream_version INT NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    metadata JSONB DEFAULT '{}',
    org_id UUID,  -- Multi-tenancy support
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Optimistic concurrency: unique stream_id + version
    CONSTRAINT events_stream_version_unique UNIQUE(stream_id, stream_version)
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_events_stream_id ON events(stream_id);
CREATE INDEX IF NOT EXISTS idx_events_event_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_org_id ON events(org_id);
CREATE INDEX IF NOT EXISTS idx_events_stream_version ON events(stream_id, stream_version);

-- Function for atomic event append with concurrency check
CREATE OR REPLACE FUNCTION append_event(
    p_stream_id VARCHAR(255),
    p_expected_version INT,
    p_event_type VARCHAR(100),
    p_event_data JSONB,
    p_metadata JSONB DEFAULT '{}',
    p_org_id UUID DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    v_current_version INT;
    v_event_id BIGINT;
BEGIN
    -- Get current stream version with lock
    SELECT COALESCE(MAX(stream_version), -1)
    INTO v_current_version
    FROM events
    WHERE stream_id = p_stream_id
    FOR UPDATE;

    -- Check expected version (-1 means no check)
    IF p_expected_version != -1 AND v_current_version != p_expected_version THEN
        RAISE EXCEPTION 'Concurrency conflict on stream %: expected version %, found %',
            p_stream_id, p_expected_version, v_current_version
            USING ERRCODE = 'serialization_failure';
    END IF;

    -- Insert new event
    INSERT INTO events (stream_id, stream_version, event_type, event_data, metadata, org_id)
    VALUES (p_stream_id, v_current_version + 1, p_event_type, p_event_data, p_metadata, p_org_id)
    RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql;

-- Event subscriptions table (for tracking projection positions)
CREATE TABLE IF NOT EXISTS event_subscriptions (
    subscription_id VARCHAR(100) PRIMARY KEY,
    last_position BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Function to update subscription position
CREATE OR REPLACE FUNCTION update_subscription_position(
    p_subscription_id VARCHAR(100),
    p_position BIGINT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO event_subscriptions (subscription_id, last_position, updated_at)
    VALUES (p_subscription_id, p_position, NOW())
    ON CONFLICT (subscription_id)
    DO UPDATE SET
        last_position = p_position,
        updated_at = NOW()
    WHERE event_subscriptions.last_position < p_position;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE events IS 'Append-only event store for event sourcing';
COMMENT ON COLUMN events.stream_id IS 'Unique identifier for the event stream (e.g., task-{uuid})';
COMMENT ON COLUMN events.stream_version IS 'Monotonically increasing version within stream';
COMMENT ON COLUMN events.event_type IS 'Type of event (e.g., TaskCreated, TaskUpdated)';
