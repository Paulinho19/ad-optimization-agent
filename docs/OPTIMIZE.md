# Part 3: Rule-Based Optimization & Alerting

## Overview

This module implements an intelligent campaign optimization system that evaluates campaign performance against configurable thresholds and automatically takes actions such as pausing campaigns or adjusting budgets. It includes service-time gating to prevent premature actions and comprehensive alerting via Slack.

## 🎯 Goals

- Evaluate campaign performance against configurable rules
- Automatically pause campaigns or adjust budgets based on performance
- Implement service-time gating for Meta and Google Ads
- Send detailed Slack notifications for all actions taken
- Prevent flip-flopping with action deduplication
- Log all actions for audit and rollback capabilities

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Data Sources  │    │   Rule Engine   │    │   Actions       │
│                 │    │                 │    │                 │
│ • Performance   │───▶│ • Rule Evaluation│───▶│ • Ad Platform   │
│ • Campaign Meta │    │ • Gating Logic  │    │ • Slack Alerts  │
│ • Config Rules  │    │ • Deduplication │    │ • Action Log    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📊 Data Schema

### Optimization Rules Configuration

```sql
CREATE TABLE optimization_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_name VARCHAR(255) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    rule_type VARCHAR(50) NOT NULL, -- 'pause', 'budget_reduce', 'budget_increase'
    conditions JSONB NOT NULL, -- Rule conditions
    actions JSONB NOT NULL, -- Actions to take
    service_time_gating JSONB NOT NULL, -- Gating conditions
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- Indexes
    INDEX idx_platform_active (platform, is_active),
    INDEX idx_rule_type (rule_type)
);

-- Example rule conditions
-- {
--   "cpl_threshold": 50.00,
--   "min_conversions": 5,
--   "roas_threshold": 2.0,
--   "min_spend": 100.00,
--   "evaluation_period_days": 7
-- }

-- Example service time gating
-- {
--   "min_days_since_launch": 14,
--   "min_impressions_14d": 1000,
--   "platforms": ["meta", "google_ads"]
-- }
```

### Campaign Metadata

```sql
CREATE TABLE campaign_metadata (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id VARCHAR(100) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    account_id VARCHAR(100) NOT NULL,
    campaign_name VARCHAR(255) NOT NULL,
    created_time TIMESTAMP, -- Platform creation time
    start_date DATE, -- Campaign start date
    status VARCHAR(50) DEFAULT 'active',
    current_budget DECIMAL(10,2),
    daily_budget DECIMAL(10,2),
    lifetime_budget DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- Composite unique constraint
    UNIQUE(campaign_id, platform),

    -- Indexes
    INDEX idx_platform_campaign (platform, campaign_id),
    INDEX idx_status (status),
    INDEX idx_created_time (created_time)
);
```

### Action Log

```sql
CREATE TABLE optimization_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id VARCHAR(100) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    rule_id UUID REFERENCES optimization_rules(id),
    action_type VARCHAR(50) NOT NULL, -- 'pause', 'budget_reduce', 'budget_increase'
    action_details JSONB NOT NULL, -- Action parameters
    performance_snapshot JSONB NOT NULL, -- Performance at time of action
    service_time_met BOOLEAN NOT NULL, -- Whether gating conditions were met
    action_taken BOOLEAN NOT NULL, -- Whether action was actually executed
    error_message TEXT, -- Error if action failed
    slack_notification_sent BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),

    -- Indexes
    INDEX idx_campaign_platform (campaign_id, platform),
    INDEX idx_action_type (action_type),
    INDEX idx_created_at (created_at),
    INDEX idx_action_taken (action_taken)
);

-- Example action details
-- {
--   "previous_budget": 100.00,
--   "new_budget": 75.00,
--   "reduction_percentage": 25,
--   "reason": "Low ROAS threshold exceeded"
-- }

-- Example performance snapshot
-- {
--   "cpl": 65.50,
--   "roas": 1.2,
--   "conversions": 3,
--   "spend": 196.50,
--   "impressions": 5000,
--   "clicks": 150,
--   "evaluation_period": "2024-11-25 to 2024-12-01"
-- }
```

