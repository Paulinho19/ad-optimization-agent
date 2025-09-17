# Part 4: Social Listening & Mini Dashboard

## Overview

This module implements a comprehensive social media moderation system that monitors Facebook and Instagram comments, mentions, and DMs. It uses AI to classify sentiment and intent, takes automated moderation actions, and provides a streamlined approval workflow for responses through Notion integration.

## 🎯 Goals

- Monitor FB/IG comments, mentions, and DMs in real-time
- Classify sentiment and intent using AI
- Take automated moderation actions (hide/delete spam/toxic content)
- Escalate complaints to Slack with context
- Generate suggested replies for approval
- Implement one-click approval workflow in Notion
- Provide a mini dashboard for monitoring and KPIs

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Social Media  │    │   AI Processing │    │   Actions       │
│                 │    │                 │    │                 │
│ • FB/IG API     │───▶│ • Sentiment     │───▶│ • Auto Actions  │
│ • Webhooks      │    │ • Intent        │    │ • Notion Queue  │
│ • Polling       │    │ • Moderation    │    │ • Slack Alerts  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   Dashboard     │
                       │                 │
                       │ • KPIs          │
                       │ • Recent Actions│
                       │ • Analytics     │
                       └─────────────────┘
```

## 📊 Data Schema

### Social Media Items

```sql
CREATE TABLE social_media_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform VARCHAR(50) NOT NULL, -- 'facebook', 'instagram'
    object_id VARCHAR(255) NOT NULL, -- Platform-specific ID
    parent_id VARCHAR(255), -- For replies
    object_type VARCHAR(50) NOT NULL, -- 'comment', 'mention', 'dm'
    user_id VARCHAR(255) NOT NULL,
    user_name VARCHAR(255),
    text TEXT NOT NULL,
    permalink TEXT,
    created_time TIMESTAMP NOT NULL,
    raw_data JSONB, -- Original API response
    created_at TIMESTAMP DEFAULT NOW(),

    -- Composite unique constraint
    UNIQUE(platform, object_id),

    -- Indexes
    INDEX idx_platform_object_type (platform, object_type),
    INDEX idx_created_time (created_time),
    INDEX idx_user_id (user_id)
);
```

### Classification Results

```sql
CREATE TABLE item_classifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID REFERENCES social_media_items(id),
    intent VARCHAR(50) NOT NULL, -- 'toxic', 'spam', 'complaint', 'question', 'praise', 'other'
    sentiment VARCHAR(20) NOT NULL, -- 'positive', 'negative', 'neutral'
    confidence_score DECIMAL(3,2) NOT NULL, -- 0.00 to 1.00
    reply_required BOOLEAN NOT NULL,
    moderation_flags JSONB, -- Additional flags
    classification_metadata JSONB, -- Model info, processing time, etc.
    created_at TIMESTAMP DEFAULT NOW(),

    -- Indexes
    INDEX idx_item_id (item_id),
    INDEX idx_intent (intent),
    INDEX idx_sentiment (sentiment),
    INDEX idx_reply_required (reply_required)
);
```

### Moderation Actions

```sql
CREATE TABLE moderation_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID REFERENCES social_media_items(id),
    action_type VARCHAR(50) NOT NULL, -- 'hide', 'delete', 'escalate', 'reply', 'like'
    action_status VARCHAR(50) NOT NULL, -- 'pending', 'approved', 'executed', 'failed'
    action_details JSONB, -- Action parameters
    suggested_reply TEXT, -- AI-generated reply
    reply_rationale TEXT, -- Why this reply was suggested
    notion_record_id VARCHAR(255), -- Notion page ID for approval
    executed_at TIMESTAMP,
    executed_by VARCHAR(100), -- 'system', 'user_id'
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW(),

    -- Indexes
    INDEX idx_item_id (item_id),
    INDEX idx_action_type (action_type),
    INDEX idx_action_status (action_status),
    INDEX idx_notion_record_id (notion_record_id)
);
```

### Dashboard Metrics

```sql
CREATE TABLE moderation_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL,
    platform VARCHAR(50) NOT NULL,
    total_items BIGINT NOT NULL,
    items_by_intent JSONB NOT NULL, -- Count by intent type
    items_by_sentiment JSONB NOT NULL, -- Count by sentiment
    actions_taken JSONB NOT NULL, -- Count by action type
    response_time_avg DECIMAL(8,2), -- Average response time in minutes
    escalation_count BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),

    -- Composite unique constraint
    UNIQUE(date, platform),

    -- Indexes
    INDEX idx_date_platform (date, platform),
    INDEX idx_date (date)
);
```

## 🔄 Workflow Implementation

### n8n Workflow: `moderation.json`

#### 1. Data Ingestion

**Facebook/Instagram API Integration**

```javascript
// Poll recent comments, mentions, and DMs
const fetchSocialMediaData = async (platform, objectType) => {
  const endpoints = {
    facebook: {
      comments: `https://graph.facebook.com/v18.0/me/comments`,
      mentions: `https://graph.facebook.com/v18.0/me/mentions`,
      messages: `https://graph.facebook.com/v18.0/me/conversations`,
    },
    instagram: {
      comments: `https://graph.facebook.com/v18.0/me/media/comments`,
      mentions: `https://graph.facebook.com/v18.0/me/media/mentions`,
    },
  };

  const response = await fetch(endpoints[platform][objectType], {
    headers: {
      Authorization: `Bearer ${process.env.META_ACCESS_TOKEN}`,
      "Content-Type": "application/json",
    },
    params: {
      since: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(), // Last 24 hours
      limit: 100,
    },
  });

  return await response.json();
};
```

**Webhook Handler (Alternative)**

```javascript
// Handle real-time webhooks from Meta
const webhookHandler = (req, res) => {
  const { entry } = req.body;

  entry.forEach((page) => {
    page.changes.forEach((change) => {
      if (change.field === "feed") {
        processSocialMediaItem(change.value);
      }
    });
  });

  res.status(200).send("OK");
};
```

#### 2. AI Classification

**Intent Classification**

```javascript
const classifyIntent = async (text) => {
  const prompt = `
Analyze the following social media text and classify its intent:

Text: "${text}"

Classify as one of these categories:
- toxic: Hate speech, harassment, threats, explicit content
- spam: Promotional content, irrelevant links, repetitive messages
- complaint: Customer service issues, product problems, negative feedback
- question: Genuine questions about products, services, or support
- praise: Positive feedback, compliments, testimonials
- other: General conversation, neutral comments

Respond with JSON format:
{
  "intent": "category",
  "confidence": 0.95,
  "reasoning": "Brief explanation of classification"
}
`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content:
            "You are an expert social media moderator. Classify content accurately and safely.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      temperature: 0.3,
      max_tokens: 200,
    }),
  });

  const result = await response.json();
  return JSON.parse(result.choices[0].message.content);
};
```

**Sentiment Analysis**

```javascript
const analyzeSentiment = async (text) => {
  const prompt = `
Analyze the sentiment of this social media text:

Text: "${text}"

Classify as:
- positive: Happy, satisfied, enthusiastic
- negative: Angry, disappointed, frustrated
- neutral: Factual, indifferent, informational

Respond with JSON format:
{
  "sentiment": "positive|negative|neutral",
  "confidence": 0.90,
  "intensity": "low|medium|high"
}
`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content:
            "You are an expert sentiment analyst. Provide accurate sentiment classification.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      temperature: 0.2,
      max_tokens: 150,
    }),
  });

  const result = await response.json();
  return JSON.parse(result.choices[0].message.content);
};
```

#### 3. Automated Moderation Actions

**Action Decision Engine**

```javascript
const determineAction = (classification) => {
  const { intent, sentiment, confidence } = classification;

  // High confidence toxic content - immediate hide
  if (intent === "toxic" && confidence > 0.8) {
    return {
      action: "hide",
      autoExecute: true,
      reason: "High confidence toxic content detected",
    };
  }

  // High confidence spam - immediate delete
  if (intent === "spam" && confidence > 0.9) {
    return {
      action: "delete",
      autoExecute: true,
      reason: "High confidence spam detected",
    };
  }

  // Complaints - escalate to Slack
  if (intent === "complaint") {
    return {
      action: "escalate",
      autoExecute: true,
      reason: "Customer complaint requires attention",
    };
  }

  // Questions and praise - generate reply
  if (intent === "question" || intent === "praise") {
    return {
      action: "reply",
      autoExecute: false,
      reason: "Response required for customer engagement",
    };
  }

  // Default - no action
  return {
    action: "none",
    autoExecute: false,
    reason: "No action required",
  };
};
```

**Auto-Execute Actions**

```javascript
const executeAutoAction = async (item, action) => {
  try {
    switch (action.action) {
      case "hide":
        await hideComment(item.platform, item.object_id);
        break;
      case "delete":
        await deleteComment(item.platform, item.object_id);
        break;
      case "escalate":
        await escalateToSlack(item, action.reason);
        break;
      default:
        return { success: false, error: "Unknown action" };
    }

    // Log the action
    await logModerationAction(item.id, action.action, "executed", {
      auto_executed: true,
      reason: action.reason,
    });

    return { success: true };
  } catch (error) {
    await logModerationAction(item.id, action.action, "failed", {
      error: error.message,
    });
    return { success: false, error: error.message };
  }
};
```

#### 4. Reply Generation

**AI Reply Generation**

```javascript
const generateSuggestedReply = async (item, classification) => {
  const prompt = `
You are a helpful customer service representative. Generate a professional, empathetic response to this social media interaction.

Original Text: "${item.text}"
Intent: ${classification.intent}
Sentiment: ${classification.sentiment}

Guidelines:
- Be professional and empathetic
- Address the specific concern or question
- Keep it concise (under 280 characters)
- Match the tone appropriately
- Include relevant information or next steps
- Never make promises you can't keep

Generate a response and provide a brief rationale for your approach.
`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4",
      messages: [
        {
          role: "system",
          content:
            "You are an expert customer service representative. Generate helpful, professional responses.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      temperature: 0.7,
      max_tokens: 300,
    }),
  });

  const result = await response.json();
  const content = result.choices[0].message.content;

  // Parse response and rationale
  const lines = content.split("\n");
  const reply = lines[0];
  const rationale = lines.slice(1).join("\n");

  return {
    suggested_reply: reply,
    rationale: rationale,
  };
};
```

#### 5. Notion Integration

**Create Approval Record**

```javascript
const createNotionApprovalRecord = async (
  item,
  classification,
  suggestedReply
) => {
  const notionRecord = {
    parent: { database_id: process.env.NOTION_MODERATION_DB_ID },
    properties: {
      Platform: { select: { name: item.platform } },
      Intent: { select: { name: classification.intent } },
      Sentiment: { select: { name: classification.sentiment } },
      "Original Text": {
        rich_text: [{ text: { content: item.text } }],
      },
      "Suggested Reply": {
        rich_text: [{ text: { content: suggestedReply.suggested_reply } }],
      },
      Rationale: {
        rich_text: [{ text: { content: suggestedReply.rationale } }],
      },
      Status: { select: { name: "Needs Approval" } },
      Action: { select: { name: "None" } },
      Permalink: { url: item.permalink },
      "Created Time": { date: { start: item.created_time } },
      "Object ID": { rich_text: [{ text: { content: item.object_id } }] },
    },
  };

  const response = await fetch("https://api.notion.com/v1/pages", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.NOTION_API_KEY}`,
      "Content-Type": "application/json",
      "Notion-Version": "2022-06-28",
    },
    body: JSON.stringify(notionRecord),
  });

  const result = await response.json();
  return result.id;
};
```

**Notion Approval Watcher**

```javascript
const watchNotionApprovals = async () => {
  // Query for approved records
  const response = await fetch(
    `https://api.notion.com/v1/databases/${process.env.NOTION_MODERATION_DB_ID}/query`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.NOTION_API_KEY}`,
        "Content-Type": "application/json",
        "Notion-Version": "2022-06-28",
      },
      body: JSON.stringify({
        filter: {
          and: [
            {
              property: "Status",
              select: { equals: "Approved" },
            },
            {
              property: "Action",
              select: { does_not_equal: "None" },
            },
          ],
        },
      }),
    }
  );

  const result = await response.json();

  // Process each approved record
  for (const record of result.results) {
    await processApprovedRecord(record);
  }
};
```

#### 6. Action Execution

**Execute Approved Actions**

```javascript
const processApprovedRecord = async (notionRecord) => {
  const properties = notionRecord.properties;
  const action = properties["Action"].select.name;
  const objectId = properties["Object ID"].rich_text[0].text.content;
  const platform = properties["Platform"].select.name;
  const suggestedReply =
    properties["Suggested Reply"].rich_text[0].text.content;

  try {
    let result;

    switch (action) {
      case "Post Reply":
        result = await postReply(platform, objectId, suggestedReply);
        break;
      case "Like":
        result = await likeComment(platform, objectId);
        break;
      default:
        throw new Error(`Unknown action: ${action}`);
    }

    if (result.success) {
      // Update Notion record
      await updateNotionRecord(notionRecord.id, "Posted", {
        posted_at: new Date().toISOString(),
        posted_by: "system",
      });

      // Send Slack confirmation
      await sendSlackConfirmation(notionRecord, result);
    }
  } catch (error) {
    await updateNotionRecord(notionRecord.id, "Failed", {
      error: error.message,
    });
  }
};
```

**Platform API Calls**

```javascript
const postReply = async (platform, objectId, replyText) => {
  const endpoints = {
    facebook: `https://graph.facebook.com/v18.0/${objectId}/comments`,
    instagram: `https://graph.facebook.com/v18.0/${objectId}/replies`,
  };

  const response = await fetch(endpoints[platform], {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.META_ACCESS_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: replyText,
    }),
  });

  return {
    success: response.ok,
    data: await response.json(),
  };
};

