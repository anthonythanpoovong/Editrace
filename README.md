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
web/         Next.js + TypeScript app (a placeholder page so far; breakdown UI, assistant and remote MCP server are planned)
workers/     Python analysis pipeline (Modal)
exporters/   OpenTimelineIO + CapCut adapters
docs/        Plan, architecture, environments and secrets, decisions (ADRs), epic proposals, customer research
.claude/     Claude Code skills shared by the team (see Claude Code Skills below)
.github/     Workflows, issue and PR templates, CODEOWNERS and the Armour review rules
```

The Editrace Bridge (local MCP server + editor adapters) gets its own folder once its language is chosen (#29).

## Team

- **CV 1, Visual timeline & editors:** calvinkafaiyuen (cuts, motion, transitions, exporters, editor adapters)
- **CV 2, Signals & scoring:** sktchan (audio, OCR, captions, color, scoring)
- **CV 3, Footage match & format benchmark:** mikeleboss (footage matching, format benchmarking)
- **Product, MCP & assistant:** anthonythanpoovong (web, auth, billing, MCP server + Bridge, RAG assistant, GTM)

## Stack

- **Web:** Next.js + TypeScript + Supabase (Postgres + pgvector)
- **Workers:** Python on Modal (GPU)
- **Exporters:** OTIO + CapCut
- **MCP:** MCP TypeScript SDK (remote server) + Editrace Bridge (local)
- **Assistant:** Claude (Anthropic API) + hybrid retrieval over editor docs
- **Billing:** Stripe

## Getting Started

1. Read [`docs/plan.md`](docs/plan.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md) (branches, PRs, review rules)
2. Install the pre-commit hooks once per clone: `pip install pre-commit && pre-commit install` (ruff, prettier, gitleaks, schema check; see CONTRIBUTING.md)
3. Check the [Project Board](https://github.com/users/anthonythanpoovong/projects/2) (views per area, incl. MCP and RAG). New issues are added to it automatically.
4. Start with Phase 0 issues

## Schema

The **template JSON Schema** (`schema/template.schema.json`, v0) is the single source of truth. TypeScript types, Pydantic models and MCP tool schemas are **generated from it**, never hand-written. Every field is explained in [`docs/schema.md`](docs/schema.md); examples, invalid fixtures and test vectors are in [`schema/`](schema/README.md).

## Development

- Setup instructions in each folder's README
- Environments, deploys and where each secret lives: [`docs/environments.md`](docs/environments.md)
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
| `/ticket-sync` | Comment on each issue a commit or merged PR references: what changed and which acceptance criteria it covers. Idempotent; the merged-PR workflow runs it for you. |

The build skills check their prerequisites first (e.g. `/new-detector` needs the worker base #53). If a prerequisite doesn't exist yet, they stop and point to its issue.

**New features and architecture changes are drafted, grilled and approved before they become issues or code.** Approval = code-owner review and merge of the proposal PR (CODEOWNERS covers `docs/decisions/`, `docs/epics/` and `.claude/`). See the [Claude Code Skills wiki page](https://github.com/anthonythanpoovong/Editrace/wiki/Claude-Code-Skills) for walkthroughs.

## CI & AI Code Review

These workflows live in `.github/workflows/`:

| Workflow | File | What it does |
|---|---|---|
| **CI** | `ci.yml` | Scans for secrets with gitleaks, lints the workflow files (actionlint), unit-tests the CI helper scripts, validates the template schema, and runs web/Python/codegen checks. Each part switches on once its folder has real code. `ci-ok` is the required check. |
| **Editrace Armour** | `ai-review.yml` | An AI reviewer (Claude **Sonnet 5.5**) that posts one summary comment and inline comments on every PR, including drafts, following the rules in [`.github/armour.md`](.github/armour.md) read from the **base branch**, so a PR can't edit its own reviewer. If it doesn't review a commit (skipped, failed, usage limit), a second job posts a ⚠️ notice on the PR, removed once a later commit is reviewed. It's advisory only, never a required check. |
| **Claude Code** | `claude.yml` | Mention `@claude` in an issue, PR comment or review to have Claude respond. It has a timeout and read-only tools. |
| **Deploy** | `deploy.yml` | Deploys a preview for every same-repo PR, staging on every push to `main`, and production only when run by hand. See [`docs/environments.md`](docs/environments.md). |
| **Discord review request / ack** | `discord-review-request.yml`, `discord-review-ack.yml` | Posts a review request in Discord when a PR is ready for review, and marks it reviewed when a person reviews. |
| **Discord review comment / PR status** | `discord-review-comment.yml`, `discord-pr-status.yml` | Pings people in Discord about their PR: comments and requested changes, approvals, merges and closes, a request to review again after new commits or a re-request, and `@mentions` and replies. |
| **Discord reminders** | `discord-reminders.yml` | Scheduled pings: the day before and the start of the weekly sync, and the day before a sprint ends. The schedule is in `.github/reminders.json`. |
| **Ticket sync** | `ticket-sync.yml` | When a PR merges, comments on the issues it references (the `/ticket-sync` skill). |
| **Sync docs nudge** | `sync-docs-nudge.yml` | When a merged PR touched the schema, an ADR, an epic, skills or CI workflows, comments once reminding the team to run `/sync-docs`. |
| **Project intake** | `project-intake.yml` | Adds every new issue to the Project Board in the current sprint (Status Backlog), fills in missing level, type and domain/area labels, and assigns it to its author. Needs the secret `PROJECT_TOKEN`; see [CONTRIBUTING.md](CONTRIBUTING.md). |

The Discord workflows are not required checks and never touch the PR's code: they run their scripts from the default branch, so a script change only takes effect once merged. They need the secret `DISCORD_REVIEW_WEBHOOK` and the repo variables `DISCORD_REVIEW_ROLE_ID` and `DISCORD_USER_MAP` (GitHub login to Discord user ID). The reminders also need `PROJECT_TOKEN` to read sprint dates, and can post to another channel through `DISCORD_MEETING_WEBHOOK`.

**Authentication:** Armour and `@claude` authenticate with the `CLAUDE_CODE_OAUTH_TOKEN` repo secret, which is billed to the owner's Claude Pro plan. CI runs count against the same Pro usage limits as personal Claude use. A Console API key (`ANTHROPIC_API_KEY`) would need separately purchased API credits, because Pro doesn't include them.

**Ownership:** `.github/CODEOWNERS` requires owner approval for changes under `.github/` (workflows and Armour rules), `docs/decisions/`, `docs/epics/` and `.claude/` (skills). All four collaborators are code owners on every path, so any of them can approve any PR. Review rules and the no-admin-bypass decision are in [CONTRIBUTING.md](CONTRIBUTING.md).

**Gotcha:** a PR that changes a Claude workflow file skips its own Armour/`@claude` run ("workflow validation failed"). The action only runs when the workflow matches `main`, so a green check on that PR doesn't mean Claude ran (for `ai-review.yml`, the skip notice says so). Merge it first, then test on another PR (for example, close and reopen it).

See the [wiki](https://github.com/anthonythanpoovong/Editrace/wiki) for per-feature documentation (web app, analysis pipeline, schema, editor integrations, MCP, RAG assistant, billing) and CI details.
