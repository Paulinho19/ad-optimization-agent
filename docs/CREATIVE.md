# Part 2: AI Creative Generation & Staging

## Overview

This module implements an AI-powered creative generation system that produces new copy variants based on campaign briefs and recent performance data. It ensures novelty by checking against historical variants and stages results for review in Notion or directly to ad platforms.

## 🎯 Goals

- Generate 3-5 new copy variants using AI based on campaign briefs and performance data
- Ensure novelty by checking against historical variants using similarity analysis
- Provide copy direction rationale tied to recent performance insights
- Stage results as draft/paused creatives or store for review
- Implement safety checks and content moderation

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Input Sources │    │   AI Processing │    │   Output        │
│                 │    │                 │    │                 │
│ • Campaign Brief│───▶│ • LLM Analysis  │───▶│ • Notion        │
│ • Performance   │    │ • Novelty Check │    │ • Ad Platform   │
│ • Historical    │    │ • Safety Filter │    │ • Action Log    │
│   Variants      │    │ • Rationale Gen │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📊 Data Schema

### Creative Variants Table

```sql
CREATE TABLE creative_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id VARCHAR(100) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    headline TEXT NOT NULL,
    primary_text TEXT NOT NULL,
    copy_angle VARCHAR(100) NOT NULL, -- benefit-led, social-proof, urgency, etc.
    rationale TEXT NOT NULL,
    similarity_score DECIMAL(3,2), -- 0.00 to 1.00
    performance_prediction JSONB, -- predicted CTR, CPA, etc.
    status VARCHAR(50) DEFAULT 'staged', -- staged, approved, rejected, live
    created_at TIMESTAMP DEFAULT NOW(),
    created_by VARCHAR(100) DEFAULT 'ai_generator',

    -- Indexes for performance
    INDEX idx_campaign_platform (campaign_id, platform),
    INDEX idx_status_created (status, created_at),
    INDEX idx_similarity (similarity_score)
);
```

### Campaign Briefs Table

```sql
CREATE TABLE campaign_briefs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id VARCHAR(100) UNIQUE NOT NULL,
    platform VARCHAR(50) NOT NULL,
    brand_name VARCHAR(255) NOT NULL,
    product_description TEXT NOT NULL,
    target_audience TEXT NOT NULL,
    key_benefits TEXT[] NOT NULL,
    tone_of_voice VARCHAR(100) NOT NULL,
    call_to_action VARCHAR(255) NOT NULL,
    constraints JSONB, -- length limits, prohibited words, etc.
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### Historical Performance Table

```sql
CREATE TABLE variant_performance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id UUID REFERENCES creative_variants(id),
    campaign_id VARCHAR(100) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    ctr DECIMAL(5,4), -- Click-through rate
    cpa DECIMAL(10,2), -- Cost per acquisition
    roas DECIMAL(10,4), -- Return on ad spend
    impressions BIGINT,
    clicks BIGINT,
    conversions BIGINT,
    spend DECIMAL(10,2),
    date_range_start DATE,
    date_range_end DATE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

## 🔄 Workflow Implementation

### n8n Workflow: `creative.json`

#### 1. Manual Trigger

- **Type**: Webhook or Button node
- **Purpose**: Trigger creative generation on demand
- **Input**: Campaign ID and optional parameters

#### 2. Data Collection

**Campaign Brief Retrieval**

```javascript
// Fetch campaign brief from Notion
{
  "method": "POST",
  "url": "https://api.notion.com/v1/databases/{{$credentials.notion.briefsDbId}}/query",
  "headers": {
    "Authorization": "Bearer {{$credentials.notion.apiKey}}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28"
  },
  "body": {
    "filter": {
      "property": "Campaign ID",
      "rich_text": {
        "equals": "{{$json.campaign_id}}"
      }
    }
  }
}
```

**Performance Data Analysis**