const likeComment = async (platform, objectId) => {
  const response = await fetch(
    `https://graph.facebook.com/v18.0/${objectId}/likes`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.META_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
    }
  );

  return {
    success: response.ok,
    data: await response.json(),
  };
};
```

#### 7. Slack Notifications

**Escalation Alerts**

```javascript
const escalateToSlack = async (item, reason) => {
  const message = {
    text: `🚨 Social Media Escalation Required`,
    blocks: [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: "🚨 Social Media Escalation Required",
        },
      },
      {
        type: "section",
        fields: [
          {
            type: "mrkdwn",
            text: `*Platform:* ${item.platform}`,
          },
          {
            type: "mrkdwn",
            text: `*Type:* ${item.object_type}`,
          },
          {
            type: "mrkdwn",
            text: `*User:* ${item.user_name}`,
          },
          {
            type: "mrkdwn",
            text: `*Reason:* ${reason}`,
          },
        ],
      },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: `*Content:* ${item.text}`,
        },
      },
      {
        type: "actions",
        elements: [
          {
            type: "button",
            text: {
              type: "plain_text",
              text: "View Post",
            },
            url: item.permalink,
            style: "primary",
          },
        ],
      },
    ],
  };

  await fetch(process.env.SLACK_WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });
};
```

**Action Confirmations**

```javascript
const sendSlackConfirmation = async (notionRecord, result) => {
  const properties = notionRecord.properties;
  const action = properties["Action"].select.name;
  const platform = properties["Platform"].select.name;

  const message = {
    text: `✅ Social Media Action Completed`,
    blocks: [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: "✅ Social Media Action Completed",
        },
      },
      {
        type: "section",
        fields: [
          {
            type: "mrkdwn",
            text: `*Action:* ${action}`,
          },
          {
            type: "mrkdwn",
            text: `*Platform:* ${platform}`,
          },
          {
            type: "mrkdwn",
            text: `*Status:* Success`,
          },
          {
            type: "mrkdwn",
            text: `*Time:* ${new Date().toLocaleString()}`,
          },
        ],
      },
    ],
  };

  await fetch(process.env.SLACK_WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });
};
```

## 📊 Mini Dashboard

### Databox Integration

```sql
-- Daily KPIs query
SELECT
    DATE(created_at) as date,
    platform,
    COUNT(*) as total_items,
    COUNT(CASE WHEN ic.intent = 'complaint' THEN 1 END) as complaints,
    COUNT(CASE WHEN ic.intent = 'question' THEN 1 END) as questions,
    COUNT(CASE WHEN ic.intent = 'praise' THEN 1 END) as praise,
    COUNT(CASE WHEN ma.action_type = 'reply' THEN 1 END) as replies_sent,
    AVG(EXTRACT(EPOCH FROM (ma.executed_at - smi.created_time))/60) as avg_response_time_minutes
