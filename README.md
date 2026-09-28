# Viral Template Tool

Reverse-engineer videos into editable templates and export to CapCut, DaVinci Resolve, Premiere, Final Cut Pro.

**Positioning:** "Rebuild the edit in minutes" — a faithful reconstruction of cut decisions, pacing, transitions, and motion from any video.

## Quick Start

See [`docs/plan.md`](docs/plan.md) for the full project plan and roadmap.

## Repo Layout

```
schema/      Template JSON Schema (source of truth)
web/         Next.js + TypeScript app
workers/     Python analysis pipeline (Modal)
exporters/   OpenTimelineIO + CapCut adapters
docs/        Plan, architecture, decisions, customer research
```

## Team

- **CV 1 — Visual Timeline:** calvinkafaiyuen (cuts, motion, transitions, exporters)
- **CV 2 — Signals & Scoring:** sktchan (audio, OCR, captions, color, scoring)
- **Product & Business:** anthonythanpoovong (web, auth, billing, GTM)

## Stack

- **Web:** Next.js + TypeScript + Supabase
- **Workers:** Python on Modal (GPU)
- **Exporters:** OTIO + CapCut
- **Billing:** Stripe

## Getting Started

1. Read [`docs/plan.md`](docs/plan.md)
2. Check the [Project Board](https://github.com/users/anthonythanpoovong/projects/2)
3. Start with Phase 0 issues

## Schema

The **template JSON Schema** (`schema/template.schema.json`) is the single source of truth. TypeScript types and Pydantic models are **generated from it**, never hand-written.

## Development

- Setup instructions in each folder's README
- Generated code: run type generation before committing schema changes
- Tests: CI validates schema compliance