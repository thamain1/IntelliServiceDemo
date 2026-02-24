# IntelliService Deployment Reference

This document captures all tools, credentials, and processes used to deploy IntelliService to Cloudflare. Use this as a reference for future deployments.

---

## Project Information

| Item | Value |
|------|-------|
| **Project Name** | IntelliService |
| **Repository** | https://github.com/thamain1/IntelliServiceBeta.git |
| **Local Path** | `C:\dev\intelliservicebeta` |
| **Frontend Framework** | React + Vite + TypeScript |
| **Build Output** | `project/dist` |

---

## Hosting & Services

### Cloudflare Pages (Frontend Hosting)

| Item | Value |
|------|-------|
| **Project Name** | `intelliservice` |
| **Production URL** | https://intelliservice.pages.dev |
| **Dashboard** | https://dash.cloudflare.com → Pages → intelliservice |
| **Account ID** | `77c86d39bc8dbac1cdec9a260d1bbcab` |

### Supabase (Database & Auth)

| Item | Value |
|------|-------|
| **Project URL** | `https://uuarbdrzfakvlhlrnwgc.supabase.co` |
| **Project Reference** | `uuarbdrzfakvlhlrnwgc` |
| **Dashboard** | https://app.supabase.com/project/uuarbdrzfakvlhlrnwgc |
| **Region** | (check Supabase dashboard) |

### Google Cloud (Maps API)

| Item | Value |
|------|-------|
| **API Key** | `AIzaSyBEw5SAoo07mHoNBzOcgGKLkE3IJGeXLvo` |
| **Console** | https://console.cloud.google.com |
| **APIs Enabled** | Maps JavaScript API, Geocoding API, Directions API |

---

## Environment Variables

### Frontend (.env file in project/)

```env
VITE_SUPABASE_URL=https://uuarbdrzfakvlhlrnwgc.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV1YXJiZHJ6ZmFrdmxobHJud2djIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI4MDAzNTIsImV4cCI6MjA3ODM3NjM1Mn0.h2lv9FkVM-4HmztJaqM7MoTTPD92R_ZkU4zSP3sncKQ
VITE_GOOGLE_MAPS_API_KEY=AIzaSyBEw5SAoo07mHoNBzOcgGKLkE3IJGeXLvo
```

### Future Backend (SendGrid, Twilio - for Workers)

**Note**: These credentials are stored locally in `C:\dev\IntelliOptics 2.0\docs\Twilio Recovery.txt`

```env
SENDGRID_API_KEY=<see local credentials file>
SENDGRID_FROM_EMAIL=notifications@yourdomain.com
TWILIO_ACCOUNT_SID=<see local credentials file>
TWILIO_AUTH_TOKEN=<see local credentials file>
TWILIO_PHONE_NUMBER=+18338545203
```

---

## Required Tools

### Installed Globally

| Tool | Purpose | Install Command |
|------|---------|-----------------|
| **Node.js** | JavaScript runtime | Download from nodejs.org (v18+) |
| **npm** | Package manager | Comes with Node.js |
| **Wrangler** | Cloudflare CLI | `npm install -g wrangler` |
| **Git** | Version control | Download from git-scm.com |

### Wrangler Authentication

```bash
# Login to Cloudflare (opens browser)
wrangler login

# Verify login
wrangler whoami
```

---

## Deployment Commands

### Quick Deploy (Most Common)

```bash
cd C:/dev/intelliservicebeta/project
npm run build
npx wrangler pages deploy dist --project-name=intelliservice --commit-dirty=true
```

### Full Deployment Process

```bash
# 1. Navigate to project
cd C:/dev/intelliservicebeta/project

# 2. Install dependencies (if needed)
npm install

# 3. Build for production
npm run build

# 4. Deploy to Cloudflare Pages
npx wrangler pages deploy dist --project-name=intelliservice --commit-dirty=true

# 5. Commit and push to Git
cd ..
git add -A
git commit -m "Description of changes"
git push origin master
```

### First-Time Setup (New Project)

