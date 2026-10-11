# Observability

How Editrace logs, tracks errors and watches spend (#50). Every service follows these rules so a failing job can be traced from the UI to the worker logs with one ID.

## Log format

Every log line is a single JSON object on stdout. Use the shared helpers instead of `console.log` or `print`:

- Web and MCP (TypeScript): [`web/lib/log.ts`](../web/lib/log.ts)
- Workers (Python): [`workers/common/log.py`](../workers/common/log.py)

| Field | Set when | Notes |
|---|---|---|
| `ts` | always | ISO-8601, UTC |
| `level` | always | `debug`, `info`, `warn`, `error` |
| `msg` | always | Short, fixed text, e.g. `"job started"`. Put variable data in fields, not in the message |
| `service` | always | `web`, `mcp`, `assistant`, `worker:<name>` |
| `env` | always | `dev`, `preview`, `staging`, `prod`, from `APP_ENV` |
| `request_id` | every HTTP request or MCP call | New UUID per request, returned as the `x-request-id` response header |
| `job_id` | once a job exists | **The key for tracing a job.** The jobs table's primary key (#58) |
| `template_id` | when known | Supabase UUID |
| `user_id` | when known | Supabase auth UUID |
| `err` | on errors | `{ name, message, stack }` |
| `sentry_event_id` | when an error is sent to Sentry | Links the log line to the Sentry event |

Other fields are fine (`duration_ms`, `gpu_seconds`, `detector`, ...). Use `snake_case`.

## How IDs travel

```
browser ──request──▶ web route ──creates job row──▶ Supabase (jobs.id = job_id)
                         │
                         └──calls Modal with { job_id, user_id, template_id, request_id }
                                              │
                                              ▼
                               worker base binds them to every log line
```

- The web route creates `request_id` (or reuses an incoming `x-request-id`) and binds it to its logger.
- Once the job row exists, the route logs with `job_id` and passes all IDs to the worker.
- The worker base (#53) binds the IDs as soon as it starts, so every line it writes, including from detectors, carries them.
- Errors are sent to Sentry with the same IDs as tags, and the job row stores `error` and `sentry_event_id` (#58).

To trace a job: get its `job_id` from the UI or the jobs table, then search for it in the logs and in Sentry. See [`runbooks/find-a-job.md`](runbooks/find-a-job.md).

## What never goes in logs

Log IDs, never content. Never log:

- Emails, names or other personal details
- Supabase JWTs, API keys, `Authorization` headers, OAuth tokens
- Signed storage URLs (they grant access to the user's video)
- Prompt or assistant message text, transcript text, OCR text

Both helpers replace values under sensitive keys (`token`, `authorization`, `password`, `email`, `api_key`, `secret`, `cookie`, ...) with `"[redacted]"`. That's a safety net, not a licence. Don't pass content to the logger in the first place.

## Error tracking

[Sentry](https://sentry.io) collects errors from the web app and the workers, with one project each (`editrace-web`, `editrace-workers`) and `env` as the environment. Every event carries the `job_id`, `user_id` and `request_id` tags.

- **Workers:** `sentry-sdk` set up in the worker base (#53).
- **Web:** the SDK depends on where the app is hosted: `@sentry/nextjs` on Vercel, `@sentry/cloudflare` if [ADR 0001](decisions/0001-host-web-app-on-cloudflare-workers.md) is accepted. Set it up once that's decided.
- **Seats:** Sentry's free plan has one seat. Alerts go to a shared channel so the team sees them without a seat. Paying for team seats needs the owner's approval because it breaks the $0 rule.

Variables are listed in [`.env.example`](../.env.example). Where they live is in [`environments.md`](environments.md).

## Spend alerts

Alerts are delivered to the **`#alerts`** channel on Discord through a webhook. Its URL is the `DISCORD_ALERTS_WEBHOOK` GitHub secret ([environments.md](environments.md)). Provider alerts arrive by email, and the people on the provider's notification list post anything that fires in `#alerts`. The daily budget check (part 2 of #50) posts to the webhook directly.

| Provider | Guardrail | Where it's set | Status |
|---|---|---|---|
| Modal (GPU, CPU) | Workspace spend limit + usage notifications | Modal dashboard → workspace settings | **Not set up yet.** No Editrace workspace exists. Set up and tested when it's created (#163) |
| Anthropic (assistant, LLM tokens) | Monthly spend limit + notification thresholds | Anthropic Console → Settings → Limits | **Not set up yet.** No Editrace organisation exists. Set up and tested when the assistant's API key is created (#65) |

Setting up a provider's alert means: set the monthly limit, add notifications at 50% and 80%, add the team to the notification list, then cross a temporary low threshold and confirm the alert is posted in `#alerts`. Test on the real Editrace account, not a personal one: alerts belong to one account, so a test elsewhere proves nothing.

Budgets (the owner sets these when the accounts are created):

| Provider | Monthly limit | Alert at |
|---|---|---|
| Modal | TBD (#163) | 50%, 80% |
| Anthropic | TBD (#65) | 50%, 80% |

When an alert fires, follow [`runbooks/spend-alert.md`](runbooks/spend-alert.md). Per-job cost tracking (`job_costs`) and a daily budget check come with the worker base (#53) and jobs table (#58).

## Log retention

The 2-minute trace target only works if the logs still exist. Free tiers keep logs for a short time, so check the current limits for each host:

- **Web on Vercel Hobby:** runtime logs are kept for a short window (about an hour). Anything older is only in Sentry.
- **Modal:** keeps app and function logs longer, searchable in the dashboard.
- **Sentry:** keeps events for the plan's retention period.

Because web logs disappear quickly, the job row stores `error` and `sentry_event_id` (#58). The Sentry event is the long-lived record, and the logs are for recent failures.

## Not built yet

Tracked in #50 and depending on other stories:

- Job-ID wiring in the worker base (#53) and jobs table (#58), and the status UI linking to it (#60)
- `job_costs` table, spend dashboard and daily budget check (#53, #58; shared with #102)
- Per-user rate limits on uploads (#57), MCP calls (#27) and assistant messages (#65)
- Modal and Anthropic spend limits and alert tests, when the Editrace accounts are created (#163, #65)