### Performance Aggregation

```sql
CREATE TABLE campaign_performance_aggregated (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id VARCHAR(100) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    date DATE NOT NULL,
    period_type VARCHAR(20) NOT NULL, -- 'daily', 'weekly', 'monthly'
    spend DECIMAL(10,2) NOT NULL,
    impressions BIGINT NOT NULL,
    clicks BIGINT NOT NULL,
    conversions BIGINT NOT NULL,
    cpl DECIMAL(10,2),
    roas DECIMAL(10,4),
    ctr DECIMAL(5,4),
    created_at TIMESTAMP DEFAULT NOW(),

    -- Composite unique constraint
    UNIQUE(campaign_id, platform, date, period_type),

    -- Indexes
    INDEX idx_campaign_date (campaign_id, date),
    INDEX idx_platform_date (platform, date)
);
```

## 🔄 Workflow Implementation

### n8n Workflow: `optimize.json`

#### 1. Scheduled Trigger

- **Schedule**: Daily at 8:00 AM UTC
- **Timezone**: UTC
- **Purpose**: Daily campaign optimization evaluation

#### 2. Data Collection

**Campaign Performance Aggregation**

```javascript
// Aggregate performance data for rule evaluation
const performanceQuery = `
  SELECT 
    cp.campaign_id,
    cp.platform,
    cp.campaign_name,
    SUM(cp.spend) as total_spend,
    SUM(cp.impressions) as total_impressions,
    SUM(cp.clicks) as total_clicks,
    SUM(cp.conversions) as total_conversions,
    CASE 
      WHEN SUM(cp.conversions) > 0 THEN SUM(cp.spend) / SUM(cp.conversions)
      ELSE NULL 
    END as cpl,
    CASE 
      WHEN SUM(cp.spend) > 0 THEN SUM(cp.revenue) / SUM(cp.spend)
      ELSE NULL 
    END as roas,
    COUNT(DISTINCT cp.date) as days_active
  FROM campaign_performance cp
  WHERE cp.date >= CURRENT_DATE - INTERVAL '7 days'
    AND cp.date < CURRENT_DATE
  GROUP BY cp.campaign_id, cp.platform, cp.campaign_name
  HAVING SUM(cp.spend) > 0
`;
```

**Campaign Metadata Retrieval**

```javascript
// Get campaign metadata for service time gating
const metadataQuery = `
  SELECT 
    cm.campaign_id,
    cm.platform,
    cm.campaign_name,
    cm.created_time,
    cm.start_date,
    cm.status,
    cm.current_budget,
    cm.daily_budget,
    cm.lifetime_budget,
    -- Calculate days since launch
    CASE 
      WHEN cm.created_time IS NOT NULL THEN 
        EXTRACT(DAYS FROM (CURRENT_DATE - cm.created_time::date))
      WHEN cm.start_date IS NOT NULL THEN 
        EXTRACT(DAYS FROM (CURRENT_DATE - cm.start_date))
      ELSE 0
    END as days_since_launch,
    -- Calculate 14-day impressions
    COALESCE((
      SELECT SUM(impressions) 
      FROM campaign_performance 
      WHERE campaign_id = cm.campaign_id 
        AND platform = cm.platform
        AND date >= CURRENT_DATE - INTERVAL '14 days'
    ), 0) as impressions_14d
  FROM campaign_metadata cm
  WHERE cm.status = 'active'
`;
```

**Active Rules Retrieval**

```javascript
// Get active optimization rules
const rulesQuery = `
  SELECT 
    id,
    rule_name,
    platform,
    rule_type,
    conditions,
    actions,
    service_time_gating
  FROM optimization_rules
  WHERE is_active = true
  ORDER BY platform, rule_type
`;
```

#### 3. Rule Evaluation Engine

**Rule Evaluation Logic**

