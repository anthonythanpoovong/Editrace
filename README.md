# Sequa

Reverse-engineer short-form videos into editable templates, then apply them in DaVinci Resolve, Premiere Pro, Final Cut Pro or CapCut through an MCP tool.

**Positioning:** "Rebuild the edit in minutes." It's a faithful reconstruction of cut decisions, pacing, transitions, motion, text and beats from any video.

## What it does

- **Web app:** upload a video, get a template breakdown (scrubbable timeline, "Tools used" per editor), and download exports.
- **MCP integration:** a remote MCP server exposes your templates to MCP clients (Claude, Cursor, …). The local **Sequa Bridge** applies them directly in your editor.
- **Template assistant:** a RAG chatbot on the breakdown page that answers which editor tools are used and how to reproduce them, with timestamps and doc citations.

## Quick Start

See [`docs/plan.md`](docs/plan.md) for the full project plan, architecture and roadmap.

## Repo Layout

```
schema/      Template JSON Schema (source of truth) + editor tool ontology
web/         Next.js + TypeScript app (breakdown UI, assistant, remote MCP server)
workers/     Python analysis pipeline (Modal)
exporters/   OpenTimelineIO + CapCut adapters
docs/        Plan, architecture, decisions, customer research
```

The Sequa Bridge (local MCP server + editor adapters) gets its own folder once its language is chosen (#29).

## Team

- **CV 1, Visual timeline & editors:** calvinkafaiyuen (cuts, motion, transitions, exporters, editor adapters)
- **CV 2, Signals & scoring:** sktchan (audio, OCR, captions, color, scoring)
- **Product, MCP & assistant:** anthonythanpoovong (web, auth, billing, MCP server + Bridge, RAG assistant, GTM)

## Stack

- **Web:** Next.js + TypeScript + Supabase (Postgres + pgvector)
- **Workers:** Python on Modal (GPU)
- **Exporters:** OTIO + CapCut
- **MCP:** MCP TypeScript SDK (remote server) + Sequa Bridge (local)
- **Assistant:** Claude (Anthropic API) + hybrid retrieval over editor docs
- **Billing:** Stripe

## Getting Started

1. Read [`docs/plan.md`](docs/plan.md)
2. Check the [Project Board](https://github.com/users/anthonythanpoovong/projects/2) (views per area, incl. MCP and RAG)
3. Start with Phase 0 issues

## Schema

The **template JSON Schema** (`schema/template.schema.json`) is the single source of truth. TypeScript types, Pydantic models and MCP tool schemas are **generated from it**, never hand-written.

## Development

- Setup instructions in each folder's README
- Generated code: run type generation before committing schema changes
- Tests: CI validates schema compliance
