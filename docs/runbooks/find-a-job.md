# Find a job's logs

Goal: from a user's report or a failed job in the UI to the worker's logs and error in under 2 minutes. Log fields are explained in [observability.md](../observability.md).

## 1. Get the `job_id`

- **From the UI:** the job status view shows the job ID and error. *TODO (#60): add the ID, the error and links to Sentry and Modal.*
- **From the database:** in the Supabase dashboard (right project: staging or prod), open the SQL editor:
  ```sql
  select id, status, error, sentry_event_id, created_at
  from jobs
  where user_id = '<user uuid>'
  order by created_at desc
  limit 10;
  ```
  *TODO (#58): the `jobs` table and its `error` / `sentry_event_id` columns.*
- **From a user:** ask for the upload's time and name, then use the query above.

## 2. Open the error in Sentry

- If the job row has `sentry_event_id`, search for it in Sentry.
- Otherwise filter by tag: `job_id:<id>` in the `editrace-workers` and `editrace-web` projects, with the environment set to `staging` or `prod`.

## 3. Read the worker logs (Modal)

- Modal dashboard → the right environment → the worker's app → **Logs**.
- Search for the `job_id`. Every line the worker writes carries it once the worker base (#53) binds it.

## 4. Read the web logs

- Vercel → project → **Logs**, search for the `job_id` or the `request_id` (the `x-request-id` response header).
- Vercel Hobby keeps runtime logs for a short time only. For older failures, Sentry and the job row are the record.

## If you can't find it

- No log lines with the `job_id`: the worker may never have started. Check the job's status and whether the Modal call was made (web logs around `created_at`).
- No Sentry event: the error was caught and logged without being reported. Note it in #50 so the code path gets fixed.
