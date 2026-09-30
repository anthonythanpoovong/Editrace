# Contributing to Editrace

## Review rules

Changes to `main` go through a pull request with one approving review, and that review must come from a code owner of every path the PR touches (see `.github/CODEOWNERS`).

Code ownership is shared: @anthonythanpoovong, @calvinkafaiyuen and @sktchan are listed on every path, so any of them can approve any PR (you can't approve your own). `@calvinkafaiyuen` and `@sktchan` are the primary reviewers for `workers/` and `exporters/` (CV).

### Admin bypass: none

Branch protection on `main` is enforced for admins too. Nobody, including the repo owner, can merge without the required code-owner approval.

**Why:** with a single `/.github/` owner, enforcing for admins would have blocked the owner's own PRs to those files, since nobody else could approve them. All three collaborators are now `/.github/` owners, so each can approve the others' changes.

**Coverage-exemption allowlist:** the allowlist for `/coverage-exempt` reviews (#129) is the plain `@username` entries on the `/.github/` line of CODEOWNERS. Adding `@calvinkafaiyuen` and `@sktchan` there also lets them grant coverage exemptions. This was a deliberate decision (#132).

**If you change `/.github/` owners:** keep it as one line with pattern exactly `/.github/` and plain `@username` entries, and treat it as a change to who may exempt the coverage gate.
