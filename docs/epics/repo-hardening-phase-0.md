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

**Suggested ship order** (story numbers don't follow dependencies): **2** (skip notice) and **8** (teammates accept invites slowly) first, then **5** (coverage gate), **1** (files + coverage in reviews), **4** (eval set), **3** (sharper rules, scored by the eval set), then **6** (CONTRIBUTING, needs the review rules from 8) and **7** (pre-commit, documented in 6).

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
- **Context:** Armour exits "successfully" without reviewing when the PR changes its workflow or when the action errors or hits a usage limit, and nobody can tell.
- **Scope:**
  - A **separate job in `ai-review.yml` that always runs** (`if: always()`, `needs: review`), because a step inside the review job never runs when that job is skipped or fails early. It checks the review job's result and the action's log/outputs, and detects a skip (workflow validation, error, usage limit).
  - It posts or updates one **sticky notice comment**, marked with a hidden HTML marker, saying "⚠️ Editrace Armour did not review this commit: <reason>". When Armour later reviews the PR, the notice is deleted or replaced. **The "exactly one top-level comment" rule in the Armour prompt is about reviews; this notice is separate and never both exist for the same commit.**
  - **Forks are out of scope:** the repo is private, and fork PRs get a read-only token that can't post comments anyway (the alternative, `pull_request_target`, would run with secrets against untrusted code, so we don't).
- **Acceptance criteria:**
  - [ ] A PR that edits `ai-review.yml` gets the skip notice
  - [ ] A normal PR gets no notice, and after a real review any earlier notice for that PR is gone
  - [ ] The notice is posted even when the review job itself is skipped or fails
- **Depends on:** —
- **Note:** ship this **first**. **This story's own PR edits `ai-review.yml`, so Armour skips it and it needs a manual review.** The same goes for any later story that edits `ai-review.yml` (e.g. story 1's wait step), but once this story is merged, those PRs at least show the skip notice.

### 3. Armour: sharper review rules
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** `armour.md` predates coverage data and the team's skills.
- **Scope:** add rules to `.github/armour.md` for:
  - **Uncovered risky logic:** changed lines with auth, billing, time conversion or cost limits that CI's coverage report shows as uncovered (Python and TypeScript only)
  - **Migrations and RLS (SQL) aren't in the coverage report**, so the rule differs: flag a PR that adds or changes a migration or RLS policy **without a matching two-user RLS test** (the `/db-migration` requirement, #49)
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
  - **The runner opens PRs with a dedicated token, not the default `GITHUB_TOKEN`.** Events caused by `GITHUB_TOKEN` don't trigger other workflows, so Armour would never run on the eval PRs. Use a fine-grained PAT (or GitHub App token) scoped to this repo only (contents + pull requests: read/write), with an expiry.
  - **Store it as an environment secret, not a repo secret.** A repo secret is readable by any workflow on any branch, so a collaborator could push a workflow that leaks it (story 8 adds two write collaborators). Create an environment `armour-eval` with **deployment branches limited to `main`** and a **required reviewer (the code owner)**, put `ARMOUR_EVAL_TOKEN` there, and have the runner job declare `environment: armour-eval`. Workflows on other branches can't read it, and each run waits for the owner's approval.
  - **Check the plan first:** environment protection rules (required reviewers, branch limits) on **private** repos need a paid GitHub plan (Pro, Team or Enterprise). If the account doesn't have one, fall back to running the eval **locally by the owner** (`gh workflow run` with the token in the owner's own shell), and keep the token off the repo entirely.
  - Run only when `armour.md` or the Armour model changes (bounded Pro usage: about 5 reviews per run)
- **Acceptance criteria:**
  - [ ] One command runs all 5 cases and reports a score
  - [ ] Eval PRs are never merged, and are closed automatically
  - [ ] Score recorded for the current rules and model (target ≥ 4/5)
  - [ ] Armour actually runs on every eval PR (PRs opened with `ARMOUR_EVAL_TOKEN`, not `GITHUB_TOKEN`)
  - [ ] `ARMOUR_EVAL_TOKEN` exists only as an `armour-eval` environment secret (main-only, owner approval required), or the eval runs locally; a workflow on a non-`main` branch can't read it
- **Depends on:** story 2

