# Product analytics plan (#51)

- **Status:** Planning — part of #51; no instrumentation code lands with this doc
- **Date:** 2026-10-05 (revised 2026-10-18 after review)
- **Author:** @calvinkafaiyuen
- **Related:** #15, #16, #18, #27, #32, #37, #39, #50, #56, #64, #65, #66, #70, #72, #73, #75

This doc fixes what Editrace measures, the events that measure it, where they're stored, and the dashboard that closes #51. Analytics are built in-house on our own Supabase Postgres, with no third-party analytics vendor. Each flow (auth, upload, breakdown, export, MCP, assistant) adds its own events as it ships, against the contract below, instead of analytics being bolted on afterwards.

## Objective

#51 scopes in the product-usage metrics from `docs/plan.md`'s Metrics section, plus the activation funnel. Each one must be answerable from real events, without guessing:

| Metric | Definition | Target |
|---|---|---|
| **Time to editor** | Per job: from `upload_completed` to the first `template_exported` or `template_applied` for the same `job_id` (see [Time to editor](#time-to-editor)) | Median < 10 min (MVP gate) |
| **Activation funnel** | Per user: signup → upload started → upload queued → breakdown viewed → exported or applied | Tracked, no target yet |
| **MCP adoption** | % of active users with at least one `mcp_client_connected` | Tracked, no target yet |
| **Applies per week per editor** | Count of `template_applied` per ISO week, split by `editor_type` | Tracked, no target yet |
| **Assistant thumbs-up rate** | `assistant_feedback` with `thumbs_up = true` ÷ all `assistant_feedback` | Tracked, no target yet |
| **Assistant citation rate** | `assistant_answered` with `had_citation = true` ÷ all `assistant_answered` | Tracked, no target yet |

**Active user:** a user with at least one event in the trailing 28 days. This is a starting definition, to revisit once real usage shows a natural cadence.

**Out of scope.** The other metrics in `docs/plan.md` don't come from product events:
- Editing time saved and editor satisfaction come from interviews and design partners (#20, #55).
- Format Match Score and footage match lift come from the scoring pipeline (#26, #105).
- The assistant's #39 scores come from the offline eval harness.

## Rationale

No launch gate is blocked on this doc. But the MVP gate (time to editor < 10 min) can only be checked with these events, and they're cheapest to add while each flow is being built. There's no customer-interview evidence to cite yet.

This is its own story rather than part of whichever flow touches the UI first. #15 (auth) is scoped to *implementing* registration and login, not to deciding how the whole product is measured. Keeping "what do we track and why" separate from "build the login form" keeps each story's owner focused on one concern.

The schema is a starting contract, not a frozen spec. Expect it to change as #15, #16 and #18 land and show what's actually easy to instrument.

`web/` is scaffolded (Next.js) but has no product flows yet. Auth (#15), upload (#16), the breakdown page (#18), export (#64), the remote MCP server (#27, #70) and the Bridge (#32, #73, #75) are all still open. The dashboard can't show real numbers until they land.

## Decision: build in-house, no analytics vendor

Events are stored in a table in our own Supabase Postgres. The dashboard is an admin-only page in the web app, backed by SQL functions over that table. No event data leaves our system.

**Why not a vendor.** PostHog was the leaning candidate, with Amplitude, Mixpanel and GA4 also considered. For the dashboard #51 needs, a vendor saves little work and adds a lot:
- **The hardest tile is custom SQL either way.** Vendors' built-in funnels measure time per *person*, but time to editor is measured per *job*. Only the funnel and the charting itself come ready-made.
- **A vendor adds:**
  - a pseudonymous ID with a mapping table, so the vendor never sees `user_id`;
  - a vendor-side deletion step on every account deletion;
  - a new data processor for the privacy policy and contracts (#56);
  - another account, set of keys, and eventually a bill.
- **In-house gets most of that for free.** Events sit inside the existing RLS boundary, account deletion is a cascade, and it costs $0, in line with the plan's "$0 until revenue" constraint.

**What we give up:**
- **Ready-made charts.** We build the five charts ourselves, in the dashboard page.
- **Point-and-click exploration**, such as ad-hoc funnels, cohorts and retention charts. Asking a new question means writing SQL, which the team can run in Supabase Studio.

That's acceptable while #51 needs fixed metrics. [If we outgrow this](#if-we-outgrow-this) covers the way out.

**Why one events table, not queries over product tables.** Some metrics could be read from the tables each flow writes anyway (`jobs`, the export audit log, tokens). But those tables don't exist yet and will keep changing, and two of the events (`upload_started`, `breakdown_viewed`) have no product row at all. One events table keeps the dashboard independent of other stories' schemas, and keeps the whole contract in this doc.

## Storage

All events go in one table, created by #15's migration via the `db-migration` skill:

| Column | Type | Notes |
|---|---|---|
| `id` | `bigint`, generated identity | Primary key |
| `user_id` | `uuid`, not null | References `auth.users` with `on delete cascade` |
| `event` | `text`, not null | A `check` constraint limits it to the event names below, so adding an event means a migration. That's deliberate: the event list can't grow without review |
| `job_id` | Same type as `jobs.id` (#16), nullable | Set on job-related events. Deliberately not a foreign key, so deleting a job doesn't rewrite past metrics. Account deletion still removes the rows, through `user_id` |
| `properties` | `jsonb`, not null, default `'{}'` | The other properties in the Event schema table |
| `occurred_at` | `timestamptz`, not null | Server time when the event happened, set by `track()` (see [Time to editor](#time-to-editor)) |

Indexes:
- `(event, occurred_at)` and `(job_id)` serve the dashboard queries.
- `(user_id, occurred_at)` serves the funnel and active-user queries. It also keeps account deletion fast, since the cascade finds a user's rows through it rather than scanning the table.

**Only what the metrics need is stored.** Each event is one small row: an event name, the user, an optional job, a few closed-value properties and a timestamp. There's no content, no free text, and nothing kept beyond the 1-year retention. A row with no metric to feed doesn't get an event.

**Access:**
- **RLS is enabled with no policies**, and `anon` and `authenticated` have all privileges revoked:

  ```sql
  revoke all on public.analytics_events from anon, authenticated;
  ```

  Either one alone would block the browser. Both together mean a mistaken policy added later still can't expose the table.
- **Only server code writes to it**, through `track()`, using the service role. The service-role client is imported only from server-only modules (`import 'server-only'`), so a client-side import fails the build rather than leaking the key.
- **Users can't read it**, not even their own rows.
- **The dashboard reads it** through one SQL function per tile (see [Dashboard](#dashboard)). Postgres lets everyone (`PUBLIC`) execute new functions by default, so each one has `execute` revoked from `public`, `anon` and `authenticated` and granted only to `service_role`. The browser can't call them.
- **Test:** the migration's two-user access test checks that a signed-in user gets zero rows and can't insert, including for their own `user_id`.

## Event schema

One shared module, e.g. `web/lib/analytics/`, exports a typed `track(event, properties)`. It's created by #15. Every event automatically carries `user_id` and `occurred_at`, added by `track()`. The table lists only the properties each call site supplies.

Every event feeds a metric in the [Objective](#objective) table. Nothing is tracked "just in case."

| Event | Fires when | Sent from | Properties | Feeds |
|---|---|---|---|---|
| `signup_completed` | Once per user, the first time the auth callback sees them | Server: auth callback (#15) | `signup_method` | Funnel entry |
| `upload_started` | The user selects or drops a file, before validation | Browser: upload page (#16) | none | Funnel: drop-off before a job is queued (bad file, rejected, abandoned) |
| `upload_completed` | The job is inserted and queued | Server: job-queue route (#16) | `job_id`, `file_duration_s` | **Starts the time-to-editor clock.** `file_duration_s` lets the tile split long and short videos |
| `breakdown_viewed` | The breakdown page first renders with data | Browser: breakdown page (#18) | `job_id` | Funnel step; separates processing time from time the user spends acting |
| `template_exported` | The server issues a signed export URL | Server: export route (#64) or the `export_template` MCP tool (#72) | `job_id`, `editor_type`, `via` | **Stops the clock, download path** (a proxy, see [Open questions](#open-questions)) |
| `mcp_client_connected` | The first authenticated MCP call with a new OAuth grant (#70) or personal token (#37), on the remote server or through the Bridge (#73) | Server | `client_kind`, `client_name` | MCP adoption |
| `template_applied` | A real (not dry-run) Bridge `apply_template` finishes with at least one element applied, and the Bridge reports it | Server: the Bridge's apply-report call (#75) | `job_id`, `editor_type` | Applies per week per editor. **Stops the clock, Bridge path** |
| `assistant_answered` | The assistant returns an answer, in the web chat or through MCP | Server: assistant backend (#65) | `answer_id`, `had_citation` | Citation rate |
| `assistant_feedback` | The user gives a thumbs up or down on an answer | Browser: chat panel (#66) | `answer_id`, `thumbs_up` | Thumbs-up rate |

**Property values** are closed lists, so the allowlist can check them:

| Property | Values |
|---|---|
| `signup_method` | `email` \| `google` \| …, whatever #15 ships |
| `editor_type` | `capcut` \| `resolve` \| `premiere` \| `fcp` |
| `via` | `web` \| `mcp` |
| `client_kind` | `remote` \| `bridge` |
| `client_name` | `claude-desktop` \| `claude-code` \| `claude-ai` \| `cursor` \| `other`. The server maps the client's self-reported name from the MCP `initialize` handshake onto this list, and stores anything it doesn't recognise, or a missing name, as `other`. The raw string is never stored, because the client controls it. Add a value when a new client shows up often enough to matter |
| `file_duration_s` | Number |
| `had_citation`, `thumbs_up` | Boolean |
| `answer_id` | The answer's ID from #65 |

**The Bridge reports applies; it doesn't write events itself.** The Bridge runs on the user's machine and has no database access. After a successful apply, it sends a short summary (template ID, editor) to the Editrace API with the token it already uses. The API looks up the template's `job_id` and calls `track()`. This adds one small API call to #75's scope. It doesn't change any MCP tool's inputs or outputs. If the Bridge is offline when an apply finishes, that event is lost, which [Reliability](#reliability) accepts.

**Repeat events are expected.** A user can start several uploads or open a breakdown many times, and each one is a row. Queries use the first occurrence per user or per job where that's what the metric means, as in the funnel and time to editor.

**Citations are counted per answer, not per rating.** Only some answers get rated, so reading `had_citation` off feedback events would measure the citation rate of rated answers only.

### Time to editor

Time to editor is computed at query time from server timestamps. No event carries an elapsed-time property. For each `job_id`:

```
reached_editor_at = earliest occurred_at of template_exported or template_applied for this job_id
time_to_editor    = reached_editor_at − occurred_at of upload_completed
```

- **Timestamps:** `occurred_at` is the server time when `track()` was called, or when `/api/track` received a browser event. It's never a client clock, and it's set at call time rather than insert time, because the insert happens after the response (see [Reliability](#reliability)). The start and both end events are emitted server-side, so there's no client/server clock skew to reconcile.
- **Which week a job counts in:** the week of its `upload_completed`.
- **Median and p90** are taken over jobs that reached the editor.
- **"% under 10 min"** is taken over *all* queued jobs. A job that never reached the editor counts as over 10 minutes, so abandoned jobs can't make the number look better. Jobs queued in the last 10 minutes haven't had their chance yet, so the current week reads slightly low until it's over.
- **`breakdown_viewed` is diagnostic only.** `breakdown_viewed − upload_completed` is an upper bound on processing time. It's exact only if the user waited on the page.

A sketch of the weekly query:

```sql
with queued as (
  select job_id, occurred_at as queued_at
  from analytics_events
  where event = 'upload_completed'
), reached as (
  select job_id, min(occurred_at) as reached_at
  from analytics_events
  where event in ('template_exported', 'template_applied')
  group by job_id
)
select
  date_trunc('week', q.queued_at) as week,
  count(*) as jobs_queued,
  percentile_cont(0.5) within group (order by r.reached_at - q.queued_at) as median,
  percentile_cont(0.9) within group (order by r.reached_at - q.queued_at) as p90,
  avg(case when r.reached_at - q.queued_at <= interval '10 minutes' then 1 else 0 end) as share_under_10_min
from queued q
left join reached r using (job_id)
group by 1
order by 1;
```

Jobs that never reached the editor have a null duration. The percentiles skip them, and the share counts them as over 10 minutes.

## Collection method

Every event is written by **our server**. The browser and the Bridge never write to the table directly.

**Browser events** (`upload_started`, `breakdown_viewed`, `assistant_feedback`) go to a thin first-party route, e.g. `POST /api/track`. The route:
1. requires a signed-in Supabase session, and drops the event otherwise;
2. accepts only the three browser events, and drops everything else. Server-only events such as `upload_completed` or `template_exported` are never accepted here, so nobody can forge the events time to editor depends on;
3. checks every property against the typed allowlist, and drops the event if anything doesn't match;
4. checks that any `job_id` or `answer_id` in the body belongs to the signed-in user, so nobody can attach events to someone else's job;
5. applies a per-user rate limit (#50), so one client can't flood the metrics;
6. takes `user_id` from the session, never from the request body, so a user can only ever record events as themselves;
7. stamps `occurred_at` and passes the event to `track()`.

**Server events** (all the others) call `track()` directly from the route or service where the action happens, including the remote MCP server (#27).

### Reliability

**`track()` must never break the feature it instruments.** This is a hard requirement on every implementation:
- **It never throws.** Errors are caught, logged as a warning through #50's logging (event name and error only), and the event is dropped.
- **It never blocks a response.** Server code writes events after the response, e.g. with Next's `after()`, using the `occurred_at` captured at call time. The browser posts to `/api/track` with `fetch(..., { keepalive: true })` and ignores the result.
- **It has a short timeout and no retries in v1.** Losing an occasional event is acceptable. Slowing down an upload or an export is not.
- **It can be switched off.** With analytics disabled by an environment flag (unit tests, and any environment without the service-role key), it's a no-op, so tests never depend on the table.

## Privacy & data

- **Never in any event:**
  - email, name, or any other account profile field;
  - filenames, source video URLs, or template titles;
  - transcripts, frames, or any video or audio content;
  - assistant questions, answers, or any other free text;
  - IP address or user agent.

  The typed allowlist and the closed `properties` values are what enforce this. There's no column a free-text value could land in by accident.
- **Still personal data.** Events are linked to `user_id`, so under GDPR this is personal data, handled like the rest of the database. It never leaves our Supabase project, so no new data processor is involved. #56's privacy policy should still say that we measure product usage.
- **What changes in the system:**
  - **New:** the `analytics_events` table (migration and RLS test with #15), the `/api/track` route (#15), the Bridge's apply-report call to the API (#75), and the dashboard's SQL functions and admin page (#51).
  - **Unchanged:** `template.schema.json`, existing tables and RLS policies, and every MCP tool's inputs and outputs.
- **Retention:** events are kept for 1 year, which is long enough to compare cohorts across a year. A daily scheduled job deletes older rows, using `pg_cron` or #56's retention job.
- **Account deletion:** deleting the user removes all their events through `on delete cascade`. There's no separate step, and nothing outside our database to clean up. Database backups keep deleted rows until the backups expire, like every other table. #56's policy should say so.

## Dashboard

#51's acceptance criterion is "a dashboard with the metrics from `docs/plan.md`". It's an admin-only page in the web app, e.g. `/admin/metrics`, built by #51.

**How it works:**
- **One SQL function per tile**, e.g. `analytics_time_to_editor()`, each returning the rows its chart needs. They ship in #51's migration, with the grants described in [Storage](#storage). Keeping the SQL in Postgres means each tile can be tested and run on its own, including from Supabase Studio.
- **The page is a server component.** It checks that the signed-in user is an admin, calls the functions with the service-role client, and renders the charts. No analytics data or query reaches the browser except the chart values.
- **Who counts as an admin:** users with `role: "admin"` in their Supabase `app_metadata`. Users can't edit `app_metadata` themselves; only the service role can set it.
- **Everyone else gets a 404**, so the page's existence isn't advertised. A test covers both cases: a non-admin gets a 404, and an admin sees data.
- **Charts** use a charting library chosen during implementation. Each tile also shows its numbers as a table, so the values can be checked without reading the chart.

**Tiles:**

| Tile | Shows | Built from |
|---|---|---|
| Time to editor | Weekly median and p90; % of queued jobs that reached the editor within 10 min; download vs Bridge path | `upload_completed`, `template_exported`, `template_applied`, paired by `job_id` (query sketch above) |
| Activation funnel | Conversion at each step, within 7 days of signup | `signup_completed` → `upload_started` → `upload_completed` → `breakdown_viewed` → `template_exported` or `template_applied`, per `user_id` |
| MCP adoption | % of 28-day active users who have connected a client, split by `client_kind` | `mcp_client_connected` ÷ active users |
| Applies per week per editor | Weekly count, stacked by `editor_type` | `template_applied` |
| Assistant quality | Weekly thumbs-up rate and citation rate | `assistant_feedback`, `assistant_answered` |

**#51 is done when:**
- every tile on the admin page renders from real staging or production events, not seeded data;
- the time-to-editor figures for at least 3 jobs have been checked by hand against their `jobs` rows; and
- the access test passes: a non-admin gets a 404, and the browser can't call the dashboard functions.

This PR doesn't close #51; the issue stays open until the dashboard meets that bar.

## If we outgrow this

Move to a vendor such as PostHog when the team regularly needs questions the fixed tiles can't answer, when writing SQL for each question becomes the bottleneck, or when event writes start to show up in the production database's load. It's a two-way door, because `track()` is the only code that knows where events go:
1. **Identity:** add an `analytics_id`, a random UUID per user in a service-role-only mapping table. The vendor gets `analytics_id`, never `user_id`. It's random rather than a hash of `user_id`, so nobody can recompute it, and deleting the mapping row cuts the link for good.
2. **Collection:** `track()` forwards each event to the vendor's server-side API, in addition to (or instead of) the table. `/api/track` keeps the vendor key and SDK out of the browser and the Bridge.
3. **Deletion:** account deletion gains a vendor-side step: read the `analytics_id`, ask the vendor to delete its events, then delete the user.
4. **History:** past events in `analytics_events` can be backfilled to the vendor under each user's `analytics_id`.

Choosing a vendor adds a new data processor holding personal data, so it should get an ADR.

## Rollout

Each story below adds its own `track()` calls against this contract when it ships. This doc changes none of their code:

| Story | Adds |
|---|---|
| #15 (auth) | The `analytics_events` migration with its RLS test; the `track()` module; `/api/track`; `signup_completed` |
| #16 (upload flow) | `upload_started`, `upload_completed` |
| #18 (breakdown page) | `breakdown_viewed` |
| #64 (export buttons), #72 (`export_template`) | `template_exported` |
| #70 (MCP OAuth), #37 (personal tokens), #73 (Bridge token auth) | `mcp_client_connected` |
| #75 (Bridge tools) | The apply-report call to the API, which emits `template_applied` |
| #65 (assistant backend), #66 (chat panel) | `assistant_answered`, `assistant_feedback` |
| #56 (privacy and retention) | Product analytics in the privacy policy; the 1-year retention job, if it's shared |
| #51 (this story) | The admin `/admin/metrics` page, the admin check, and one SQL function per tile, each tile built as its events start flowing |

## Open questions

| Open question | Owner |
|---|---|
| The exclusion list in [Privacy & data](#privacy--data) needs reconciling with #56, which also defines what we record | Whoever picks up #56 |
| Is opt-out legally required for product analytics (e.g. under GDPR)? If so, `track()` checks a per-user flag and drops that user's events | Whoever picks up #56 |
| `template_exported` records an export URL being issued, not the template being opened in an editor | Whoever picks up #64; revisit once the Bridge's `open_export` (#75) could report a real open |
| MCP adoption counts users who have *ever* connected, which overstates adoption as users churn. #37's token "last used" time could tighten it once there are enough users for the difference to matter | Whoever picks up #37 |
| A thumbs up or down shows *whether* an answer was good, not *why*. A fixed list of reasons on thumbs-down (not free text) could be added once usage shows what goes wrong | Whoever reviews assistant quality against #39's scores |

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ weak | No customer evidence; justified by the MVP gate needing a measurement and by separation of concerns (own story vs. folding into #15) |
| Smallest valuable version | ✅ | One events table, a typed `track()`, and an admin page with five tiles; no vendor |
| Alternatives | ✅ | PostHog, Amplitude, Mixpanel and GA4 considered; rejected for now because the hardest tile is custom SQL either way, and a vendor adds identity mapping, deletion and processor work |
| Fit with Key Decisions | ✅ | Uses the existing stack (Supabase, Next.js) and the $0-until-revenue constraint; no ADR needed unless a vendor is added later |
| Data/schema | ⚠️ | One new table (`analytics_events`), with migration and RLS test in #15, plus service-role-only dashboard functions in #51; no `template.schema.json` or MCP tool contract changes |
| Security/privacy | ✅ | No data leaves our system; RLS with no policies plus revoked grants; server-side allowlist; 1-year retention; deletion by cascade |
| Cost | ✅ | $0; one small table in the existing database |
| Failure modes | ✅ | `track()` never throws or blocks, and dropped events are acceptable; see Reliability |
| Reversibility | ✅ | Two-way door: `track()` is the only code that knows where events go; see If we outgrow this |
| Observability | ✅ | The allowlist rejects unknown events and properties; dropped events log a warning via #50 |
| Success metric | ✅ | Every dashboard tile renders from real events, and time to editor is checked by hand against `jobs` |
| Effort & ownership | ✅ | Each dependent story's owner adds their own events (see Rollout); no new dedicated role needed |

</details>
