# Product analytics plan (#51)

- **Status:** Planning — feeds #51, no instrumentation code lands with this doc
- **Date:** 2026-10-05 (revised 2026-10-18 after review)
- **Author:** @calvinkafaiyuen
- **Related:** #15, #16, #18, #64, #66, #65, #70, #73, #75, #32, #37, #39, #50, #56

This doc fixes the objectives, a tool-agnostic event schema, the identity and privacy model, and the dashboard that closes #51. Each flow (auth, upload, breakdown, export, MCP, assistant) adds its own events as it ships, instead of analytics being bolted on after the fact.

## Objective

Make it possible to answer the metrics in `docs/plan.md`'s Metrics section that #51 scopes in, from real data, without guessing:

| Metric (from `docs/plan.md`) | Definition used here | Target |
|---|---|---|
| **Time to editor** | Per job: `upload_completed` → first `template_exported` or `template_applied` for the same `job_id` | Median < 10 min (MVP gate) |
| **MCP adoption** | % of active users with ≥1 `mcp_client_connected` | Tracked, no target yet |
| **Applies per week per editor** | Count of `template_applied` per ISO week, split by `editor_type` | Tracked, no target yet |
| **Assistant thumbs-up rate** | `thumbs_up = true` ÷ all `assistant_feedback` | Tracked, no target yet |
| **Assistant citation rate** | `had_citation = true` ÷ all `assistant_answered` | Tracked, no target yet |

**Active user:** an `anon_id` with at least one event in the trailing 28 days. This is a starting definition. Revisit once real usage shows a natural cadence.

