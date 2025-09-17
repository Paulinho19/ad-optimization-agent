# Part 1: Data Ingestion & Normalization

## Overview

This module implements a robust data ingestion system that pulls daily performance metrics from multiple marketing platforms, normalizes the data into a unified schema, and stores it in both Supabase and Notion for analysis and visualization.

## 🎯 Goals

- Pull daily performance data from Klaviyo (real API) and Mock API (Supabase functions)
- Normalize data into a unified schema across platforms
- Store data in Supabase and Notion with proper indexing
- Visualize performance comparison in Databox
- Ensure idempotent operations and error handling

## 📊 Data Sources

### 1. Klaviyo API (Real)

- **Platform**: Email Marketing
- **Authentication**: API Key
- **Rate Limits**: 600 requests/minute
- **Data Retrieved**:
  - Campaign performance metrics
  - Email open rates, click rates
  - Revenue attribution
  - Customer engagement metrics

### 2. Mock API (Supabase Functions)

- **Platform**: Social Media Advertising (Simulated)
- **Authentication**: Supabase service key
- **Implementation**: Edge functions with realistic data patterns
- **Data Retrieved**:
  - Campaign spend and impressions
  - Click-through rates
  - Conversion metrics
  - Cost per acquisition (CPA)

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Data Sources  │    │   n8n Workflow  │    │   Storage       │
│                 │    │                 │    │                 │
│ • Klaviyo API   │───▶│ • Cron Trigger  │───▶│ • Supabase      │
│ • Mock API      │    │ • Data Fetch    │    │ • Notion        │
│                 │    │ • Normalization │    │ • Databox       │
│                 │    │ • Deduplication │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📋 Unified Data Schema

### Normalized Schema

```sql
CREATE TABLE campaign_performance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL,
    platform VARCHAR(50) NOT NULL,
    account_id VARCHAR(100) NOT NULL,
    campaign_id VARCHAR(100) NOT NULL,
    campaign_name VARCHAR(255) NOT NULL,
    spend DECIMAL(10,2) NOT NULL,
    impressions BIGINT,
    clicks BIGINT,
    conversions BIGINT,
    cpl DECIMAL(10,2), -- Cost Per Lead
    roas DECIMAL(10,4), -- Return on Ad Spend
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- Composite unique constraint
    UNIQUE(date, platform, campaign_id)
);
```

### Field Mapping

| Field           | Klaviyo           | Mock API            | Description                 |
| --------------- | ----------------- | ------------------- | --------------------------- |
| `date`          | `date`            | `date`              | Campaign date               |
| `platform`      | `klaviyo`         | `mock_social`       | Platform identifier         |
| `account_id`    | `account_id`      | `account_id`        | Account identifier          |
| `campaign_id`   | `campaign_id`     | `campaign_id`       | Campaign identifier         |
| `campaign_name` | `campaign_name`   | `campaign_name`     | Campaign display name       |
| `spend`         | `revenue`         | `spend`             | Total spend/revenue         |
| `impressions`   | `sent`            | `impressions`       | Email sent / Ad impressions |
| `clicks`        | `clicked`         | `clicks`            | Email clicks / Ad clicks    |
| `conversions`   | `purchased`       | `conversions`       | Conversions/purchases       |
| `cpl`           | `revenue/clicked` | `spend/conversions` | Cost per lead               |
| `roas`          | `revenue/spend`   | `revenue/spend`     | Return on ad spend          |

## 🔄 Workflow Implementation

### n8n Workflow: `ingest.json`

#### 1. Cron Trigger

- **Schedule**: Daily at 6:00 AM UTC
- **Timezone**: UTC
- **Purpose**: Trigger daily data collection

#### 2. Data Fetching Nodes

**Klaviyo Data Fetch**

```javascript
// HTTP Request to Klaviyo API
{
  "method": "GET",
  "url": "https://a.klaviyo.com/api/campaigns/",
  "headers": {
    "Authorization": "Klaviyo-API-Key {{$credentials.klaviyo.apiKey}}",
    "revision": "2024-10-15"
  },
  "qs": {
    "filter": "greater-than(updated,{{$now.minus({days: 1}).toISO()}})",
    "page[size]": 100
  }
}
```

**Mock API Data Fetch**

```javascript
// HTTP Request to Supabase Edge Function
{
  "method": "POST",
  "url": "{{$credentials.supabase.url}}/functions/v1/mock-ad-data",
  "headers": {
    "Authorization": "Bearer {{$credentials.supabase.serviceKey}}",
    "Content-Type": "application/json"
  },
  "body": {
    "date": "{{$now.minus({days: 1}).toFormat('yyyy-MM-dd')}}",
    "limit": 100
  }
}
```

#### 3. Data Normalization

**Klaviyo Normalization**

