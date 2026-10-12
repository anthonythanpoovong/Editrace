# A worker fails

Use when Sentry alerts on a worker error, a user reports a stuck or failed job, or many jobs fail at once.

## 1. How wide is it?

- **One job:** go to step 2.
- **Many jobs, one worker:** probably a deploy or a dependency. Check what changed in that worker's last deploy (`git log workers/<worker>`), and consider rolling it back.
- **Many jobs, all workers:** probably infrastructure (Modal, Supabase storage, credentials). Check [status.modal.com](https://status.modal.com) and the Supabase status page, and check for a rotated or expired secret.

Post in `#alerts` on Discord what you're looking at, so two people don't debug the same thing.

## 2. Find the cause

Follow [find-a-job.md](find-a-job.md) to get the error and logs. Common causes:

| Symptom | Likely cause | What to do |
|---|---|---|
| Can't download the video | File missing, signed URL expired, wrong bucket | Check the storage object exists; retry |
| Out of memory, GPU OOM | Video longer or higher resolution than expected | Check the downsampling settings; retry on a bigger GPU only if the job is legitimate |
| Timeout | Very long video or a hung model | Check the video length against limits (#57) |
| Invalid template output | Detector returns data the schema rejects | Bug in the detector: open an issue with the job ID and input |
| Auth or permission errors | Secret rotated or missing in Modal | Check Modal secrets for that environment |

## 3. Retry or fail

- **Transient** (network, storage blip, preempted GPU): retry the job. The worker base retries with backoff and is idempotent, so a retry doesn't pay for GPU work twice. *TODO (#53, #58): retry command or button.*
- **Permanent** (bad input, bug): leave the job failed with a clear, user-facing error message. Don't retry in a loop.
- **Bad input that reached Sentry as an error:** it's a bug in how the worker reports it. User input failures are logged at `warn` and never sent to Sentry ([observability.md](../observability.md#what-goes-to-alerts)). Open an issue to fix the reporting.

## 4. Follow up

- A bug: open an issue with the job ID, Sentry link and steps, and link it from the alert thread.
- A user affected: tell them what happened and whether they need to re-upload.
- A gap in logs or alerts that slowed you down: note it in #50 or a new issue.
