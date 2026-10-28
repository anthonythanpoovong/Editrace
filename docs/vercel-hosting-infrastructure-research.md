# Vercel Hosting & Infrastructure Research

*Prototype feasibility • commercial terms • long-term architecture • monthly budget*

Prepared 21 October 2026 | Planning assumption: four GitHub developers, private repository, web-based product with potential AI/video processing. All amounts USD unless stated otherwise.

## Executive decision

Vercel is a strong choice for frontend hosting, especially for Next.js and GitHub-based deployments. It reduces deployment and CDN administration, provides HTTPS/custom domains, and supports preview environments. However, Hobby is explicitly restricted to personal, non-commercial use. For a startup prototype intended to market, sell, or otherwise operate commercially, budget for Pro rather than assuming Hobby is permitted. [1][2]

Recommendation: use Vercel Pro for the frontend when commercial use begins; Supabase for Postgres/auth/storage; PostHog for product analytics; Resend for transactional email; and Modal only if heavy CPU/GPU jobs are actually needed. Keep compute-heavy video/AI processing outside Vercel functions. Revisit Cloudflare or another host if bandwidth and seat costs become dominant.

## 1 | Is Vercel free for the prototype?

### Hobby plan and terms

Hobby price: $0/month; intended for personal, non-commercial projects. The Terms of Service expressly limit Hobby to personal or non-commercial use. [1][2]

Useful for a non-commercial technical demo or experimentation; do not assume an investor demo, waitlist, public launch, or startup MVP is automatically permitted under Hobby. Obtain clarification from Vercel if the classification is uncertain.

Published Hobby examples: 1 million CDN requests/month and 100 GB fast data transfer/month, subject to the current product-specific limits and fair-use rules. Usage cannot simply be purchased beyond Hobby caps. [2]

Hobby deployment storage and retention limits matter during active iteration; Vercel has changed deployment retention, so check the current limits before launch. [3]

### When to upgrade

Upgrade to Pro before commercial operation; when multiple developers need deploying permissions; or when Hobby limits, support, and production reliability requirements are insufficient. Pro begins at $20/month and includes $20 monthly usage credit, but excess resource use is charged separately. [2]

## 2 | Why Vercel is a good fit

- **GitHub integration:** automatically builds and deploys selected branches; production deployments can follow merges to main.
- **Developer experience:** straightforward CI/CD, deployment history, rollbacks, environment variables, and preview URLs.
- **Performance:** global CDN and optimized delivery for static assets and frontend routes.
- **Framework fit:** particularly convenient for Next.js and modern React apps.
- **Operational simplicity:** no servers to patch for a typical frontend; managed HTTPS and domain integration.
- **Growth path:** Pro adds collaboration, spend management and commercial-use suitability.

**Tradeoff:** Vercel does not replace a relational database, robust background job infrastructure, transactional email provider, or specialized GPU processing. These should be separate services.

## 3 | Long-term suitability and risks

### Pricing, scaling and team access

Plans: Hobby $0 for eligible non-commercial use; Pro starts at $20/month; Enterprise is custom-priced. Pro includes a usage credit, not unlimited infrastructure. Monitor request volumes, data transfer, function duration, image optimization, and any paid add-ons. [2]

Four-person private GitHub team: GitHub commits, branch pushes, and PR reviews do not require Vercel seats. However, Vercel's private-repository Git deployment author checks can make one paid deploying seat insufficient when other developers author deployable commits. Do not assume that having the lead developer merge or using squash merges avoids this requirement. Confirm the current seat policy with Vercel before committing to a one-seat budget. Budget four paid seats as the conservative native-deployment case (~$80/month if $20/seat).

### Vendor lock-in

Low-to-moderate if the frontend remains standard React/Next.js, environment variables are portable, and database/auth are external. Higher if the app relies heavily on Vercel-specific edge/runtime behavior, proprietary storage, analytics, caching or deployment configuration. Keep APIs and background workers deployable separately, document environment variables, and test a second host periodically.

### Alternatives

