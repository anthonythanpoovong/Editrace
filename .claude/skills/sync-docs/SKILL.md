---
name: sync-docs
description: Update Editrace's README, docs/plan.md and GitHub wiki after large changes land on main (new feature or service, accepted epic/ADR, schema or MCP contract change, new setup steps, CI changes, new skills, parked or rejected ideas). Use when someone says "update the docs", "sync the README/plan/wiki", "document what changed", after merging a big PR, or when an epic/ADR is accepted. Only documents what is merged; README and plan.md changes go through a PR, wiki changes are pushed after the author confirms.
---

# Sync docs: README + plan.md + wiki

Keeps three places in step with what's actually on `main`:

- **`README.md`**: the short front door (what it is, layout, how to start)
- **`docs/plan.md`**: the plan (Key Decisions, Architecture, Epics, Roadmap, Risks, Metrics, Open Questions)
- **The [wiki](https://github.com/editrace-app/Editrace/wiki)**: per-feature detail

Only document **merged** work, and only **large** changes. The README stays short; detail goes in the wiki; `plan.md` records what the team has decided and planned.

## 1. Find what changed since the last sync

```sh
git fetch origin main
WIKI=$(mktemp -d)/wiki
git clone -q https://github.com/editrace-app/Editrace.wiki.git "$WIKI"
git -C "$WIKI" log --format=%B | grep -m1 '^Docs-Synced-To:'    # last synced main SHA
```

- **Baseline** = that SHA. If there's no marker, ask the author for a starting point (a date or PR number). Don't guess.
- Collect the changes since then:
  ```sh
  git log --oneline --no-merges <base>..origin/main
  git diff --stat <base>..origin/main
  gh pr list --state merged --base main --search "merged:>=<base commit date>" --json number,title,body,labels
  ```
- Also check issues created or closed since the baseline that change the plan (e.g. new stories under an epic, a closed spike with a decision): `gh issue list --state all --search "updated:>=<base commit date>"`.
- If the author named a specific PR or change, focus on that.

## 2. Keep only the large changes

**Large (document it):**
- A new top-level folder, service, app route, worker/detector, exporter or editor adapter
- An epic or ADR merged (`docs/epics/`, `docs/decisions/`), including its **Out of scope** / parked ideas
- Changes to `schema/template.schema.json` sections, DB tables/RLS, or MCP tools (remote server or Bridge)
- New or changed setup: commands, env vars, required secrets, dependencies someone must install
- New or changed CI workflows, reviewers, CODEOWNERS or branch rules
- New or changed Claude Code skills in `.claude/skills/`
- Stack changes (new provider, model, framework)
- A feature moving from planned to working (a wiki page's `Status` should change)
- New stories or epics created, or a roadmap phase changing

**Small (skip it):** bug fixes, refactors, tests, formatting, dependency bumps, copy tweaks, internal renames.

If nothing is large, say so, list what you skipped, and stop.

## 3. Map each change to where it's documented

| Change | README | `docs/plan.md` | Wiki page |
|---|---|---|---|
| Web app routes, data model, auth | Stack / What it does (only if the headline changes) | Architecture (if the flow changes) | `Web-App` |
| Workers, detectors, golden dataset | — | Architecture (if the flow changes) | `Video-Analysis-Pipeline` |
| Schema sections, codegen | Schema | Template Schema table | `Template-Schema` |
| Exporters, editor adapters, ontology | What it does (if a new editor ships) | Editor Integrations table | `Editor-Integrations-and-Exports` |
| MCP tools, Bridge, client setup | What it does | MCP Design tables | `MCP-and-Editrace-Bridge` |
| Assistant, corpus, evals | — | Template Assistant (RAG) | `Template-Assistant-RAG` |
| Plans, quotas, Stripe | — | — | `Billing-and-Accounts` |
| Stack change | Stack | Stack table | Relevant page |
| Workflows, Armour, CODEOWNERS | CI & AI Code Review | — | `CI-and-Editrace-Armour` |
| Skills in `.claude/skills/` | Claude Code Skills table | Epics (only if the proposal process changes) | `Claude-Code-Skills` |
| New top-level folder | Repo Layout | — | Relevant page |
| Accepted epic / new stories | — | **Epics** table + **Roadmap** phase line; new **Risks** and **Metrics** from the proposal | Owning page (+ `Home` features table if it's a new feature area) |
| Accepted ADR | — | **Key Decisions** (only if the ADR changes one) + the affected section | Relevant page |
| Parked or rejected idea (from a proposal's Out of scope, or a Rejected ADR/epic) | — | **Open Questions** (what it's waiting on) | — |
| Team or ownership change | Team | Team table | Page headers |
| A new feature area with no page | — | — | New page from the existing page structure + `Home` + `_Sidebar` |

## 4. Draft the edits

- **Facts only from the diff, PR descriptions, merged docs and issues.** Don't invent numbers, commands or behaviour. If something's unclear, read the code, or leave the `TODO` in place.
- Replace wiki `TODO`s the code now answers (real commands, routes, env var names, tool names), and update `Status` lines (🟡 Planned → 🟢 In progress / ✅ Shipped).
- **`plan.md` Key Decisions change only through an accepted ADR.** Never add, remove or reword a Key Decision because code or a PR drifted from it. Flag the drift to the author and suggest `/propose-adr` instead.
- Keep `plan.md` issue references (`#n`) current: Epics table stories, Roadmap phase lines, Risks mitigations and Metrics.
- Match the existing style: short sections, tables, links to issues/PRs as `#n`.
- Edit in place. Don't rewrite or reorder sections that didn't change, and don't delete content someone else wrote unless it's now wrong.
- Keep internal wiki links working. Page links are file names without `.md`.

## 5. Confirm with the author

Show a short summary (the change → which README section / `plan.md` section / wiki page → what changed) plus the diffs. Also list the changes you judged small and skipped, and any Key Decision drift you flagged. **Wait for a yes.** The wiki has no PR review, so this is its only check.

## 6. Publish

**README and `docs/plan.md`**: together in one PR, because CODEOWNERS/branch rules apply:
```sh
git checkout -b docs/sync-YYYY-MM-DD origin/main
# edit README.md and/or docs/plan.md
git commit -am "Sync docs with <summary>"
git push -u origin docs/sync-YYYY-MM-DD
gh pr create --base main --title "Sync docs: <summary>" --body "<changes per file + source PRs>"
```

**Wiki**: commit with the sync marker set to the `origin/main` SHA you documented up to:
```sh
git -C "$WIKI" add -A
git -C "$WIKI" commit -m "Sync docs: <summary>

Source PRs: #n, #m
Docs-Synced-To: $(git rev-parse origin/main)"
git -C "$WIKI" push origin HEAD
```
Then check with `git ls-remote https://github.com/editrace-app/Editrace.wiki.git HEAD`.

If there were only small changes, still record the new baseline so they aren't reviewed again. Use an empty wiki commit:
`git -C "$WIKI" commit --allow-empty -m "Docs sync: no large changes" -m "Docs-Synced-To: <sha>"`, after the author says yes.

## Rules
- Never document unmerged branches or open PRs.
- Never put secrets, tokens or private customer details in docs.
- README and `plan.md` changes always go through a PR, never a direct push to `main`.
- Never change a Key Decision without an accepted ADR.
