# IntelliService Agentic AI Test Plan

## Overview
This document outlines the testing strategy for implementing agentic AI capabilities within IntelliService, including projected token costs, testing methodology, and cost optimization strategies.

## Target AI Providers & Pricing (as of Feb 2025)

### Claude (Anthropic)
| Model | Input (per 1M tokens) | Output (per 1M tokens) | Context Window |
|-------|----------------------|------------------------|----------------|
| Claude 3.5 Sonnet | $3.00 | $15.00 | 200K |
| Claude 3.5 Haiku | $0.80 | $4.00 | 200K |
| Claude 3 Opus | $15.00 | $75.00 | 200K |

### OpenAI
| Model | Input (per 1M tokens) | Output (per 1M tokens) | Context Window |
|-------|----------------------|------------------------|----------------|
| GPT-4o | $2.50 | $10.00 | 128K |
| GPT-4o-mini | $0.15 | $0.60 | 128K |
| GPT-4 Turbo | $10.00 | $30.00 | 128K |

### Google Gemini
| Model | Input (per 1M tokens) | Output (per 1M tokens) | Context Window |
|-------|----------------------|------------------------|----------------|
| Gemini 1.5 Pro | $1.25 | $5.00 | 2M |
| Gemini 1.5 Flash | $0.075 | $0.30 | 1M |
| Gemini 2.0 Flash | $0.10 | $0.40 | 1M |

---

## Agentic Use Cases & Token Estimates

### 1. DISPATCH OPTIMIZATION

**Use Case**: AI agent analyzes technician availability, job locations, skills, and priorities to suggest optimal dispatch assignments.

**Typical Workflow**:
1. Fetch open tickets (context)
2. Fetch technician schedules & locations
3. Analyze constraints (skills, travel time, urgency)
4. Generate recommendations
5. Handle user follow-up questions

**Estimated Tokens per Operation**:
| Step | Input Tokens | Output Tokens |
|------|-------------|---------------|
| System prompt + context | 2,000 | - |
| Ticket data (10 tickets) | 3,000 | - |
| Technician data (5 techs) | 1,500 | - |
| Initial analysis | - | 800 |
| Follow-up (avg 2 turns) | 500 | 600 |
| **Total per dispatch session** | **7,000** | **1,400** |

**Projected Cost per Operation**:
| Provider/Model | Cost |
|----------------|------|
| Claude Haiku | $0.011 |
| GPT-4o-mini | $0.002 |
| Gemini Flash | $0.001 |
| Claude Sonnet | $0.042 |
| GPT-4o | $0.032 |

**Daily Volume Estimate**: 20-50 dispatch sessions
**Monthly Cost Range**: $0.60 - $63.00 (depending on model)

---

### 2. PARTS ORDERING AUTOMATION

**Use Case**: AI agent monitors inventory levels, analyzes usage patterns, and generates purchase order recommendations or auto-creates POs.

**Typical Workflow**:
1. Analyze reorder alerts
2. Check vendor pricing/availability
3. Optimize order quantities
4. Generate PO draft
5. Confirm with user

**Estimated Tokens per Operation**:
| Step | Input Tokens | Output Tokens |
|------|-------------|---------------|
| System prompt | 1,500 | - |
| Reorder alert data | 2,000 | - |
| Vendor/pricing context | 1,000 | - |
| Analysis & recommendations | - | 600 |
| PO generation | - | 400 |
| **Total per PO session** | **4,500** | **1,000** |

**Projected Cost per Operation**:
| Provider/Model | Cost |
|----------------|------|
| Claude Haiku | $0.008 |
| GPT-4o-mini | $0.001 |
| Gemini Flash | $0.001 |
| Claude Sonnet | $0.029 |

**Daily Volume Estimate**: 5-15 PO sessions
**Monthly Cost Range**: $0.15 - $13.05 (depending on model)

---

### 3. TECHNICIAN CO-PILOT

**Use Case**: AI assistant helps technicians with diagnostics, repair procedures, parts lookup, and documentation while on-site.

**Typical Workflow**:
1. Technician describes issue/equipment
2. AI provides diagnostic steps
3. Multi-turn troubleshooting conversation
4. Parts recommendations
5. Documentation assistance

**Estimated Tokens per Operation**:
| Step | Input Tokens | Output Tokens |
|------|-------------|---------------|
| System prompt + equipment context | 2,500 | - |
| Initial query | 200 | - |
| Diagnostic response | - | 500 |
| Follow-up turns (avg 4) | 1,200 | 1,600 |
| Parts lookup | 500 | 300 |
| Documentation help | 300 | 400 |
| **Total per co-pilot session** | **4,700** | **2,800** |