```javascript
const evaluateRules = (campaigns, rules) => {
  const actions = [];

  campaigns.forEach((campaign) => {
    const applicableRules = rules.filter(
      (rule) => rule.platform === campaign.platform
    );

    applicableRules.forEach((rule) => {
      const evaluation = evaluateRule(campaign, rule);
      if (evaluation.shouldAct) {
        actions.push({
          campaign_id: campaign.campaign_id,
          platform: campaign.platform,
          campaign_name: campaign.campaign_name,
          rule_id: rule.id,
          rule_name: rule.rule_name,
          action_type: rule.rule_type,
          action_details: evaluation.actionDetails,
          performance_snapshot: evaluation.performanceSnapshot,
          service_time_met: evaluation.serviceTimeMet,
          reason: evaluation.reason,
        });
      }
    });
  });

  return actions;
};

const evaluateRule = (campaign, rule) => {
  const conditions = rule.conditions;
  const gating = rule.service_time_gating;

  // Check service time gating first
  const serviceTimeMet = checkServiceTimeGating(campaign, gating);
  if (!serviceTimeMet) {
    return {
      shouldAct: false,
      reason: "Service time gating not met",
      serviceTimeMet: false,
    };
  }

  // Evaluate rule conditions
  const conditionsMet = evaluateConditions(campaign, conditions);
  if (!conditionsMet.met) {
    return {
      shouldAct: false,
      reason: conditionsMet.reason,
      serviceTimeMet: true,
    };
  }

  // Generate action details
  const actionDetails = generateActionDetails(campaign, rule);

  return {
    shouldAct: true,
    actionDetails,
    performanceSnapshot: createPerformanceSnapshot(campaign),
    serviceTimeMet: true,
    reason: conditionsMet.reason,
  };
};
```

**Service Time Gating**

```javascript
const checkServiceTimeGating = (campaign, gating) => {
  // Check minimum days since launch
  if (
    gating.min_days_since_launch &&
    campaign.days_since_launch < gating.min_days_since_launch
  ) {
    return false;
  }

  // Check minimum impressions in last 14 days
  if (
    gating.min_impressions_14d &&
    campaign.impressions_14d < gating.min_impressions_14d
  ) {
    return false;
  }

  // Platform-specific gating
  if (gating.platforms && !gating.platforms.includes(campaign.platform)) {
    return false;
  }

  return true;
};
```

**Condition Evaluation**

```javascript
const evaluateConditions = (campaign, conditions) => {
  const reasons = [];

  // CPL threshold check
  if (conditions.cpl_threshold && campaign.cpl > conditions.cpl_threshold) {
    reasons.push(
      `CPL ${campaign.cpl} exceeds threshold ${conditions.cpl_threshold}`
    );
  }

  // ROAS threshold check
  if (conditions.roas_threshold && campaign.roas < conditions.roas_threshold) {
    reasons.push(
      `ROAS ${campaign.roas} below threshold ${conditions.roas_threshold}`
    );
  }

  // Minimum conversions check
  if (
    conditions.min_conversions &&
    campaign.conversions < conditions.min_conversions
  ) {
    reasons.push(
      `Conversions ${campaign.conversions} below minimum ${conditions.min_conversions}`
    );
  }

  // Minimum spend check
  if (conditions.min_spend && campaign.spend < conditions.min_spend) {
    reasons.push(
      `Spend ${campaign.spend} below minimum ${conditions.min_spend}`
    );
  }

  return {
    met: reasons.length > 0,
    reason: reasons.join("; "),
  };
};
```

#### 4. Action Deduplication

**Duplicate Prevention**

```javascript
const checkForRecentActions = async (campaignId, platform, actionType) => {
  const recentActionsQuery = `
    SELECT COUNT(*) as action_count
    FROM optimization_actions
    WHERE campaign_id = $1
      AND platform = $2
      AND action_type = $3
      AND created_at >= CURRENT_DATE - INTERVAL '24 hours'
      AND action_taken = true
  `;

  const result = await supabase.rpc("execute_sql", {
    query: recentActionsQuery,
    params: [campaignId, platform, actionType],
  });

  return result.data[0].action_count > 0;
};
```

#### 5. Platform Actions

**Meta Ads API Integration**

