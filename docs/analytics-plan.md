# Product analytics plan (#51)

Status: **planning only** — no instrumentation code lands in this PR. This doc fixes the objectives and a tool-agnostic event schema so each flow (auth, upload, breakdown, export, MCP, assistant) adds its own events as it ships, instead of analytics being bolted on after the fact. Grilled before drafting; open questions carried below rather than resolved speculatively.

## Objective

Make it possible to answer the three `docs/plan.md` § Metrics questions from real data, without guessing:

1. **Time to editor** — upload → template open, target < 10 min (MVP gate).
2. **MCP adoption** — % of active users with a connected client; applies per week per editor.
3. **Assistant quality** — thumbs-up rate; % of answers with citations.

## Why this is its own story, not folded into #15

There's no forcing deadline for this — it's "good practice before we scale," not blocking a launch gate. The reason it's worth doing as a standalone piece now rather than deferring to whichever story happens to touch the UI first: #15 (auth) is scoped to *implementing* registration/auth, not to deciding a company-wide analytics vendor and a 7-event schema. Separating "what do we track and why" from "build the login form" keeps each story's owner focused on one concern. The schema itself is expected to change as #15/#16/#18 land and reveal what's actually easy to instrument — this doc is a starting contract, not a frozen spec.

`web/` is currently a stub (no Next.js app yet) — Auth (#15), upload (#16), breakdown page (#18), export (#64), and MCP tools (#69–75) are all still open. The dashboard this feeds can't be real until those land.

## Tool: not decided yet

No tool is committed to in this PR. Candidates for whoever makes the call (likely whenever #15 wires in the first SDK, or a dedicated decision before then):

- **PostHog** — funnels/retention built in, matches the signup→upload→breakdown→export funnel shape directly; self-hostable, which keeps analytics data out of the Supabase RLS boundary that guards user video/template data; feature flags come free.
- **Amplitude / Mixpanel** — comparable funnel analytics, no self-host option, pricier at scale.
- **GA4** — built for marketing funnels, weaker at product/session-level event modeling.
- **Build on Supabase** — duplicates a query layer the above tools already provide, for no clear benefit at this stage.

Whichever is picked, it sits behind one module (see below) so switching later touches one file, not every call site.

**Open question:** per-user/per-month cost at 100 and 10k users can't be priced until a tool is chosen — flagging rather than guessing.

## Event schema (the actual contract)

One shared module, e.g. `web/lib/analytics/events.ts` (created whenever #15 scaffolds the app), exporting a typed `track(event, properties)` function. Call sites never import a vendor SDK directly — only this module does. That's the full extent of the "swap the tool later" guarantee: one file changes, not six.

Every event maps to one of the three objectives above — nothing is tracked "just in case."

| Event | Fires when | Properties | Feeds |
|---|---|---|---|
| `signup_completed` | Supabase Auth user created | `user_id`, `signup_method` | Time to editor (start) |
| `upload_started` | User selects/drops a file, pre-validation | `user_id`, `job_id` | Funnel step |
| `upload_completed` | Job enters queue successfully | `user_id`, `job_id`, `file_duration_s` | Funnel step |
| `breakdown_viewed` | Breakdown page first paints with data | `user_id`, `job_id`, `time_since_upload_s` | Time to editor (end, non-editor path) |
| `template_exported` | Export fires (CapCut/Resolve/Premiere/FCP XML) | `user_id`, `job_id`, `editor_type` | Time to editor (end, export path) |
| `mcp_client_connected` | OAuth/token handshake succeeds (#70) | `user_id`, `client_name` | MCP adoption (% connected) |
| `mcp_apply_invoked` | `apply_template` tool call succeeds (#72) | `user_id`, `job_id`, `editor_type` | MCP adoption (applies/week/editor); time to editor (MCP path) |
| `assistant_feedback` | Thumbs up/down on an assistant answer | `user_id`, `thumbs_up`, `had_citation` | Assistant quality |

`time_since_upload_s` is computed server-side at fire time, not derived later from event timestamps, so the metric survives client clock skew or dropped events.

**Explicitly excluded from every event:** filenames, transcripts, frame data, video/audio content, raw IP beyond whatever the eventual tool's default pipeline captures. **Open question:** this needs to be checked against whatever #56 (terms/privacy/retention) commits to once that story is picked up — both stories define "what do we record about a session," and they haven't been reconciled yet.

## Collection method

- **Client-side:** `track()` calls from the browser for UI-driven events — auth, upload, breakdown, export.
- **Server-side:** `mcp_client_connected` and `mcp_apply_invoked` fire from the MCP server (#69, #72) via the same module's server-side path — these happen in a Claude Desktop / editor context with no browser.
- **Identity:** `user_id` = Supabase auth UID on every event, so funnels/adoption can be computed per-user, not per-session.

## What lands in which PR

This doc is the contract; it doesn't touch any of these stories' code. Each one adds its own 1–2 `track()` calls when it ships:

- #15 (auth) → `signup_completed`, tool SDK init + tool decision
- #16 (upload flow) → `upload_started`, `upload_completed`
- #18 (breakdown page) → `breakdown_viewed`
- #64 (export buttons) → `template_exported`
- #70/#72 (MCP OAuth / apply tool) → `mcp_client_connected`, `mcp_apply_invoked`
- assistant feedback UI (wherever that lands) → `assistant_feedback`

## Definition of done — for this PR

This PR is done when the doc is merged and available for #15/#16/#18/#64/#70/#72 to reference when they add their first event. It does **not** require a live dashboard — that's #51's full acceptance criteria, met later once those stories land and emit real data.

## Open questions (carried from review, not resolved here)

- No forcing deadline or customer evidence justifies doing this before Phase 1 ships — accepted anyway on separation-of-concerns grounds (see above).
- Tool choice and its real per-user cost are unresolved until someone picks one; do that as part of #15 or as a dedicated decision beforehand, not here.
- Privacy scope (what's excluded from events) needs reconciling with #56 once that story exists.
