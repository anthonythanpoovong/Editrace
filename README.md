# Editrace

Reverse-engineer short-form videos into editable templates, then apply them in DaVinci Resolve, Premiere Pro, Final Cut Pro or CapCut through an MCP tool.

**Positioning:** "Rebuild the edit in minutes." It's a faithful reconstruction of cut decisions, pacing, transitions, motion, text and beats from any video.

## What it does

- **Web app:** upload a video, get a template breakdown (scrubbable timeline, "Tools used" per editor), and download exports.
- **MCP integration:** a remote MCP server exposes your templates to MCP clients (Claude, Cursor, …). The local **Editrace Bridge** applies them directly in your editor.
- **Template assistant:** a RAG chatbot on the breakdown page that answers which editor tools are used and how to reproduce them, with timestamps and doc citations.

## Quick Start

See [`docs/plan.md`](docs/plan.md) for the full project plan, architecture and roadmap.

## Repo Layout

```
schema/      Template JSON Schema (source of truth) + editor tool ontology
web/         Next.js + TypeScript app (breakdown UI, assistant, remote MCP server)
workers/     Python analysis pipeline (Modal)
exporters/   OpenTimelineIO + CapCut adapters
docs/        Plan, architecture, decisions (ADRs), epic proposals, customer research
.claude/     Claude Code skills shared by the team (see Claude Code Skills below)
```

The Editrace Bridge (local MCP server + editor adapters) gets its own folder once its language is chosen (#29).

## Team

- **CV 1, Visual timeline & editors:** calvinkafaiyuen (cuts, motion, transitions, exporters, editor adapters)
- **CV 2, Signals & scoring:** sktchan (audio, OCR, captions, color, scoring)
- **Product, MCP & assistant:** anthonythanpoovong (web, auth, billing, MCP server + Bridge, RAG assistant, GTM)

## Stack

- **Web:** Next.js + TypeScript + Supabase (Postgres + pgvector)
- **Workers:** Python on Modal (GPU)
- **Exporters:** OTIO + CapCut
- **MCP:** MCP TypeScript SDK (remote server) + Editrace Bridge (local)
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

## Claude Code Skills

The repo ships Claude Code skills in `.claude/skills/`. They're available automatically when you run `claude` in this repo: type the slash command, or just describe what you want.

**Plan & decide**

| Skill | Use it for |
|---|---|
| `/grill` | Pressure-test an idea like a founding engineer: problem, alternatives, cost, security, failure modes, reversibility and success metric. Nothing gets written. |
| `/log-interview` | Record a customer or design-partner conversation in `docs/customers/` as tagged evidence that `/grill` cites. |
| `/spike` | Open, run and close a time-boxed spike that answers one unknown, then hand off to an ADR or epic. |
| `/propose-epic` | Grill → break into stories → draft `docs/epics/<name>.md` → draft PR. After approval, it creates the `epic` and `story` issues. |
| `/propose-adr` | Grill → draft `docs/decisions/NNNN-<name>.md` (options, decision, consequences) → draft PR. |

**Build**

| Skill | Use it for |
|---|---|
| `/pick-up-story` | Check a story is ready, branch, and open a draft PR with its acceptance criteria as a checklist. |
| `/schema-change` | Change `schema/template.schema.json` safely: additive vs breaking (→ ADR), examples, `make codegen`, versioning. |
| `/new-detector` | Scaffold an analysis worker on the shared base (#53) with confidence/provenance, caching, downsampling and cost logging. |
| `/golden-eval` | Score a detector against the golden set (#52) vs `main`, and post the metrics table on the PR. |
| `/db-migration` | Supabase migration + RLS policies + a two-user access test, together (#49). |
| `/mcp-tool` | Add a tool to the remote MCP server (#27) or the Bridge (#32): generated Zod, auth, RLS, audit, Inspector tests. |
| `/editor-adapter` | Bridge adapter for Resolve / Premiere / FCP / CapCut: `detect / capabilities / plan / apply → report`, with contract tests. |
| `/rag-eval` | Run the assistant eval (#39): recall@5, citations, tool mapping, refusals. Thresholds block merge. |

**Docs**

| Skill | Use it for |
|---|---|
| `/sync-docs` | After large changes merge, update this README, `docs/plan.md` (via PR) and the wiki to match `main`. |

The build skills check their prerequisites first (e.g. `/new-detector` needs the worker base #53). If a prerequisite doesn't exist yet, they stop and point to its issue.

**New features and architecture changes are drafted, grilled and approved before they become issues or code.** Approval = code-owner review and merge of the proposal PR (CODEOWNERS covers `docs/decisions/`, `docs/epics/` and `.claude/`). See the [Claude Code Skills wiki page](https://github.com/anthonythanpoovong/Editrace/wiki/Claude-Code-Skills) for walkthroughs.

## CI & AI Code Review

Three workflows in `.github/workflows/` run on every pull request:

| Workflow | File | What it does |
|---|---|---|
| **CI** | `ci.yml` | Scans for secrets with gitleaks, validates the template schema, and runs web/Python/codegen checks. Each job switches on once its part of the monorepo has real code. |
| **Editrace Armour** | `ai-review.yml` | An AI reviewer (Claude **Sonnet 5.5**) that posts one summary comment and inline comments on every PR, including drafts, following the rules in [`.github/armour.md`](.github/armour.md). It's advisory only, never a required check. |
| **Claude Code** | `claude.yml` | Mention `@claude` in an issue, PR comment or review to have Claude respond. |

**Authentication:** Armour and `@claude` authenticate with the `CLAUDE_CODE_OAUTH_TOKEN` repo secret, which is billed to the owner's Claude Pro plan. CI runs count against the same Pro usage limits as personal Claude use. A Console API key (`ANTHROPIC_API_KEY`) would need separately purchased API credits, because Pro doesn't include them.

**Ownership:** `.github/CODEOWNERS` requires owner approval for changes under `.github/` (workflows and Armour rules), `docs/decisions/`, `docs/epics/` and `.claude/` (skills). All three collaborators are code owners on every path, so any of them can approve any PR. Review rules and the no-admin-bypass decision are in [CONTRIBUTING.md](CONTRIBUTING.md).

**Gotcha:** a PR that changes a Claude workflow file skips its own Armour/`@claude` run ("workflow validation failed"). The action only runs when the workflow matches `main`, so a green check on that PR doesn't mean Claude ran. Merge it first, then test on another PR (for example, close and reopen it).

See the [wiki](https://github.com/anthonythanpoovong/Editrace/wiki) for per-feature documentation (web app, analysis pipeline, schema, editor integrations, MCP, RAG assistant, billing) and CI details.
