# Product analytics plan (#51)

- **Status:** Planning — part of #51; no instrumentation code lands with this doc
- **Date:** 2026-10-05 (revised 2026-10-18 after review)
- **Author:** @calvinkafaiyuen
- **Related:** #15, #16, #18, #27, #32, #37, #39, #50, #56, #64, #65, #66, #70, #72, #73, #75

This doc fixes what Editrace measures, the events that measure it, how a user is identified without exposing who they are, and the dashboard that closes #51. Each flow (auth, upload, breakdown, export, MCP, assistant) adds its own events as it ships, against the contract below, instead of analytics being bolted on afterwards.

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

This is its own story rather than part of whichever flow touches the UI first. #15 (auth) is scoped to *implementing* registration and login, not to choosing an analytics vendor and an event schema for the whole product. Keeping "what do we track and why" separate from "build the login form" keeps each story's owner focused on one concern.

The schema is a starting contract, not a frozen spec. Expect it to change as #15, #16 and #18 land and show what's actually easy to instrument.

`web/` is scaffolded (Next.js) but has no product flows yet. Auth (#15), upload (#16), the breakdown page (#18), export (#64), the remote MCP server (#27, #70) and the Bridge (#32, #73, #75) are all still open. The dashboard can't show real numbers until they land.

## Tool choice

The tool choice is deferred on purpose: picking a vendor before any code needs one gains nothing. Whoever wires in the first event (#15), or a dedicated decision before then, makes the call from these candidates:

| Tool | Pros | Cons |
|---|---|---|
| **PostHog** | Self-hostable, keeping data off third-party infra; funnels/retention built in; SQL over raw events; generous free tier | Usage-based pricing beyond the free tier, so cost grows continuously rather than in fixed steps |
| **Amplitude** | Largest free tier of the four vendors | No self-host option |
| **Mixpanel** | Simple free/paid split | Smallest free tier of the four vendors; no self-host option; pricing model changed recently |
| **GA4** | Free, with no event cap on the standard tier | Built for marketing traffic, not product funnels; the paid tier is enterprise-priced and irrelevant here |
| **Build on Supabase** | No new vendor or bill; data stays inside the RLS boundary | Rebuilds the query and charting layer the vendors already provide |

Exact limits and prices aren't quoted: vendor pricing changes, and a number here would go stale with no way to notice. At Editrace's expected early-stage volume, every candidate's free tier should cover usage without payment.

**Leaning candidate: PostHog**, for the self-host option, SQL over raw events (which the per-job time-to-editor query needs), and free-tier headroom at MVP scale.

**The chosen tool must:**
1. **Accept events from a server.** All events are sent from our backend (see [Collection method](#collection-method)), so a browser-only SDK isn't enough.
2. **Accept an explicit event timestamp.** Events are sent after the response (see [Reliability](#reliability)), so the time the vendor receives an event isn't the time it happened.
3. **Pair events by a property.** Time to editor pairs two events by `job_id`, not by user. If the tool can't compute the time between them, that one tile falls back to a saved Supabase query.
4. **Delete all events for one ID**, for account deletion.
5. **Let us turn off IP and geo enrichment.** Events come from our server, so any geo lookup would describe the server, not the user.

Whichever tool is picked sits behind the `track()` module, so switching later changes one module, not every call site.

## Identity

Every event is keyed by an **`anon_id`**, never the Supabase auth `user_id`. The analytics vendor only ever sees `anon_id`.

- **What it is:** a random UUID, generated once per user. It isn't derived from `user_id` (no hash or HMAC), so nobody can recompute it from a `user_id`, even with server access.
- **Where it lives:** in a new table, `analytics_identities`:
  - `user_id`: primary key, referencing `auth.users` with `on delete cascade`
  - `anon_id`: `uuid`, unique, `default gen_random_uuid()`
  - `created_at`

  A user's row is created the first time one of their events is tracked.
- **Who can read it:** RLS is enabled with **no** policies for `anon` or `authenticated`, so only the service role (our server code) can read or write it. The migration and its two-user access test land with #15, via the `db-migration` skill.
- **How the browser gets it:** it doesn't need to. The browser sends events to our own endpoint, and the server looks up `anon_id` from the signed-in session.
- **What this protects:** the browser already holds the user's Supabase session, so hiding `user_id` from the browser isn't the goal. The goal is that **nothing outside our server and database can link an `anon_id` to a `user_id`.**
- **Going back from `anon_id` to a user:** a service-role lookup in `analytics_identities`. It's used for account deletion and support, never for dashboards, which only ever count `anon_id`s.

## Event schema

One shared module, e.g. `web/lib/analytics/`, exports a typed `track(event, properties)`. It's created by #15. Only this module imports the vendor SDK. Every event automatically carries `anon_id` and a server timestamp, added by `track()`; the table lists only the properties each call site supplies.

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
| `client_name` | The MCP client's self-reported name from the `initialize` handshake (e.g. `claude-ai`), or `unknown` |
| `file_duration_s` | Number |
| `had_citation`, `thumbs_up` | Boolean |

**`job_id` and `answer_id` are opaque database IDs.** They carry no personal data on their own. They exist so that two events can be paired.

**The Bridge reports applies but never tracks them itself.** The Bridge runs on the user's machine, so it must not hold a vendor key. After a successful apply, it sends a short summary (template ID, editor) to the Editrace API with the token it already uses. The API looks up the template's `job_id` and calls `track()`. This adds one small API call to #75's scope. It doesn't change any MCP tool's inputs or outputs. If the Bridge is offline when an apply finishes, that event is lost, which [Reliability](#reliability) accepts.

**Citations are counted per answer, not per rating.** Only some answers get rated, so reading `had_citation` off feedback events would measure the citation rate of rated answers only.

### Time to editor

Time to editor is computed at query time from server timestamps. No event carries an elapsed-time property. For each `job_id`:

```
reached_editor_at = earliest ts of template_exported or template_applied for this job_id
time_to_editor    = reached_editor_at − ts of upload_completed
```

- **Timestamps:** `ts` is the server time when `track()` was called, or when `/api/track` received a browser event. It's never a client clock. Both end events and the start event are emitted server-side, so there's no client/server clock skew to reconcile.
- **Which week a job counts in:** the week of its `upload_completed`.
- **Median and p90** are taken over jobs that reached the editor.
- **"% under 10 min"** is taken over *all* queued jobs. A job that never reached the editor counts as over 10 minutes, so abandoned jobs can't make the number look better.
- **`breakdown_viewed` is diagnostic only.** `breakdown_viewed − upload_completed` is an upper bound on processing time. It's exact only if the user waited on the page.

Adding a duration property to the end events would duplicate what the timestamps already give, and a client-reported duration would be less trustworthy.

## Collection method

Every event reaches the vendor from **our server**, never directly from the browser or the Bridge.

**Browser events** (`upload_started`, `breakdown_viewed`, `assistant_feedback`) go to a thin first-party route, e.g. `POST /api/track`. The route:
1. requires a signed-in Supabase session, and drops the event otherwise;
2. checks the event name and every property against the typed allowlist, and drops anything that doesn't match;
3. applies a per-user rate limit (#50), so one client can't flood the metrics;
4. looks up (or creates) the user's `anon_id`;
5. stamps the server timestamp and passes the event to `track()`.

**Server events** (all the others) call `track()` directly from the route or service where the action happens, including the remote MCP server (#27).

Sending everything through the server means:
- **One clock.** Every timestamp comes from the server.
- **No vendor key or SDK in the browser or the Bridge.**
- **One place translates `user_id` to `anon_id`.**
- **The allowlist is enforced at one choke point**, so no PII can creep in when someone adds a property.
- **The vendor never receives the user's IP address or user agent**, because the request to the vendor comes from our server.

The cost is losing vendor autocapture and session replay. We don't want those anyway, because they would record content the [Privacy](#privacy--data) section excludes.

### Reliability

**`track()` must never break the feature it instruments.** This is a hard requirement on every implementation:
- **It never throws.** Errors are caught, logged as a warning through #50's logging, and the event is dropped.
- **It never blocks a response.** Server code sends events after the response, e.g. with Next's `after()`, passing the timestamp captured at call time. The browser posts to `/api/track` with `fetch(..., { keepalive: true })` and ignores the result.
- **It has a short timeout and no retries in v1.** Losing an occasional event is acceptable. Slowing down an upload or an export is not.
- **It's a no-op when no vendor key is configured**, as in local dev, CI and preview builds.

## Privacy & data

- **Never in any event:**
  - email, name, or any other account profile field;
  - filenames, source video URLs, or template titles;
  - transcripts, frames, or any video or audio content;
  - assistant questions, answers, or any other free text;
  - IP address or user agent (the collection method keeps these away from the vendor).
- **Pseudonymous is still personal data.** Under GDPR, `anon_id` is pseudonymous rather than anonymous, because we hold the mapping. That's why deletion and opt-out are handled like any other personal data, and why #56's privacy policy must cover analytics.
- **What changes in the system:**
  - **New:** the `analytics_identities` table (service-role only, migration and RLS test with #15), the `/api/track` route (#15), and the Bridge's apply-report call to the API (#75).
  - **Unchanged:** `template.schema.json`, existing tables and RLS policies, and every MCP tool's inputs and outputs.
- **Retention:** events are kept for 1 year, which matches PostHog's free-tier default. If another tool is chosen, it must be configured to match, since not every vendor defaults to 1 year. An `analytics_identities` row lives as long as the account.
- **Account deletion** (part of #56's deletion job) runs in this order:
  1. Read the user's `anon_id`.
  2. Ask the vendor to delete all events for that `anon_id`. Retry until the vendor accepts the request; never skip this step silently.
  3. Delete the user. `on delete cascade` removes the `analytics_identities` row.

  Once the row is gone, nothing can link the `anon_id` back to the person, because it's random. Step 2 still matters: without it, the vendor would keep that person's unlinked event history until retention expires.

## Dashboard

#51's acceptance criterion is "a dashboard with the metrics from `docs/plan.md`". It lives in the chosen tool, except the time-to-editor tile, which falls back to a saved Supabase query if the tool can't pair events by `job_id`.

| Tile | Shows | Built from |
|---|---|---|
| Time to editor | Weekly median and p90; % of queued jobs that reached the editor within 10 min; download vs Bridge path | `upload_completed`, `template_exported`, `template_applied`, paired by `job_id` |
| Activation funnel | Conversion at each step, within 7 days of signup | `signup_completed` → `upload_started` → `upload_completed` → `breakdown_viewed` → `template_exported` or `template_applied`, per `anon_id` |
| MCP adoption | % of 28-day active users who have connected a client, split by `client_kind` | `mcp_client_connected` ÷ active users |
| Applies per week per editor | Weekly count, stacked by `editor_type` | `template_applied` |
| Assistant quality | Weekly thumbs-up rate and citation rate | `assistant_feedback`, `assistant_answered` |

**#51 is done when:**
- every tile renders from real staging or production events, not seeded data; and
- the time-to-editor figures for at least 3 jobs have been checked by hand against their `jobs` rows.

This PR doesn't close #51; the issue stays open until the dashboard meets that bar.

## Rollout

Each story below adds its own `track()` calls against this contract when it ships. This doc changes none of their code:

| Story | Adds |
|---|---|
| #15 (auth) | The tool decision; the `track()` module; `/api/track`; the `analytics_identities` migration and RLS test; `signup_completed` |
| #16 (upload flow) | `upload_started`, `upload_completed` |
| #18 (breakdown page) | `breakdown_viewed` |
| #64 (export buttons), #72 (`export_template`) | `template_exported` |
| #70 (MCP OAuth), #37 (personal tokens), #73 (Bridge token auth) | `mcp_client_connected` |
| #75 (Bridge tools) | The apply-report call to the API, which emits `template_applied` |
| #65 (assistant backend), #66 (chat panel) | `assistant_answered`, `assistant_feedback` |
| #56 (privacy and retention) | The analytics step in the account-deletion job; analytics in the privacy policy |
| #51 (this story) | The dashboard tiles, built as their events start flowing |

## Open questions

| Open question | Owner |
|---|---|
| Which tool? Check each candidate's current free-tier limits and the five requirements in [Tool choice](#tool-choice) against the vendor's own docs | Whoever picks up #15, or a dedicated decision before then |
| Does the tool choice need an ADR? Not now, but it adds a cost and a new vendor that holds personal data | Whoever makes the tool decision |
| The exclusion list in [Privacy & data](#privacy--data) needs reconciling with #56, which also defines what we record | Whoever picks up #56 |
| Is opt-out legally required for this pseudonymous data (e.g. under GDPR)? If so, `/api/track` and `track()` check a per-user flag and drop that user's events | Whoever picks up #56 |
| `template_exported` records an export URL being issued, not the template being opened in an editor | Whoever picks up #64; revisit once the Bridge's `open_export` (#75) could report a real open |
| MCP adoption counts users who have *ever* connected, which overstates adoption as users churn. #37's token "last used" time could tighten it once there are enough users for the difference to matter | Whoever picks up #37 |
| A thumbs up or down shows *whether* an answer was good, not *why*. A fixed list of reasons on thumbs-down (not free text) could be added once usage shows what goes wrong | Whoever reviews assistant quality against #39's scores |

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ weak | No customer evidence; justified by the MVP gate needing a measurement and by separation of concerns (own story vs. folding into #15) |
| Smallest valuable version | ✅ | Objectives, provider-agnostic schema, collection contract and dashboard spec; the tool stays a reference option |
| Alternatives | ✅ | PostHog is the leaning candidate, with alternatives compared and requirements stated; explicitly non-binding |
| Fit with Key Decisions | ✅ | Deliberately not an ADR yet, since the tool isn't decided; revisit once it is (tracked in Open questions) |
| Data/schema | ⚠️ | One new service-role-only table (`analytics_identities`), with migration and RLS test in #15; no `template.schema.json` or MCP tool contract changes |
| Security/privacy | ✅ | A random `anon_id`, never `user_id`, leaves the system; server-side allowlist; 1-year retention; ordered deletion; opt-out narrowed to one legal question for #56 |
| Cost | ⚠️ deferred | Compared qualitatively, with no figures so nothing goes stale; the tool and real cost are still undecided (see Open questions) |
| Failure modes | ✅ | `track()` never throws or blocks, and dropped events are acceptable; see Reliability |
| Reversibility | ✅ | Two-way door: the vendor sits behind one module, and `anon_id` stays valid if the vendor changes |
| Observability | ✅ | The allowlist rejects unknown events and properties; dropped events log a warning via #50 |
| Success metric | ✅ | Every dashboard tile renders from real events, and time to editor is checked by hand against `jobs` |
| Effort & ownership | ✅ | Each dependent story's owner adds their own events (see Rollout); no new dedicated role needed |

</details>