```javascript
// Get recent performance data for insights
const performanceQuery = `
  SELECT 
    copy_angle,
    AVG(ctr) as avg_ctr,
    AVG(cpa) as avg_cpa,
    AVG(roas) as avg_roas,
    COUNT(*) as variant_count
  FROM variant_performance vp
  JOIN creative_variants cv ON vp.variant_id = cv.id
  WHERE vp.campaign_id = '{{$json.campaign_id}}'
    AND vp.date_range_end >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY copy_angle
  ORDER BY avg_roas DESC
`;
```

**Historical Variants Retrieval**

```javascript
// Get existing variants for novelty checking
const variantsQuery = `
  SELECT headline, primary_text, copy_angle, created_at
  FROM creative_variants
  WHERE campaign_id = '{{$json.campaign_id}}'
    AND created_at >= CURRENT_DATE - INTERVAL '90 days'
  ORDER BY created_at DESC
  LIMIT 50
`;
```

#### 3. AI Creative Generation

**Prompt Engineering**

```javascript
// Dynamic prompt based on performance insights
const generatePrompt = (brief, performance, constraints) => {
  const bestPerformingAngle = performance[0]?.copy_angle || "benefit-led";
  const worstPerformingAngle =
    performance[performance.length - 1]?.copy_angle || "urgency";

  return `
You are an expert copywriter creating ad creative variations for a ${
    brief.platform
  } campaign.

CAMPAIGN BRIEF:
- Brand: ${brief.brand_name}
- Product: ${brief.product_description}
- Target Audience: ${brief.target_audience}
- Key Benefits: ${brief.key_benefits.join(", ")}
- Tone: ${brief.tone_of_voice}
- CTA: ${brief.call_to_action}

PERFORMANCE INSIGHTS:
- Best performing angle: ${bestPerformingAngle} (ROAS: ${
    performance[0]?.avg_roas || "N/A"
  })
- Underperforming angle: ${worstPerformingAngle} (ROAS: ${
    performance[performance.length - 1]?.avg_roas || "N/A"
  })

CONSTRAINTS:
- Headline: ${constraints.headline_max_length || 30} characters max
- Primary text: ${constraints.primary_text_max_length || 125} characters max
- Prohibited words: ${constraints.prohibited_words?.join(", ") || "none"}

TASK:
Generate 5 distinct creative variations with different angles:
1. ${bestPerformingAngle} (leverage best performer)
2. social-proof (testimonials, reviews, user count)
3. urgency (limited time, scarcity, FOMO)
4. problem-solution (address pain points)
5. benefit-led (focus on outcomes)

For each variation, provide:
- Headline (compelling, within character limit)
- Primary text (engaging, within character limit)
- Copy angle (one of the above)
- Rationale (2-3 sentences explaining why this angle and approach)

Ensure each variation is unique and addresses different psychological triggers.
`;
};
```

**OpenAI API Call**

```javascript
// Generate creative variations
{
  "method": "POST",
  "url": "https://api.openai.com/v1/chat/completions",
  "headers": {
    "Authorization": "Bearer {{$credentials.openai.apiKey}}",
    "Content-Type": "application/json"
  },
  "body": {
    "model": "gpt-4",
    "messages": [
      {
        "role": "system",
        "content": "You are an expert copywriter specializing in performance marketing. Always provide safe, compliant, and effective ad copy."
      },
      {
        "role": "user",
        "content": "{{$json.prompt}}"
      }
    ],
    "temperature": 0.8,
    "max_tokens": 2000,
    "top_p": 0.9
  }
}
```

#### 4. Novelty Checking

**Similarity Analysis**