**Projected Cost per Operation**:
| Provider/Model | Cost |
|----------------|------|
| Claude Haiku | $0.015 |
| GPT-4o-mini | $0.002 |
| Gemini Flash | $0.001 |
| Claude Sonnet | $0.056 |

**Daily Volume Estimate**: 30-100 sessions (across all techs)
**Monthly Cost Range**: $0.90 - $168.00 (depending on model)

---

### 4. CUSTOMER COMMUNICATIONS

**Use Case**: AI generates/drafts customer communications including appointment confirmations, status updates, follow-ups, and marketing messages.

**Typical Workflow**:
1. Receive trigger (appointment scheduled, job complete, etc.)
2. Fetch customer context & history
3. Generate personalized message
4. Optional: human review before send

**Estimated Tokens per Operation**:
| Step | Input Tokens | Output Tokens |
|------|-------------|---------------|
| System prompt | 1,000 | - |
| Customer/job context | 800 | - |
| Message templates | 500 | - |
| Generated message | - | 200 |
| **Total per message** | **2,300** | **200** |

**Projected Cost per Operation**:
| Provider/Model | Cost |
|----------------|------|
| Claude Haiku | $0.003 |
| GPT-4o-mini | $0.0005 |
| Gemini Flash | $0.0002 |
| Claude Sonnet | $0.010 |

**Daily Volume Estimate**: 50-200 messages
**Monthly Cost Range**: $0.30 - $60.00 (depending on model)

---

### 5. INVOICING & ESTIMATES

**Use Case**: AI assists with generating estimates from job descriptions, creating invoices, explaining line items, and handling pricing questions.

**Typical Workflow**:
1. Parse job description/scope
2. Look up parts/labor rates
3. Generate line items
4. Calculate totals
5. Format document

**Estimated Tokens per Operation**:
| Step | Input Tokens | Output Tokens |
|------|-------------|---------------|
| System prompt + pricing rules | 2,000 | - |
| Job description | 500 | - |
| Parts/labor lookup | 1,000 | - |
| Generated estimate/invoice | - | 800 |
| Revision (avg 1 turn) | 300 | 400 |
| **Total per document** | **3,800** | **1,200** |

**Projected Cost per Operation**:
| Provider/Model | Cost |
|----------------|------|
| Claude Haiku | $0.008 |
| GPT-4o-mini | $0.001 |
| Gemini Flash | $0.001 |
| Claude Sonnet | $0.029 |

**Daily Volume Estimate**: 10-30 documents
**Monthly Cost Range**: $0.30 - $26.10 (depending on model)

---

## Monthly Cost Summary (Projected)

### Low-Cost Model Strategy (GPT-4o-mini / Gemini Flash)

| Use Case | Daily Sessions | Monthly Cost |
|----------|---------------|--------------|
| Dispatch | 35 | $2.10 |
| Parts Ordering | 10 | $0.30 |
| Technician Co-pilot | 65 | $3.90 |
| Customer Comms | 125 | $1.88 |
| Invoicing/Estimates | 20 | $0.60 |
| **TOTAL** | **255** | **$8.78/month** |

### Mid-Tier Model Strategy (Claude Haiku / GPT-4o)

| Use Case | Daily Sessions | Monthly Cost |
|----------|---------------|--------------|
| Dispatch | 35 | $11.55 |
| Parts Ordering | 10 | $2.40 |
| Technician Co-pilot | 65 | $29.25 |
| Customer Comms | 125 | $11.25 |
| Invoicing/Estimates | 20 | $4.80 |
| **TOTAL** | **255** | **$59.25/month** |

### Premium Model Strategy (Claude Sonnet / GPT-4o)

| Use Case | Daily Sessions | Monthly Cost |
|----------|---------------|--------------|
| Dispatch | 35 | $44.10 |
| Parts Ordering | 10 | $8.70 |
| Technician Co-pilot | 65 | $109.20 |
| Customer Comms | 125 | $37.50 |
| Invoicing/Estimates | 20 | $17.40 |
| **TOTAL** | **255** | **$216.90/month** |

---

## Recommended Hybrid Strategy

Use different models for different tasks based on complexity:

| Use Case | Recommended Model | Rationale |
|----------|------------------|-----------|
| Dispatch | Claude Sonnet or GPT-4o | Complex reasoning, high value decisions |
| Parts Ordering | GPT-4o-mini or Gemini Flash | Structured data, rule-based |
| Technician Co-pilot | Claude Haiku or GPT-4o-mini | Balance of quality & cost for high volume |
| Customer Comms | Gemini Flash | Simple generation, very high volume |
| Invoicing/Estimates | GPT-4o-mini | Structured output, medium complexity |

**Estimated Hybrid Monthly Cost**: ~$45-65/month

