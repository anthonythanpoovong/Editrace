# 0001: Host the web app on Cloudflare Workers instead of Vercel

- **Status:** Proposed
- **Date:** 2026-10-07
- **Author:** @anthonythanpoovong
- **Deciders:** @anthonythanpoovong
- **Related:** #171, #48 (CI/CD + environments), #19 (Stripe), #27 (remote MCP server), #149 (coming-soon site)

## Context

The web app (Next.js, see Key Decisions in `docs/plan.md`) is deployed on Vercel's free Hobby plan, under the owner's personal account. Hobby has no collaborators, so any deploy triggered by a teammate fails: Vercel emails "Failed CLI deployment from <teammate> ... they're not a member of the team" and asks for an upgrade to Pro. Pro bills per seat. Only the account owner can currently deploy or get preview URLs.

Constraints from the team:
- $0 until revenue.
- Managed hosting preferred (no servers to run).
- Needs SSR and per-PR preview URLs.

Hobby also prohibits commercial use, which would block us again once Stripe billing ships in Phase 1 (#19). This is Phase 0 work: #48 requires a PR preview and a staging deploy, and neither works for teammates today.

## Options considered

### Option A: Cloudflare Workers with `@opennextjs/cloudflare`
- Next.js built with OpenNext and deployed as a Worker, with preview URLs per PR/branch.
- ✅ Free plan allows commercial use; account members are believed to be free (to verify). Supports SSR, Route Handlers, middleware and ISR.
- ❌ Not Vercel, so some Next.js features may differ. Free limits: 100k requests/day, small CPU budget per SSR request, 3 MiB Worker bundle size. The Streamable HTTP MCP route (#27) is untested there.
- Cost / effort: $0; about a day to port and validate.

### Option B: Netlify Pro
- Same Next.js app on Netlify.
- ✅ Unlimited members; free plan allows commercial use; mature previews.
- ❌ Free plan is limited to 1 member, so the problem returns without paying. Pro is about $20/month.
- Cost / effort: about $20/month flat; small port.

### Option C: Render, Fly.io, Railway or a self-hosted VPS (Coolify)
- ❌ Render's free tier sleeps after 15 minutes (30-50 s cold start), which hurts the MCP server and demos. Fly.io and Railway have no real free tier. Self-hosting is not managed and adds ops load.

### Option D: Do nothing (stay on Vercel)
- ❌ Teammates can't deploy or get previews unless we pay for Pro seats. Breaks the $0 rule and Hobby's non-commercial terms still block launch.

## Decision

We will **host the Next.js web app on Cloudflare Workers via OpenNext**, because it is the only managed option that keeps $0 cost, allows commercial use, and (to be verified) lets every teammate deploy without a paid seat. **Netlify Pro (about $20/month flat)** is the pre-agreed fallback if validation fails; using it needs the owner's explicit approval because it breaks the $0 rule.

## Consequences

- **Good:** teammates can open PRs and get working previews; no per-seat cost; no commercial-use ban at launch.
- **Bad / accepted trade-offs:** free-plan limits on requests, CPU and bundle size; OpenNext compatibility risk; losing Vercel-native features (Vercel Analytics, Vercel MCP tooling in the workflow).
- **One-way or two-way door:** two-way. Nothing is in production yet; switching again means re-pointing CI and environment variables.
- **Follow-up work:** the migration ticket (amends the Vercel parts of #48), including a validation step before the Vercel project is retired.
- **Affected:** no schema, DB, RLS or MCP contract changes. Secrets now live in GitHub/Cloudflare/Modal instead of GitHub/Vercel/Modal (update `docs/plan.md` and `.env.example` on acceptance). Cost stays $0.

## How we'll know

Every teammate can open a PR and get a working preview URL, and a merge to `main` deploys staging, all at $0 with no paid seat, by the end of Phase 0 (the #48 CI/CD gate). Revisit if validation shows SSR, previews or the MCP route can't run within free limits (switch to Option B), or if free limits are hit in normal use.

## Open questions

- Are Cloudflare account members free, and does the Workers Builds / GitHub integration give previews to all members? (@anthonythanpoovong, answered by the validation step)
- Does the remote MCP server (#27) work over Streamable HTTP within the free CPU limits? (@anthonythanpoovong, can be answered when #27 starts)
- Is the Worker bundle under 3 MiB once the app grows? (@anthonythanpoovong, ongoing)

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ✅ solid | Vercel "Failed CLI deployment" email; Hobby has no collaborators |
| Smallest valuable version | ✅ solid | Preview + staging deploy for every teammate at $0 |
| Alternatives | ✅ solid | Netlify, Render/Fly/Railway/VPS, do nothing compared |
| Fit with Key Decisions | ✅ solid | Only the hosting layer changes |
| Data & schema | ✅ solid | None touched |
| Security & privacy | ⚠️ weak | Secrets move; account-member roles to be set up |
| Cost | ✅ solid | $0; fallback $20/month needs owner approval |
| Failure modes | ⚠️ weak | Free limits and OpenNext gaps; fallback defined |
| Reversibility | ✅ solid | Two-way door |
| Observability | ⚠️ weak | Use Cloudflare logs; formal setup is #50 |
| Success metric | ✅ solid | All teammates deploy and preview at $0 by Phase 0 gate |
| Effort & ownership | ✅ solid | Owner: @anthonythanpoovong; amends #48 |

</details>
