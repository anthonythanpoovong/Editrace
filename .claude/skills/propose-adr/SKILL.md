---
name: propose-adr
description: Draft an Architecture Decision Record for Sequa and open it for approval. Use when someone wants to make or change a technical decision (stack choice, schema change, API contract, new service, reversing a Key Decision), says "write an ADR", "propose a decision", or when a grill verdict says the idea is a one-way door. Grills the author first; the ADR stays Proposed until the code owner approves the PR.
---

# Propose an ADR

An ADR records **one** decision: the context, the options, what we chose and what it costs us. It lives in `docs/decisions/NNNN-short-title.md` and starts as **Proposed**. It becomes **Accepted** only when the code owner approves and merges its PR.

## Workflow

### 1. Grill
Load the `grill` skill and run it in full. Focus on areas 3 (alternatives), 4 (fit with Key Decisions), 5 (data and schema), 9 (reversibility) and 7 (cost). An ADR without two real alternatives isn't an ADR, so keep asking until there are at least two.

Stop if the verdict is "Needs a spike first" or "Not worth pursuing". Offer to open a `type:spike` issue instead.

### 2. Check scope
One ADR = one decision. If the idea contains several decisions (e.g. "use Python for the Bridge **and** ship it via Homebrew"), split it and ask which to write first. If the idea is really a body of work rather than a decision, switch to `propose-epic`.

### 3. Draft
- Next number: take the highest `NNNN` in `docs/decisions/` and add 1. Zero-pad to 4 digits. `0000-template.md` doesn't count.
- Filename: `docs/decisions/NNNN-kebab-title.md`.
- Copy `docs/decisions/0000-template.md` and fill in every section **from the author's grill answers**. Don't invent facts, numbers or evidence. Anything unknown goes under **Open questions**.
- `Status: Proposed`, today's date, the author's GitHub handle, and links to related issues/ADRs.
- If it supersedes an ADR, add `Supersedes: NNNN` here. Don't edit the old ADR yet; that happens after approval.
- Show the full draft to the author and revise until they're happy. **Don't open a PR without their explicit go-ahead.**

### 4. Open for approval
```sh
git checkout -b adr/NNNN-kebab-title origin/main
git add docs/decisions/NNNN-kebab-title.md
git commit -m "ADR NNNN: <title> (proposed)"
git push -u origin adr/NNNN-kebab-title
gh pr create --draft --label proposal,adr \
  --title "ADR NNNN: <title>" \
  --body "<summary + grill scorecard + 'Approval = code-owner review and merge'>"
```
Tell the author: the PR is a draft. Mark it **Ready for review** when discussion is done. It merges only with code-owner approval (CODEOWNERS covers `docs/decisions/`).

### 5. After approval (only when asked, and only once merged)
Check the PR is merged: `gh pr view <n> --json state` must be `MERGED`. If it isn't, stop. Merging is the approval. Status isn't flipped inside the proposal PR, because `main` dismisses approvals on new commits. Then, on a new branch:
- Set `Status: Accepted` and the accepted date.
- If it supersedes an ADR, set the old one to `Status: Superseded by NNNN`.
- If it changes a Key Decision, update `docs/plan.md` to match.
- Open a normal PR with those changes.

If a proposal PR is closed without merging, set `Status: Rejected` with the reason. Rejected ADRs are kept; they stop the same debate happening twice.

## Rules
- Never set `Accepted` on an unmerged ADR, and never merge the PR yourself.
- Never edit the decision of an Accepted ADR. Write a new one that supersedes it.
- Keep it under about 2 pages. Detail goes in linked issues or docs.
