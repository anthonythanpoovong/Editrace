# Product analytics plan (#51)

- **Status:** Planning — feeds #51, no instrumentation code lands with this doc
- **Date:** 2026-10-05
- **Author:** @calvinkafaiyuen
- **Related:** #15, #16, #18, #64, #70, #72, #56, #32, #39

This doc fixes the objectives and a tool-agnostic event schema. Each flow (auth, upload, breakdown, export, MCP, assistant) adds its own events as it ships, instead of analytics being bolted on after the fact.

## Objective

Make it possible to answer the three questions in `docs/plan.md`'s Metrics section from real data, without guessing:

1. **Time to editor** — upload → template open, target < 10 min (MVP gate).
2. **MCP adoption** — % of active users with a connected client; applies per week per editor.
3. **Assistant quality** — thumbs-up rate; % of answers with citations.

## Rationale

This is groundwork, done ahead of need rather than in response to a blocking requirement. No launch gate depends on it, and there's no customer-interview evidence to cite yet.

It stands as its own story rather than folding into whichever flow happens to touch the UI first. #15 (auth) is scoped to *implementing* registration/auth, not to deciding a company-wide analytics vendor and an event schema. Separating "what do we track and why" from "build the login form" keeps each story's owner focused on one concern. That separation is the reason this is worth doing now.

The schema itself is expected to change as #15/#16/#18 land and reveal what's actually easy to instrument. This is a starting contract, not a frozen spec.