```javascript
// Transform Klaviyo data to unified schema
return items.map((item) => ({
  date: $now.minus({ days: 1 }).toFormat("yyyy-MM-dd"),
  platform: "klaviyo",
  account_id: item.data.attributes.account_id,
  campaign_id: item.data.id,
  campaign_name: item.data.attributes.name,
  spend: item.data.attributes.revenue || 0,
  impressions: item.data.attributes.sent || 0,
  clicks: item.data.attributes.clicked || 0,
  conversions: item.data.attributes.purchased || 0,
  cpl:
    item.data.attributes.clicked > 0
      ? item.data.attributes.revenue / item.data.attributes.clicked
      : 0,
  roas:
    item.data.attributes.spend > 0
      ? item.data.attributes.revenue / item.data.attributes.spend
      : 0,
}));
```

**Mock API Normalization**

```javascript
// Transform Mock API data to unified schema
return items.map((item) => ({
  date: item.date,
  platform: "mock_social",
  account_id: item.account_id,
  campaign_id: item.campaign_id,
  campaign_name: item.campaign_name,
  spend: item.spend,
  impressions: item.impressions,
  clicks: item.clicks,
  conversions: item.conversions,
  cpl: item.conversions > 0 ? item.spend / item.conversions : 0,
  roas: item.spend > 0 ? item.revenue / item.spend : 0,
}));
```

#### 4. Data Storage

**Supabase Upsert**

```javascript
// Upsert to Supabase with conflict resolution
{
  "method": "POST",
  "url": "{{$credentials.supabase.url}}/rest/v1/campaign_performance",
  "headers": {
    "Authorization": "Bearer {{$credentials.supabase.serviceKey}}",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates"
  },
  "body": normalizedData
}
```

**Notion Database Update**

```javascript
// Update Notion database
{
  "method": "POST",
  "url": "https://api.notion.com/v1/pages",
  "headers": {
    "Authorization": "Bearer {{$credentials.notion.apiKey}}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28"
  },
  "body": {
    "parent": {"database_id": "{{$credentials.notion.databaseId}}"},
    "properties": {
      "Date": {"date": {"start": item.date}},
      "Platform": {"select": {"name": item.platform}},
      "Campaign": {"title": [{"text": {"content": item.campaign_name}}]},
      "Spend": {"number": item.spend},
      "Impressions": {"number": item.impressions},
      "Clicks": {"number": item.clicks},
      "Conversions": {"number": item.conversions},
      "CPL": {"number": item.cpl},
      "ROAS": {"number": item.roas}
    }
  }
}
```

## 🔧 Authentication Methods

### Klaviyo API

- **Method**: API Key
- **Storage**: n8n credentials
- **Rate Limiting**: 600 requests/minute
- **Headers**: `Authorization: Klaviyo-API-Key {key}`

### Mock API (Supabase)

- **Method**: Service Key
- **Storage**: n8n credentials
- **Rate Limiting**: 1000 requests/minute
- **Headers**: `Authorization: Bearer {service_key}`

## 🛡️ Error Handling & Retry Logic

### Retry Configuration

```javascript
// Retry settings for API calls
{
  "retry": {
    "maxAttempts": 3,
    "backoffStrategy": "exponential",
    "baseDelay": 1000,
    "maxDelay": 10000
  }
}
```

### Error Handling

- **API Failures**: Log to error table, continue with other sources
- **Data Validation**: Skip invalid records, log validation errors
- **Rate Limiting**: Implement exponential backoff
- **Network Issues**: Retry with circuit breaker pattern

### Idempotency

- **Unique Constraints**: `(date, platform, campaign_id)`
- **Upsert Operations**: Use `ON CONFLICT` for safe re-runs
- **Timestamp Tracking**: Track `created_at` and `updated_at`

## 📊 Data Visualization

### Databox Integration

- **Connector**: Supabase SQL connector
- **Metrics**:
  - Total spend by platform (last 7 days)
  - ROAS comparison (current vs previous period)
  - CPL trends by platform
  - Conversion volume comparison

### Chart Configuration

```sql
-- Databox query for platform comparison
SELECT
    platform,
    DATE_TRUNC('day', date) as day,
    SUM(spend) as total_spend,
    AVG(roas) as avg_roas,
    SUM(conversions) as total_conversions
FROM campaign_performance
WHERE date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY platform, day
ORDER BY day DESC;
```

## 🔍 Data Quality & Validation

### Validation Rules

1. **Required Fields**: date, platform, campaign_id, campaign_name
2. **Numeric Validation**: spend >= 0, impressions >= 0, clicks >= 0
3. **Date Validation**: date <= current_date
4. **Platform Validation**: platform in ['klaviyo', 'mock_social']

### Data Quality Metrics

- **Completeness**: % of records with all required fields
- **Accuracy**: % of records passing validation rules
- **Timeliness**: % of records ingested within SLA
- **Consistency**: % of records matching expected schema