**Out of scope for this doc.** The other metrics in `docs/plan.md` don't come from product events:
- Editing time saved and editor satisfaction come from interviews and design partners (#20, #55).
- Format Match Score comes from the scoring pipeline (#26, #105).
- The assistant's #39 eval scores come from the offline eval harness.

## Rationale

This is groundwork, done ahead of need rather than in response to a blocking requirement. No launch gate depends on the instrumentation itself, but the MVP gate (time to editor < 10 min) can't be checked without it, and there's no customer-interview evidence to cite yet.

It stands as its own story rather than folding into whichever flow happens to touch the UI first. #15 (auth) is scoped to *implementing* registration/auth, not to deciding a company-wide analytics vendor and an event schema. Separating "what do we track and why" from "build the login form" keeps each story's owner focused on one concern. That separation is the reason this is worth doing now.

The schema is expected to change as #15/#16/#18 land and reveal what's actually easy to instrument. This is a starting contract, not a frozen spec.

`web/` is scaffolded (Next.js) but has no product flows yet. Auth (#15), upload (#16), breakdown page (#18), export (#64), the remote MCP server (#27, #70) and the Bridge (#32, #73, #75) are all still open. The dashboard can't show real numbers until they land.

## Tool choice

Tool choice is deferred by design, not left unresolved. Picking one now would mean deciding a vendor before any code exists to need it. Candidates for whoever makes the call (likely whenever #15 wires in the first event, or a dedicated decision before then):

| Tool | Pros | Cons |
|---|---|---|
| **PostHog** | Self-hostable, keeping data off third-party infra; funnels/retention built in; SQL queries over raw events; generous free tier | Usage-based pricing beyond the free tier — cost grows continuously, not in fixed steps |
| **Amplitude** | Largest free tier of the four vendors | No self-host option |
| **Mixpanel** | Simple free/paid split | Smallest free tier of the four vendors; no self-host option; pricing model changed recently |
| **GA4** | Free with no event cap on the standard tier | Built for marketing traffic, not product funnels; paid tier is enterprise-priced and irrelevant here |
| **Build on Supabase** | No new vendor or bill; data stays inside the RLS boundary | Duplicates the query and charting layer the vendors already provide |

Exact limits and prices aren't quoted — vendor pricing changes, and a specific number here would go stale with no way to notice (see Open questions). At Editrace's expected early-stage volume, every candidate's free tier should comfortably cover usage without payment.

**Leaning candidate: PostHog**, for the self-host option, SQL over raw events (needed for the per-job time-to-editor join below), and free-tier headroom at MVP scale.

**Requirements the chosen tool must meet:**
1. **Server-side ingestion API.** All events are sent from our server (see Collection method), so a browser-only SDK is not enough.
2. **Per-property joins.** Time to editor pairs two events by `job_id`, not by user. The tool must be able to compute "time between event A and event B with the same property value". Otherwise the dashboard falls back to a Supabase query for that one tile.
3. **Deletion by ID.** The tool must support deleting all events for one `anon_id` (see Deletion).
4. **IP and geo capture can be turned off**, or at least ignored. Events arrive from our server, so they would carry its IP anyway.

Whichever is picked, it sits behind the module described in Event schema, so switching later is contained to that one module.

## Identity

Every event carries an **`anon_id`**, never the Supabase auth `user_id`. The vendor only ever sees `anon_id`.

- **What it is:** a random UUID generated once per user. It's random, not derived from `user_id` (no hash or HMAC), so nobody can recompute it from a `user_id`, even with server access.
- **Where it lives:** a new table, `analytics_identities` (`user_id` PK → `auth.users` with `on delete cascade`, `anon_id uuid unique default gen_random_uuid()`, `created_at`). It's created lazily, on a user's first tracked event.
- **Who can read it:** RLS is enabled with **no** policies for `anon` or `authenticated`, so only the service role (server code) can read or write it. The migration and its two-user access test land with #15, via the `db-migration` skill.
- **How the browser gets it:** it doesn't. The browser sends events to our own endpoint, and the server looks up `anon_id` from the authenticated session (see Collection method). The browser already holds the user's Supabase session, so "the browser never sees `user_id`" isn't a goal. The goal is that **nothing outside our server and database ever links `anon_id` to `user_id`.**
- **Reversing it:** `anon_id` → `user_id` is a service-role lookup in `analytics_identities`. It's used for account deletion and for support, never for dashboards, which are computed per `anon_id`.

## Event schema

One shared module, e.g. `web/lib/analytics/`, exports a typed `track(event, properties)` function. It's created by #15. Only this module imports the vendor SDK, so swapping vendors later changes one module, not every call site.

Every event maps to a metric in the Objective table. Nothing is tracked "just in case."

| Event | Fires when | Fired from | Properties | Feeds |
|---|---|---|---|---|
| `signup_completed` | A Supabase Auth user is created | Server (auth callback, #15) | `anon_id`, `signup_method` | Funnel entry; active-user denominator |
| `upload_started` | The user selects or drops a file, before validation | Browser | `anon_id` | Funnel: drop-off between selecting a file and the job being queued (bad file, rejected, abandoned) |
| `upload_completed` | The job is inserted and queued | Server (job-queue route, #16) | `anon_id`, `job_id`, `file_duration_s` | **Start of the time-to-editor clock** |
| `breakdown_viewed` | The breakdown page first paints with data | Browser | `anon_id`, `job_id` | Funnel step; splits time to editor into "processing" and "user acting on it" |
| `template_exported` | An export download starts (CapCut / Resolve / Premiere / FCP XML) | Server (signed-URL route, #64; `export_template`, #72) | `anon_id`, `job_id`, `editor_type`, `via` (`web` \| `mcp`) | **End of the time-to-editor clock, export path** (a proxy, see Open questions) |
| `mcp_client_connected` | Remote MCP OAuth succeeds (#70), or a Bridge makes its first authenticated call with a new token (#73) | Server | `anon_id`, `client_kind` (`remote` \| `bridge`), `client_name` | MCP adoption |
| `template_applied` | Bridge `apply_template` finishes a real apply (not a dry run) and reports back | Server, on the Bridge's apply report (#75) | `anon_id`, `job_id`, `editor_type` | Applies per week per editor; **end of the time-to-editor clock, MCP path** |
| `assistant_answered` | The assistant returns an answer | Server (assistant backend, #65) | `anon_id`, `answer_id`, `had_citation` | Citation rate |
| `assistant_feedback` | Thumbs up/down on an answer | Browser (chat panel, #66) | `anon_id`, `answer_id`, `thumbs_up` | Thumbs-up rate |

Notes on the table:
- **`job_id` and `answer_id` are opaque database IDs.** They aren't personal data on their own, and they're what lets two events be paired.
- **`template_applied` is reported by the Bridge, not tracked by it.** The Bridge runs on the user's machine and must not carry a vendor key. After a successful apply, it sends the apply report summary (template, editor) to the Editrace API with its existing token. The API resolves the `job_id` and calls `track()`. Dry runs (`plan`) never emit it. This adds one small Bridge → API call to #75's scope. It doesn't change any MCP tool's contract.
- **Citations are recorded per answer, not per rating.** The citation rate counts every answer, while the thumbs-up rate covers only answers someone rated. Reading `had_citation` off feedback events would only cover rated answers, which skews the rate.

### Time to editor

Time to editor is computed at query time, not carried as a property on any event. For each `job_id`:

```
time_to_editor = min(ts of template_exported, ts of template_applied) − ts of upload_completed
```

`ts` is the timestamp our server stamps when it receives or emits the event (see Collection method), never a client clock. All three events are emitted server-side anyway, so there's no client/server clock skew to reconcile. `breakdown_viewed` is the only browser event involved, and it's diagnostic only: `breakdown_viewed − upload_completed` approximates processing time. Its timestamp is also stamped on arrival at our server, so it's consistent with the others to within network latency.

No elapsed-time property is added to the end events. Their server timestamps plus `job_id` already give the answer. A client-reported duration would be less trustworthy, and it would duplicate data.

## Collection method

All events reach the vendor from **our server**, never directly from the browser:

- **Browser events** (`upload_started`, `breakdown_viewed`, `assistant_feedback`) are sent to a thin first-party route, e.g. `POST /api/track`. The route:
  1. authenticates the Supabase session,
  2. checks the event name and properties against the typed allowlist, and drops anything else,
  3. looks up (or creates) the user's `anon_id`,
  4. stamps the server timestamp,
  5. forwards the event through `track()`.
- **Server events** (everything else) call `track()` directly from the route or service where the action happens. That includes the remote MCP server (#27), which is server code too.

Why route everything through the server:
- **One timestamp source.** All events use the server clock.
- **No vendor key or SDK in the browser**, and none on the Bridge.
- **`user_id` → `anon_id` translation happens in one place.**
- **Nothing outside the allowlist can be sent by accident**, so PII can't creep in when someone adds a property.
- **The vendor never receives the user's IP or user agent**, because the request comes from our server.

The trade-off is losing vendor autocapture and session replay. We don't want those anyway (see Privacy & data).

### Reliability

**`track()` must never break the feature it instruments.** This is a hard requirement on every implementation, not a nice-to-have:
- It never throws. Every error is caught and logged as a warning through #50's logging, then dropped.
- It's never awaited on the request's critical path. Server code sends events after the response, e.g. with Next's `after()` or Vercel's `waitUntil`. The browser sends with `fetch(..., { keepalive: true })` and ignores the result.
- It has a short timeout and no retries in v1. Losing an occasional event is acceptable. Slowing an upload or export is not.
- With no vendor key configured (local dev, CI, preview builds), it's a no-op.

## Privacy & data

- **Excluded from every event:**
  - email, name, and any other account profile field;
  - filenames, source video URLs, and template titles;
  - transcripts, frame data, and video or audio content;
  - assistant question and answer text, and any other free text;
  - raw IP and user agent, which the server-side collection method above keeps away from the vendor.
- **Pseudonymous is still personal data.** Under GDPR, `anon_id` is pseudonymous, not anonymous, because we hold the mapping. That's why deletion and opt-out below are handled like any other personal data, and why #56's privacy policy has to cover analytics.
- **Schema/DB/RLS/MCP contract impact:**
  - **New:** the `analytics_identities` table (service-role only, migration + RLS test with #15), the `/api/track` route (#15), and the Bridge's apply-report call (#75).
  - **Unchanged:** `template.schema.json`, existing tables and RLS policies, and every MCP tool's inputs and outputs.
- **Retention:** 1 year. That matches PostHog's free-tier default at time of writing. If a different tool is chosen, it must be configured to match, since not every vendor defaults to 1 year.
- **Deletion:** on account deletion (#56), the deletion job, in this order:
  1. reads the user's `anon_id`,
  2. requests that the vendor delete all events for that `anon_id`,
  3. deletes the user. The `on delete cascade` removes the `analytics_identities` row.

  Because `anon_id` is random, nothing can rebuild the link once the row is gone. Step 2 still matters, though. Without it, the vendor keeps unlinked but still per-person event histories until retention expires.

## Dashboard (acceptance criterion for #51)

#51's acceptance criterion is a dashboard with the `docs/plan.md` metrics. It lives in the chosen tool. If the tool can't do the per-job join, that tile falls back to a saved Supabase query. It has these tiles:

| Tile | Shows | Built from |
|---|---|---|
| Time to editor | Weekly median and p90, the % of jobs under 10 min, and an export vs MCP split | `upload_completed`, `template_exported`, `template_applied` joined on `job_id` |
| Activation funnel | Signup → upload queued → breakdown viewed → exported or applied, within 7 days of signup | `signup_completed`, `upload_completed`, `breakdown_viewed`, `template_exported`/`template_applied` per `anon_id` |
| MCP adoption | % of 28-day active users with a connected client, split by `client_kind` | `mcp_client_connected` ÷ active users |
| Applies per week per editor | Weekly count, stacked by `editor_type` | `template_applied` |
| Assistant quality | Thumbs-up rate and citation rate, weekly | `assistant_feedback`, `assistant_answered` |

**#51 is done when** every tile renders from real (staging or production) events, not seeded data, and the time-to-editor number has been checked by hand against `jobs` rows for at least 3 jobs. Tiles whose flows haven't shipped yet are tracked in the follow-up issue, so #51 doesn't stay open on work owned by other stories.

## Rollout

Each story below builds against the contract defined above, adding its own `track()` calls when it ships. This doc touches none of their code directly:

| Story | Adds |
|---|---|
| #15 (auth) | The `track()` module, the `/api/track` route, the `analytics_identities` migration + RLS test, the tool decision, and `signup_completed` |
| #16 (upload flow) | `upload_started`, `upload_completed` |
| #18 (breakdown page) | `breakdown_viewed` |
| #64 (export buttons), #72 (`export_template`) | `template_exported` |
| #70 (MCP OAuth), #73 (Bridge token auth) | `mcp_client_connected` |
| #75 (Bridge tools) | The apply-report call to the API, which emits `template_applied` |
| #65 (assistant backend), #66 (chat panel) | `assistant_answered`, `assistant_feedback` |
| #56 (privacy/retention) | The analytics step in the account-deletion job; analytics covered in the privacy policy |
| Follow-up to #51 | Build the dashboard tiles once their events flow |

## Open questions

| Open question | Owner |
|---|---|
| Tool choice isn't final; current free-tier/pricing limits and the four requirements above must be checked against each vendor's own docs before deciding | Whoever picks up #15, or a dedicated decision beforehand |
| Once a tool is chosen, is it worth writing an ADR to record it? Not needed now, but the decision adds cost and a new external vendor that holds personal data | Whoever makes the tool decision |
| Privacy scope (the exclusion list) needs reconciling with #56 | Whoever picks up #56 |
| Is opt-out legally required for this pseudonymous data (e.g. under GDPR), and if so, what mechanism satisfies it? If yes, `/api/track` and `track()` check a per-user flag and drop events | Whoever picks up #56 |
| `template_exported` measures a download, not a confirmed editor open | Whoever picks up #64, revisit once #32 lands |
| MCP adoption counts users who *ever* connected, not users who are still connected. #37's token "last used" time could tighten this later | Whoever picks up #37 |
| `assistant_feedback`'s thumbs up/down shows *whether* an answer was good, not *why* | Whoever reviews assistant quality against #39's eval scores |

- **Privacy scope:** #56 and this doc both define what we record about a session. They haven't been reconciled yet.
- **`template_exported`:** accepted as the closest available proxy until the Bridge (#32) can report a real "opened" signal. `template_applied` doesn't share this gap, since the Bridge confirms the template was applied.
- **MCP adoption:** "ever connected" overstates adoption as users churn. It's good enough until there are enough users for the difference to matter.
- **Thumbs up/down:** can't point at what to fix, only whether something worked. May need a reason code on thumbs-down later, once usage shows what's actually going wrong. That would be a fixed list, not free text, to keep text out of events.

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ weak | No customer evidence; justified by the MVP gate needing a measurement and by separation of concerns (own story vs. folding into #15) |
| Smallest valuable version | ✅ | Objectives + provider-agnostic schema + collection contract + dashboard spec; tool stays a reference option |
| Alternatives | ✅ | PostHog is the leaning candidate, with alternatives compared and requirements stated; explicitly non-binding |
| Fit with Key Decisions | ✅ | Deliberately not an ADR yet; tool choice isn't decided. Revisit as an ADR once it is — tracked in Open questions |
| Data/schema | ⚠️ | One new service-role-only table (`analytics_identities`) with migration + RLS test in #15; no `template.schema.json` or MCP tool contract changes |
| Security/privacy | ✅ | Random `anon_id`, never `user_id`, leaves the system; server-side allowlist; 1-year retention; ordered deletion; opt-out narrowed to one legal question for #56 |
| Cost | ⚠️ deferred | Compared qualitatively (pros/cons, no figures, to avoid staleness); tool and real cost still undecided — see Open questions |
| Failure modes | ✅ | `track()` never throws or blocks; stated in Collection method → Reliability |
| Reversibility | ✅ | Two-way door; vendor sits behind one module, and `anon_id` stays valid if the vendor changes |
| Observability | ✅ | The typed allowlist rejects unknown events/properties; dropped events log a warning via #50 |
| Success metric | ✅ | Every dashboard tile renders from real events; time to editor checked by hand against `jobs` |
| Effort & ownership | ✅ | Each dependent story's owner adds their own events (Rollout table); no new dedicated role needed |

</details>
