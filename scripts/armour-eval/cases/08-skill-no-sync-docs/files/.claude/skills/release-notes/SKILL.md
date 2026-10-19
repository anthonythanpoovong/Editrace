---
name: release-notes
description: Draft plain-language release notes for Editrace from the PRs merged since the last release. Use when someone says "release notes", "what shipped", "changelog for this release", or before tagging a release.
---

# Release notes

Turns merged PRs into short notes a user can read. Drafts only: a person edits and publishes them.

## 1. Find what shipped

```sh
git fetch origin main --tags
LAST=$(git describe --tags --abbrev=0 origin/main)
gh pr list --state merged --base main --search "merged:>=$(git log -1 --format=%cs "$LAST")" \
  --json number,title,labels,body --limit 200
```

If there's no tag yet, ask the author for a starting date. Don't guess.

## 2. Keep what a user would notice

- **Keep:** new features, changed behaviour, fixes to bugs users reported, new editor support, plan or limit changes.
- **Skip:** refactors, tests, CI, dependency bumps, docs-only changes.

## 3. Write them

Group under **New**, **Improved** and **Fixed**. One line each, in plain words, with the PR number:

```markdown
### New
- Import a reference video from a link, not only a file upload (#312)
```

No internal names, ticket jargon or customer details. Show the draft to the author and wait for edits before anything is published.
