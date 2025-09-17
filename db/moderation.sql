CREATE TABLE IF NOT EXISTS moderation_items (
    id SERIAL PRIMARY KEY,
    platform TEXT NOT NULL,
    object_id TEXT NOT NULL,
    user_name TEXT,
    original_text TEXT NOT NULL,
    permalink TEXT,
    intent TEXT, -- toxic | spam | complaint | question | praise | other
    sentiment TEXT, -- positive | neutral | negative
    reply_required BOOLEAN DEFAULT false,
    suggested_reply TEXT,
    rationale TEXT,
    status TEXT DEFAULT 'Needs Approval', -- Needs Approval | Approved | Posted | Rejected
    action TEXT DEFAULT 'None', -- None | Post Reply | Like | Hide
    approved_by TEXT,
    approved_at TIMESTAMP,
    posted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT now(),
    UNIQUE(platform, object_id)
);

CREATE INDEX IF NOT EXISTS idx_moderation_status ON moderation_items(status);
CREATE INDEX IF NOT EXISTS idx_moderation_intent ON moderation_items(intent);
