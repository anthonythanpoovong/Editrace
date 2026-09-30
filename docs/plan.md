# Sequa — Project Plan

## Overview

Sequa is a web app that reverse-engineers short-form videos into editable **templates** (cuts, pacing, motion, transitions, text overlays, captions, beat markers, color) and connects them to the user's editor through an **MCP tool**. Supported editors are DaVinci Resolve, Premiere Pro, Final Cut Pro and CapCut.

It has three surfaces:

1. **Web app.** Upload a video, get a template breakdown, export files.
2. **MCP integration.** Any MCP client (Claude, Cursor, …) can read templates and apply them directly in the user's editor.
3. **Template assistant.** A RAG chatbot on the breakdown page that answers "what tools are used here, and how do I do this in my editor?"

**Positioning:** "Rebuild the edit in minutes." It's a faithful reconstruction, not an exact copy. A finished MP4 doesn't contain its edit decisions, so we infer them and say how confident we are.

## Key Decisions

- **Upload-first.** No link downloading in MVP (TOS and legal risk, #21).
- **No copyrighted audio in exports.** Fingerprint and identify the sound, link to it, export beat and cut markers only. Audio is discarded after analysis.
- **Web app, not desktop.** Heavy processing runs on Modal GPU workers. The only local component is the optional Sequa Bridge.
- **Two-tier MCP.** A **remote MCP server** (hosted, OAuth) handles templates and exports. A **local Sequa Bridge** (stdio MCP server on the user's machine) drives desktop editors, because the cloud can't reach them.
- **Live where possible, file handoff otherwise.** Each editor gets the best mechanism it supports; capabilities are decided in spike #29.
- **Templates hold slots, not media.** Clips are placeholders for the user's own footage.
- **Schema-driven.** `schema/template.schema.json` is the single source of truth. TypeScript types, Pydantic models and MCP tool schemas (Zod) are generated from it, never hand-written.
- **Frames + rational fps, not float seconds.** Editors use rational time, and float drift causes off-by-one cuts.
- **Deterministic first, LLM second.** "Which tools are used" comes from the editor tool ontology (#31), not an LLM guess. The assistant explains and adds how-to guidance from docs, with citations.
- **One monorepo.** Docs live in `/docs` as Markdown; decisions go in `docs/decisions/` as ADRs.

## Architecture

```
                   ┌──────────────────────── Cloud ────────────────────────┐
 Browser ─────────▶│ Next.js web app ── Supabase (auth, Postgres+pgvector, │
                   │   │  breakdown UI     storage, realtime)               │
                   │   │  assistant  ───▶ Claude API + search_docs          │
                   │   ▼                                                    │
                   │ Job orchestrator ──▶ Modal workers (cuts, motion,      │
                   │                      captions, OCR, beats, color)      │
                   │ Exporters (OTIO→FCPXML/Premiere XML, CapCut draft)     │
                   │ Remote MCP server (Streamable HTTP, OAuth)             │
                   └───────────────▲────────────────────────────────────────┘
                                   │ HTTPS (token)
 MCP client (Claude, Cursor) ──stdio──▶ Sequa Bridge (local MCP server)
                                          ├─ Resolve adapter  (scripting API, live)
                                          ├─ Premiere adapter (UXP panel, live)
                                          ├─ FCP adapter      (FCPXML handoff)
                                          └─ CapCut adapter   (drafts folder)
```

**Analysis flow:** upload → `jobs` row → orchestrator fans out workers in parallel → each writes a partial template with confidence/provenance → merge → validate → breakdown page updates via Realtime.

**Editor flow:** the user asks their MCP client to "apply template X in Resolve". The client calls the Bridge's `apply_template`. The Bridge fetches the template from the Sequa API and passes it to the Resolve adapter, which builds the timeline and returns a report of applied, skipped and approximated elements.

## Template Schema (v0 outline, #1)

| Section | Contents |
|---|---|
| `source` | duration (frames), fps (rational), resolution, aspect, content hash |
| `clips` / slots | source range, speed, zoom/pan keyframes |
| `cuts`, `transitions` | position, type, duration |
| `text_overlays` | text, normalized bbox, style hints, in/out |
| `captions` | word-level timing, line grouping |
| `beats`, `sound_ref` | bpm, beat/downbeat markers; sound id, title, artist, link (no audio) |
| `color` | per-shot params, optional LUT |
| every element | `confidence`, `provenance` (detector, version) |

## Editor Integrations

| Editor | Mode | Mechanism | Phase | Main risk |
|---|---|---|---|---|
| DaVinci Resolve | Live | Python scripting API via Bridge (#33); OTIO/FCPXML fallback (#9) | 1 | Free vs Studio scripting limits |
| Final Cut Pro | Handoff | FCPXML opened in FCP via Bridge (#34) | 1 | No live API: no incremental updates |
| Premiere Pro | Live | UXP panel ↔ Bridge over local WebSocket (#35); Premiere XML fallback | 2 | UXP API coverage for sequence edits |
| CapCut | Handoff | Draft written into local drafts folder (#36, #10) | 2 | Undocumented, version-sensitive draft format |

All four also get plain file downloads from the web app (#9, #10), so the Bridge is optional.

## MCP Design

**Remote MCP server (#27):** MCP TypeScript SDK, Streamable HTTP, OAuth backed by Supabase Auth, with personal tokens as a fallback (#37).

| Tool | Purpose |
|---|---|
| `list_templates` | Find the user's templates |
| `get_template` / `get_elements` | Full template or filtered by type/time range |
| `get_tools_used` | Editor features used, from the ontology |
| `export_template` | Signed URL for FCPXML / Premiere XML / CapCut draft |
| `ask_about_template` | Proxy to the assistant (Phase 2) |

**Sequa Bridge (#32):** local stdio MCP server with the tools `list_editors`, `apply_template`, `add_beat_markers` and `open_export`. The adapter interface is `detect / capabilities / plan (dry run) / apply → report`.

## Template Assistant (RAG)

Goal: answer questions about a breakdown, especially **which editor tools are used and how to reproduce them**, e.g. "What transition is at 0:07 and how do I do it in CapCut?"

Grounding sources, exposed to a Claude tool-use agent:

| Source | What it answers | Tool |
|---|---|---|
| Template JSON | What's in this video, when, and how confident we are | `get_template_elements` |
| Editor tool ontology (#31) | Which feature in editor X produces this element | `lookup_editor_tool`, `tools_used` |
| Editor docs index (#38) | How to use that feature, step by step | `search_docs` (pgvector + full-text hybrid, filtered by editor/version) |

Rules:
- Cite timestamps (clickable) and doc links.
- Flag low-confidence or inferred elements.
- Never present a guess as the exact effect used.
- Stay in scope.
- Enforce a per-plan message quota.

Quality is gated by the eval harness (#39): retrieval recall@5, citation support, tool-mapping accuracy and refusal correctness. The corpus approach is decided in spike #30, and doc licensing is cleared in #21.

## Stack

| Layer | Choice |
|---|---|
| App | Next.js + TypeScript |
| DB, auth, storage, realtime | Supabase (Postgres + pgvector) |
| Workers | Python on Modal (serverless GPU) |
| Exporters | OpenTimelineIO + CapCut draft writer |
| MCP | MCP TypeScript SDK (remote); Bridge language chosen in #29 |
| Assistant | Claude (Anthropic API, tool use) + hybrid retrieval; embedding model chosen in #30 |
| Billing | Stripe Billing |

## Team

| Role | Owner | Labels | Owns |
|---|---|---|---|
| CV 1: Visual timeline & editors | calvinkafaiyuen | `ml`, `platform` | Cuts, motion, transitions, exporters, editor adapters, ontology (visual) |
| CV 2: Signals & scoring | sktchan | `ml` | Audio, OCR/captions, color, Format Match Score, ontology (signals) |
| Product, MCP & assistant | anthonythanpoovong | `product` | Web app, auth, billing, job queue, MCP server + Bridge core, RAG assistant, GTM |

## Roadmap

### Phase 0: De-risk (spikes & foundation)
- Template JSON Schema v0 (#1), type generation (#2), monorepo scaffold (#3, done)
- CV1: cut detection spike (#4), Resolve rebuild spike (#5), CapCut draft spike (#6)
- CV1: **live editor control spike (#29)**
- CV2: beat tracking + sound ID spike (#11)
- Product: **RAG corpus + retrieval spike (#30)**
- Product: customer interviews incl. MCP appetite and assistant questions (#20); legal consult incl. docs corpus and editor TOS (#21)

**Gate:** An editor reviews a detected cut timeline rebuilt in Resolve and confirms it feels like the original. #29 shows at least one editor can be driven live.

### Phase 1: MVP (analyze → breakdown → editor via MCP)
**Visual timeline (CV1):** cut-detection worker (#7), motion estimation (#8), Resolve/Premiere/FCP exporter (#9), CapCut exporter (#10)
**Signals (CV2):** captions (#12), OCR (#13), beat + sound (#14)
**Ontology:** editor tool ontology (#31)
**Product:** auth (#15), upload + job queue (#16), history (#17), breakdown page with the Tools used panel (#18), Stripe Solo + trial (#19)
**MCP:** remote MCP server v1 (#27), settings page (#37), Sequa Bridge (#32), Resolve adapter (#33), FCP adapter (#34)

**Gate:** A new user uploads a video, sees a breakdown, and from Claude Desktop applies it to Resolve or FCP in under 10 minutes.

### Phase 2: Assistant & more editors
- Docs ingestion pipeline (#38), RAG assistant (#22), eval harness (#39); `ask_about_template` MCP tool
- Premiere adapter (#35), CapCut adapter (#36)
- Transition classification (#23)

**Gate:** The assistant passes #39 thresholds; all 4 editors are reachable via the Bridge.

### Phase 3: Depth & scale
- Per-shot color / LUT (#24), Format Match Score v1 (#26)
- Team tier (#25), Enterprise: API, SSO, volume pricing (#28)

## Risks

| Risk | Mitigation |
|---|---|
| Editor APIs limited or version-sensitive (Resolve Free, UXP coverage, CapCut drafts) | Spike #29 before committing; file-handoff fallback for every editor; version pinning + tests |
| Users unwilling to install a local Bridge | Web downloads always work; measure appetite in #20 |
| Assistant gives wrong tool advice | Ontology-first answers, citations required, eval gate #39 |
| Docs licensing | #21 before ingestion; link-only mode as fallback |
| Detection quality below "feels like the original" | Phase 0 gate; confidence shown in the UI and passed to adapters |

## Metrics

- **Time to editor:** upload → template open in the user's editor (target < 10 min, MVP gate)
- **Editing time saved:** minutes to rebuild with Sequa vs manually
- **Format Match Score:** 1–10 with sub-scores (lighting, loudness/pitch, framing/angle, pacing); similarity to the original, not "virality"
- **MCP adoption:** % of active users with a connected client; applies per week per editor
- **Assistant quality:** #39 scores; thumbs-up rate; % of answers with citations
- **Editor satisfaction:** qualitative feedback on template accuracy

## Open Questions

- Bridge language: Python (Resolve API is Python) or Node (MCP SDK, UXP)? Decided in #29.
- Windows support timing for the Bridge.
- Should the assistant be available to trial users, and with what quota?

## Links

- GitHub: https://github.com/anthonythanpoovong/Sequa
- Project Board: https://github.com/users/anthonythanpoovong/projects/2 (views: Spikes, Blocked, Quick wins, per-area incl. MCP and RAG)
