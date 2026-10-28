---
name: draft-stories
description: Draft new story issues into an existing Editrace epic — pick the epic, check for overlap, write stories in the repo's story format with labels, owner, phase and dependencies, then create them as sub-issues of the epic after the author confirms. Use when someone says "add a story to epic N", "draft issues for the X epic", "we forgot a ticket in <epic>", or "file this under the Engineering foundations epic". For a brand-new epic use propose-epic instead.
---

# Draft stories into an existing epic

Adds stories to an epic that already exists (labels `epic` / `story`, GitHub sub-issues, phases as milestones). Nothing is created on GitHub until the author says yes: creating issues notifies the team.

## 1. Choose the epic
- If no epic was named, list them: `gh issue list --label epic --state all --json number,title,state`. Suggest the best fit by title and goal; don't pick silently.
- Read it: `gh issue view <epic>` (Goal, Exit criteria, Owner, Stories) and its sub-issues: `gh api repos/{owner}/{repo}/issues/<epic>/sub_issues -q '.[]|"\(.number) \(.state) \(.title)"'`.
- If the epic is **closed**, say so and ask whether to reopen it or use a newer epic.
- If the idea doesn't serve the epic's Goal or Exit criteria, it's a new epic: stop and offer `propose-epic`.
- If the work changes the epic's Goal or Exit criteria, or adds more than about 3 stories, it needs the proposal route (`propose-epic`, as #124 did for repo hardening). Say why and ask.

## 2. Check overlap
Search open and closed issues for the same work: `gh issue list --state all --search "<keywords>" --json number,title,state`. If a story already covers it, offer to edit that one instead. Never create a duplicate.

## 3. Draft each story
Fill everything **from the author's answers**; don't invent evidence. Unknowns go in the body as a question. Each story must be shippable and testable on its own: push back on stories that are really epics ("build the Premiere adapter") or tasks ("add a button").

Body, in the existing story format:
```
## Scope
- <what is in, as bullets>

## Acceptance criteria
- [ ] <checkable, specific>

## Depends on
#<n> (or "None")

## Owner
<github handle>
```
Metadata:
- **Title:** plain and specific; a follow-up to another ticket ends with `(#n)` as existing ones do.
- **Labels:** `story`, exactly one `type:*` (`type:build` / `type:research` / `type:spike`), one or more `area:*`, one role label (`ml` / `platform` / `product`), and `risk:*` if relevant. Use only labels that exist: `gh label list`.
- **Milestone:** the phase (`gh api repos/{owner}/{repo}/milestones -q '.[].title'`). Default to the phase the epic's other open stories use, and say so.
- **Depends on:** check each `#n` exists. If a dependency is closed, say so.
- **Owner:** ask; don't assume.

## 4. Confirm
Show the full drafts (title, labels, milestone, body) and the epic they go into. Revise until the author says yes. Don't create anything before that.

## 5. Create
For each story:
```sh
gh issue create --title "<title>" --label "story,<other labels>" --milestone "<phase>" --assignee <owner> --body-file <file>
gh api repos/{owner}/{repo}/issues/<story> -q .id          # numeric id, not the issue number
gh api repos/{owner}/{repo}/issues/<epic>/sub_issues -X POST -F sub_issue_id=<id>
gh project item-add 1 --owner editrace-app --url <story url>
```
Then add the new story numbers to the epic's `## Stories` or equivalent list, keeping the rest of its body exactly as is (`gh issue edit <epic> --body-file`). Pull requests don't go on the board: only these story issues.

## 6. Report
List the created issues with links, the epic, and anything left unresolved (open questions, unassigned owner).

## Rules
- Never create stories in a closed epic, or an epic itself, from this skill.
- Never create an issue the author hasn't seen and approved.
- Never edit other people's stories except to link or fix a dependency the author asks for.
- Keep the epic's Goal and Exit criteria untouched; changing them goes through `propose-epic`.
