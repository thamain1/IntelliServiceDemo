# IntelliService Demo - Project Context for Claude

## Overview
This is the **local demo build** of IntelliService — a full field service management platform with AI agent features layered on top. It is used for demonstrations, token usage testing, and agentic AI development. It is **NOT a production build** and should **NEVER** be confused with IntelliServiceBeta or IntelliService-MES.

## ⚠️ Critical Rules
- **NEVER push Neural Command, COPQ, or agent features into IntelliServiceBeta or IntelliService-MES** — those are production builds
- **NEVER apply database migrations from this repo to Production or MES** without explicit approval
- This build connects to the Demo/Test Supabase database (uuarbdrzfakvlhlrnwgc)
- Changes here are demo/experimental only

## Related Repositories

### IntelliService-Demo (This Repo) - Local Demo Build
- **Repository**: https://github.com/thamain1/IntelliServiceDemo
- **Local Path**: `C:\dev\IntelliService-Demo`
- **Purpose**: Full ISB build + Neural Command + COPQ + AI agent features for demos and token testing
- **NOT deployed** — local only, run with `npm run dev`

### IntelliServiceBeta - Production FSM
- **Repository**: https://github.com/thamain1/IntelliServiceBeta
- **Deployment**: Cloudflare Pages → https://intelliservice.pages.dev
- **Purpose**: Production field service management — dispatching, ticketing, inventory, invoicing, BI

### IntelliService-MES - Production Manufacturing
- **Repository**: https://github.com/thamain1/IntelliService-MES
- **Purpose**: Production manufacturing execution system

## Running Locally
```bash
cd C:\dev\IntelliService-Demo
npm run dev
```
Starts on http://localhost:5173 (or next available port).

## Tech Stack
- **Frontend**: React + TypeScript + Vite
- **Styling**: Tailwind CSS
- **Database**: Supabase (PostgreSQL) — Demo/Test project
- **Auth**: Supabase Auth
- **AI Agents**: Claude API + Gemini API

## Project Structure
```
src/
├── components/
│   ├── Neural/              # Neural Command - Multi-Agent Orchestration Hub
│   │   └── NeuralCommandView.tsx
│   ├── BI/
│   │   └── COPQReport.tsx   # Cost of Poor Quality dashboard
│   ├── Tickets/             # Includes Tech Co-Pilot Advisory panel
│   └── ...                  # All standard ISB components
├── services/
│   ├── agents/
│   │   ├── AgentOrchestrator.ts   # Multi-agent orchestration logic
│   │   └── LiveDataService.ts     # Live Supabase data for agents
│   └── ...
├── types/
│   └── agents.ts            # TypeScript types for agent system
└── config/
    └── navigationConfig.ts  # Includes Neural Command nav entries
```

## Demo-Only Features

### Neural Command (Multi-Agent Orchestration Hub)
- Located: `src/components/Neural/NeuralCommandView.tsx`
- Sidebar: **Neural Command → Command Hub**
- **LIVE / Demo toggle** at top right — switches between live Supabase data and mock data
- **Swarm Feed**: Real-time agent message log (Orchestrator, Dispatch Agent, etc.)
- **Intelligence Canvas**: Technician availability panel
- **Approval Gate**: Pending agent actions requiring human approval
- Token usage tracked: messages in/out, session cost displayed live

### COPQ Report (Cost of Poor Quality)
- Located: `src/components/BI/COPQReport.tsx`
- Accessible from BI reports section

### Tech Co-Pilot Advisory
- Embedded in ticket detail view
- AI-powered diagnostic signal panel
- Shows equipment warranty status and diagnostic confidence

## Key Documentation Files
- `synapse2.md` — Primary Neural Command architecture and agent system guide (1363 lines)
- `Agentic Test.md` — Agent testing notes and scenarios (418 lines)
- `SESSION_LOG_2026-02-14.md` — Session log from initial agent build (209 lines)

## Database
- **Supabase Project**: Demo/Test (`uuarbdrzfakvlhlrnwgc`)
- **URL**: https://uuarbdrzfakvlhlrnwgc.supabase.co
- Types file: `src/lib/database.types.ts`

## User Roles
- `admin` — Full access including Neural Command (demo as Kelsey Venable)
- `dispatcher` — Scheduling and dispatch
- `technician` — Field work, includes Tech Co-Pilot panel (demo as 4ward Test)

## Common Issues

### Neural Command not loading
Check that the Supabase demo database is accessible and the `.env` file has valid keys.

### Live mode vs Demo mode
Toggle the **LIVE** button in the top right of Neural Command. Demo mode uses mock data from `mockAgentData.ts`. Live mode queries Supabase directly.

### Agent token costs
Session cost is tracked live in the Command Hub header. Claude and Gemini API keys must be set in environment variables.