```bash
# Create new Cloudflare Pages project
npx wrangler pages project create intelliservice --production-branch=master

# Then deploy
npx wrangler pages deploy dist --project-name=intelliservice
```

---

## Project Structure

```
C:\dev\intelliservicebeta\
├── project/                    # Main application
│   ├── src/                    # Source code
│   │   ├── components/         # React components
│   │   ├── services/           # Business logic services
│   │   ├── contexts/           # React contexts
│   │   ├── hooks/              # Custom hooks
│   │   └── lib/                # Utilities
│   ├── dist/                   # Build output (deploy this)
│   ├── docs/                   # Documentation
│   ├── .env                    # Environment variables
│   ├── package.json            # Dependencies
│   └── vite.config.ts          # Vite configuration
├── supabase/
│   └── migrations/             # Database migrations
└── .claude/                    # Claude Code settings
```

---

## Key Files Modified During Deployment

| File | Purpose |
|------|---------|
| `project/src/App.tsx` | Main routing, view switching |
| `project/src/components/Auth/LoginForm.tsx` | Login page (removed signup) |
| `project/src/components/Mapping/DispatchMapView.tsx` | Dispatch map with route optimization |
| `project/.env` | Environment variables (not committed) |

---

## Common Issues & Solutions

### Issue: "vite: not found" during build
**Solution**: Run `npm install` in the project directory first.

### Issue: Wrangler not authenticated
**Solution**: Run `wrangler login` and complete browser authentication.

### Issue: Project not found on deploy
**Solution**: Create the project first with `wrangler pages project create`.

### Issue: Old code still showing after deploy
**Causes**:
1. Browser cache - hard refresh (Ctrl+Shift+R)
2. Cloudflare cache - wait a few minutes or purge in dashboard
3. Code not committed - ensure changes are saved and built

### Issue: Environment variables not working
**Note**: Vite `VITE_*` variables are baked in at BUILD time, not runtime. Rebuild after changing .env.

---

## Deployment Checklist

- [ ] All code changes saved
- [ ] `.env` file has correct credentials
- [ ] `npm run build` completes without errors
- [ ] `wrangler pages deploy` succeeds
- [ ] Test the live URL
- [ ] Commit and push to Git

---

## URLs Reference

| Environment | URL |
|-------------|-----|
| **Production** | https://intelliservice.pages.dev |
| **Cloudflare Dashboard** | https://dash.cloudflare.com |
| **Supabase Dashboard** | https://app.supabase.com/project/uuarbdrzfakvlhlrnwgc |
| **GitHub Repository** | https://github.com/thamain1/IntelliServiceBeta |
| **Google Cloud Console** | https://console.cloud.google.com |

---

## Related Documentation

| Document | Path |
|----------|------|
| Multi-Tenant Deployment | `docs/MULTI_TENANT_DEPLOYMENT.md` |
| Cloudflare Architecture | `docs/CLOUDFLARE_ARCHITECTURE.md` |
| Full Deployment Guide | `docs/CLOUDFLARE_FULL_DEPLOYMENT.md` |
| Medium Priority Features | `docs/MEDIUM_PRIORITY_FEATURES.md` |
| Environment Template | `.env.example` |

---

## Notes for Claude Code

When deploying IntelliService:

1. **Working Directory**: Always start from `C:\dev\intelliservicebeta`
2. **Build Directory**: The app code is in `project/` subdirectory
3. **Wrangler Auth**: User has authenticated via browser - check with `wrangler whoami`
4. **Git Branch**: Using `master` branch (not `main`)
5. **Environment Variables**: Already configured in `project/.env`
6. **Project Name**: `intelliservice` on Cloudflare Pages

**Standard Deploy Command**:
```bash
cd C:/dev/intelliservicebeta/project && npm run build && npx wrangler pages deploy dist --project-name=intelliservice --commit-dirty=true
```

**Commit and Push**:
```bash
cd C:/dev/intelliservicebeta && git add -A && git commit -m "message" && git push origin master
```
