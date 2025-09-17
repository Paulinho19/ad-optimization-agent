CREATE TABLE IF NOT EXISTS creative_variants (
    id SERIAL PRIMARY KEY,
    campaign_id TEXT NOT NULL,
    variant_headline TEXT,
    variant_text TEXT,
    rationale TEXT,
    similarity_score NUMERIC(5,2),
    status TEXT DEFAULT 'staged', -- staged, approved, rejected, published
    created_at TIMESTAMP DEFAULT now()
);

-- Simple Relantionships
CREATE INDEX IF NOT EXISTS idx_creative_campaign ON creative_variants(campaign_id);
CREATE INDEX IF NOT EXISTS idx_creative_status ON creative_variants(status);
