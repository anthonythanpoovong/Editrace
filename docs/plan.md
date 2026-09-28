# Viral Template Tool — Project Plan

## Overview

A web app that reverse-engineers videos into editable templates (cuts, pacing, transitions, text overlays, beat markers, color) and exports them to editing tools (CapCut, DaVinci Resolve, Premiere, Final Cut).

**Positioning:** "Rebuild the edit in minutes" — a faithful reconstruction, not an exact copy. A finished MP4 doesn't contain its edit decisions, so we infer them.

## Key Decisions

- **Upload-first.** No link downloading in MVP (TOS and legal risk).
- **No copyrighted audio in exports.** Fingerprint and identify sound, link to it, export beat/cut markers only.
- **Web app, not desktop.** Heavy processing runs on Modal GPU workers.
- **One monorepo.** Docs live in `/docs` as Markdown.
- **Schema-driven.** `schema/template.schema.json` is the single source of truth. TypeScript types and Pydantic models are generated, never hand-written.

## Stack

| Layer | Choice |
|---|---|
| App | Next.js + TypeScript |
| DB, auth, storage | Supabase |
| Workers | Python on Modal (serverless GPU) |
| Billing | Stripe Billing |
| Chat | LLM with template JSON as context (no vector search) |

## Team

| Role | Owner | Labels | Owns |
|---|---|---|---|
| CV 1 — Visual timeline | calvinkafaiyuen | `ml`, `platform` | Cuts, motion, transitions, both exporters |
| CV 2 — Signals & scoring | sktchan | `ml` | Audio, OCR/captions, color, Format Match Score |
| Product & business | anthonythanpoovong | `product` | Web app, auth, billing, chat, job queue, GTM |

## Roadmap

### Phase 0 — De-risk (Spikes & Foundation)
- Define template JSON Schema v0
- Set up type generation
- Scaffold monorepo
- CV1: Cut detection spike (TransNetV2 vs PySceneDetect)
- CV1: Rebuild timeline in Resolve spike
- CV1: CapCut draft spike
- CV2: Beat tracking + sound ID spike
- Product: Customer interviews (5 creators + 5 agency editors)
- Product: Legal consult on link input and audio

**Gate:** Editor reviews detected cut timeline. Does it feel like the original?

### Phase 1 — MVP
**Visual Timeline (CV1)**
- Production cut-detection worker
- Motion estimation (zooms, pans, speed ramps)
- Resolve / Premiere / FCP exporter (OTIO → FCPXML)
- CapCut exporter

**Signals & Scoring (CV2)**
- Captions worker (Whisper)
- Text overlay OCR worker
- Beat + sound worker

**Product**
- Auth: registration and login (Supabase)
- Upload flow + job queue
- Upload history page (row-level security)
- Template breakdown page (scrubbable timeline, export buttons)
- Stripe: Solo tier + free trial

### Phase 2+ — Future
- Template chat (LLM over JSON)
- Transition classification
- Per-shot color / LUT estimation
- Team tier with seats
- Format Match Score v1 (lighting, loudness, framing, pacing)
- MCP server over template API
- Enterprise: API access, SSO, volume pricing

## Metrics

- **Format Match Score:** 1–10 with sub-scores (lighting, loudness/pitch, framing/angle, pacing). Measures similarity to original, not "virality".
- **Editing time saved:** Minutes to rebuild in CapCut/Resolve vs. manual work.
- **Editor satisfaction:** Qualitative feedback on template accuracy.

## Links

- GitHub: https://github.com/anthonythanpoovong/Sequa
- Project Board: https://github.com/users/anthonythanpoovong/projects/2
