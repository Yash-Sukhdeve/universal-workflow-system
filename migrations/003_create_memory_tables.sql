-- Semantic Memory Schema
-- pgvector-based memory for agent learning and context enhancement

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Memory types enum
DO $$ BEGIN
    CREATE TYPE memory_type AS ENUM (
        'task',
        'decision',
        'code_pattern',
        'handoff',
        'skill',
        'error'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Main memories table
CREATE TABLE IF NOT EXISTS memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

    memory_type memory_type NOT NULL,
    content TEXT NOT NULL,
    embedding vector(1536) NOT NULL,  -- OpenAI text-embedding-3-small dimensions

    -- Quality and usage tracking
    quality_score FLOAT DEFAULT 0.5 CHECK (quality_score >= 0 AND quality_score <= 1),
    usage_count INT DEFAULT 0,
    last_used_at TIMESTAMPTZ,

    -- Flexible metadata
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row Level Security for multi-tenancy
ALTER TABLE memories ENABLE ROW LEVEL SECURITY;

-- RLS policy: users can only access their organization's memories
CREATE POLICY memories_org_isolation ON memories
    USING (org_id = current_setting('app.current_org_id', true)::uuid);

-- Vector similarity search index (IVFFlat for large datasets)
CREATE INDEX IF NOT EXISTS idx_memories_embedding ON memories
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Other indexes
CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(memory_type);
CREATE INDEX IF NOT EXISTS idx_memories_org ON memories(org_id);
CREATE INDEX IF NOT EXISTS idx_memories_created ON memories(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_memories_quality ON memories(quality_score DESC);
CREATE INDEX IF NOT EXISTS idx_memories_metadata ON memories USING GIN(metadata);

-- Memory links (for related memories)
CREATE TABLE IF NOT EXISTS memory_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    link_type VARCHAR(50) NOT NULL,  -- 'related', 'supersedes', 'derives_from'
    strength FLOAT DEFAULT 1.0 CHECK (strength >= 0 AND strength <= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(source_id, target_id, link_type)
);

CREATE INDEX IF NOT EXISTS idx_memory_links_source ON memory_links(source_id);
CREATE INDEX IF NOT EXISTS idx_memory_links_target ON memory_links(target_id);

-- Skill effectiveness tracking
CREATE TABLE IF NOT EXISTS skill_effectiveness (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    skill_name VARCHAR(100) NOT NULL,
    context_embedding vector(1536),  -- Context where skill was used
    success_rate FLOAT NOT NULL CHECK (success_rate >= 0 AND success_rate <= 1),
    avg_quality FLOAT NOT NULL CHECK (avg_quality >= 0 AND avg_quality <= 1),
    sample_count INT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(org_id, skill_name)
);

CREATE INDEX IF NOT EXISTS idx_skill_effectiveness_org ON skill_effectiveness(org_id);
CREATE INDEX IF NOT EXISTS idx_skill_effectiveness_name ON skill_effectiveness(skill_name);

-- Skill chains (which skills work well together)
CREATE TABLE IF NOT EXISTS skill_chains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    skills VARCHAR(100)[] NOT NULL,
    context_embedding vector(1536),
    effectiveness FLOAT NOT NULL CHECK (effectiveness >= 0 AND effectiveness <= 1),
    usage_count INT DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_skill_chains_org ON skill_chains(org_id);
CREATE INDEX IF NOT EXISTS idx_skill_chains_skills ON skill_chains USING GIN(skills);

-- Function to search similar memories
CREATE OR REPLACE FUNCTION search_memories(
    p_org_id UUID,
    p_query_embedding vector(1536),
    p_memory_types memory_type[] DEFAULT NULL,
    p_min_similarity FLOAT DEFAULT 0.5,
    p_limit INT DEFAULT 10
) RETURNS TABLE (
    id UUID,
    memory_type memory_type,
    content TEXT,
    embedding vector(1536),
    quality_score FLOAT,
    metadata JSONB,
    created_at TIMESTAMPTZ,
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.memory_type,
        m.content,
        m.embedding,
        m.quality_score,
        m.metadata,
        m.created_at,
        1 - (m.embedding <=> p_query_embedding) as similarity
    FROM memories m
    WHERE m.org_id = p_org_id
      AND (p_memory_types IS NULL OR m.memory_type = ANY(p_memory_types))
      AND 1 - (m.embedding <=> p_query_embedding) >= p_min_similarity
    ORDER BY m.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to consolidate similar memories
CREATE OR REPLACE FUNCTION consolidate_memories(
    p_org_id UUID,
    p_memory_type memory_type,
    p_similarity_threshold FLOAT DEFAULT 0.95
) RETURNS INT AS $$
DECLARE
    v_deleted_count INT := 0;
    v_cluster RECORD;
BEGIN
    -- Find and delete lower quality duplicates
    FOR v_cluster IN
        SELECT
            m1.id as id1,
            m2.id as id2,
            m1.quality_score as q1,
            m2.quality_score as q2
        FROM memories m1
        JOIN memories m2 ON m1.id < m2.id
        WHERE m1.org_id = p_org_id
          AND m2.org_id = p_org_id
          AND m1.memory_type = p_memory_type
          AND m2.memory_type = p_memory_type
          AND 1 - (m1.embedding <=> m2.embedding) >= p_similarity_threshold
    LOOP
        IF v_cluster.q1 >= v_cluster.q2 THEN
            DELETE FROM memories WHERE id = v_cluster.id2;
        ELSE
            DELETE FROM memories WHERE id = v_cluster.id1;
        END IF;
        v_deleted_count := v_deleted_count + 1;
    END LOOP;

    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Update trigger for memories
CREATE TRIGGER update_memories_updated_at
    BEFORE UPDATE ON memories
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TABLE memories IS 'Semantic memory store for agent learning';
COMMENT ON COLUMN memories.embedding IS 'Vector embedding for semantic similarity search';
COMMENT ON COLUMN memories.quality_score IS 'Human-rated quality (0-1)';
COMMENT ON TABLE skill_effectiveness IS 'Tracks how effective each skill is in different contexts';
COMMENT ON TABLE skill_chains IS 'Tracks which skill combinations work well together';
