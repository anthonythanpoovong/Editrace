# Product analytics plan (#51)

- **Status:** Planning — part of #51; no instrumentation code lands with this doc
- **Date:** 2026-10-05 (revised 2026-10-18 after review)
- **Author:** @calvinkafaiyuen
- **Related:** #15, #16, #18, #27, #37, #39, #50, #56, #64, #65, #66, #70, #72, #73, #75

What Editrace measures, the events that measure it, where they're stored, and the dashboard #51 needs. Analytics are built in-house on our Supabase Postgres, with no third-party vendor. Each flow adds its own events as it ships, against this contract.

## Metrics

| Metric | Definition | Target |
|---|---|---|
| **Time to editor** | Per job: `upload_completed` → first `template_exported` or `template_applied` for that `job_id` | Median < 10 min (MVP gate) |
| **Activation funnel** | Per user: signup → upload started → upload queued → breakdown viewed → exported or applied | — |
| **MCP adoption** | % of active users with at least one `mcp_client_connected` | — |
| **Applies per week per editor** | `template_applied` per ISO week, by `editor_type` | — |
| **Assistant thumbs-up rate** | Thumbs up ÷ all `assistant_feedback` | — |
| **Assistant citation rate** | `had_citation` ÷ all `assistant_answered` | — |

**Active user:** at least one event in the trailing 28 days (a starting definition).

**Out of scope:** the other `docs/plan.md` metrics don't come from product events. Editing time saved and editor satisfaction come from interviews (#20, #55), Format Match Score from the scoring pipeline (#26, #105), and the assistant's #39 scores from the eval harness.

**Why now:** the MVP gate can only be checked with these events, and they're cheapest to add while each flow is built. It's its own story so that #15 builds login, not the measurement plan. The schema is a starting contract; expect changes as the first flows land.

## Decision: build in-house

Events go in one table in our Supabase Postgres, and the dashboard is an admin page in the web app. No event data leaves our system.

**Why not a vendor** (PostHog, Amplitude, Mixpanel and GA4 were considered):
- **It saves little.** The key tile, time to editor, is measured per *job*, while vendor funnels measure per *person*, so it's custom SQL either way. Only the funnel and the charting come ready-made.
- **It adds a lot:** a pseudonymous ID and mapping table so the vendor never sees `user_id`, a vendor deletion step on every account deletion, a new data processor for #56, and eventually a bill.
- **In-house is simpler:** events stay inside our RLS boundary, account deletion is a cascade, and it costs $0.

**What we give up:** ready-made charts, which we build in the dashboard page, and point-and-click exploration. New questions mean writing SQL, which the team can run in Supabase Studio.

**One events table, not queries over product tables:** those tables don't exist yet and will change, and two events (`upload_started`, `breakdown_viewed`) have no product row at all. A dedicated table keeps the dashboard independent of other stories' schemas.

## Storage

`analytics_events`, created by #15's migration:

