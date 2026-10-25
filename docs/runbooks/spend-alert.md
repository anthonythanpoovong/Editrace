# A spend alert fires

Use when Modal or Anthropic sends a spend notification. Limits and who gets alerts are in [observability.md](../observability.md#spend-alerts).

## 1. Is it real and still growing?

- **Modal:** dashboard → **Usage**, filter by environment and app. Look for one app or function using far more than usual.
- **Anthropic:** Console → **Usage**, filter by workspace and API key.
- Compare with the last few days. A steady rise from more users is different from a sudden spike.

Post in `#alerts` that you're on it.

## 2. Stop the spend if it's a spike

Do this first if spend is still climbing fast. Investigate after.

- **Modal:**
  - Stop the app that's spending: `modal app stop <app> --env <env>`, or stop it from the dashboard.
  - Or lower its concurrency and redeploy, if users still need it.
- **Anthropic:**
  - Lower the workspace spend limit in the Console, or
  - Disable or rotate the key (see the rotation rule in [environments.md](../environments.md)). This turns the assistant off for everyone.

## 3. Find the cause

| Pattern | Likely cause |
|---|---|
| One user, many jobs or messages | Abuse or a script. Check their uploads and requests by `user_id` in the logs. *TODO (#50 part 3): per-user rate limits.* |
| Same job ID repeating | A retry loop. The job never reaches a final state. |
| Cost per job much higher than usual | A detector stopped downsampling, or a bigger GPU or model was deployed |
| Steady increase, many users | Real growth. Raise the budget with the owner's approval. |

*TODO (#53, #58): the `job_costs` table answers "which jobs and users cost the most" directly.*

## 4. Follow up

- Restore anything you stopped once the cause is fixed.
- Open an issue for the fix (a missing cap, a retry bug, rate limits).
- If the budget itself was wrong, update the table in [observability.md](../observability.md#spend-alerts).
