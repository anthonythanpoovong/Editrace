---
name: propose-epic
description: Turn a new idea or implementation into a Sequa epic proposal (goal, exit criteria, stories) and open it for approval; after approval, create the epic and story issues on GitHub. Use when someone has a new feature idea, says "propose an epic", "I want to build X", "scope this out", or asks to create issues for an approved proposal. Grills the author first; no issues are created until the code owner approves.
---

# Propose an epic

Sequa organizes work as **Epic → Story → Subtask** (labels `epic` / `story` / `subtask`, GitHub sub-issues, phases as milestones). A new epic starts as a proposal file in `docs/epics/` and becomes GitHub issues **only after** the code owner approves and merges it.

## Workflow

### 1. Grill
Load the `grill` skill and run it in full. Focus on areas 1 (problem and evidence), 2 (smallest valuable version), 7 (cost), 11 (success metric) and 12 (effort and ownership).

Stop if the verdict is "Needs a spike first" or "Not worth pursuing". Offer `/spike` to open a time-boxed spike instead.

### 2. Check overlap and decisions
- Compare with the existing epics (`gh issue list --label epic --state all`) and `docs/plan.md` → Epics. If it fits inside an existing epic, propose **stories** for that epic instead, and ask the author.
- If the epic depends on an unmade one-way-door decision (schema change, new service, reversing a Key Decision), that needs an ADR first. Offer `propose-adr` and link the ADR from the epic.

### 3. Break it down
With the author, write 3–8 stories. Each story must:
- Be shippable and testable on its own.
- Have acceptance criteria as checkboxes.
- Have one owner, a phase and labels: one `type:*`, one or more `area:*`, one role label (`ml` / `platform` / `product`), and `risk:*` if relevant.
- List dependencies (`#n` or another story in this proposal).

Push back on stories that are really epics ("build the Premiere adapter") or tasks ("add a button").

### 4. Draft
- Filename: `docs/epics/kebab-title.md`, copied from `docs/epics/TEMPLATE.md`.
- Fill every section **from the author's answers**. Don't invent numbers or evidence; unknowns go under **Open questions**.
- `Status: Proposed`, today's date, author handle, and the grill scorecard.
- Show the full draft and revise until the author is happy. **Don't open a PR without their explicit go-ahead.**

### 5. Open for approval
```sh
git fetch origin main
git checkout -b epic/kebab-title origin/main
git add docs/epics/kebab-title.md
git commit -m "Epic proposal: <title>"
git push -u origin epic/kebab-title
gh pr create --draft --label proposal,epic \
  --title "Epic proposal: <title>" \
  --body "<summary + story list + grill scorecard + 'Approval = code-owner review and merge'>"
```
Tell the author: mark it **Ready for review** when discussion is done. It merges only with code-owner approval (CODEOWNERS covers `docs/epics/`). **No issues exist yet.**

### 6. After approval: create the issues
Only when asked, and only if **all** of these hold (otherwise stop and say which failed):
- The proposal PR is merged: `gh pr view <n> --json state` → `MERGED`. Merging is the approval. The file still says `Proposed`, because `main` dismisses approvals on new commits, so status is flipped afterwards in step 6.5.
- The proposal file exists on `origin/main` and says `Status: Proposed`. A merged `Rejected` file is a record, not an approval.
- The epic doesn't already exist (search issues for its title).

Then:
1. Create the epic issue with label `epic`, in the existing epic format: `## Goal`, `## Exit criteria`, `## Owner`, `## Stories` (filled in at step 3), and a link to the proposal file.
2. Create each story with label `story` + its labels, in the existing story format: `## Context`, `## Scope`, `## Acceptance criteria`, `## Depends on`, `## Owner`. Set the milestone for its phase if one exists.
3. Link each story as a sub-issue of the epic:
   ```sh
   gh api repos/{owner}/{repo}/issues/<epic>/sub_issues -X POST -F sub_issue_id=<story issue id, not number>
   ```
4. Edit the epic body to list the stories, and add both to the project board if possible (`gh project item-add 2 --owner anthonythanpoovong --url <issue url>`).
5. On a new branch, update the proposal file: `Status: Accepted`, the epic number, and the story numbers. Add the epic to the Epics table in `docs/plan.md`. Open a normal PR.

Show the author the list of issues before creating them and get a yes. Creating issues notifies the team.

## Rules
- Never create epic or story issues from an unmerged proposal.
- Never merge the proposal PR yourself.
- To record a rejection (a closed PR never reaches `main`): on the proposal branch, set `Status: Rejected`, add a **Rejection reason** section and have the code owner merge it. For trivial ideas, just closing the PR is fine.