| Provider | Strength | Tradeoff / best use |
| :-- | :-- | :-- |
| Cloudflare Pages/Workers | Global edge platform; potentially attractive cost structure | Runtime compatibility and execution model need validation for app features |
| Netlify | Git-based frontend deployments and previews | Compare team, bandwidth, build and function pricing |
| Render / Railway | Convenient app servers and background workers | Often better for persistent backends; instance charges |
| AWS / Google Cloud | Broad services and control | More operations, complexity and variable billing |

## 4 | Recommended architecture

GitHub → PR review and automated tests → merge to protected main → Vercel frontend. Frontend talks to Supabase for auth/Postgres/storage, Resend for outbound transactional email, PostHog for event analytics, and a separate Modal worker/API for optional AI/video processing. Keep provider API keys server-side. Use object storage and signed URLs for large media; do not route large videos through frontend serverless functions.

Deployment control: protect main and require PR approval; optionally suppress preview builds. Note that Vercel's Ignored Build Step can cancel builds after a deployment has been created, so it is not necessarily equivalent to preventing all deployment events or avoiding private-repo author checks.

## 5 | Monthly budget: prototype to growth

Planning assumptions: one domain (~$12–25/year, modeled as $2/month), PostHog free tier initially, Resend free initially, Supabase Pro at $25/month when production-grade database backups are needed. Modal Starter includes $30/month compute credit but has three workspace seats, so a four-person team may need to limit Modal access or assess Team ($250/month + compute). Modal workloads are highly variable. [4][5][6][7]

| Service | Non-commercial demo | Lean commercial MVP | 4-seat production baseline |
| :-- | :-- | :-- | :-- |
| Vercel hosting | 0 | 20 | 80 |
| Supabase | 0 | 25 | 25 |
| PostHog analytics | 0 | 0 | 0 |
| Resend email | 0 | 0 | 20 |
| Modal CPU/GPU | 0–30* | 0–100* | 50–200* |
| Domain (monthly equivalent) | 2 | 2 | 2 |
| **Estimated total / month** | **~2–32** | **~47–147** | **~177–327** |

\* Modal figures are planning allowances for billable compute, not fixed subscriptions. Starter includes $30 monthly free compute credits; the actual invoice depends on usage and whether credits apply. Domain price is an estimate, not a provider quote. Vercel overages, taxes, payment processing, third-party AI APIs, SMS, storage overages, and monitoring upgrades are excluded.

### What changes the bill most?

- **Team seats:** moving from one to four Vercel deploying seats adds approximately $60/month at the assumed seat rate.
- **Media/AI workloads:** GPU seconds, concurrency, storage and egress can quickly exceed the frontend bill; model jobs per active user and minutes per job.
- **Email:** Resend Free includes 3,000 emails/month with a 100/day cap; Pro is $20/month for 50,000 emails. [6]
- **Database:** Supabase Free is suitable for small tests but can pause inactive projects; Pro starts at $25/month and includes daily backups. [4]
- **Analytics:** PostHog offers 1 million free product analytics events/month; costs depend on additional products and overages. [7]

## 6 | Action plan and open decisions

- Confirm whether the prototype is genuinely non-commercial; if not, use Pro from the outset.
- Ask Vercel to confirm private-repo commit-author and paid deploying-seat policy for the exact four-developer workflow.
- Protect main, require PR approvals, and run tests before production merges.
- Start with Supabase Free for experiments, then Pro before production reliability matters.
- Measure expected monthly users, page views, uploads, AI jobs, average processing time and email volume before finalizing budget.
- Set Vercel spend alerts/limits and per-provider usage budgets; review invoices monthly.
- Validate Cloudflare as a fallback with a small proof-of-concept before adopting platform-specific features.

## Sources (official provider pages; accessed October 2026)

1. Vercel Terms of Service: https://vercel.com/legal/terms
2. Vercel pricing: https://vercel.com/pricing
3. Vercel Hobby deployment retention: https://vercel.com/changelog/hobby-projects-now-retain-fewer-deployments-to-free-up-storage
4. Supabase pricing: https://supabase.com/pricing
5. Modal pricing: https://modal.com/pricing
6. Resend pricing: https://resend.com/pricing
7. PostHog pricing: https://posthog.com/pricing
8. Vercel Git documentation: https://vercel.com/docs/git
