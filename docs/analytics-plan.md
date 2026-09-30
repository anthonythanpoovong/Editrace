# Product analytics plan (#51)

Status: **planning only** — no instrumentation code lands in this PR. This doc fixes the tool, event schema, and collection points so each flow (auth, upload, breakdown, export, MCP, assistant) adds its own events as it ships, instead of analytics being bolted on after the fact.

## Why now, before the flows exist

`web/` is currently a stub (no Next.js app yet). Auth (#15), upload (#16), breakdown page (#18), export (#64), and MCP tools (#69–75) are all still open. This doc can't be "complete" in the sense of a working dashboard until those land — but the event schema needs to exist *before* they're built, so each of those PRs instruments itself against a shared contract rather than five different ad-hoc event shapes.

## Tool choice: PostHog

Self-hosted or cloud, decide based on infra cost at #50 (observability) time.

**Why PostHog over the alternatives:**
- Funnels and retention out of the box — the signup → upload → breakdown → export/apply funnel in scope here is PostHog's core use case, not a custom SQL job.
- Session data stays out of Supabase — keeps product analytics separate from the Postgres RLS boundary that guards user video/template data, so an analytics bug can't leak into rows governed by RLS policies.
- Feature flags come free, useful later for staged rollouts (e.g. MCP client support, Phase 2 editor adapters) without a second vendor.
- Self-hostable if data residency becomes a concern before Phase 1 exit; avoids a second procurement/ADR cycle later.

Rejected: Amplitude/Mixpanel (funnel analytics comparable, but no self-host option and pricier at scale); GA4 (built for marketing funnels, weak at product/session-level event modeling); rolling our own on Supabase (duplicates PostHog's query layer for no benefit at this stage).

This is a real tool decision (new external service, cost implications) — if you want it locked in rather than just proposed, this should go through `/propose-adr` before #15 wires the SDK in. Flagging, not doing that here since scope was "planning only."

## Event schema

One shared TS module (`web/lib/analytics/events.ts`, created when #15 scaffolds the app) exporting a typed `track()` wrapper. Every event below maps to a metric in `docs/plan.md` § Metrics — nothing is tracked "just in case."

| Event | Fires when | Properties | Metric it feeds |
|---|---|---|---|
| `signup_completed` | Supabase Auth user created | `user_id`, `signup_method` (email) | Funnel start; time-to-editor start |
| `upload_started` | User selects/drops a file, pre-validation | `user_id`, `job_id` | Funnel step |
| `upload_completed` | Job enters queue successfully | `user_id`, `job_id`, `file_duration_s` | Funnel step |
| `breakdown_viewed` | Breakdown page first paints with data | `user_id`, `job_id`, `time_since_upload_s` | **Time to editor** (upload → this) |
| `template_exported` | Export button fires (CapCut/Resolve/Premiere/FCP XML) | `user_id`, `job_id`, `editor_type` | Funnel end (non-MCP path); time-to-editor end |
| `mcp_client_connected` | OAuth/token handshake succeeds (#70) | `user_id`, `client_name` | **MCP adoption** (% active users connected) |
| `mcp_apply_invoked` | `apply_template` tool call succeeds (#72) | `user_id`, `job_id`, `editor_type` | **MCP adoption** (applies/week/editor); time-to-editor end (MCP path) |
| `assistant_feedback` | Thumbs up/down on an assistant answer | `user_id`, `thumbs_up` (bool), `had_citation` (bool) | **Assistant quality** (thumbs-up rate, % with citations) |

**Explicitly excluded from every event:** filenames, transcripts, frame data, video/audio content, IP address beyond what PostHog's default pipeline captures. This needs to be consistent with whatever #56 (terms/privacy/retention) commits to — worth a cross-check when that story is picked up, since both stories are touching "what do we record about a user's session."

`time_since_upload_s` is precomputed server-side (not derived later from event timestamps), so the metric survives client clock skew or dropped events.

## Collection method

- **Client-side:** PostHog JS SDK, initialized once in the Next.js root layout when #15 lands. Auth, upload, breakdown, export events fire from the client since they're UI-driven.
- **Server-side:** `mcp_client_connected` and `mcp_apply_invoked` fire from the MCP server (#69, #72) via PostHog's server SDK — these happen in a Claude Desktop / editor context with no browser, so they can't be client events.
- **Identity:** `user_id` = Supabase auth UID in every event, so PostHog funnels can be user-level rather than session-level (matters for "% of active users with a connected client").

## Dashboard (stub now, live later)

Skeleton PostHog insights/dashboard can be built against seeded fake events now (so the query definitions exist), then pointed at real data as each flow ships:

1. **Time to editor** — funnel: `signup_completed` → `upload_completed` → `breakdown_viewed` → (`template_exported` OR `mcp_apply_invoked`), median time first-to-last step. Gate: < 10 min.
2. **MCP adoption** — distinct `user_id` with `mcp_client_connected` ÷ distinct active `user_id` (any event in trailing 7d); `mcp_apply_invoked` count grouped by `editor_type`, per week.
3. **Assistant quality** — `assistant_feedback` thumbs-up rate; % where `had_citation = true`. Paired with #39's separate eval scores, not a replacement for them.

## What lands in which PR

This doc is the contract. Each story below adds its own 1–2 `track()` calls referencing it — #51 doesn't touch their code:

- #15 (auth) → `signup_completed`, PostHog SDK init
- #16 (upload flow) → `upload_started`, `upload_completed`
- #18 (breakdown page) → `breakdown_viewed`
- #64 (export buttons) → `template_exported`
- #70/#72 (MCP OAuth / apply tool) → `mcp_client_connected`, `mcp_apply_invoked`
- assistant feedback UI (wherever that lands) → `assistant_feedback`

#51 itself is done when the dashboard reflects real data across all of the above — tracked as a follow-up once those land, not in this PR.
