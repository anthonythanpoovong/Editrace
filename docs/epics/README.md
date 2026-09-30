# Epic proposals

New bodies of work start here as a proposal, **not** as GitHub issues. One file per epic: `kebab-title.md`, copied from [`TEMPLATE.md`](TEMPLATE.md).

## Lifecycle

1. **Propose:** in Claude Code, run `/propose-epic`. It grills you like a founding engineer, breaks the work into stories and opens a **draft PR** labeled `proposal` + `epic`.
2. **Discuss:** in the PR. Mark it Ready for review when done.
3. **Approve:** CODEOWNERS covers this folder, so the PR can't merge without code-owner approval. **Merged = approved.**
4. **Create issues:** run `/propose-epic` again and ask it to create the issues for the merged proposal. It creates the `epic` issue and its `story` sub-issues, adds them to the project board, and marks the file `Accepted` with the issue numbers.

No epic or story issues are created from an unmerged proposal. Rejected proposals stay here with `Status: Rejected` and the reason.

Just want to pressure-test an idea without writing anything? Run `/grill`.
