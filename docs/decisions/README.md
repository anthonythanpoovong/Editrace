# Architecture Decision Records

One file per decision: `NNNN-kebab-title.md`, copied from [`0000-template.md`](0000-template.md).

## Lifecycle

```
Proposed ──(code owner approves + merges PR)──▶ Accepted ──▶ Superseded by NNNN
    └──(set Status: Rejected + reason, merge)──▶ Rejected
```

1. **Propose:** in Claude Code, run `/propose-adr`. It grills you on the decision, drafts the ADR and opens a **draft PR** labeled `proposal` + `adr`.
2. **Discuss:** in the PR. Mark it Ready for review when done.
3. **Approve:** CODEOWNERS covers this folder, so the PR can't merge without code-owner approval. **Merged = Accepted.** A follow-up PR flips the `Status:` line.
4. **Change your mind later:** write a new ADR that supersedes the old one. Accepted ADRs are never rewritten.

To reject an ADR, set `Status: Rejected` with a reason on the PR branch and merge it; a closed PR never reaches `main`. Rejected ADRs stay in the folder so the same debate doesn't happen twice. Merging a Rejected file is a record, not an approval.

## Index

| # | Title | Status |
|---|---|---|
| — | *No ADRs yet* | — |
