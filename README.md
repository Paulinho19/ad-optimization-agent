# Cross-Platform Ad Optimization Agent

A low-code AI agent built with n8n that ingests marketing performance data, generates AI-powered creative variations, optimizes campaigns through rule-based actions, and moderates social media interactions.

## 🎯 Project Overview

This project implements a comprehensive ad optimization system that:

- **Ingests** spend & performance data from multiple marketing platforms (Klaviyo + Mock API)
- **Generates** new creative variations using AI and stages them for review
- **Optimizes** campaigns via rule-based actions (pause/budget changes + alerts)
- **Moderates** social comments with sentiment/intent analysis and surfaces activity on a dashboard

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Data Sources  │    │   n8n Workflows │    │   Storage & UI  │
│                 │    │                 │    │                 │
│ • Klaviyo API   │───▶│ • Ingest        │───▶│ • Supabase      │
│ • Mock API      │    │ • Creative      │    │ • Notion        │
│ • Meta Graph    │    │ • Optimize      │    │ • Databox       │
│                 │    │ • Moderation    │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   AI Services   │
                       │                 │
                       │ • OpenAI        │
                       │ • Claude        │
                       │ • Gemini        │
                       └─────────────────┘
```

## 🛠️ Tech Stack

- **Workflow Engine**: n8n
- **Database**: Supabase (PostgreSQL)
- **Documentation**: Notion
- **Analytics**: Databox
- **AI Services**: OpenAI/Claude/Gemini
- **Notifications**: Slack
- **APIs**: Klaviyo (real), Mock API (Supabase functions)

## 📁 Project Structure

```
├── workflows/           # n8n workflow exports
│   ├── ingest.json     # Data ingestion workflow
│   ├── creative.json   # AI creative generation
│   ├── optimize.json   # Campaign optimization
│   └── moderation.json # Social media moderation
├── db/                 # Database schemas and migrations
│   ├── schema.sql      # Main database schema
│   ├── creative.sql    # Creative generation tables
│   ├── config_and_actions.sql # Optimization config
│   └── moderation.sql  # Social moderation tables
├── docs/               # Documentation
│   ├── INGEST.md       # Part 1 documentation
│   ├── CREATIVE.md     # Part 2 documentation
│   ├── OPTIMIZE.md     # Part 3 documentation
│   ├── MODERATION.md   # Part 4 documentation
│   └── ARCHITECTURE.md # System architecture
├── screenshots/        # UI screenshots and demos
└── README.md          # This file
```

## 🚀 Quick Start

### Prerequisites

- n8n instance (cloud or self-hosted)
- Supabase account
- Notion workspace
- Slack workspace
- OpenAI/Claude API key
- Klaviyo API key

### Setup Instructions

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd ad-optimization-agent
   ```

2. **Set up Supabase**

   ```bash
   # Run the database migrations
   psql -h your-supabase-host -U postgres -d postgres -f db/schema.sql
   psql -h your-supabase-host -U postgres -d postgres -f db/creative.sql
   psql -h your-supabase-host -U postgres -d postgres -f db/config_and_actions.sql
   psql -h your-supabase-host -U postgres -d postgres -f db/moderation.sql
   ```

3. **Configure n8n**

   - Import workflows from `workflows/` directory
   - Set up credentials for all services
   - Configure environment variables

4. **Set up Notion**

   - Create databases as specified in documentation
   - Configure API integration
   - Set up webhook endpoints

5. **Configure Slack**
   - Create incoming webhook
   - Set up bot permissions
   - Configure notification channels

## 📊 Data Sources

### Real API: Klaviyo

- **Purpose**: Email marketing performance data
- **Authentication**: API Key
- **Rate Limits**: 600 requests/minute
- **Data Retrieved**: Campaign performance, email metrics, customer engagement

### Mock API: Supabase Functions

- **Purpose**: Simulated social media advertising data
- **Authentication**: Supabase service key
- **Implementation**: Edge functions with realistic data patterns
- **Data Retrieved**: Campaign spend, impressions, clicks, conversions

## 🔄 Workflow Overview

### Part 1: Data Ingestion (`ingest.json`)

- Scheduled daily data collection from Klaviyo and Mock API
- Data normalization and deduplication
- Storage in Supabase and Notion
- Performance visualization in Databox

