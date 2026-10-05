# Environments and secrets

How Editrace's environments are deployed and where each secret lives (#48). The variable names are in [`.env.example`](../.env.example).

## Environments

| Environment | Purpose | How it deploys | URL |
|---|---|---|---|
| **dev** | Local development | `npm run dev` in `web/` with your own `.env.local` | localhost |
| **preview** | One per PR | The Vercel GitHub integration builds every PR and posts the URL on it | Per PR (needs a Vercel login, SSO protection is on) |
| **staging** | Latest `main` | `deploy.yml` runs on every push to `main` and aliases the build to the staging URL | `https://editrace-staging.vercel.app` (repo variable `STAGING_ALIAS`) |
| **prod** | Live | Run `deploy.yml` by hand from `main` (Actions → Deploy → Run workflow); needs the `Production` environment, which only accepts protected branches | `editrace.vercel.app` |

Vercel's own auto-deploy for `main` is turned off in `web/vercel.json`, so a merge never reaches prod on its own.

### Limitations (revisit on upgrade)

- Vercel Hobby has no custom environments, so staging is a preview build aliased to a stable URL, not a separate project.
- GitHub required reviewers on environments need a paid plan for private repos, so `Production` has no approval gate. The `main` branch protection (PR plus 1 approval plus `ci-ok`) is the only gate.
- Supabase and Modal staging/prod environments aren't set up yet. Add them when the first schema and worker code land.

## Where each secret lives

Each secret lives in **one** place. Don't copy values between systems except through the deploy workflow.

| Secret or variable | Lives in | Used by |
|---|---|---|
| `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` | GitHub repo secrets | `deploy.yml` |
| `STAGING_ALIAS` | GitHub repo variable | `deploy.yml` (staging URL) |
| `CLAUDE_CODE_OAUTH_TOKEN` | GitHub repo secret | Armour review and `@claude` |
| `DISCORD_REVIEW_WEBHOOK` | GitHub repo secret | Discord review notifications |
| `NEXT_PUBLIC_SUPABASE_*`, `SUPABASE_SERVICE_ROLE_KEY` | Vercel project env vars, per environment | Web app |
| `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET` | GitHub repo secrets (deploys) and Modal (runtime) | Workers |
| `ANTHROPIC_API_KEY`, `STRIPE_*` | Vercel project env vars, per environment | Web app and assistant |

Rules:

- Real values never go in git. `.env`, `.env.local` and `.env.*.local` are ignored, and gitleaks runs on every PR.
- Staging and prod use different Supabase projects, Stripe keys (test vs live) and Modal environments, so a staging mistake can't touch production data.
- Rotate a token by creating the new one first, updating the secret, then revoking the old one. If a token shows up in a chat, log or commit, revoke it straight away.
