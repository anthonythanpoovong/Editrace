---
name: propose-adr
description: Draft an Architecture Decision Record for Editrace and open it for approval. Use when someone wants to make or change a technical decision (stack choice, schema change, API contract, new service, reversing a Key Decision), says "write an ADR", "propose a decision", or when a grill verdict says the idea is a one-way door. Grills the author first; the ADR stays Proposed until the code owner approves the PR.
---

# Propose an ADR

An ADR records **one** decision: the context, the options, what we chose and what it costs us. It lives in `docs/decisions/NNNN-short-title.md` and starts as **Proposed**. It becomes **Accepted** only when the code owner approves and merges its PR.

## Workflow

### 1. Grill
Load the `grill` skill and run it in full. Focus on areas 3 (alternatives), 4 (fit with Key Decisions), 5 (data and schema), 9 (reversibility) and 7 (cost). An ADR without two real alternatives isn't an ADR, so keep asking until there are at least two.

Stop if the verdict is "Needs a spike first" or "Not worth pursuing". Offer `/spike` to open a time-boxed spike instead.

### 2. Check scope
One ADR = one decision. If the idea contains several decisions (e.g. "use Python for the Bridge **and** ship it via Homebrew"), split it and ask which to write first. If the idea is really a body of work rather than a decision, switch to `propose-epic`.

### 3. Draft
- Next number: take the highest `NNNN` across **both** `docs/decisions/` on `origin/main` **and** open ADR PRs (`gh pr list --label adr --state open --json title`, titles start `ADR NNNN:`), then add 1. Zero-pad to 4 digits. `0000-template.md` doesn't count. If a collision still happens at merge, renumber the later PR.
- Filename: `docs/decisions/NNNN-kebab-title.md`.
- Copy `docs/decisions/0000-template.md` and fill in every section **from the author's grill answers**. Don't invent facts, numbers or evidence. Anything unknown goes under **Open questions**.
- `Status: Proposed`, today's date, the author's GitHub handle, and links to related issues/ADRs.
- If it supersedes an ADR, add `Supersedes: NNNN` here. Don't edit the old ADR yet; that happens after approval.
- Show the full draft to the author and revise until they're happy. **Don't open a PR without their explicit go-ahead.**

### 4. Open for approval
```sh
git fetch origin main
git checkout -b adr/NNNN-kebab-title origin/main
git add docs/decisions/NNNN-kebab-title.md
git commit -m "ADR NNNN: <title> (proposed)"
git push -u origin adr/NNNN-kebab-title
gh pr create --draft --label proposal,adr \
  --title "ADR NNNN: <title>" \
  --body "<summary + grill scorecard + 'Approval = code-owner review and merge'>"
```
Then start the discussion thread in the **ADR** category of GitHub Discussions, so the team can talk it through, and link the two:
```sh
read -r REPO_ID OWNER NAME < <(gh repo view --json id,owner,name --jq '[.id,.owner.login,.name]|@tsv')
CAT_ID=$(gh api graphql -f query='query($o:String!,$n:String!){repository(owner:$o,name:$n){discussionCategories(first:20){nodes{id name}}}}' \
  -f o="$OWNER" -f n="$NAME" --jq '.data.repository.discussionCategories.nodes[]|select(.name=="ADR").id')
if [ -n "$CAT_ID" ]; then
  # Write the title and body with a quoted heredoc so backticks and $(...) in the ADR text are not expanded.
  TMP=$(mktemp -d)
  cat > "$TMP/title" <<'EOF_TITLE'
ADR NNNN: <title>
EOF_TITLE
  cat > "$TMP/body" <<'EOF_BODY'
<decision in short, options, open questions, PR link>
EOF_BODY
  gh api graphql -f query='mutation($r:ID!,$c:ID!,$t:String!,$b:String!){createDiscussion(input:{repositoryId:$r,categoryId:$c,title:$t,body:$b}){discussion{url}}}' \
    -f r="$REPO_ID" -f c="$CAT_ID" -F t=@"$TMP/title" -F b=@"$TMP/body" \
    --jq '.data.createDiscussion.discussion.url'
  gh pr comment <pr-number> --body "Discussion thread for this ADR: <discussion-url>"
fi
```
The body is the decision in short, the options, the open questions and the PR link, and says approval happens on the PR. If there is no `ADR` category (empty `CAT_ID`), the guard skips the thread and the PR comment; tell the author. Never create the discussion with an empty category ID.

Tell the author: the PR is a draft and the discussion thread is open. Mark the PR **Ready for review** when discussion is done. It merges only with code-owner approval (CODEOWNERS covers `docs/decisions/`).

### 5. After approval (only when asked, and only once merged)
Check the PR is merged (`gh pr view <n> --json state` must be `MERGED`) and the file on `origin/main` still says `Status: Proposed`. A merged `Rejected` file is a record, not an approval. If either check fails, stop. Merging a Proposed ADR is the approval. Status isn't flipped inside the proposal PR, because `main` dismisses approvals on new commits. Then, on a new branch:
- Set `Status: Accepted` and the accepted date.
- If it supersedes an ADR, set the old one to `Status: Superseded by NNNN`.
- If it changes a Key Decision, update `docs/plan.md` to match.
- Update the **Index** table in `docs/decisions/README.md`: add or update the row (number, linked title, status), change a superseded ADR's status, and remove the `No ADRs yet` placeholder row.
- Open a normal PR with those changes.

### Rejecting
A closed PR never reaches `main`, so to keep the record: on the proposal branch, set `Status: Rejected`, add a **Rejection reason** section, and add a `Rejected` row to the Index in `docs/decisions/README.md`. The code owner then approves and merges it. Rejected ADRs stop the same debate happening twice. For trivial ideas, just closing the PR is fine.

## Rules
- Never set `Accepted` on an unmerged ADR, and never merge the PR yourself.
- Never edit the decision of an Accepted ADR. Write a new one that supersedes it.
- Keep it under about 2 pages. Detail goes in linked issues or docs.