FROM social_media_items smi
LEFT JOIN item_classifications ic ON smi.id = ic.item_id
LEFT JOIN moderation_actions ma ON smi.id = ma.item_id
WHERE smi.created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(created_at), platform
ORDER BY date DESC;
```

### v0/Lovable Dashboard

```javascript
// Dashboard component structure
const ModerationDashboard = () => {
  const [metrics, setMetrics] = useState(null);
  const [recentActions, setRecentActions] = useState([]);

  return (
    <div className="dashboard">
      <div className="kpi-cards">
        <KPICard
          title="Items Reviewed Today"
          value={metrics?.todayItems || 0}
          change={metrics?.itemsChange || 0}
        />
        <KPICard
          title="Response Rate"
          value={`${metrics?.responseRate || 0}%`}
          change={metrics?.responseRateChange || 0}
        />
        <KPICard
          title="Avg Response Time"
          value={`${metrics?.avgResponseTime || 0}m`}
          change={metrics?.responseTimeChange || 0}
        />
        <KPICard
          title="Escalations"
          value={metrics?.escalations || 0}
          change={metrics?.escalationsChange || 0}
        />
      </div>

      <div className="recent-actions">
        <h3>Recent Actions</h3>
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Platform</th>
              <th>Action</th>
              <th>Intent</th>
              <th>Link</th>
            </tr>
          </thead>
          <tbody>
            {recentActions.map((action) => (
              <tr key={action.id}>
                <td>{action.time}</td>
                <td>{action.platform}</td>
                <td>{action.action}</td>
                <td>{action.intent}</td>
                <td>
                  <a href={action.permalink} target="_blank" rel="noopener">
                    View
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};
```

## 🛡️ Safety & Moderation

### Content Safety

- **Toxic Content**: Automatic hiding with high confidence
- **Spam Detection**: Automatic deletion with 90%+ confidence
- **Complaint Escalation**: Immediate Slack notification
- **Human Review**: All replies require approval

### Moderation Policies

```javascript
const moderationPolicies = {
  toxic: {
    threshold: 0.8,
    action: "hide",
    autoExecute: true,
    escalation: false,
  },
  spam: {
    threshold: 0.9,
    action: "delete",
    autoExecute: true,
    escalation: false,
  },
  complaint: {
    threshold: 0.7,
    action: "escalate",
    autoExecute: true,
    escalation: true,
  },
  question: {
    threshold: 0.6,
    action: "reply",
    autoExecute: false,
    escalation: false,
  },
  praise: {
    threshold: 0.6,
    action: "reply",
    autoExecute: false,
    escalation: false,
  },
};
```

## 📊 Analytics & Reporting

### Key Metrics

- **Items Processed**: Daily count by platform and type
- **Response Rate**: % of items that received responses
- **Response Time**: Average time from item to response
- **Escalation Rate**: % of items escalated to Slack
- **Action Distribution**: Breakdown by action type

### Performance Tracking

```sql
-- Weekly performance report
SELECT
    DATE_TRUNC('week', smi.created_at) as week,
    platform,
    COUNT(*) as total_items,
    COUNT(CASE WHEN ma.action_type = 'reply' THEN 1 END) as replies,
    COUNT(CASE WHEN ma.action_type = 'escalate' THEN 1 END) as escalations,
    AVG(EXTRACT(EPOCH FROM (ma.executed_at - smi.created_time))/60) as avg_response_time,
    COUNT(CASE WHEN ic.intent = 'complaint' THEN 1 END) as complaints,
    COUNT(CASE WHEN ic.intent = 'praise' THEN 1 END) as praise
FROM social_media_items smi
LEFT JOIN item_classifications ic ON smi.id = ic.item_id
LEFT JOIN moderation_actions ma ON smi.id = ma.item_id
WHERE smi.created_at >= CURRENT_DATE - INTERVAL '12 weeks'
GROUP BY DATE_TRUNC('week', smi.created_at), platform
ORDER BY week DESC;
```

## 🔧 Configuration

### Environment Variables

```bash
# Meta/Facebook
META_ACCESS_TOKEN=your-meta-access-token
META_APP_SECRET=your-meta-app-secret
META_WEBHOOK_VERIFY_TOKEN=your-webhook-verify-token

# AI Services
OPENAI_API_KEY=your-openai-key

# Database
SUPABASE_URL=your-supabase-url
SUPABASE_SERVICE_KEY=your-service-key

# Notion
NOTION_API_KEY=your-notion-key
NOTION_MODERATION_DB_ID=your-moderation-db-id

# Slack
SLACK_WEBHOOK_URL=your-slack-webhook-url

# Dashboard
DATABOX_API_KEY=your-databox-key
```

### Notion Database Schema

```javascript
const notionSchema = {
  Platform: { type: "select", options: ["facebook", "instagram"] },
  Intent: {
    type: "select",
    options: ["toxic", "spam", "complaint", "question", "praise", "other"],
  },
  Sentiment: { type: "select", options: ["positive", "negative", "neutral"] },
  "Original Text": { type: "rich_text" },
  "Suggested Reply": { type: "rich_text" },
  Rationale: { type: "rich_text" },
  Status: {
    type: "select",
    options: ["Needs Approval", "Approved", "Posted", "Rejected"],
  },
  Action: { type: "select", options: ["None", "Post Reply", "Like"] },
  Permalink: { type: "url" },
  "Created Time": { type: "date" },
  "Object ID": { type: "rich_text" },
};
```

## 🧪 Testing & Validation

### Unit Tests

- **Classification Accuracy**: Test intent and sentiment classification
- **Action Logic**: Validate action determination logic
- **API Integration**: Test platform API calls
- **Notion Integration**: Verify approval workflow

### Integration Tests

- **End-to-End**: Complete moderation workflow
- **Real-time Processing**: Test webhook handling
- **Approval Flow**: Verify Notion to platform integration
- **Error Handling**: Test failure scenarios

### A/B Testing

- **Classification Models**: Compare different AI models
- **Response Strategies**: Test different reply approaches
- **Escalation Thresholds**: Optimize escalation criteria

## 📚 API Documentation

### Meta Graph API

- **Comments**: `GET /{object-id}/comments`
- **Replies**: `POST /{comment-id}/replies`
- **Likes**: `POST /{object-id}/likes`
- **Rate Limits**: 200 calls/hour per user
- **Documentation**: [Meta Graph API Docs](https://developers.facebook.com/docs/graph-api)

### OpenAI API

- **Endpoint**: `https://api.openai.com/v1/chat/completions`
- **Model**: `gpt-4`
- **Rate Limits**: 10,000 tokens/minute
- **Documentation**: [OpenAI API Docs](https://platform.openai.com/docs/api-reference)

## 🔄 Maintenance & Updates

### Daily Operations

- **Monitor**: Check processing success rates
- **Review**: Manual review of escalated items
- **Validate**: Verify AI classification accuracy
- **Respond**: Handle approved replies

### Weekly Operations

- **Analyze**: Review performance metrics
- **Optimize**: Adjust classification thresholds
- **Update**: Refresh training data
- **Report**: Generate weekly summaries

### Monthly Operations

- **Audit**: Review all moderation actions
- **Scale**: Optimize for increased volume
- **Document**: Update policies and procedures
- **Train**: Improve AI models with feedback

## 🆘 Troubleshooting

### Common Issues

**API Rate Limiting**

- **Symptom**: 429 Too Many Requests errors
- **Solution**: Implement exponential backoff, reduce polling frequency
- **Prevention**: Monitor API usage, implement queuing

**Classification Accuracy**

- **Symptom**: High false positive/negative rates
- **Solution**: Adjust confidence thresholds, improve prompts
- **Prevention**: Regular model evaluation and retraining

**Notion Sync Issues**

- **Symptom**: Approval records not updating
- **Solution**: Check API credentials, verify database schema
- **Prevention**: Implement retry logic and error monitoring

### Debug Commands

```bash
# Test Meta API
curl -H "Authorization: Bearer $META_ACCESS_TOKEN" \
     "https://graph.facebook.com/v18.0/me/comments?limit=5"

# Test OpenAI API
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"gpt-4","messages":[{"role":"user","content":"test"}]}' \
     https://api.openai.com/v1/chat/completions

# Check recent items
psql -h $SUPABASE_HOST -U postgres -d postgres -c "
  SELECT * FROM social_media_items
  WHERE created_at >= CURRENT_DATE - INTERVAL '24 hours'
  ORDER BY created_at DESC LIMIT 10;
"
```

## 📊 Success Metrics

### Acceptance Criteria Met

✅ **FB/IG Integration**: Real-time comment, mention, and DM monitoring  
✅ **AI Classification**: Intent and sentiment analysis with high accuracy  
✅ **Automated Actions**: Hide/delete spam/toxic content automatically  
✅ **Escalation System**: Complaints escalated to Slack with context  
✅ **Reply Generation**: AI-generated suggested replies with rationale  
✅ **Notion Approval**: Streamlined approval workflow with one-click actions  
✅ **Dashboard**: Mini dashboard with KPIs and recent actions  
✅ **No Auto-Reply**: All replies require human approval

### Performance Benchmarks

- **Processing Time**: < 30 seconds from item to classification
- **Classification Accuracy**: > 90% for intent, > 85% for sentiment
- **Response Rate**: > 80% of questions/complaints receive responses
- **Response Time**: < 2 hours average for approved replies
- **Escalation Accuracy**: > 95% of escalations are valid
- **System Uptime**: > 99.5% availability for monitoring