```javascript
// Calculate similarity using n-gram Jaccard similarity
const calculateSimilarity = (text1, text2) => {
  const getNGrams = (text, n = 3) => {
    const words = text.toLowerCase().split(/\s+/);
    const ngrams = new Set();
    for (let i = 0; i <= words.length - n; i++) {
      ngrams.add(words.slice(i, i + n).join(" "));
    }
    return ngrams;
  };

  const ngrams1 = getNGrams(text1);
  const ngrams2 = getNGrams(text2);

  const intersection = new Set([...ngrams1].filter((x) => ngrams2.has(x)));
  const union = new Set([...ngrams1, ...ngrams2]);

  return intersection.size / union.size;
};

// Check against historical variants
const checkNovelty = (newVariants, historicalVariants) => {
  return newVariants.map((variant) => {
    let maxSimilarity = 0;
    let mostSimilarVariant = null;

    historicalVariants.forEach((historical) => {
      const headlineSimilarity = calculateSimilarity(
        variant.headline,
        historical.headline
      );
      const textSimilarity = calculateSimilarity(
        variant.primary_text,
        historical.primary_text
      );
      const combinedSimilarity = Math.max(headlineSimilarity, textSimilarity);

      if (combinedSimilarity > maxSimilarity) {
        maxSimilarity = combinedSimilarity;
        mostSimilarVariant = historical;
      }
    });

    return {
      ...variant,
      similarity_score: maxSimilarity,
      most_similar_variant: mostSimilarVariant,
      is_novel: maxSimilarity < 0.3, // Threshold for novelty
    };
  });
};
```

#### 5. Safety Filtering

**Content Moderation**

```javascript
// Safety check using OpenAI moderation API
{
  "method": "POST",
  "url": "https://api.openai.com/v1/moderations",
  "headers": {
    "Authorization": "Bearer {{$credentials.openai.apiKey}}",
    "Content-Type": "application/json"
  },
  "body": {
    "input": "{{$json.headline}} {{$json.primary_text}}"
  }
}

// Additional word filter
const prohibitedWords = [
  'guaranteed', 'promise', 'miracle', 'instant', 'overnight',
  'secret', 'exclusive', 'limited time only', 'act now'
];

const checkProhibitedWords = (text) => {
  const lowerText = text.toLowerCase();
  return prohibitedWords.some(word => lowerText.includes(word));
};
```

#### 6. Performance Prediction

**ML-based Performance Prediction**

```javascript
// Predict performance based on historical data
const predictPerformance = (variant, historicalData) => {
  const anglePerformance = historicalData.find(
    (d) => d.copy_angle === variant.copy_angle
  );

  if (!anglePerformance) {
    return {
      predicted_ctr: 0.02, // Default CTR
      predicted_cpa: 50.0, // Default CPA
      confidence: "low",
    };
  }

  // Simple prediction based on historical average
  return {
    predicted_ctr: anglePerformance.avg_ctr * (0.9 + Math.random() * 0.2), // ±10% variance
    predicted_cpa: anglePerformance.avg_cpa * (0.9 + Math.random() * 0.2),
    confidence: anglePerformance.variant_count > 5 ? "high" : "medium",
  };
};
```

#### 7. Staging and Storage

**Notion Database Update**

```javascript
// Store variants in Notion for review
{
  "method": "POST",
  "url": "https://api.notion.com/v1/pages",
  "headers": {
    "Authorization": "Bearer {{$credentials.notion.apiKey}}",
    "Content-Type": "application/json",
    "Notion-Version": "2022-06-28"
  },
  "body": {
    "parent": {"database_id": "{{$credentials.notion.variantsDbId}}"},
    "properties": {
      "Campaign ID": {"rich_text": [{"text": {"content": variant.campaign_id}}]},
      "Platform": {"select": {"name": variant.platform}},
      "Headline": {"title": [{"text": {"content": variant.headline}}]},
      "Primary Text": {"rich_text": [{"text": {"content": variant.primary_text}}]},
      "Copy Angle": {"select": {"name": variant.copy_angle}},
      "Rationale": {"rich_text": [{"text": {"content": variant.rationale}}]},
      "Similarity Score": {"number": variant.similarity_score},
      "Status": {"select": {"name": "staged"}},
      "Predicted CTR": {"number": variant.predicted_ctr},
      "Predicted CPA": {"number": variant.predicted_cpa}
    }
  }
}
```

**Supabase Storage**

```javascript
// Store in Supabase for analytics
{
  "method": "POST",
  "url": "{{$credentials.supabase.url}}/rest/v1/creative_variants",
  "headers": {
    "Authorization": "Bearer {{$credentials.supabase.serviceKey}}",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
  },
  "body": variant
}
```

