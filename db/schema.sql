CREATE TABLE IF NOT EXISTS campaign_metrics (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    platform TEXT NOT NULL,
    account_id TEXT NOT NULL,
    campaign_id TEXT NOT NULL,
    campaign_name TEXT,
    spend NUMERIC(12,2) DEFAULT 0,
    impressions BIGINT DEFAULT 0,
    clicks BIGINT DEFAULT 0,
    conversions BIGINT DEFAULT 0,
    cpl NUMERIC(12,2),
    roas NUMERIC(12,2),
    created_at TIMESTAMP DEFAULT now(),
    UNIQUE(date, platform, campaign_id)
);

-- Indexes to accelerate common queries
CREATE INDEX IF NOT EXISTS idx_metrics_date ON campaign_metrics(date);
CREATE INDEX IF NOT EXISTS idx_metrics_platform ON campaign_metrics(platform);
CREATE INDEX IF NOT EXISTS idx_metrics_campaign ON campaign_metrics(campaign_id);
