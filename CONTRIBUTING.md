# Contributing to Editrace

## Review rules

Changes to `main` go through a pull request with one approving review, and that review must come from a code owner of every path the PR touches (see `.github/CODEOWNERS`).

Code ownership is shared: @anthonythanpoovong, @calvinkafaiyuen, @sktchan and @mikeleboss are listed on every path, so any of them can approve any PR (you can't approve your own). `@calvinkafaiyuen` and `@sktchan` are the primary reviewers for `workers/` and `exporters/` (CV).

### Admin bypass: none

Admins can't bypass the review requirement on `main`. Nobody, including the repo owner, can merge without the required code-owner approval. This is the "Do not allow bypassing the above settings" (enforce for admins) option in Settings → Branches, which the owner turns on once the PR that adds the second and third `/.github/` owners has merged.

**Why:** with a single `/.github/` owner, enforcing for admins would have blocked the owner's own PRs to those files, since nobody else could approve them. All four collaborators are now `/.github/` owners, so each can approve the others' changes.

**Coverage-exemption allowlist:** the allowlist for `/coverage-exempt` reviews (#129) is the plain `@username` entries on the `/.github/` line of CODEOWNERS. Adding `@calvinkafaiyuen`, `@sktchan` and `@mikeleboss` there also lets them grant coverage exemptions. This was a deliberate decision (#132 for Calvin and Serena; Mike was added the same way).

**If you change `/.github/` owners:** keep it as one line with pattern exactly `/.github/` and plain `@username` entries, and treat it as a change to who may exempt the coverage gate.