## 📈 Performance Monitoring

### Key Metrics

- **Ingestion Time**: Average time to complete daily sync
- **Success Rate**: % of successful API calls
- **Data Volume**: Records processed per day
- **Error Rate**: % of failed operations

### Monitoring Dashboard

- **Real-time Status**: Current ingestion status
- **Historical Trends**: Performance over time
- **Error Alerts**: Slack notifications for failures
- **Data Quality**: Validation results and trends

## 🚀 Deployment & Configuration

### Environment Variables

```bash
# Database
SUPABASE_URL=your-supabase-url
SUPABASE_SERVICE_KEY=your-service-key

# APIs
KLAVIYO_API_KEY=your-klaviyo-key

# Notion
NOTION_API_KEY=your-notion-key
NOTION_DATABASE_ID=your-database-id

# Monitoring
SLACK_WEBHOOK_URL=your-slack-webhook
```

### n8n Configuration

1. Import `workflows/ingest.json`
2. Configure credentials for all services
3. Set up environment variables
4. Test workflow with manual trigger
5. Schedule cron trigger for daily execution

## 🧪 Testing

### Unit Tests

- **API Response Parsing**: Validate data transformation
- **Schema Validation**: Ensure data matches expected format
- **Error Handling**: Test retry logic and failure scenarios

### Integration Tests

- **End-to-End**: Complete workflow execution
- **Data Consistency**: Verify data integrity across storage systems
- **Performance**: Measure ingestion time and resource usage

### Mock API Testing

The mock API provides realistic test data:

- **Campaign Variations**: Different performance patterns
- **Seasonal Trends**: Simulated seasonal fluctuations
- **Error Scenarios**: Network failures and rate limiting
- **Edge Cases**: Empty responses and malformed data

## 📚 API Documentation

### Klaviyo API

- **Base URL**: `https://a.klaviyo.com/api/`
- **Version**: `2024-10-15`
- **Documentation**: [Klaviyo API Docs](https://developers.klaviyo.com/en/reference/api_overview)

### Mock API (Supabase Functions)

- **Base URL**: `{SUPABASE_URL}/functions/v1/`
- **Endpoint**: `mock-ad-data`
- **Method**: POST
- **Authentication**: Bearer token

## 🔄 Maintenance & Updates

### Daily Operations

- **Monitor**: Check ingestion status and error logs
- **Validate**: Verify data quality and completeness
- **Alert**: Respond to any failures or anomalies

### Weekly Operations

- **Review**: Analyze performance metrics and trends
- **Optimize**: Adjust retry logic and error handling
- **Update**: Refresh API credentials if needed

### Monthly Operations

- **Audit**: Review data quality and validation rules
- **Scale**: Adjust rate limits and batch sizes
- **Document**: Update API documentation and schemas

## 🆘 Troubleshooting

### Common Issues

**API Rate Limiting**

- **Symptom**: 429 Too Many Requests errors
- **Solution**: Implement exponential backoff, reduce batch size
- **Prevention**: Monitor rate limit headers, implement queuing

**Data Validation Failures**

- **Symptom**: Records skipped due to validation errors
- **Solution**: Review validation rules, check data source changes
- **Prevention**: Implement data quality monitoring

**Network Timeouts**

- **Symptom**: Connection timeout errors
- **Solution**: Increase timeout values, implement retry logic
- **Prevention**: Monitor network connectivity, use connection pooling

### Debug Commands

```bash
# Check Supabase connection
curl -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
     "$SUPABASE_URL/rest/v1/campaign_performance?limit=1"

# Test Klaviyo API
curl -H "Authorization: Klaviyo-API-Key $KLAVIYO_API_KEY" \
     "https://a.klaviyo.com/api/campaigns/"

# Test Mock API
curl -X POST \
     -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
     -H "Content-Type: application/json" \
     -d '{"date":"2024-12-01","limit":5}' \
     "$SUPABASE_URL/functions/v1/mock-ad-data"
```

## 📊 Success Metrics

### Acceptance Criteria Met

✅ **Repeatable Ingestion**: Safe to re-run with idempotent operations  
✅ **Real API Integration**: Klaviyo API with proper authentication  
✅ **Mock API Implementation**: Supabase functions with realistic data  
✅ **Unified Schema**: Normalized data across platforms  
✅ **Data Visualization**: Databox charts showing platform comparison  
✅ **Error Handling**: Comprehensive retry logic and failure recovery  
✅ **Documentation**: Complete setup and operational documentation

### Performance Benchmarks

- **Ingestion Time**: < 3 minutes for daily sync
- **Success Rate**: > 99% for API calls
- **Data Quality**: > 95% validation pass rate
- **Availability**: 99.9% uptime for scheduled runs