---

## Testing Methodology

### Phase 1: Baseline Measurement (Week 1)

1. **Create test scenarios** for each use case
   - 10 representative scenarios per category
   - Include edge cases and complex scenarios

2. **Manual token counting**
   - Use tiktoken (OpenAI) or Anthropic's token counter
   - Log actual input/output for each test

3. **Quality assessment**
   - Rate outputs on accuracy, helpfulness, safety
   - Document failure modes

### Phase 2: Cloudflare AI Gateway Setup (Week 2)

1. **Configure AI Gateway**
   - Set up logging and analytics
   - Enable caching for repeated queries
   - Configure rate limiting

2. **Implement token tracking**
   ```javascript
   // Example tracking structure
   {
     use_case: "dispatch",
     model: "claude-3-haiku",
     input_tokens: 7000,
     output_tokens: 1400,
     latency_ms: 2300,
     cache_hit: false,
     timestamp: "2025-02-13T10:30:00Z"
   }
   ```

3. **Set up cost alerts**
   - Daily spend alerts
   - Per-use-case budgets

### Phase 3: A/B Testing (Weeks 3-4)

1. **Compare models** on same tasks
   - Quality scores
   - Latency
   - Cost

2. **Optimize prompts**
   - Reduce token usage without quality loss
   - Test system prompt compression

3. **Caching analysis**
   - Identify cacheable patterns
   - Measure cache hit rates

### Phase 4: Production Pilot (Week 5+)

1. Start with lowest-risk use case (Customer Comms)
2. Gradually enable additional use cases
3. Monitor costs and quality continuously

---

## Cost Optimization Strategies

### 1. Prompt Caching (Cloudflare AI Gateway)
- Cache static system prompts
- Cache common context (pricing rules, etc.)
- **Potential savings: 20-40%**

### 2. Tiered Model Selection
- Use fast/cheap models for simple tasks
- Escalate to powerful models only when needed
- **Potential savings: 30-50%**

### 3. Context Compression
- Summarize long conversations
- Only include relevant context
- **Potential savings: 15-25%**

### 4. Batch Processing
- Batch similar requests where possible
- Process non-urgent tasks in bulk
- **Potential savings: 10-20%**

### 5. Response Length Limits
- Set max_tokens appropriately per task
- Train models to be concise
- **Potential savings: 10-15%**

---

## Test Simulation Scenarios

### Dispatch Test Cases
1. Simple: 3 open tickets, 2 available techs, no conflicts
2. Medium: 8 tickets, 4 techs, skill matching required
3. Complex: Emergency callback + scheduled jobs + traffic considerations
4. Edge: All techs busy, need to reschedule existing jobs

### Parts Ordering Test Cases
1. Simple: Single part below min, one vendor
2. Medium: Multiple parts, vendor comparison needed
3. Complex: Bulk order optimization across vendors
4. Edge: Part discontinued, need substitute recommendation

### Technician Co-pilot Test Cases
1. Simple: Common repair procedure lookup
2. Medium: Diagnostic troubleshooting flow
3. Complex: Unusual equipment, limited documentation
4. Edge: Safety-critical situation requiring escalation

### Customer Communications Test Cases
1. Simple: Appointment confirmation
2. Medium: Job completion summary with recommendations
3. Complex: Complaint response with service recovery
4. Edge: Multi-language support needed

### Invoicing Test Cases
1. Simple: Single service call, standard pricing
2. Medium: Multi-day project with phases
3. Complex: Warranty work + billable items mixed
4. Edge: Disputed charges requiring justification

---

## Next Steps

1. [ ] Set up Cloudflare AI Gateway account
2. [ ] Create API keys for Claude, OpenAI, Gemini
3. [ ] Build token tracking infrastructure
4. [ ] Create test scenario dataset
5. [ ] Run Phase 1 baseline tests
6. [ ] Document results in this file
7. [ ] Make model selection decisions
8. [ ] Begin Phase 2 implementation

---

## Test Results Log

### Simulation Results (To be populated)

| Date | Use Case | Model | Scenario | Input Tokens | Output Tokens | Cost | Quality (1-5) | Notes |
|------|----------|-------|----------|--------------|---------------|------|---------------|-------|
| | | | | | | | | |

---

## Appendix: Token Estimation Reference

**Rule of thumb**:
- 1 token ≈ 4 characters (English)
- 1 token ≈ 0.75 words
- 100 tokens ≈ 75 words

**Common element sizes**:
- Typical system prompt: 500-2,000 tokens
- JSON ticket object: 200-400 tokens
- Customer profile: 150-300 tokens
- Generated email: 100-300 tokens
- Detailed analysis: 400-800 tokens