| Column | Type | Notes |
|---|---|---|
| `id` | `bigint` identity | Primary key |
| `user_id` | `uuid`, not null | → `auth.users`, `on delete cascade` |
| `event` | `text`, not null | `check` constraint on the event names below, so a new event needs a migration (deliberate) |
| `job_id` | Type of `jobs.id` (#16), nullable | Not a foreign key, so deleting a job doesn't rewrite past metrics |
| `properties` | `jsonb`, default `'{}'` | Only the allowlisted properties below |
| `occurred_at` | `timestamptz`, not null | Server time when the event happened, set by `track()` |

Indexes: `(event, occurred_at)` and `(job_id)` for the dashboard; `(user_id, occurred_at)` for the funnel and active users, which also keeps the deletion cascade fast.

**Access:**
- **Nobody reads or writes it from the browser.** RLS is on with no policies, and all privileges are revoked from `anon` and `authenticated`. With both, a policy added by mistake still can't expose the table.
- **Only server code writes**, through `track()` with the service-role client. That client lives in `server-only` modules, so importing it into browser code fails the build.
- **The dashboard reads** through SQL functions whose `execute` is revoked from `public`, `anon` and `authenticated` and granted only to `service_role`. Postgres grants `execute` to everyone by default, so the revoke is required.
- **Test:** the two-user access test checks that a signed-in user can't read or insert any row, including their own.

## Event schema

`track(event, properties)` lives in one module, e.g. `web/lib/analytics/` (created by #15). It adds `user_id` and `occurred_at` to every event; the table lists what call sites supply. Every event feeds a metric above.

| Event | Fires when | From | Properties |
|---|---|---|---|
| `signup_completed` | First time the auth callback sees a user | Server (#15) | `signup_method` |
| `upload_started` | A file is selected or dropped, before validation | Browser (#16) | — |
| `upload_completed` | The job is queued. **Starts the clock** | Server (#16) | `job_id`, `file_duration_s` |
| `breakdown_viewed` | The breakdown page first renders with data | Browser (#18) | `job_id` |
| `template_exported` | A signed export URL is issued. **Stops the clock** (download path) | Server (#64, #72) | `job_id`, `editor_type`, `via` |
| `mcp_client_connected` | First authenticated MCP call with a new OAuth grant (#70) or personal token (#37), remote or via the Bridge (#73) | Server | `client_kind`, `client_name` |
| `template_applied` | A real (not dry-run) Bridge apply finishes with at least one element applied. **Stops the clock** (Bridge path) | Server (#75) | `job_id`, `editor_type` |
| `assistant_answered` | The assistant returns an answer, in the web chat or via MCP | Server (#65) | `answer_id`, `had_citation` |
| `assistant_feedback` | Thumbs up or down on an answer | Browser (#66) | `answer_id`, `thumbs_up` |

**Every property value is a closed list or a typed value**, so no free text can be stored:

| Property | Values |
|---|---|
| `signup_method` | Whatever #15 ships, e.g. `email` \| `google` |
| `editor_type` | `capcut` \| `resolve` \| `premiere` \| `fcp` |
| `via` | `web` \| `mcp` |
| `client_kind` | `remote` \| `bridge` |
| `client_name` | `claude-desktop` \| `claude-code` \| `claude-ai` \| `cursor` \| `other`. The server maps the name from the MCP `initialize` handshake onto this list; the raw, client-controlled string is never stored |
| `file_duration_s` | Number |
| `had_citation`, `thumbs_up` | Boolean |
| `job_id`, `answer_id` | Opaque database IDs |

Notes:
- **The Bridge reports applies; it never writes events.** After a real apply, it sends a short summary (template ID, editor) to the Editrace API with its existing token, and the API emits `template_applied`. This adds one API call to #75, with no MCP tool contract change. If the Bridge is offline, the event is lost.
- **Repeat events are normal.** For example, a breakdown can be viewed many times. Queries use the first occurrence where that's what the metric means.
- **Citations are counted per answer.** Reading them off feedback would only cover rated answers.

### Time to editor

Computed at query time from server timestamps. No event carries a duration.

- **Start and end:** for each `job_id`, the time from `upload_completed` to the earliest `template_exported` or `template_applied`. All three are emitted server-side, so there's no client clock involved.
- **Week:** a job counts in the week of its `upload_completed`.
- **Median and p90:** over jobs that reached the editor.
- **"% under 10 min":** over *all* queued jobs. A job that never reached the editor counts as over, so abandoned jobs can't flatter the number. The current week reads slightly low until it's over.
- **`breakdown_viewed − upload_completed`** is an upper bound on processing time. It's diagnostic only.

```sql
with queued as (
  select job_id, occurred_at as queued_at
  from analytics_events where event = 'upload_completed'
), reached as (
  select job_id, min(occurred_at) as reached_at
  from analytics_events where event in ('template_exported', 'template_applied')
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

## Collection method

Every event is written by our server. Server events call `track()` where the action happens, including in the remote MCP server (#27).

Browser events go to `POST /api/track`, which:
1. requires a signed-in session, and takes `user_id` from it, never from the request body;
2. accepts only the three browser events (`upload_started`, `breakdown_viewed`, `assistant_feedback`), so server-side events like `upload_completed` can't be forged;
3. checks every property against the allowlist, and that any `job_id` or `answer_id` belongs to the user;
4. applies a per-user rate limit (#50);
5. stamps `occurred_at` and calls `track()`.

Anything that fails a check is dropped.

### Reliability

**`track()` must never break the feature it instruments:**
- **It never throws.** Errors are logged as a warning via #50 (event name and error only), and the event is dropped.
- **It never blocks a response.** Server code writes after the response, e.g. with Next's `after()`, keeping the `occurred_at` captured at call time. The browser posts with `fetch(..., { keepalive: true })` and ignores the result.
- **Short timeout, no retries in v1.** A lost event is acceptable; a slower upload isn't.
- **It's a no-op when analytics is disabled**, e.g. in unit tests or without the service-role key.

## Privacy

- **Never in an event:** email, name or other profile fields; filenames, source URLs or template titles; transcripts, frames, video or audio; assistant questions, answers or any other free text; IP address or user agent. The allowlist enforces this.
- **Still personal data:** events are linked to `user_id`, so they're personal data under GDPR, like the rest of the database. No new processor is involved, but #56's privacy policy should mention product analytics.
- **Retention:** 1 year. A daily scheduled job deletes older rows, using `pg_cron` or #56's retention job.
- **Account deletion:** `on delete cascade` removes all of a user's events. Backups keep them until the backups expire, as for every table.
- **Contract impact:** this adds the `analytics_events` table, `/api/track`, the Bridge's apply-report call, and the dashboard functions and page. `template.schema.json`, existing tables and policies, and MCP tool contracts are unchanged.

## Dashboard

An admin-only page in the web app, e.g. `/admin/metrics`, built by #51:
- **Data:** one SQL function per tile, e.g. `analytics_time_to_editor()`, with the grants in [Storage](#storage). Each one can also be run on its own in Supabase Studio.
- **Page:** a server component. It checks the user is an admin, calls the functions with the service-role client, and sends only the chart values to the browser.
- **Admins:** users with `role: "admin"` in Supabase `app_metadata`, which users can't edit themselves. Everyone else gets a 404.
- **Charts:** use a library chosen during implementation. Each tile also shows its numbers as a table.

| Tile | Shows |
|---|---|
| Time to editor | Weekly median, p90 and % under 10 min, split by download vs Bridge path |
| Activation funnel | Conversion at each step, within 7 days of signup |
| MCP adoption | % of active users who have connected a client, by `client_kind` |
| Applies per week per editor | Weekly count, stacked by `editor_type` |
| Assistant quality | Weekly thumbs-up rate and citation rate |

**#51 is done when:**
- every tile renders from real staging or production events;
- time to editor has been checked by hand against `jobs` for at least 3 jobs; and
- a non-admin gets a 404 and the browser can't call the dashboard functions.

## If we outgrow this

Add a vendor (e.g. PostHog) when the fixed tiles can't answer the team's questions, or event writes start to load the production database. Only `track()` knows where events go, so this is a two-way door:
- **Identity:** the vendor gets a random `analytics_id` from a service-role-only mapping table, never `user_id`. Because it's random, it can't be recomputed after deletion.
- **Collection and history:** `track()` forwards events to the vendor's server API, and past rows are backfilled under each user's `analytics_id`.
- **Deletion:** account deletion gains a vendor-side delete, done before the user row is removed.
- **Decision record:** it needs an ADR, because it adds a data processor holding personal data.

## Rollout

| Story | Adds |
|---|---|
| #15 (auth) | `analytics_events` migration and RLS test, `track()`, `/api/track`, `signup_completed` |
| #16 (upload) | `upload_started`, `upload_completed` |
| #18 (breakdown page) | `breakdown_viewed` |
| #64 (export), #72 (`export_template`) | `template_exported` |
| #70 (OAuth), #37 (tokens), #73 (Bridge auth) | `mcp_client_connected` |
| #75 (Bridge tools) | The apply-report call, which emits `template_applied` |
| #65 (assistant backend), #66 (chat panel) | `assistant_answered`, `assistant_feedback` |
| #56 (privacy) | Analytics in the privacy policy; the retention job, if shared |
| #51 (this story) | The admin page, the admin check and the tile functions, each tile built as its events start flowing |

## Open questions

| Question | Owner |
|---|---|
| Reconcile the exclusion list in [Privacy](#privacy) with #56 | #56 |
| Is opt-out legally required? If so, `track()` drops events for opted-out users | #56 |
| `template_exported` means a URL was issued, not that the template was opened. Revisit when the Bridge's `open_export` (#75) can report a real open | #64 |
| MCP adoption counts users who *ever* connected. #37's token "last used" time could tighten it later | #37 |
| Thumbs up or down says *whether* an answer was good, not *why*. Consider a fixed list of reasons on thumbs-down | Assistant quality review (#39) |

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ weak | No customer evidence; justified by the MVP gate needing a measurement |
| Smallest valuable version | ✅ | One table, a typed `track()`, an admin page with five tiles |
| Alternatives | ✅ | Vendors considered; custom SQL is needed either way, and a vendor adds identity, deletion and processor work |
| Fit with Key Decisions | ✅ | Existing stack, $0; an ADR only if a vendor is added |
| Data/schema | ⚠️ | One new table (#15) and service-role-only functions (#51); no template schema or MCP contract changes |
| Security/privacy | ✅ | Nothing leaves our system; no browser access; allowlist; 1-year retention; cascade deletion |
| Cost | ✅ | $0 |
| Failure modes | ✅ | `track()` never throws or blocks |
| Reversibility | ✅ | Two-way door via `track()` |
| Observability | ✅ | Allowlist rejects bad events; drops log a warning via #50 |
| Success metric | ✅ | Tiles render from real events; time to editor checked by hand |
| Effort & ownership | ✅ | Each story adds its own events (see Rollout) |

</details>
