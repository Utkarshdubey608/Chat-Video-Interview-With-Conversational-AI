# TalbotIQ Platform — React + TypeScript + Vite

## Quick Start

### 1. Install Node.js (required — not yet installed)
Download from: https://nodejs.org/en/download  
Choose the **LTS** version for Windows (.msi installer).  
Restart your terminal after install.

### 2. Install dependencies
```
cd c:\Users\thoshith.a\Downloads\Virtual\talbotiq-platform
npm install
```

### 3. Run dev server
```
npm run dev
```
Opens at **http://localhost:3001**

---

## What's built

| Page | Route | Description |
|------|-------|-------------|
| Setup | `/setup` | Full Tavus conversation configurator + live JSON preview |
| Interview | `/interview` | Tavus iframe + live AI sidebar + override + fullscreen |
| Results | `/results` | Scorecard, timeline, AI rec, export |
| Replicas | `/replicas` | Full CRUD, training progress, video preview |
| Personas | `/personas` | All layers: LLM, TTS, STT, Perception, VQA |
| Analytics | `/analytics` | Charts, filters, bulk actions |
| Settings | `/settings` | All API keys, webhook, multi-tenant |

## Tech stack
- React 18 + TypeScript + Vite
- Tailwind CSS (TalbotIQ dark theme)
- React Router v6
- Zustand (persisted state)
- TanStack React Query (all API calls, auto-polling)
- Recharts (analytics charts)
- react-hot-toast (notifications)
- lucide-react (icons)
