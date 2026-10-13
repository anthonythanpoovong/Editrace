# Armour eval

Measures whether [Editrace Armour](../../.github/armour.md) catches real problems (#128). Each case is a small, plausible change with one seeded bug. The runner opens every case as a draft PR, waits for Armour, and scores it.

## When to run it

Only when `.github/armour.md` or the Armour model (`--model` in `.github/workflows/ai-review.yml`) changes. Do it after that change is on `main`, because Armour reviews with `main`'s rules. Each run costs about one Armour review per case (5 today) from the owner's Claude Pro usage, plus about 20 Actions minutes.

## Run it

```sh
scripts/armour-eval/run.sh               # prints the score table
scripts/armour-eval/run.sh --post 128    # also comments the table on issue or PR 128
scripts/armour-eval/run.sh --cleanup     # close eval PRs and delete eval branches a killed run left behind
```

Run it on your own machine, logged in with `gh auth login`. It needs `git`, `gh` and `jq`, plus push access to the repo. It refuses to run in GitHub Actions: PRs opened with `GITHUB_TOKEN` don't trigger other workflows, so Armour would never review them. No token is created or stored anywhere.

It takes 5–15 minutes. A valid score is appended to [`RESULTS.md`](RESULTS.md): commit that file with the rules or model change. **Target: at least 4 of 5 caught.** If Armour didn't review a case (usage limit, error or timeout), the score is marked not valid, nothing is recorded, and the script exits with code 2. Re-run it later.

## How it works

- **Eval PRs can't reach `main`.** They target a temporary base branch: `main` with this folder removed. The script never merges, and on every exit (success, error or Ctrl-C) it closes the PRs and deletes the branches. Deleting the base branch would also close any PR still open.
- **Armour never sees the answers.** The base branch has no `scripts/armour-eval/`, so neither the PR diff nor the files Armour can browse contain the cases' `expect` patterns. The bait code has no comments pointing at the bug.
- **Scoring** (`score.sh`, tested by `test-score.sh` in CI): a case is **caught** only when a 🔴 or 🟠 finding, in Armour's summary or inline on that commit, matches the case's `expect` pattern (case-insensitive). A 🟢 "consider" mention of a security or cost bug doesn't count.
- Side effects per eval PR: CI and the Deploy workflow run too. Vercel blocks the preview for non-team authors and posts a "No preview" comment. Drafts closed by their author send no Discord pings.

## Cases

| Case | Seeded bug |
|---|---|
| `01-rls-bypass` | An API route reads templates with the service-role client and no owner check |
| `02-float-seconds` | The cut detector writes float seconds into frame fields |
| `03-hand-written-type` | A hand-written `Template` interface instead of a generated one |
| `04-llm-no-backoff` | A Claude call retried forever with no backoff or cap |
| `05-stored-audio` | A worker uploads the reference video's audio to storage |

To add a case, create `cases/<nn-name>/` with:

- `title`: the PR title Armour sees. Keep it neutral, so it doesn't name the bug.
- `expect`: a regex (case-insensitive) that a 🔴/🟠 finding about the bug must match. It must match only findings about *this* bug: Armour also reports unrelated problems in the same code, and a loose pattern (such as just `audio`) scores those as catches.
- After its first run, add `fixtures/<nn-name>.txt` with Armour's real 🔴/🟠 findings on that PR: `+ ` before the ones about the seeded bug, `- ` before the rest. `test-score.sh` checks `expect` matches every `+` line and no `-` line.
- `files/`: the files to add, at their paths in the repo.
