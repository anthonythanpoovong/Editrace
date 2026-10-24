---
name: pick-up-story
description: Start work on an Editrace story or subtask issue — check it's ready (dependencies closed, owner, acceptance criteria), create the branch, turn acceptance criteria into a checklist, and open a draft PR linked to the issue. Use when someone says "pick up #N", "start on story N", "what should I work on next", or "work on #N".
---

# Pick up a story

Gets from an approved issue to a draft PR that's linked to it, with nothing forgotten.

## 1. Choose (if no issue was named)
Suggest ready work for the person:
```sh
gh issue list --label story --state open --assignee @me
gh issue list --label story --state open --search "no:assignee"
```
Prefer the current milestone's phase, `risk:quick-win`, and stories whose dependencies are all closed. Don't pick for them. Show 3 options with a reason each.

## 2. Readiness check
Read the issue: `gh issue view <n>`. Then check:
- **It's a story or subtask**, not an epic. For an epic, list its open sub-issues instead.
- **Dependencies:** for every `#n` under "Depends on", check `gh issue view <dep> --json state`. If any is open, stop and say which ones block it. Offer to help with the blocker instead.
- **Acceptance criteria** exist as checkboxes. If they're vague ("works well"), ask the author to sharpen them before starting.
- **Owner:** if it's unassigned, or assigned to someone else, confirm with the person before taking it.
- **Needs a decision?** If the scope implies a breaking schema change or a Key Decision change, stop → `/schema-change` or `/propose-adr`.

Also search `docs/learnings/` (`grep -ril "<keyword>" docs/learnings`) for the story's area, and surface any relevant notes to the person before they start.

## 3. Start
```sh
gh issue edit <n> --add-assignee @me
git fetch origin main
git checkout -b story/<n>-<short-slug> origin/main
git commit --allow-empty -m "Start #<n>: <title>"
git push -u origin story/<n>-<short-slug>
gh pr create --draft --base main \
  --title "<title> (#<n>)" \
  --body "## Summary
<1-3 plain sentences: what this PR does and why. The Discord review request quotes this.>

Closes #<n>

## Acceptance criteria
<copy each checkbox from the issue>

## Plan
<3–6 bullet implementation plan>

## Notes
<decisions, open questions>"
```
Move the item to "In progress" on the project board if the board has that status.

## 4. Point to the right skill
Based on the story's area, tell the person which skill fits:
- Schema fields → `/schema-change`
- New worker or detector → `/new-detector`, then `/golden-eval`
- DB table or RLS → `/db-migration`
- MCP tool → `/mcp-tool`
- Editor adapter → `/editor-adapter`
- Assistant, prompts or retrieval → `/rag-eval`

## 5. Finishing (when asked)
Ask whether the work taught the team anything worth keeping (a gotcha, a failed approach, a surprise). If so, add a note to `docs/learnings/` from `TEMPLATE.md` and the index, in this PR. Then tick the PR checklist from real evidence: tests or eval output, not claims. Mark the PR ready for review. `Closes #<n>` closes the issue on merge. If the story changed something large, remind them to run `/sync-docs` after merge.

## Rules
- Never start a story whose dependencies are open without the author explicitly accepting the risk.
- One story per branch or PR.