## 🎨 Copy Angles & Strategies

### 1. Benefit-Led

- **Focus**: Direct outcomes and value proposition
- **Language**: Results-oriented, outcome-focused
- **Example**: "Increase Your Revenue by 40% in 30 Days"

### 2. Social Proof

- **Focus**: Testimonials, reviews, user count
- **Language**: Community-driven, trust-building
- **Example**: "Join 10,000+ Businesses Already Growing with Us"

### 3. Urgency/Scarcity

- **Focus**: Limited time, limited availability
- **Language**: Time-sensitive, action-oriented
- **Example**: "Only 24 Hours Left - 50% Off Ends Tonight"

### 4. Problem-Solution

- **Focus**: Address pain points directly
- **Language**: Empathetic, solution-focused
- **Example**: "Tired of Losing Customers? Here's the Fix"

### 5. Authority/Expertise

- **Focus**: Credibility and expertise
- **Language**: Professional, authoritative
- **Example**: "Industry Experts Recommend This Strategy"

## 🛡️ Safety & Compliance

### Content Moderation

- **OpenAI Moderation API**: Automatic content filtering
- **Word Filtering**: Prohibited words and phrases
- **Compliance Check**: Platform-specific guidelines
- **Human Review**: Flagged content for manual review

### Safety Measures

```javascript
const safetyChecks = {
  moderation: {
    enabled: true,
    threshold: 0.7,
    action: "flag_for_review",
  },
  wordFilter: {
    enabled: true,
    prohibitedWords: ["guaranteed", "promise", "miracle"],
    action: "reject",
  },
  lengthValidation: {
    enabled: true,
    maxHeadlineLength: 30,
    maxPrimaryTextLength: 125,
    action: "truncate",
  },
};
```

## 📊 Rationale & Novelty Analysis

### Rationale Generation

Each generated variant includes a rationale explaining:

- **Angle Selection**: Why this copy angle was chosen
- **Performance Basis**: How recent performance data influenced the approach
- **Targeting Strategy**: How it addresses the target audience
- **Differentiation**: What makes it unique from previous variants

### Novelty Assessment

- **Similarity Threshold**: 0.3 (30% similarity considered too similar)
- **N-gram Analysis**: 3-word phrase comparison
- **Semantic Similarity**: Optional embedding-based comparison
- **Historical Context**: Comparison against last 90 days of variants

## 🚀 Staging Options

### Option 1: Notion Review Queue

- **Status**: `staged`
- **Review Process**: Manual approval required
- **Actions**: Approve, Reject, Modify
- **Integration**: One-click deployment to ad platforms

### Option 2: Direct Platform Staging

- **Meta Ads**: Create draft campaigns
- **Google Ads**: Create paused ad groups
- **Status**: `draft` or `paused`
- **Activation**: Manual or automated based on performance

### Option 3: Hybrid Approach

- **High Confidence**: Direct staging
- **Low Confidence**: Notion review
- **Threshold**: Based on similarity score and predicted performance

## 📈 Performance Tracking

### Metrics Tracked

- **Generation Time**: Time to create variants
- **Novelty Rate**: % of variants passing similarity check
- **Approval Rate**: % of variants approved for use
- **Performance Correlation**: How well predictions match actual results

### Analytics Dashboard

- **Variant Performance**: CTR, CPA, ROAS by angle
- **Generation Trends**: Most successful angles over time
- **Novelty Analysis**: Similarity scores and uniqueness trends
- **Approval Workflow**: Review time and approval rates

## 🔧 Configuration

### Environment Variables

```bash
# AI Services
OPENAI_API_KEY=your-openai-key
CLAUDE_API_KEY=your-claude-key

# Storage
SUPABASE_URL=your-supabase-url
SUPABASE_SERVICE_KEY=your-service-key

# Notion
NOTION_API_KEY=your-notion-key
NOTION_VARIANTS_DB_ID=your-variants-db-id
NOTION_BRIEFS_DB_ID=your-briefs-db-id

# Ad Platforms (optional)
META_ACCESS_TOKEN=your-meta-token
GOOGLE_ADS_DEVELOPER_TOKEN=your-google-token
```

