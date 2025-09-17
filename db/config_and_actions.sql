-- Threshold and configuration settings for optimization actions
CREATE TABLE IF NOT EXISTS optimization_config (
    id SERIAL PRIMARY KEY,
    platform TEXT NOT NULL,
    pause_cpl_threshold NUMERIC(12,2),
    min_conversions INT,
    reduce_roas_threshold NUMERIC(12,2),
    min_spend NUMERIC(12,2),
    updated_at TIMESTAMP DEFAULT now()
);

-- Executed log of actions taken on campaigns
CREATE TABLE IF NOT EXISTS campaign_actions (
    id SERIAL PRIMARY KEY,
    campaign_id TEXT NOT NULL,
    campaign_name TEXT,
    platform TEXT,
    action TEXT NOT NULL, -- pause | reduce_budget
    details JSONB,
    executed_at TIMESTAMP DEFAULT now(),
    UNIQUE(campaign_id) 
);

CREATE INDEX IF NOT EXISTS idx_actions_campaign ON campaign_actions(campaign_id);
CREATE INDEX IF NOT EXISTS idx_actions_date ON campaign_actions(executed_at);
