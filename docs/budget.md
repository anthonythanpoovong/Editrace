# Budget and break-even

What it costs to keep Editrace running, what one paying user costs to serve, and how many paying users cover it.

_Last updated 2026-10-25. These are estimates. Prices marked **(list)** are vendor list prices and should be checked before a decision. Cost per analysis is a guess until `job_costs` (#53, #58) measures it._

## Summary

| Stage | Fixed cost / month | Paying users to break even at $19 |
|---|---|---|
| Today | ~$40 | n/a (no revenue yet) |
| MVP beta (Sprint 8, 2027-01-07) | ~$77 | **6** |
| After launch, lean | ~$240 | **18** |
| After launch, Modal Team plan | ~$490 | **37** |
| After launch, plus 4 founder stipends of $1,500 | ~$6,500 | **~480** (~$9.2k MRR) |

Infrastructure is not the constraint. Paying the team is.

## Fixed costs (per month)

| Provider | Today | MVP beta | After launch | Notes |
|---|---|---|---|---|
| Vercel Pro | $20 (1 seat) | $20 | $80 (4 seats) | Pro since 2026-10-12 ([ADR 0001](decisions/0001-host-web-app-on-cloudflare-workers.md)). Non-members can't open previews ([environments.md](environments.md)) |
| Supabase | $0 (Free) | ~$35 | ~$50 | **(list)** Pro is $25/org with $10 compute credit; second project ~$10. **Free blocks the beta:** 50 MB upload limit and idle projects pause. Prod compute upgrade after launch |
| Modal | $0 | $0 | $0–250 | **(list)** Starter includes ~$30/month of credit. Team plan only if we outgrow Starter. Spend limit still TBD ([observability.md](observability.md#spend-alerts)) |
| Sentry | $0 | $0 | ~$26 | **(list)** Free plan has one seat. Team seats need the owner's approval |
| Transactional email | $0 | $0 | $0–20 | Supabase's default mailer is too rate-limited for real users. Resend's free tier covers beta |
| Domain, Apple Developer | – | ~$2 | ~$10 | Apple Developer ($99/year) only if the Bridge (#32) ships a signed macOS binary |
| Claude Pro for CI | $20 | $20 | $20 | Armour, ticket sync and `@claude` use `CLAUDE_CODE_OAUTH_TOKEN` from a Claude Pro subscription, not API billing. If Pro's usage limits start throttling reviews as PR volume grows, Max costs more **(list)** |
| GitHub, Discord, Stripe account | $0 | $0 | $0 | Stripe charges per transaction (below) |
| **Total** | **~$40** | **~$77** | **~$240–490** | |

**One-time:** legal consult (#21), about $1–3k. Meta ads test (#121), budget not set.

## Cost per analysis

A 60 s 1080p video through every worker.

| Step | Runs on | Est. cost |
|---|---|---|
| Cuts (#7), motion (#8) | CPU | ~$0.001 |
| Captions (#12, Whisper) | GPU | ~$0.007 |
| Text overlay OCR (#13) | GPU | ~$0.004 |
| Transitions (#23), color (#24) | GPU | ~$0.005 |
| Sound ID (#14) | ACRCloud | $0.003–0.009 (quote on #11: $6 per 1k matches, half for a no-match) |
| Beats (#14) | CPU | negligible |
| Storage (60 MB kept 30 days) | Supabase | ~$0.001 |
| Subtotal | | ~$0.025 |
| **With 2× for cold starts and retries** | | **~$0.05** |

**Assistant (Phase 2, #22):** about $0.015 per message on `claude-sonnet-5-5` ($2 / $10 per million input / output tokens, $0.20 cached input), assuming ~10k input tokens (mostly cached) and ~600 output tokens. 100 messages a month is ~$1.50 per user.

**Not included:** footage match (#99–#105). It scores users' raw footage on GPUs and needs its own estimate (#102).

## Cost to serve one paying user (per month)

Solo is assumed to be **$19/month**; the real price is decided in #19.

| Line | Before assistant | With assistant |
|---|---|---|
| Stripe (2.9% + $0.30, Billing 0.7%) | $0.98 | $0.98 |
| Analyses: 30 × $0.05 | $1.50 | $1.50 |
| Assistant: 100 messages | – | $1.50 |
| Free trials that don't convert: 3 templates each, 10% convert | $1.50 | $1.50 |
| Storage and egress | $0.10 | $0.10 |
| **Cost to serve** | **~$4.00** | **~$5.50** |
| **Margin at $19** | **~$15 (79%)** | **~$13.50 (71%)** |

## Break-even

```
paying users to break even = fixed cost per month / margin per user
margin per user            = price − Stripe fees − cost to serve
```

| Price | Margin per user | Beta ($77) | Lean ($240) | Modal Team ($490) | With stipends ($6,500) |
|---|---|---|---|---|---|
| $12 | ~$6.50 | 12 | 37 | 76 | ~1,000 |
| $19 | ~$13.50 | 6 | 18 | 37 | ~480 |
| $29 | ~$23 | 4 | 11 | 22 | ~285 |

Price moves break-even far more than infrastructure does. Interviews (#20) should test willingness to pay.

## Assumptions to replace with real numbers

| Assumption | Value used | Replaced by |
|---|---|---|
| Cost per analysis | $0.05 | `job_costs` per job (#53, #58) |
| Analyses per paying user | 30 / month | Product analytics (#51, #296) |
| Assistant messages per user | 100 / month | Conversation counts (#67) |
| Trial-to-paid conversion | 10% | Stripe and analytics after beta |
| Solo price | $19 / month | #19, informed by #20 |
| Sound-ID vendor | ACRCloud entry tier | Sound-ID ADR from #11 |
| Modal plan after launch | Starter or Team | Seats and concurrency we actually need |

## Before beta

- Upgrade Supabase to Pro (Sprint 6 or 7). Beta uploads won't fit the Free plan.
- Set the Modal and Anthropic monthly limits in [observability.md](observability.md#spend-alerts). They are TBD.
- Set up custom SMTP for auth emails.

## Updating this page

Update it when a provider plan changes, a price is decided (#19), or `job_costs` gives a measured cost per analysis. Change the date at the top. Spending beyond these plans needs the owner's approval, as in [runbooks/spend-alert.md](runbooks/spend-alert.md).