`web/` is currently a stub — no Next.js app yet. Auth (#15), upload (#16), breakdown page (#18), export (#64), and MCP tools (#69–75) are all still open. The dashboard this feeds can't be real until those land.

## Tool choice

Tool choice is deferred by design, not left unresolved. Picking one now would mean deciding a vendor before any code exists to need it. Candidates for whoever makes the call (likely whenever #15 wires in the first SDK, or a dedicated decision before then):

| Tool | Pros | Cons |
|---|---|---|
| **PostHog** | Self-hostable, keeping data off third-party infra; funnels/retention built in; generous free tier | Usage-based pricing beyond the free tier — cost grows continuously, not in fixed steps |
| **Amplitude** | Largest free tier of the four | No self-host option |
| **Mixpanel** | Simple free/paid split | Smallest free tier of the four; no self-host option; pricing model changed recently |
| **GA4** | Free with no event cap on the standard tier | Built for marketing traffic, not product funnels; paid tier is enterprise-priced and irrelevant here |
| **Build on Supabase** | No new vendor or bill | Duplicates a query layer the above already provide |

Exact limits and prices aren't quoted — vendor pricing changes, and a specific number here would go stale with no way to notice (see Open questions). At Editrace's expected early-stage volume, every candidate's free tier should comfortably cover usage without payment.

**Leaning candidate: PostHog**, for the self-host option and free-tier headroom at MVP scale.

Whichever is picked, it sits behind the module described in Event schema, so switching later is contained to that one file.

**Constraint on the choice:** the tool only ever receives a pseudonymous ID (see Privacy & data → Identity), never the raw Supabase `user_id`. This rules out nothing in the candidate list above. It's a requirement on how the module calls whichever SDK is chosen, not on which vendor.

## Event schema

One shared module, e.g. `web/lib/analytics/events.ts` (created whenever #15 scaffolds the app), exports a typed `track(event, properties)` function. Call sites never import a vendor SDK directly — only this module does. That's the full extent of the "swap the tool later" guarantee: one file changes, not six.

Every event maps to one of the three objectives above. Nothing is tracked "just in case."

| Event | Fires when | Properties | Purpose |
|---|---|---|---|
| `signup_completed` | Supabase Auth user created | `user_id`, `signup_method` | Counts how many users enter the funnel. Anchors the start of the time-to-editor clock |
| `upload_started` | User selects/drops a file, pre-validation | `user_id`, `job_id` | Marks entry into the upload step. Paired with `upload_completed`, the gap measures drop-off (bad file, rejected, abandoned) — not processing speed |
| `upload_completed` | Job enters queue successfully | `user_id`, `job_id`, `file_duration_s` | Marks the job queued for processing. `jobs.created_at` from this event is the real start of the time-to-editor clock, not `upload_started` |
| `breakdown_viewed` | Breakdown page first paints with data | `user_id`, `job_id` | Marks the non-editor end of time-to-editor: how long from job-queued to the breakdown rendering |
| `template_exported` | Export fires (CapCut/Resolve/Premiere/FCP XML) | `user_id`, `job_id`, `editor_type` | Marks the export-path end of time-to-editor. Also the only signal for which editor users go to — an approximation, see Open questions |
| `mcp_client_connected` | OAuth/token handshake succeeds (#70) | `user_id`, `client_name` | Numerator for MCP adoption: how many active users have linked a client |
| `mcp_apply_invoked` | `apply_template` tool call succeeds (#72) | `user_id`, `job_id`, `editor_type` | Counts applies per editor per week. Also the MCP-path end of time-to-editor — the strongest "reached the editor" signal, since it confirms the template was applied |
| `assistant_feedback` | Thumbs up/down on an assistant answer | `user_id`, `thumbs_up`, `had_citation` | Measures whether users find answers useful, and whether they cite sources. See Open questions for the limits of thumbs up/down as a signal |

**Time to editor is computed at query time, not carried as a client-reported field.** None of `breakdown_viewed`, `template_exported`, or `mcp_apply_invoked` carry an elapsed-time property. Each carries `job_id`. The dashboard joins that against `jobs.created_at` and the server-received timestamp of the event — when it lands at the collection endpoint, not whatever clock the client claims — to get the elapsed seconds. This avoids trusting a client clock, and avoids adding a redundant field to every funnel-ending event.

Every `user_id` value in this table is the pseudonymous ID described in Privacy & data below, not the raw Supabase UID. See there before implementing any of these events.

## Privacy & data

- **Excluded from every event:** filenames, transcripts, frame data, video/audio content, raw IP beyond whatever the eventual tool's default pipeline captures.
- **Identity:** every event is keyed by a pseudonymous ID — a one-way HMAC of the Supabase auth UID, computed server-side. Only the `track()` module's server-side mapping can reverse it back to a real `user_id`, for internal dashboards. Neither the vendor nor the browser ever sees anything but the pseudonymous ID, keeping funnels computable per-user without exposing a real identifier outside the RLS boundary.
- **Schema/DB/RLS/MCP contract impact:** none. Analytics events live entirely in whichever external tool is chosen. Nothing here touches `template.schema.json`, Postgres tables, RLS policies, or MCP tool contracts.
- **Retention:** 1 year, matching PostHog's free-tier default. If a different tool is eventually chosen, it must be configured to match — not every vendor defaults to 1 year.
- **Deletion:** when a user deletes their account, delete the server-side pseudonymous-ID mapping (above), and request the vendor delete that pseudonymous ID's event history too. Deleting only the mapping leaves orphaned events sitting in the vendor's system.

## Collection method

- **Client-side:** `track()` calls from the browser for UI-driven events — auth, upload, breakdown, export.
- **Server-side:** `mcp_client_connected` and `mcp_apply_invoked` fire from the MCP server (#69, #72) via the same module's server-side path. These happen in a Claude Desktop / editor context with no browser.

## Rollout

Each story below builds against the contract defined above, adding its own 1–2 `track()` calls when it ships. This doc touches none of their code directly:

- #15 (auth) → `signup_completed`, tool SDK init + tool decision
- #16 (upload flow) → `upload_started`, `upload_completed`
- #18 (breakdown page) → `breakdown_viewed`
- #64 (export buttons) → `template_exported`
- #70/#72 (MCP OAuth / apply tool) → `mcp_client_connected`, `mcp_apply_invoked`
- assistant feedback UI (wherever that lands) → `assistant_feedback`

## Open questions

| Open question | Owner |
|---|---|
| Tool choice isn't final; current free-tier/pricing limits must be checked against each vendor's own page before deciding | Whoever picks up #15, or a dedicated decision beforehand |
| Once a tool is chosen, is it worth writing an ADR to record it? Not needed now, but the decision touches cost and a new external vendor | Whoever makes the tool decision |
| Privacy scope (the exclusion list) needs reconciling with #56 | Whoever picks up #56 |
| Is opt-out legally required for this pseudonymous data (e.g. under GDPR), and if so, what mechanism satisfies it? | Whoever picks up #56 |
| `template_exported` measures a download, not a confirmed editor open | Whoever picks up #64, revisit once #32 lands |
| `assistant_feedback`'s thumbs up/down shows *whether* an answer was good, not *why* | Whoever reviews assistant quality against #39's eval scores |

- **Privacy scope:** #56 and this doc both define what we record about a session. They haven't been reconciled yet.
- **`template_exported`:** accepted as the closest available proxy until the Bridge (#32) can report a real "opened" signal. `mcp_apply_invoked` doesn't share this gap, since it confirms the template was applied.
- **Thumbs up/down:** can't point at what to fix, only whether something worked. May need a reason code or free-text on thumbs-down later, once usage shows what's actually going wrong.

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ weak | No customer evidence, no forcing deadline; justified by separation-of-concerns (own story vs. folding into #15) |
| Smallest valuable version | ✅ | Objectives + provider-agnostic schema + collection contract; tool stays optional/reference-only |
| Alternatives | ✅ | PostHog kept as a concrete reference option alongside alternatives, explicitly non-binding |
| Fit with Key Decisions | ✅ | Deliberately not an ADR yet; tool choice isn't decided. Revisit as an ADR once it is — tracked in Open questions |
| Data/schema | ✅ | No changes to `template.schema.json`, DB tables, RLS, or MCP tool contracts |
| Security/privacy | ⚠️ | Retention (1yr, matches PostHog free tier) and deletion (mapping + vendor-side) now decided; opt-out narrowed to one legal question for #56 |
| Cost | ⚠️ deferred | Compared qualitatively (pros/cons, no figures, to avoid staleness); tool and real cost still undecided — see Open questions |
| Failure modes | ✅ | `track()` must fail silently and never block the feature it instruments; confirmed as a constraint, left for #15 to implement, not stated in the doc body |
| Reversibility | ✅ | Two-way door; no lock-in created by this PR |
| Observability | ✅ | No check proposed for whether future stories implement the schema correctly; confirmed as out of scope for this doc, left to implementation |
| Success metric | ✅ | Merged and referenced by each Rollout story's first event |
| Effort & ownership | ✅ | Each dependent story's author owns adding their own event; no new dedicated role needed |

</details>