### 5. CI: changed-line coverage gate (80%)
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 0
- **Context:** without a gate, untested code merges. Gating only **changed** lines avoids punishing unrelated PRs.
- **Scope:**
  - Collect coverage in the existing CI jobs: `pytest --cov` (Python), Vitest/Jest coverage (web)
  - Use **`diff-cover`** on the coverage reports vs `main`: **fail when changed lines are < 80% covered**
  - Switches on automatically via the existing `detect` job (only when `web/` or Python code exists)
  - **SQL (migrations, RLS policies) is outside the coverage gate**: it's tested by the two-user RLS harness (#49, `/db-migration`), not by line coverage. Generated code (#2) is excluded too.
  - Publish a coverage summary (overall %, change vs `main`, changed-lines %) as **check output** and as a **sticky "Coverage" PR comment** (updated in place on each push), so the numbers are visible even if Armour hasn't run. Armour quotes them (story 1).
  - **Exemption: the owner's PR review, checked by CI.** A label can't carry this authority: anyone with triage or write access can apply one (and story 8 adds two write collaborators), a commit status or stored record can be created by any collaborator, and even a check run can be faked by a workflow on a collaborator's own branch. So the exemption rests on something **GitHub records itself**: a **pull request review**. Every review carries the **exact commit SHA it was submitted on** (`commit_id`, set by GitHub), and only its author can submit it. `ci-ok` honors an exemption only when **all** of these hold, checked against `GET /repos/{owner}/{repo}/pulls/{n}/reviews` (**all pages**: `gh api --paginate`):
    - The review's **`commit_id` equals the PR's current head SHA**, read at gate time. A new push changes the head SHA, so an old exemption stops applying on its own, with no label to clear and no race with the coverage job.
    - The review's **body starts with `/coverage-exempt`**, followed by a reason. A "Comment" review works, so the owner can exempt their own PR (GitHub doesn't allow approving your own PR).
    - The review's **state isn't `DISMISSED`**. Dismissing the review revokes the exemption.
    - The **author is in the exemption allowlist**: the plain `@username` entries on the **single line in `.github/CODEOWNERS` whose pattern is exactly `/.github/`** (today, @anthonythanpoovong), read from the file on `main`, not from the PR branch. It's a literal line match, **not** CODEOWNERS last-match-wins, so area entries added in story 8 can't change who may exempt. Team (`@org/team`) and email entries are ignored, not expanded.
    - **Fail closed:** if the review author is a bot or can't be resolved, if the `/.github/` line is missing or duplicated, if the allowlist has no plain `@username` entries, or if the API call fails, the exemption is ignored and the gate applies. CI says why.
    - A **label named `coverage-exempt` has no effect at all.**
    - The job re-runs when a review is submitted or dismissed (`pull_request_review` events) and writes the exemption (reviewer, reason, SHA) into the job summary. Story 5 must confirm the re-run's result attaches to the head SHA; if it doesn't, the owner re-runs the failed job after reviewing.
    - **Threat model, stated plainly:** this stops accidental or casual self-exemption by trusted collaborators, and it doesn't depend on anything a collaborator can create (labels, statuses, comments). It can't stop a *malicious* insider with write access: on GitHub any workflow, including one pushed on a collaborator's own branch, can create a check named `ci-ok`. Write access is therefore treated as trusted. If that changes, move the gate to a repository ruleset with required workflows.
    - **Protecting the gate itself:** the check lives in `.github/workflows/ci.yml`, which a PR could edit. That's covered by CODEOWNERS on `/.github/` plus `main`'s required code-owner review: any PR that touches the workflow needs the owner's approval. Story 8's admin-bypass decision determines whether the owner's own PRs are also reviewed.
- **Acceptance criteria:**
  - [ ] A PR that adds untested code fails `ci-ok`; adding tests makes it pass
  - [ ] Docs-only PRs aren't affected
  - [ ] An owner "Comment" review starting `/coverage-exempt <reason>` on the current head commit lets an under-covered PR pass, and the job summary records reviewer, reason and SHA
  - [ ] The same review by a non-owner collaborator is **ignored**, and the gate still fails with a message naming the reviewer
  - [ ] A `coverage-exempt` **label** has no effect
  - [ ] Pushing a new commit makes the gate apply to the new code again (the review is bound to the old SHA)
  - [ ] Dismissing the owner's review restores the gate
  - [ ] Editing the CODEOWNERS allowlist in the PR itself doesn't change the result (read from `main`), and adding an area line (story 8) doesn't change who may exempt
  - [ ] Fail closed: a bot or unresolvable reviewer, a missing or duplicated `/.github/` line, or an API error leaves the gate in force
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
| The coverage gate blocks an urgent fix | Medium | Owner's `/coverage-exempt` PR review, bound to the head SHA and honored by CI only when its author is the `/.github/` code owner per `main`'s CODEOWNERS |
| A collaborator self-exempts (label, status or comment tricks) | Medium | Only the owner's PR review counts: GitHub sets its author and commit; labels, statuses and comments have no effect |
| A malicious insider with write access forges `ci-ok` | Low | Out of scope by threat model; write access is trusted. Move to a ruleset with required workflows if that changes |
| Eval PRs with deliberate bugs get merged | Low | Always drafts, labeled `armour-eval`, closed automatically, never merged |
| Pro usage from eval runs | Low | Manual trigger, only on rules or model change, ~5 reviews |
| `ARMOUR_EVAL_TOKEN` leaked or over-scoped | Low | Fine-grained, this repo only, contents + PRs only; stored as an environment secret limited to `main` with the owner as required reviewer (or kept local if the plan doesn't allow it); expiry set and rotated |
| Hooks slow down commits | Low | Fast hooks only; CI stays the source of truth |

Cost: $0 in tools. Pro usage for eval runs.

## Security & data

No schema, DB or MCP changes. Eval cases contain deliberate security bugs, isolated as described above. gitleaks runs locally (pre-commit) as well as in CI.

## Open questions

- **Admin bypass:** decided in story 8 once teammates are active.
- **Coverage for generated code:** exclude generated types (#2) from coverage. Confirm the paths when codegen lands.
- **How Armour waits for coverage (story 1):** a bounded poll keeps a runner idle for up to ~10 min per push, which counts against private-repo Actions minutes. Prefer triggering Armour when the coverage job completes (`workflow_run`) if `claude-code-action` supports that context. Otherwise keep the poll, but short. Decide during implementation.

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
| Failure modes | ✅ | Exemption via the owner's PR review bound to the head SHA; skip notice first |
| Reversibility | ✅ | Two-way door |
| Observability | ✅ | Eval score history; coverage on every PR |
| Success metric | ✅ | Eval ≥ 4/5 + first 5 code PRs pass, by the Phase 0 gate |
| Effort & ownership | ⚠️ | Mostly the owner; teammates must accept invites |

</details>
