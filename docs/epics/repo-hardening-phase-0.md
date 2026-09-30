# Epic proposal: Repo hardening for Phase 0 (stories for #40)

- **Status:** Proposed
- **Date:** 2026-09-30
- **Author:** @anthonythanpoovong
- **Owner(s):** @anthonythanpoovong (teammates join via story 8)
- **Phase:** 0 (De-risk)
- **Related:** #40 Engineering foundations (parent epic), #48 CI/CD + environments, #2 codegen, #50 observability
- **Epic issue:** Not a new epic. These are new stories under **#40**.

## Problem

Code is about to land in an empty monorepo, and three people will ship into it. Today:
- **Editrace Armour** doesn't show which files it reviewed or anything about test coverage, and it **skips silently** on PRs that change its workflow (#93, #95, #112). A green check there doesn't mean Armour ran.
- Nothing measures whether Armour is right. On Haiku it **missed a service-role RLS bypass** that Sonnet caught (#94).
- There's **no coverage measurement or gate**, so untested code can merge.
- There are **no written practices**: no contributing guide, PR or issue templates, or local hooks. Only the owner is a repo collaborator, so teammates can't review.

**Evidence:** mostly preventive (setting this up before code lands). The Armour gaps above were seen in this repo.

## Goal

Before the first real code PRs: every PR shows **which files changed and what the tests cover**, CI **blocks untested new code**, Armour's accuracy is **measured**, and the team follows **one written way of working** with real reviewers.

## Exit criteria

- Armour reviews list the changed files and report CI's coverage numbers, and say visibly when Armour didn't run
- CI fails `ci-ok` when changed lines are < 80% covered (automatic once code exists)
- The Armour eval set runs on demand and records a score
- CONTRIBUTING.md, PR and issue templates, and pre-commit hooks are in place
- Both teammates are collaborators with review responsibilities

## Success metric

By the **Phase 0 gate**:
- **(a)** Armour catches **≥ 4 of 5** seeded bugs in its eval set (including the RLS bypass), re-checked whenever `armour.md` or the Armour model changes
- **(b)** The **first 5 code PRs** pass the changed-line coverage gate **without a bypass**, and each Armour review shows the changed files and coverage

## Out of scope

- **Dependabot, dependency/security scanning (pip-audit, npm audit, Semgrep), pinning actions to SHAs:** deferred. Revisit when dependencies exist.
- **CodeQL:** needs a paid Code Security plan for private repos.
- **Armour finding feedback (👍/👎 tracking):** deferred.
- **Anything #48 already covers:** lint, typecheck, tests, preview deploys, staging/prod, secrets.
- **Overall-coverage gates:** only changed lines are gated.

## Alternatives considered

- **Armour estimates coverage from the diff:** rejected. It's an AI guess shown as a number, which breaks "deterministic first, LLM second".
- **Hosted coverage services:** not needed. `diff-cover` on CI coverage reports is free and keeps code in-house.
- **Gate on overall coverage:** rejected. It punishes unrelated PRs and invites low-value tests.
- **Do nothing until code exists:** rejected. Retrofitting gates and habits after the first PRs is harder than starting with them.

## Stories

### 1. Armour: changed files + coverage in every review
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** reviewers and authors can't see what Armour looked at or how well the change is tested.
- **Scope:**
  - Add a collapsible **Files changed** section to the review format in `.github/armour.md`: each file, lines added/removed, and reviewed or skipped (e.g. generated or lock files)
  - Add a **Coverage** line from CI's coverage summary (story 5): overall %, the change vs `main`, and changed-lines %. If there's no data yet, say "no coverage data yet". **Armour reports CI's numbers and never estimates them.**
  - **Ordering:** Armour and CI both run on `pull_request`, in parallel, so coverage usually won't exist yet when Armour starts. Two parts:
    - **CI posts its own sticky "Coverage" comment** (story 5), so the numbers are always on the PR no matter when Armour runs. This is the source of truth.
    - Armour's workflow **waits for the coverage check to finish** (poll `gh pr checks` for it, bounded to ~10 minutes) before reviewing, then quotes the numbers. On timeout, or if the coverage job didn't run, it says "coverage pending: see the CI coverage comment" and never estimates.
  - Give Armour read access to the coverage summary (the check output or sticky comment)
  - Keep the whole comment under 400 words (the files list is collapsed)
- **Acceptance criteria:**
  - [ ] A test PR shows the files list and "no coverage data yet"
  - [ ] Once story 5 lands, a PR with code shows the real coverage numbers from CI
- **Depends on:** story 5 (coverage numbers only)

### 2. Armour: visible skip notice
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** Armour exits "successfully" without reviewing when the PR changes its workflow, when it's a fork, or when the action errors, and nobody can tell.
- **Scope:** a step after the Armour action that detects a skip (workflow validation, fork, error, usage limit) and posts or updates one comment: "⚠️ Editrace Armour did not review this commit: <reason>".
- **Acceptance criteria:**
  - [ ] A PR that edits `ai-review.yml` gets the skip notice
  - [ ] A normal PR gets no notice
- **Depends on:** —
- **Note:** ship this **first**. **This story's own PR edits `ai-review.yml`, so Armour skips it and it needs a manual review.** The same goes for any later story that edits `ai-review.yml` (e.g. story 1's wait step), but once this story is merged, those PRs at least show the skip notice.

