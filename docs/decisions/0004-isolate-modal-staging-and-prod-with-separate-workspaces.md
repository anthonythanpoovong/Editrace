# 0004: Isolate Modal staging and prod with separate workspaces, not Team-plan service users

- **Status:** Proposed
- **Date:** 2026-10-28
- **Author:** @anthonythanpoovong
- **Deciders:** @anthonythanpoovong
- **Related:** #320, #302, #163, #300, ADR 0001
- **Supersedes:**

## Context

Workers run on Modal (Key Decision: "Heavy processing runs on Modal GPU workers"). `deploy.yml` needs to deploy to staging automatically and to prod on a manual run, and a staging job must never be able to touch prod (#163, #320).

The constraint is the Modal **Starter** plan. It has no service users, so the only token is a user token that covers the whole workspace. A staging job holding it could deploy to `prod`, and the `staging` and `prod` environments we created don't change that. Scoped service users (Contributor on one environment) need the **Team** plan, $250/month plus compute (modal.com/pricing). PR #302 is written for service users and is on hold until this is decided.

What we've verified (2026-10-27/28):
- Modal's docs say API tokens are added per workspace, and that users can belong to several workspaces.
- Starter can create a second workspace once a payment method is added. The dashboard says it unlocks workspace creation and the full $30 credit, and charges $0.50 to verify the card, which is refunded.
- We now own two workspaces, `anthonythanpoovong` and `editrace-app`, both as Owner.
- Cost is the main constraint. We have no users, no revenue and no worker deployed yet.

Why now: the first real worker deploy (#7) is blocked until the isolation layout is chosen.

## Options considered

### Option A: A separate Modal workspace per environment, one token each
- `editrace-app` is prod and `anthonythanpoovong` is staging for now. Each GitHub environment (`staging`, `Production`) holds only its own workspace's token.
- ✅ Hard isolation. A staging token has no access to the prod workspace at all, not just a role boundary.
- ✅ Separate spend caps per workspace, so a staging runaway can't use the prod budget.
- ✅ $0 for the workspaces themselves.
- ❌ A card must be on file, so usage past the free credit can be billed.
- ❌ Staging lives under a personal workspace until it moves.
- ❌ #302 and `docs/environments.md` must be reworded, since they assume service users.
- Cost / effort: $0 plus compute; a small rewrite of #302.

### Option B: Upgrade to Team and use service users
- One workspace, `ci-staging` and `ci-prod` service users with Contributor on one environment each.
- ✅ Strong isolation, and #302 works as written.
- ❌ $250/month plus compute, about $3,000 a year, before any user exists.
- Cost / effort: $250/month.

### Option C: One user token for both environments
- ✅ Nothing to set up.
- ❌ No isolation. A leaked token or a bad staging job can deploy to prod. This fails the #163 criterion that a staging deploy never touches prod.
- Cost / effort: $0.

### Option D: Do nothing / defer
- ✅ No spend and no change.
- ❌ Blocks the first real worker deploy (#7) and leaves #163 open.

## Decision

We will **use a separate Modal workspace for each environment, with one API token per workspace**, because it gives hard isolation and separate spend caps for $0, while Team costs $250/month before we have a single user.

- **Prod** is `editrace-app`. **Staging** is `anthonythanpoovong` for now.
- **Nothing is live yet.** No `MODAL_TOKEN_*` secrets are created or added to GitHub until we choose to start spending, so no job can deploy.
- Each workspace gets a monthly spend limit, starting at $0 beyond the free credit where Modal allows it.
- The `staging` and `prod` environments inside a workspace become redundant. We keep one environment per workspace.

## Consequences

- **Good:** a staging token can't reach prod. Each environment has its own budget. No recurring cost now.
- **Bad / accepted trade-offs:** a card is on file, so overage past the credit is possible until the limits are confirmed. Staging sits under a personal workspace. Secrets and images are duplicated per workspace.
- **One-way or two-way door:** two-way. If we outgrow this, we upgrade to Team and move to service users, revoking the workspace tokens. The cost is a rewrite of the deploy step and docs, with no data migration.
- **Follow-up work:** reword #302 and `docs/environments.md` for workspaces and tokens per environment. Set the spend limits and update the Modal row in `docs/observability.md`. Later, move staging to its own workspace. Add tokens only when we're ready to spend (#320).
- **Affected:** no schema, DB, RLS or MCP changes. Cost: $0 now. Docs: `environments.md`, `observability.md`, #302.

## How we'll know

- A staging token that tries to deploy to the prod workspace fails, checked once the tokens exist (before the first real deploy).
- Modal spend stays at $0 until launch.
- Revisit if the team needs per-person roles inside one workspace, if Starter limits (for example seats) block us, or if spend makes Team worthwhile.

## Open questions

- Does Starter offer a hard spend stop or only alerts? Owner: @anthonythanpoovong, check **Usage & billing** and **Resource limits**.
- Does `editrace-app` show the Starter plan and its own free credit? Owner: @anthonythanpoovong.
- When do we move staging out of the personal workspace? Owner: @anthonythanpoovong.

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ✅ solid | Starter has no service users (#320, #302); no customer evidence, as expected for infrastructure |
| Smallest valuable version | ✅ solid | Two workspaces, tokens added later |
| Alternatives | ✅ solid | Team, shared token and deferring all considered |
| Fit with Key Decisions | ✅ solid | Keeps Modal, changes only the account layout |
| Data and schema | ✅ solid | None affected |
| Security and privacy | ⚠️ weak | Isolation depends on tokens never being shared across environments; not yet tested |
| Cost | ⚠️ weak | $0 now, but a card is on file and the hard-stop limit is unverified |
| Failure modes | ✅ solid | Missing token fails the deploy job; no app means a notice only |
| Reversibility | ✅ solid | Two-way door |
| Observability | ⚠️ weak | Spend alerts not yet set up (`observability.md`) |
| Success metric | ✅ solid | Cross-deploy fails; spend stays $0 |
| Effort and ownership | ✅ solid | Owner @anthonythanpoovong, small rewrite of #302 |

</details>