### Part 2: Creative Generation (`creative.json`)

- AI-powered copy generation based on performance data
- Novelty checking against historical variants
- Staging for review in Notion
- Integration with ad platforms for draft creation

### Part 3: Campaign Optimization (`optimize.json`)

- Rule-based campaign management
- Automated pause/budget adjustments
- Service-time gating for Meta/Google Ads
- Slack notifications for actions taken

### Part 4: Social Moderation (`moderation.json`)

- Social media comment ingestion
- AI-powered sentiment and intent analysis
- Automated moderation actions
- Approval workflow for responses

## 📈 Key Features

- **Idempotent Operations**: Safe to re-run workflows
- **Error Handling**: Comprehensive retry logic and failure logging
- **Rate Limit Management**: Respects API limits with backoff strategies
- **Data Quality**: Validation and normalization across platforms
- **Security**: Environment-based configuration, no hardcoded secrets
- **Monitoring**: Comprehensive logging and alerting

## 🔧 Configuration

### Environment Variables

```bash
# Database
SUPABASE_URL=your-supabase-url
SUPABASE_SERVICE_KEY=your-service-key

# APIs
KLAVIYO_API_KEY=your-klaviyo-key
OPENAI_API_KEY=your-openai-key

# Notion
NOTION_API_KEY=your-notion-key
NOTION_DATABASE_ID=your-database-id

# Slack
SLACK_WEBHOOK_URL=your-slack-webhook

# Meta (optional)
META_ACCESS_TOKEN=your-meta-token
```

## 📚 Documentation

- [Part 1: Data Ingestion](docs/INGEST.md)
- [Part 2: Creative Generation](docs/CREATIVE.md)
- [Part 3: Campaign Optimization](docs/OPTIMIZE.md)
- [Part 4: Social Moderation](docs/MODERATION.md)
- [System Architecture](docs/ARCHITECTURE.md)

## 🎥 Demo Videos
- [Introduction](https://www.loom.com/share/d8903710f6794bcc97e07dcad199a50e?sid=e244273c-4f78-46c1-a07b-b9bbaf7060ce)
- [Part 1 Walkthrough]([https://loom.com/part1-demo](https://www.loom.com/share/a8f2347e1f0245f8b73f5076292b1599?sid=27d12f1d-fccd-443d-80d2-c2e8c84bec86))
- [Part 2 Walkthrough](https://www.loom.com/share/f9fed91efe10438a8c8547839fff91fa?sid=b09294a6-72a4-4045-bb0e-7828e21ac752)
- [Part 3 Walkthrough]([https://loom.com/part3-demo](https://www.loom.com/share/640083641d0f4048b5ea4a408dadfce6?sid=8f31f6ae-0553-4999-bcc2-90f1502f6e9e))
- [Part 4 Walkthrough](https://www.loom.com/share/f7c380ab82bb42fcae9298b1dc01ac65?sid=c5a34a7b-3280-4959-81bf-7a1903154833)

## 🧪 Testing

### Mock API Testing

The mock API implemented in Supabase provides realistic data patterns for testing:

- Campaign performance variations
- Seasonal trends simulation
- Error scenarios for resilience testing
- Rate limiting simulation

### Integration Testing

- End-to-end workflow validation
- API response handling
- Error recovery scenarios
- Data consistency checks

## 🚨 Error Handling

- **Retry Logic**: 3 attempts with exponential backoff
- **Circuit Breakers**: Prevent cascade failures
- **Dead Letter Queues**: Failed items for manual review
- **Monitoring**: Comprehensive logging and alerting

## 📊 Performance Metrics

- **Data Ingestion**: ~2-3 minutes for daily sync
- **Creative Generation**: ~30-60 seconds per batch
- **Optimization**: ~1-2 minutes for rule evaluation
- **Moderation**: Real-time processing with <5 second latency

## 🔒 Security Considerations

- API keys stored in n8n credentials
- Environment-based configuration
- Read-only database connections where possible
- Input validation and sanitization
- Rate limiting and abuse prevention

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For questions or issues:

- Check the documentation in `/docs`
- Review the workflow configurations
- Check the troubleshooting section in each part's documentation