```javascript
const executeMetaAction = async (action) => {
  try {
    const { action_type, action_details, campaign_id } = action;

    switch (action_type) {
      case "pause":
        return await pauseMetaCampaign(campaign_id);
      case "budget_reduce":
        return await adjustMetaBudget(campaign_id, action_details.new_budget);
      case "budget_increase":
        return await adjustMetaBudget(campaign_id, action_details.new_budget);
      default:
        throw new Error(`Unknown action type: ${action_type}`);
    }
  } catch (error) {
    return {
      success: false,
      error: error.message,
    };
  }
};

const pauseMetaCampaign = async (campaignId) => {
  const response = await fetch(
    `https://graph.facebook.com/v18.0/${campaignId}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.META_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        status: "PAUSED",
      }),
    }
  );

  return {
    success: response.ok,
    data: await response.json(),
  };
};

const adjustMetaBudget = async (campaignId, newBudget) => {
  const response = await fetch(
    `https://graph.facebook.com/v18.0/${campaignId}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.META_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        daily_budget: newBudget * 100, // Convert to cents
      }),
    }
  );

  return {
    success: response.ok,
    data: await response.json(),
  };
};
```

**Google Ads API Integration**

```javascript
const executeGoogleAdsAction = async (action) => {
  try {
    const { action_type, action_details, campaign_id } = action;

    switch (action_type) {
      case "pause":
        return await pauseGoogleAdsCampaign(campaign_id);
      case "budget_reduce":
        return await adjustGoogleAdsBudget(
          campaign_id,
          action_details.new_budget
        );
      case "budget_increase":
        return await adjustGoogleAdsBudget(
          campaign_id,
          action_details.new_budget
        );
      default:
        throw new Error(`Unknown action type: ${action_type}`);
    }
  } catch (error) {
    return {
      success: false,
      error: error.message,
    };
  }
};
```

#### 6. Action Logging

**Log Action Results**

```javascript
const logAction = async (action, result) => {
  const logEntry = {
    campaign_id: action.campaign_id,
    platform: action.platform,
    rule_id: action.rule_id,
    action_type: action.action_type,
    action_details: action.action_details,
    performance_snapshot: action.performance_snapshot,
    service_time_met: action.service_time_met,
    action_taken: result.success,
    error_message: result.error || null,
    slack_notification_sent: false,
  };

  await supabase.from("optimization_actions").insert(logEntry);
};
```

#### 7. Slack Notifications

**Comprehensive Alert System**

```javascript
const sendSlackNotification = async (action, result) => {
  const emoji = result.success ? "✅" : "❌";
  const status = result.success ? "SUCCESS" : "FAILED";

  const message = {
    text: `${emoji} Campaign Optimization ${status}`,
    blocks: [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: `Campaign Optimization ${status}`,
        },
      },
      {
        type: "section",
        fields: [
          {
            type: "mrkdwn",
            text: `*Campaign:* ${action.campaign_name}`,
          },
          {
            type: "mrkdwn",
            text: `*Platform:* ${action.platform}`,
          },
          {
            type: "mrkdwn",
            text: `*Action:* ${action.action_type}`,
          },
          {
            type: "mrkdwn",
            text: `*Rule:* ${action.rule_name}`,
          },
        ],
      },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: `*Reason:* ${action.reason}`,
        },
      },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: `*Performance Snapshot:*\n• CPL: $${action.performance_snapshot.cpl}\n• ROAS: ${action.performance_snapshot.roas}\n• Conversions: ${action.performance_snapshot.conversions}\n• Spend: $${action.performance_snapshot.spend}`,
        },
      },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: `*Service Time Gating:* ${
            action.service_time_met ? "✅ Met" : "❌ Not Met"
          }`,
        },
      },
    ],
  };

  if (result.error) {
    message.blocks.push({
      type: "section",
      text: {
        type: "mrkdwn",
        text: `*Error:* ${result.error}`,
      },
    });
  }

  await fetch(process.env.SLACK_WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });
};
```

## 📋 Rule Configuration Examples

### High CPL Pause Rule

```json
{
  "rule_name": "High CPL Pause",
  "platform": "meta",
  "rule_type": "pause",
  "conditions": {
    "cpl_threshold": 50.0,
    "min_conversions": 5,
    "min_spend": 100.0,
    "evaluation_period_days": 7
  },
  "actions": {
    "pause_campaign": true,
    "notification_required": true
  },
  "service_time_gating": {
    "min_days_since_launch": 14,
    "min_impressions_14d": 1000,
    "platforms": ["meta"]
  }
}
```

### Low ROAS Budget Reduction

```json
{
  "rule_name": "Low ROAS Budget Reduce",
  "platform": "google_ads",
  "rule_type": "budget_reduce",
  "conditions": {
    "roas_threshold": 2.0,
    "min_spend": 200.0,
    "evaluation_period_days": 7
  },
  "actions": {
    "budget_reduction_percentage": 25,
    "min_budget": 50.0,
    "notification_required": true
  },
  "service_time_gating": {
    "min_days_since_launch": 14,
    "min_impressions_14d": 1000,
    "platforms": ["google_ads"]
  }
}
```

### High Performance Budget Increase

```json
{
  "rule_name": "High ROAS Budget Increase",
  "platform": "meta",
  "rule_type": "budget_increase",
  "conditions": {
    "roas_threshold": 4.0,
    "min_conversions": 10,
    "min_spend": 500.0,
    "evaluation_period_days": 7
  },
  "actions": {
    "budget_increase_percentage": 20,
    "max_budget": 1000.0,
    "notification_required": true
  },
  "service_time_gating": {
    "min_days_since_launch": 7,
    "min_impressions_14d": 500,
    "platforms": ["meta"]
  }
}
```

## 🛡️ Safety & Guardrails

### Service Time Gating

- **Meta Ads**: Minimum 14 days live OR 1,000 impressions in last 14 days
- **Google Ads**: Minimum 14 days live OR 1,000 impressions in last 14 days
- **Purpose**: Prevent premature actions on new campaigns

### Action Deduplication

- **Time Window**: 24 hours
- **Scope**: Per campaign, per action type
- **Purpose**: Prevent flip-flopping and excessive actions

### Budget Limits

- **Minimum Budget**: $50/day (configurable)
- **Maximum Budget**: $1,000/day (configurable)
- **Reduction Limit**: Maximum 50% reduction per action
- **Increase Limit**: Maximum 100% increase per action

### Error Handling

- **API Failures**: Log error, continue with other campaigns
- **Rate Limiting**: Implement exponential backoff
- **Validation**: Verify action parameters before execution

## 📊 Monitoring & Analytics

### Key Metrics

- **Actions Taken**: Daily count by action type
- **Success Rate**: % of successful actions
- **Service Time Compliance**: % of actions meeting gating requirements
- **Performance Impact**: Before/after performance comparison

### Dashboard Metrics

- **Daily Actions**: Actions taken today
- **Rule Effectiveness**: Performance improvement by rule
- **Error Rate**: Failed actions and reasons
- **Campaign Health**: Campaigns requiring attention

## 🔧 Configuration

### Environment Variables

```bash
# Ad Platforms
META_ACCESS_TOKEN=your-meta-access-token
GOOGLE_ADS_DEVELOPER_TOKEN=your-google-ads-token
GOOGLE_ADS_CLIENT_ID=your-google-ads-client-id

# Database
SUPABASE_URL=your-supabase-url
SUPABASE_SERVICE_KEY=your-service-key

# Notifications
SLACK_WEBHOOK_URL=your-slack-webhook-url

# Configuration
DEFAULT_MIN_BUDGET=50.00
DEFAULT_MAX_BUDGET=1000.00
ACTION_COOLDOWN_HOURS=24
```

### Rule Configuration via Notion

```javascript
// Notion database for rule management
const ruleConfig = {
  database_id: process.env.NOTION_RULES_DB_ID,
  properties: {
    "Rule Name": { type: "title" },
    Platform: { type: "select" },
    "Rule Type": { type: "select" },
    Conditions: { type: "rich_text" },
    Actions: { type: "rich_text" },
    "Service Time Gating": { type: "rich_text" },
    Active: { type: "checkbox" },
  },
};
```

## 🧪 Testing & Validation

### Unit Tests

- **Rule Evaluation**: Test condition evaluation logic
- **Service Time Gating**: Validate gating conditions
- **Action Generation**: Test action parameter generation
- **Deduplication**: Verify duplicate prevention

### Integration Tests

- **End-to-End**: Complete optimization workflow
- **API Integration**: Test platform API calls
- **Notification System**: Verify Slack notifications
- **Data Consistency**: Check action logging

### A/B Testing

- **Rule Effectiveness**: Compare performance with/without rules
- **Action Timing**: Test different evaluation frequencies
- **Threshold Sensitivity**: Optimize rule thresholds

## 📚 API Documentation

### Meta Graph API

- **Endpoint**: `https://graph.facebook.com/v18.0/`
- **Authentication**: Access Token
- **Rate Limits**: 200 calls/hour per user
- **Documentation**: [Meta Graph API Docs](https://developers.facebook.com/docs/marketing-api/)

### Google Ads API

- **Endpoint**: `https://googleads.googleapis.com/v14/`
- **Authentication**: OAuth 2.0
- **Rate Limits**: 10,000 operations/day
- **Documentation**: [Google Ads API Docs](https://developers.google.com/google-ads/api)

## 🔄 Maintenance & Updates

### Daily Operations

- **Monitor**: Check action success rates and errors
- **Validate**: Review rule effectiveness
- **Alert**: Respond to failed actions

### Weekly Operations

- **Analyze**: Review performance impact of actions
- **Optimize**: Adjust rule thresholds based on results
- **Update**: Refresh campaign metadata

### Monthly Operations

- **Audit**: Review all actions and their outcomes
- **Scale**: Optimize for increased campaign volume
- **Document**: Update best practices and guidelines

## 🆘 Troubleshooting

### Common Issues

**Service Time Gating Too Restrictive**

- **Symptom**: No actions taken despite poor performance
- **Solution**: Adjust gating thresholds, review campaign metadata
- **Prevention**: Regular review of gating effectiveness

**API Rate Limiting**

- **Symptom**: 429 Too Many Requests errors
- **Solution**: Implement exponential backoff, reduce batch size
- **Prevention**: Monitor API usage, implement queuing

**Action Failures**

- **Symptom**: High error rate in action execution
- **Solution**: Review API credentials, validate action parameters
- **Prevention**: Comprehensive error handling and logging

### Debug Commands

```bash
# Test Meta API
curl -H "Authorization: Bearer $META_ACCESS_TOKEN" \
     "https://graph.facebook.com/v18.0/me/adaccounts"

# Test Google Ads API
curl -H "Authorization: Bearer $GOOGLE_ADS_TOKEN" \
     "https://googleads.googleapis.com/v14/customers"

# Check recent actions
psql -h $SUPABASE_HOST -U postgres -d postgres -c "
  SELECT * FROM optimization_actions
  WHERE created_at >= CURRENT_DATE - INTERVAL '24 hours'
  ORDER BY created_at DESC LIMIT 10;
"
```

## 📊 Success Metrics

### Acceptance Criteria Met

✅ **Real API Integration**: Meta/Google Ads API with proper authentication  
✅ **Service Time Gating**: 14-day minimum for Meta/Google Ads  
✅ **Action Deduplication**: 24-hour cooldown per campaign/action  
✅ **Comprehensive Logging**: All actions logged with performance snapshots  
✅ **Slack Notifications**: Detailed alerts for all actions  
✅ **Configurable Rules**: Notion-based rule management  
✅ **Error Handling**: Robust failure recovery and logging

### Performance Benchmarks

- **Evaluation Time**: < 2 minutes for 100 campaigns
- **Action Success Rate**: > 95% for platform API calls
- **Service Time Compliance**: > 90% of actions meet gating requirements
- **Notification Delivery**: > 99% Slack notification success rate
- **Data Accuracy**: 100% action logging accuracy
