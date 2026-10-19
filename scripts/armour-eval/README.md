# Armour eval

Measures whether [Editrace Armour](../../.github/armour.md) catches real problems (#128). Each case is a small, plausible change with one seeded bug. The runner opens every case as a draft PR, waits for Armour, and scores it.

## When to run it

Only when `.github/armour.md` or the Armour model (`--model` in `.github/workflows/ai-review.yml`) changes. Armour reviews with its base branch's rules, so by default the eval scores `main`'s. To score a change before it merges, run it from that branch with `--base HEAD`: the eval base is then built from your branch's last commit (commit the rules first). Its score is marked `not main`. The branch's `ai-review.yml` must match `main`'s (merge `main` in first): Armour skips any PR whose workflow differs from `main`'s, so a model change can only be scored once it's on `main`. Each run costs about one Armour review per case (8 today) from the owner's Claude Pro usage, plus about 20 Actions minutes.

## Run it

```sh
scripts/armour-eval/run.sh               # prints the score table
scripts/armour-eval/run.sh --post 128    # also comments the table on issue or PR 128
scripts/armour-eval/run.sh --base HEAD   # scores this branch's armour.md, before it merges
scripts/armour-eval/run.sh --cleanup     # close eval PRs and delete eval branches a killed run left behind
```

Run it on your own machine, logged in with `gh auth login`. It needs `git`, `gh` and `jq`, plus push access to the repo. It refuses to run in GitHub Actions: PRs opened with `GITHUB_TOKEN` don't trigger other workflows, so Armour would never review them. No token is created or stored anywhere.

It refuses to start while `scripts/armour-eval/` has uncommitted changes, so every score names the commit its cases came from. It takes 5–15 minutes. A valid score is appended to [`RESULTS.md`](RESULTS.md), with the model, the `armour.md` and cases commits and the `main` commit it was built from (or `--base`'s, marked `not main`): commit that file with the rules or model change. **Target: at least 80% caught (7 of 8 today).** If Armour didn't review a case (usage limit, error or a timeout after 30 minutes) or a case couldn't be scored, the score is marked not valid, nothing is recorded, and the script exits with code 2. Re-run it later. A valid score below the target is recorded and exits with code 1.

## How it works

- **Eval PRs can't reach `main`.** They target a temporary base branch: `main` (or `--base`) with this folder removed. The script never merges, and on every exit (success, error or Ctrl-C) it closes the PRs and deletes the branches. Deleting the base branch would also close any PR still open.
- **Armour never sees the answers.** The base branch drops `scripts/armour-eval/` and the epic that lists the seeded bugs (`HIDE` in `run.sh`), so neither the PR diff nor the files Armour can browse name them. Branches are named `armour-eval/<run>/c1`, `c2`, ..., not after the case, and the PRs have no body. The bait code has no comments pointing at the bug. Armour *can* tell these PRs are a test (the `armour-eval/` branch prefix, and `docs/plan.md` mentions the eval set), so it may look harder than on a normal PR. It can't tell which bug each one holds.
- **Scoring** (`score.sh`, tested by `test-score.sh` in CI): a case is **caught** only when a 🔴 or 🟠 finding, in Armour's summary or inline on that commit, matches the case's `expect` pattern (case-insensitive). A 🟢 "consider" mention of a security or cost bug doesn't count.
- Side effects per eval PR: CI runs (it skips this folder's tests, which aren't on the base branch). The Deploy workflow skips the Vercel preview for `armour-eval/` branches, since a preview of deliberately buggy code would outlive the PR. Like every PR, they get no board card. Drafts closed by their author send no Discord pings.

## Cases

| Case | Seeded bug |
|---|---|
| `01-rls-bypass` | An API route reads templates with the service-role client and no owner check |
| `02-float-seconds` | The cut detector writes float seconds into frame fields |
| `03-hand-written-type` | A hand-written `Template` interface instead of a generated one |
| `04-llm-no-backoff` | A Claude call retried forever with no backoff or cap |
| `05-stored-audio` | A worker uploads the reference video's audio to storage |
| `06-untested-timecode` | A timecode helper's drop-frame branch has no test (CI's coverage lists those lines) |
| `07-route-no-test` | A new API route with no test |
| `08-skill-no-sync-docs` | A new skill, and the PR doesn't say to run `/sync-docs` after merge |

To add a case, create `cases/<nn-name>/` with:

- `title`: the PR title Armour sees. Keep it neutral, so it doesn't name the bug. If a doc Armour can read describes the bug, add that file to `HIDE` in `run.sh`.
- `expect`: a regex (case-insensitive) that a 🔴/🟠 finding about the bug must match. It must match only findings about *this* bug: Armour also reports unrelated problems in the same code, and a loose pattern (such as just `audio`) scores those as catches.
- `fixtures/<nn-name>.txt`, from a run on your branch: Armour's real 🔴/🟠 findings on that PR, `+ ` before the ones about the seeded bug, `- ` before the rest. `test-score.sh` (in CI) checks `expect` matches every `+` line and no `-` line, and fails a case with no fixture or no `+` line.
- `files/`: the files to add, at their paths in the repo.