### 3. Armour: sharper review rules
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** `armour.md` predates coverage data and the team's skills.
- **Scope:** add rules to `.github/armour.md` for:
  - **Uncovered risky logic:** changed lines with auth, RLS, billing, time conversion or cost limits that CI reports as uncovered
  - **Missing tests** for new endpoints, MCP tools, workers or migrations (pointing to `/db-migration`, `/mcp-tool`, `/new-detector`)
  - **Missing docs follow-up:** a large change (per `/sync-docs`'s rules) with no note to run `/sync-docs` after merge
  - Severity calibration examples, so 🔴 means "must fix"
- **Acceptance criteria:**
  - [ ] The rules are in `armour.md`, and the eval set (story 4) still scores ≥ 4/5 after the change
- **Depends on:** stories 1, 4, 5

### 4. Armour eval set
- **Labels:** `story`, `type:build`, `area:infra`, `platform`, `risk:research-heavy`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** nothing measures whether Armour catches real problems. The Haiku miss (#94) was found by chance.
- **Scope:**
  - **5 seeded-bug cases**, each a small diff with a known expected finding: (1) service-role client bypassing RLS, (2) template time stored as float seconds, (3) a hand-written type instead of a generated one, (4) an LLM/GPU call with no limit or backoff, (5) audio persisted from user uploads
  - A **manual** (`workflow_dispatch`) runner that opens each case as a **draft PR labeled `armour-eval`**, waits for Armour, scores caught / missed, posts a summary, then **closes the PRs and deletes the branches**
  - **The runner opens PRs with a dedicated token, not the default `GITHUB_TOKEN`.** Events caused by `GITHUB_TOKEN` don't trigger other workflows, so Armour would never run on the eval PRs. Use a fine-grained PAT (or GitHub App token) scoped to this repo only (contents + pull requests: read/write), stored as the `ARMOUR_EVAL_TOKEN` secret and used only by this runner.
  - Run only when `armour.md` or the Armour model changes (bounded Pro usage: about 5 reviews per run)
- **Acceptance criteria:**
  - [ ] One command runs all 5 cases and reports a score
  - [ ] Eval PRs are never merged, and are closed automatically
  - [ ] Score recorded for the current rules and model (target ≥ 4/5)
  - [ ] Armour actually runs on every eval PR (PRs opened with `ARMOUR_EVAL_TOKEN`, not `GITHUB_TOKEN`)
- **Depends on:** story 2

### 5. CI: changed-line coverage gate (80%)
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** without a gate, untested code merges. Gating only **changed** lines avoids punishing unrelated PRs.
- **Scope:**
  - Collect coverage in the existing CI jobs: `pytest --cov` (Python), Vitest/Jest coverage (web)
  - Use **`diff-cover`** on the coverage reports vs `main`: **fail when changed lines are < 80% covered**
  - Switches on automatically via the existing `detect` job (only when `web/` or Python code exists)
  - Publish a coverage summary (overall %, change vs `main`, changed-lines %) as **check output** and as a **sticky "Coverage" PR comment** (updated in place on each push), so the numbers are visible even if Armour hasn't run. Armour quotes them (story 1).
  - **Exemption, enforced by CI rather than by who can label:** GitHub can't restrict who applies a label, since anyone with triage or write access can (and story 8 adds two write collaborators). So `ci-ok` **honors `coverage-exempt` only if the code owner applied it**:
    - **Precondition: the label is on the PR right now.** The job reads the PR's current labels (`gh pr view --json labels`) at run time. If `coverage-exempt` isn't there, the gate applies, whatever the event history says. Removing the label always restores the gate.
    - The coverage job reads the PR's issue events (`GET /repos/{owner}/{repo}/issues/{n}/events`, **all pages**: `gh api --paginate`), finds the **most recent `labeled` event for `coverage-exempt`**, and takes its `actor.login`
    - That login must be in the **exemption allowlist**: the `@username` entries on the **single line in `.github/CODEOWNERS` whose pattern is exactly `/.github/`** (today, @anthonythanpoovong), read from the file on `main`, not from the PR branch, so a PR can't add itself. This is a literal line match, **not** CODEOWNERS last-match-wins resolution, so area entries added in story 8 can't change who may exempt. If that line is missing or appears more than once, fail closed.
    - **Only plain `@username` entries count.** Team (`@org/team`) and email entries in that CODEOWNERS line are ignored, not expanded.
    - **Fail closed:** the exemption is ignored (the gate applies) if the actor can't be resolved (a deleted or "ghost" user, or a missing actor), if the actor is a bot (`actor.type == "Bot"`), if the allowlist has no plain `@username` entries, or if the events API call fails
    - If anyone else applied it, or it was removed and re-added by someone else, the gate **still applies**, and CI says who applied the label and why it was ignored
    - The job re-runs on `labeled` / `unlabeled` events as well as new commits, and it writes the exemption and approver into the job summary for the record
    - **An exemption covers only the commit it was given for.** On every new push (`synchronize`), a workflow step removes `coverage-exempt`, so new code must meet the gate or be re-exempted by the owner.
    - **Protecting the gate itself:** the check lives in `.github/workflows/ci.yml`, which a PR could edit. That's covered by CODEOWNERS on `/.github/` plus `main`'s required code-owner review: any PR that touches the workflow needs the owner's approval. Story 8's admin-bypass decision determines whether the owner's own PRs are also reviewed.
- **Acceptance criteria:**
  - [ ] A PR that adds untested code fails `ci-ok`; adding tests makes it pass
  - [ ] Docs-only PRs aren't affected
  - [ ] `coverage-exempt` applied by the code owner lets an under-covered PR pass; the same label applied by a non-owner collaborator is **ignored**, and the gate still fails with a message naming who applied it
  - [ ] Editing the CODEOWNERS allowlist in the PR itself doesn't change the result (the allowlist is read from `main`)
  - [ ] Fail closed: a label applied by a bot, or by an actor that can't be resolved, or an events API error, leaves the gate in force
  - [ ] Removing `coverage-exempt` (after the owner applied it) re-runs the job, and the gate applies again
  - [ ] Pushing a new commit to an exempted PR removes the label, and the gate applies to the new code
  - [ ] Adding an area line to CODEOWNERS (story 8) doesn't change who may exempt; only the exact `/.github/` line counts
  - [ ] Each push updates one sticky "Coverage" comment (no duplicates)
- **Depends on:** #48 (test jobs)

### 6. CONTRIBUTING.md + PR and issue templates
- **Labels:** `story`, `type:build`, `documentation`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** three people need one way of working, and the skills need a guide on when to use which.
- **Scope:**
  - **CONTRIBUTING.md:** branch naming (`story/<n>-slug`), commit style, PR size guidance, the proposal flow (`/grill` → `/propose-epic` / `/propose-adr`), which build skill to use when, review expectations, the coverage gate and exemptions, running `/sync-docs` after large merges
  - **PR template:** `Closes #n`, what changed, test evidence, coverage note, a "large change → run `/sync-docs` after merge" checkbox
  - **Issue templates:** bug and spike (stories come from proposals, so no blank story template)
- **Acceptance criteria:**
  - [ ] New PRs and issues open with the templates
  - [ ] CONTRIBUTING.md is linked from the README and the wiki
- **Depends on:** story 8 (review rules to document)

### 7. Pre-commit hooks
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** catch lint, format, secret and schema problems before they reach CI.
- **Scope:** `.pre-commit-config.yaml` with ruff + ruff-format (Python), prettier (web), **gitleaks**, and `check-jsonschema` for `schema/`. Use the same tools and versions as CI. Setup documented in CONTRIBUTING.md.
- **Acceptance criteria:**
  - [ ] `pre-commit run --all-files` passes on `main`
  - [ ] A committed fake secret is blocked locally
- **Depends on:** story 6 (docs)

### 8. Add teammates + review rules
- **Labels:** `story`, `type:build`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** only the owner is a collaborator, so nobody else can review. CODEOWNERS routes everything to one person.
- **Scope:**
  - Invite @calvinkafaiyuen and @sktchan as collaborators
  - Extend CODEOWNERS by area (e.g. `workers/`, `exporters/` → CV owners), keeping `.github/`, `.claude/`, `docs/decisions/` and `docs/epics/` with the owner
  - Decide on and record **admin bypass**: once two reviewers exist, turn on "enforce for admins" so owner PRs also need a review (or document why not)
- **Acceptance criteria:**
  - [ ] Both teammates accepted, and each has reviewed at least one PR
  - [ ] The admin-bypass decision is recorded in CONTRIBUTING.md
- **Depends on:** —

## Risks & costs

| Risk / cost | Likelihood / size | Mitigation |
|---|---|---|
| Armour skips on its own workflow PRs while this is being built | Certain | Story 2 ships first; test the others on a separate PR after merge |
| The coverage gate blocks an urgent fix | Medium | `coverage-exempt` label, honored by CI only when the labeling actor (from the issue events API) is a `/.github/` code owner per `main`'s CODEOWNERS |
| A collaborator self-exempts by applying the label | Medium (labels can't be permission-restricted) | Same check: a non-owner's label is ignored and logged |
| Eval PRs with deliberate bugs get merged | Low | Always drafts, labeled `armour-eval`, closed automatically, never merged |
| Pro usage from eval runs | Low | Manual trigger, only on rules or model change, ~5 reviews |
| `ARMOUR_EVAL_TOKEN` leaked or over-scoped | Low | Fine-grained, this repo only, contents + PRs only, used by one manual workflow, expiry set and rotated |
| Hooks slow down commits | Low | Fast hooks only; CI stays the source of truth |

Cost: $0 in tools. Pro usage for eval runs.

## Security & data

No schema, DB or MCP changes. Eval cases contain deliberate security bugs, isolated as described above. gitleaks runs locally (pre-commit) as well as in CI.

## Open questions

- **Admin bypass:** decided in story 8 once teammates are active.
- **Coverage for generated code:** exclude generated types (#2) from coverage. Confirm the paths when codegen lands.

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ | Mostly preventive; Armour gaps seen in #93/#94/#95/#112 |
| Smallest valuable version | ✅ | 8 stories; security scanning etc. deferred |
| Alternatives | ✅ | AI-estimated coverage, hosted services, overall gate: rejected |
| Fit with Key Decisions | ✅ | Deterministic first: CI measures, Armour reports |
| Data & schema | ✅ | None |
| Security & privacy | ✅ | Eval PRs isolated; gitleaks locally |
| Cost | ✅ | $0 tools; ~5 Sonnet reviews per eval run |
| Failure modes | ✅ | Exemption label checked against the labeling actor; skip notice first |
| Reversibility | ✅ | Two-way door |
| Observability | ✅ | Eval score history; coverage on every PR |
| Success metric | ✅ | Eval ≥ 4/5 + first 5 code PRs pass, by the Phase 0 gate |
| Effort & ownership | ⚠️ | Mostly the owner; teammates must accept invites |

</details>