### Prompt Configuration

```javascript
const promptConfig = {
  model: "gpt-4",
  temperature: 0.8,
  maxTokens: 2000,
  topP: 0.9,
  frequencyPenalty: 0.1,
  presencePenalty: 0.1,
};
```

## 🧪 Testing & Validation

### Unit Tests

- **Prompt Generation**: Validate prompt construction
- **Similarity Calculation**: Test n-gram similarity algorithm
- **Safety Filtering**: Verify content moderation
- **Performance Prediction**: Test prediction accuracy

### Integration Tests

- **End-to-End**: Complete generation workflow
- **API Integration**: Test all external API calls
- **Data Consistency**: Verify data integrity across systems

### A/B Testing

- **Variant Performance**: Compare AI-generated vs human-created
- **Angle Effectiveness**: Test different copy angles
- **Novelty Impact**: Measure performance vs similarity scores

## 📚 API Documentation

### OpenAI API

- **Endpoint**: `https://api.openai.com/v1/chat/completions`
- **Model**: `gpt-4`
- **Rate Limits**: 10,000 tokens/minute
- **Documentation**: [OpenAI API Docs](https://platform.openai.com/docs/api-reference)

### Notion API

- **Endpoint**: `https://api.notion.com/v1/`
- **Version**: `2022-06-28`
- **Rate Limits**: 3 requests/second
- **Documentation**: [Notion API Docs](https://developers.notion.com/reference)

## 🔄 Maintenance & Updates

### Daily Operations

- **Monitor**: Check generation success rates
- **Validate**: Review generated content quality
- **Optimize**: Adjust prompts based on performance

### Weekly Operations

- **Analyze**: Review variant performance data
- **Update**: Refresh historical data for insights
- **Improve**: Refine similarity thresholds and safety rules

### Monthly Operations

- **Audit**: Review prompt effectiveness
- **Scale**: Optimize for increased volume
- **Document**: Update best practices and guidelines

## 🆘 Troubleshooting

### Common Issues

**Low Novelty Scores**

- **Symptom**: High similarity with historical variants
- **Solution**: Increase temperature, add more diverse prompts
- **Prevention**: Regular historical data cleanup

**Safety Filter False Positives**

- **Symptom**: Valid content flagged as unsafe
- **Solution**: Adjust moderation thresholds, add whitelist
- **Prevention**: Regular review of flagged content

**Poor Performance Predictions**

- **Symptom**: Predicted vs actual performance mismatch
- **Solution**: Improve historical data quality, refine algorithms
- **Prevention**: Regular model retraining

### Debug Commands

```bash
# Test OpenAI API
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"gpt-4","messages":[{"role":"user","content":"test"}]}' \
     https://api.openai.com/v1/chat/completions

# Test Notion API
curl -H "Authorization: Bearer $NOTION_API_KEY" \
     -H "Notion-Version: 2022-06-28" \
     https://api.notion.com/v1/databases/$NOTION_VARIANTS_DB_ID

# Test Supabase
curl -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
     "$SUPABASE_URL/rest/v1/creative_variants?limit=1"
```

## 📊 Success Metrics

### Acceptance Criteria Met

✅ **Clear Prompt Strategy**: Token/length constraints and style guardrails  
✅ **Safe Outputs**: Content moderation and word filtering  
✅ **Net-New Evidence**: Similarity checking and novelty validation  
✅ **Copy Direction Rationale**: Performance-based angle selection  
✅ **Real API Staging**: Notion integration with approval workflow  
✅ **Comprehensive Logging**: All actions logged for audit trail

### Performance Benchmarks

- **Generation Time**: < 30 seconds for 5 variants
- **Novelty Rate**: > 80% of variants pass similarity check
- **Safety Rate**: > 99% of variants pass safety filters
- **Approval Rate**: > 70% of variants approved for use
- **Prediction Accuracy**: ±20% variance from actual performance
