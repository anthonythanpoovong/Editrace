# Contributing to Editrace

For per-feature detail (architecture, CI and Armour, MCP, schema, skills), see the [Editrace wiki](https://github.com/editrace-app/Editrace/wiki). The plan is in [`docs/plan.md`](docs/plan.md).

## Ways of working

### Branches

Branch from an up-to-date `main`, one branch per issue.

| Kind of work | Branch name | Example |
| --- | --- | --- |
| Story or subtask | `story/<n>-slug` | `story/130-contributing-and-templates` |
| Spike (throwaway, never merged) | `spike/<n>-slug` | `spike/29-resolve-scripting` |
| Platform or tooling follow-up with no story | `platform/slug` | `platform/add-pr-template` |

`<n>` is the issue number. Use `/pick-up-story` to create the branch and a linked draft PR from an issue.

### Pre-commit hooks

Install once per clone:

```
pip install pre-commit
pre-commit install
```

From then on, every `git commit` runs ruff + ruff-format (Python), prettier (`web/`), gitleaks (secrets, anywhere in the repo), and check-jsonschema (`schema/`) against the files you're committing — the same tools CI runs, just earlier, so you find out before pushing instead of after.

- `pre-commit run --all-files` runs every hook against the whole repo on demand, not just staged files.
- A hook that **modifies** files (ruff `--fix`, prettier) fails that run on purpose — it's telling you it changed something. `git add` the result and commit again.
- Run `pre-commit autoupdate` occasionally to refresh the pinned hook versions in `.pre-commit-config.yaml` against each tool's own repo, rather than hand-editing version numbers.

### Commits

- Short, imperative subject line that says what changed: "Add pull request template", not "added stuff".
- Put the reason in the body when it isn't obvious from the diff.
- Reference the issue when it helps, e.g. `(#140 follow-up)`.
- Keep each commit to one logical change. Generated code (`make codegen`) goes in the same PR as the schema change that caused it.

### Pull requests

- Open a draft PR early. CI and Armour don't run on drafts (to save GitHub Actions minutes), so run the checks locally before marking it ready: `npm run lint`, `npm run typecheck` and `npm test` in `web/`, `make codegen` after a schema change, and `supabase test db` for migrations. Marking the PR ready runs CI and Armour once. After later pushes CI reruns automatically; add the `armour` label to ask Armour for another review.
- The PR template opens pre-filled. Use `Closes #n` so the issue closes on merge.
- **Keep PRs small.** Aim for under about 400 changed lines and one concern per PR. If a change is bigger, split it (schema first, then code that uses it) or say in the PR why it can't be split.
- A PR that changes how the system works for others (new service, schema or MCP contract change, new setup steps, CI changes, new skills) is a **large change**: tick the `/sync-docs` box in the template and run `/sync-docs` after it merges.

### Where new work comes from

Stories come from approved proposals, so there is no blank story template. To propose something:

1. **`/grill`**: stress-test the idea first. Both proposal skills run it for you.
2. **`/propose-epic`** for a new feature or body of work, or **`/propose-adr`** for a technical decision (stack, schema, API contract, anything that reverses a Key Decision). Each opens a PR.
3. The code owner approves the PR. Merging an epic PR is the approval, and the epic and story issues are created only after it.

If the grill says "Needs a spike first", use `/spike`. Bugs and spikes have issue templates; open them from **Issues → New issue**.

### What happens to a new issue

`project-intake.yml` runs on every new issue (#178). You do not add it to the board by hand.

- It is added to the [Project Board](https://github.com/orgs/editrace-app/projects/1) in the **current sprint** with Status **Backlog**. Between sprints it uses the next upcoming one; if no sprint exists, the run fails and comments on the issue. Create the next iteration on the board before a sprint ends.
- It gets any **missing labels**: a level (`subtask` if its parent is a story or subtask, otherwise `story`; being under an epic does not make it a subtask), `type:build`, and a domain/area from the issue form's Area answer. With no domain it gets `needs-triage`; set `platform`, `product` or `ml` and the workflow removes it. Labels you set yourself are never changed.
- It is assigned to whoever opened it, unless it already has an assignee or a bot opened it. Reopening does not reassign.
- A sprint or status that is already set is never overwritten, so moving a card is safe.
- Pull requests: `project-intake-pr.yml` assigns the author. A PR never gets a card of its own: only tickets are on the board, and a PR is tracked by the ticket it closes, so open it with `Closes #N`.
- To backfill open issues that are not on the board: **Actions → Project intake → Run workflow**.

**Marking tickets Done.** `project-done.yml` runs when a PR merges and sets Status Done for every ticket the PR closes (`Closes`/`Fixes`/`Resolves #n` at the start of a line in the PR body, or a link GitHub already shows), whatever the base branch. `Part of #n` does not count. A re-run changes nothing.

**Carrying over unfinished work.** `project-carry-over.yml` (Sprint carry-over) runs daily and, while a sprint is running, moves every open card that is not Done from an earlier sprint into the running one. Done cards, closed issues and PRs, cards with no sprint and cards on a later sprint stay put, and nothing moves between sprints. A re-run changes nothing. To preview: **Actions → Sprint carry-over → Run workflow** (*dry_run* is on by default). Locally: `DRY_RUN=true OWNER_TYPE=organization PROJECT_OWNER=editrace-app PROJECT_NUMBER=1 .github/scripts/project-carry-over.sh`.

It needs the secret `PROJECT_TOKEN`: a token with the `project` scope, because `GITHUB_TOKEN` cannot write to a user-owned project. It is Anthony's personal token. Note its expiry date when you create it and rotate it before then (**Settings → Secrets and variables → Actions**). A run that fails with "PROJECT_TOKEN expired, revoked or missing the project scope" means it needs replacing. If the repo moves to an organisation or the token owner changes, switch to a GitHub App.

### Which skill to use

| You are... | Use |
| --- | --- |
| Starting on an issue | `/pick-up-story` |
| Changing tables, columns, RLS or storage | `/db-migration` |
| Changing the template JSON Schema | `/schema-change` |
| Adding an analysis worker or detector | `/new-detector` |
| Checking a detector or the pipeline against the golden set | `/golden-eval` |
| Adding or changing an MCP server or Bridge tool | `/mcp-tool` |
| Building an editor adapter (Resolve, Premiere, Final Cut, CapCut) | `/editor-adapter` |
| Changing assistant prompts, retrieval or the docs corpus | `/rag-eval` |
| Answering a technical unknown | `/spike` |
| Recording a customer or user conversation | `/log-interview` |
| Updating README, `docs/plan.md` and the wiki after a big merge | `/sync-docs` |

## Review rules

Changes to `main` go through a pull request with one approving review, and that review must come from a code owner of every path the PR touches (see `.github/CODEOWNERS`).

Code ownership is shared: @anthonythanpoovong, @calvinkafaiyuen, @sktchan and @mikeleboss are listed on every path, including `/.github/`, `/.claude/` and `/docs/decisions/` (CI and review rules, the skills that enforce the proposal approval gate, and ADRs). Any of them can approve any PR (you can't approve your own). `@calvinkafaiyuen` and `@sktchan` are the primary reviewers for `workers/` and `exporters/` (CV).

### Admin bypass: none

Admins can't bypass the review requirement on `main`. Nobody, including the repo owner, can merge without the required code-owner approval. This is the "Do not allow bypassing the above settings" (enforce for admins) option in Settings → Branches, which the owner turns on once the PR that adds the second and third `/.github/` owners has merged.

**Why:** with a single `/.github/` owner, enforcing for admins would have blocked the owner's own PRs to those files, since nobody else could approve them. The three original collaborators are `/.github/` owners, so each can approve the others' changes.

**Coverage-exemption allowlist:** the allowlist for `/coverage-exempt` reviews (#129) is the plain `@username` entries on the `/.github/` line of CODEOWNERS. Adding `@calvinkafaiyuen` and `@sktchan` there also lets them grant coverage exemptions. This was a deliberate decision (#132). `@mikeleboss` (CV 3, added in #142) was added to the `/.github/` line at the repo owner's request, so he can grant coverage exemptions and approve CI and review-rule changes. He was also added to `/.claude/` and `/docs/decisions/`, so he can approve approval-gate skill and ADR changes too.

**Epic approval is intentionally delegated to `@mikeleboss`:** merging an epic PR is the approval, and `propose-epic` creates the issues only after it, so as an owner of `/docs/epics/` he can approve a new epic without any of the three original owners. The repo owner chose this on 2026-09-30 (#142) because he owns the footage match and format benchmark epic. He is also an owner of `/docs/decisions/`, so he can approve ADRs, which cover one-way-door decisions. Revisit with the owner list above.

**If you change `/.github/` owners:** keep it as one line with pattern exactly `/.github/` and plain `@username` entries, and treat it as a change to who may exempt the coverage gate.

## Coverage gate and exemptions

Changed lines must be at least 80% covered by tests (#129). SQL migrations and RLS policies are outside the gate, since the two-user RLS test covers them (`/db-migration`). Generated code and docs-only PRs are excluded too. The gate runs inside the `ci-ok` check and leaves a sticky "Coverage" comment on the PR.

If a PR can't reasonably meet the threshold, a `/.github/` code owner can exempt it:

1. The owner submits a PR review (a plain "Comment" review works, so they can exempt their own PR) whose body starts with `/coverage-exempt` followed by the reason.
2. The owner **re-runs the failed `ci-ok` job** (`gh run rerun --failed <run-id>`, or from the Actions tab). The gate reads reviews live, so the re-run picks up the exemption.

To withdraw it, the owner submits another review starting `/coverage-revoke`. The latest of the two on the commit wins. Pushing a new commit ends the exemption, because it only applies to the commit it was submitted on. A `coverage-exempt` label does nothing.

### How the gate measures

- **Web:** `npm test -- --coverage` (Vitest, config in `web/vitest.config.ts`) writes `web/coverage/lcov.info`. Every file under `app/`, `lib/` and `components/` is listed, so a new file nobody tests shows as 0%, not as missing. `npm run test:coverage` does the same locally.
- **Python:** `pytest --cov --cov-config=.github/coveragerc` writes `coverage.xml`. A Python file no test imports also shows as 0%.
- **Excluded:** generated code (`web/lib/generated/`, `editrace_schema/models.py`) and test files. SQL isn't in any report.
- **Where it runs:** the `coverage` job measures the lines the PR changed (`diff-cover` against `main`) and posts the comment; it never fails over low coverage. The decision, including the exemption, is made in `ci-ok`, which is why the exemption steps above re-run `ci-ok`.
- **A bot or an unreadable review leaves the gate on.** If CI can't read the PR's reviews, the head commit or `CODEOWNERS` on `main`, it says so and the gate applies.
