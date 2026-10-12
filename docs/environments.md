# Environments and secrets

How Editrace's environments are deployed and where each secret lives (#48). The variable names are in [`.env.example`](../.env.example).

## Environments

| Environment | Purpose | How it deploys | URL |
|---|---|---|---|
| **dev** | Local development | `npm run dev` in `web/` with your own `.env.local` | localhost |
| **preview** | One per PR | `deploy.yml` deploys to the `editrace-np` Vercel project every same-repo PR with the owner's Vercel token and posts the URL in a PR comment | Per PR (needs a Vercel login, SSO protection is on) |
| **staging** | Latest `main` | `deploy.yml` runs on every push to `main`, deploys to `editrace-np` and aliases the build to the staging URL | `https://editrace-staging.vercel.app` (repo variable `STAGING_ALIAS`) |
| **prod** | Live | Promote a commit that is live on staging: run `deploy.yml` by hand from `main` (Actions → Deploy → Run workflow); deploys to `editrace-prod` | `editrace-prod.vercel.app` (private: Vercel SSO protection is on, so only team members can open it) |

### Promotion: PR → staging → prod

1. A PR gets a preview in `editrace-np`.
2. Merging to `main` deploys staging (`editrace-np`). When staging is live, the workflow marks the commit with a `deployed/staging` commit status.
3. Test on staging, then run **Deploy** from `main`. Leave `sha` blank to promote the newest commit live on staging, or paste a SHA. The run refuses any commit without the `deployed/staging` status, so prod can only get what staging has already served.
4. The `Production` job rebuilds that exact commit in `editrace-prod` with production's env vars. It can't reuse the staging build, because `NEXT_PUBLIC_*` values are baked in at build time and differ per project. The `Production` GitHub environment only accepts protected branches, which is why the run starts from `main`.

Roll back by running the workflow again with an older `sha` that was live on staging.

Repo variables (Settings → Secrets and variables → Actions → Variables): `VERCEL_PROJECT_ID_NP` and `VERCEL_PROJECT_ID_PROD` are the two Vercel project ids. They aren't secrets.

Vercel's own Git deploys are turned off for every branch in `web/vercel.json`, so nothing reaches prod without `deploy.yml`. Branches created before that file changed still carry the old setting until they merge `main`.

### Limitations (revisit on upgrade)

- Staging shares the `editrace-np` project with PR previews (Hobby has no custom environments), so it is a preview build aliased to a stable URL. Prod is a separate project, so its env vars, domains and protection settings can't leak into staging.
- **A blocked deploy never fails a collaborator's push.** Vercel marks a deployment `BLOCKED` when the commit's author isn't on the team, and the CLI would then wait forever. `.github/scripts/vercel-deploy.sh` polls instead: the preview job comments "No preview" and ends green, and the staging job leaves staging on its last build with a warning annotation. Only the manual prod run fails on `BLOCKED`, so run it from a commit authored by a Vercel team member. Staging therefore only advances when the latest commit on `main` is by a team member, until Pro seats are bought.
- Hobby also has no team seats. Vercel's Git integration refuses commits from anyone who isn't on the team, so previews are deployed from Actions under the owner's token instead. Collaborators can't open them while SSO protection is on, because they have no Vercel access either.
- GitHub required reviewers on environments need a paid plan for private repos, so `Production` has no approval gate. The `main` branch protection (PR plus 1 approval plus `ci-ok`) is the only gate.
- Supabase and Modal staging/prod environments aren't set up yet. Add them when the first schema and worker code land.

## Where each secret lives

Each secret lives in **one** place. Don't copy values between systems except through the deploy workflow.

| Secret or variable | Lives in | Used by |
|---|---|---|
| `VERCEL_TOKEN`, `VERCEL_ORG_ID` | GitHub repo secrets | `deploy.yml` |
| `VERCEL_PROJECT_ID_NP`, `VERCEL_PROJECT_ID_PROD` | GitHub repo variables | `deploy.yml` |
| `STAGING_ALIAS` | GitHub repo variable | `deploy.yml` (staging URL) |
| `CLAUDE_CODE_OAUTH_TOKEN` | GitHub repo secret | Armour review and `@claude` |
| `DISCORD_REVIEW_WEBHOOK` | GitHub repo secret | Discord review notifications |
| `NEXT_PUBLIC_SUPABASE_*`, `SUPABASE_SERVICE_ROLE_KEY` | Vercel project env vars: `editrace-np` for preview and staging, `editrace-prod` for prod | Web app |
| `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET` | GitHub repo secrets (deploys) and Modal (runtime) | Workers |
| `ANTHROPIC_API_KEY`, `STRIPE_*` | Vercel project env vars: `editrace-np` for preview and staging, `editrace-prod` for prod | Web app and assistant |

Rules:

- Real values never go in git. `.env`, `.env.local` and `.env.*.local` are ignored, and gitleaks runs on every PR.
- Staging and prod use different Supabase projects, Stripe keys (test vs live) and Modal environments, so a staging mistake can't touch production data.
- Rotate a token by creating the new one first, updating the secret, then revoking the old one. If a token shows up in a chat, log or commit, revoke it straight away.
