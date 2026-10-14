#!/usr/bin/env bash
# Writes Editrace Armour's inputs for one PR commit (#125), so Armour quotes them instead of counting or
# estimating: $OUT/files.md (the PR's changed files) and $OUT/coverage.md (CI's coverage numbers).
# ai-review.yml runs the base branch's copy of this script, never the PR's, so a PR can't plant either file.
# Inputs (env): REPO, PR, SHA, GH_TOKEN, OUT (a directory), WAIT_SECONDS (default 600), POLL_SECONDS (default 20).
# Never fails the review: whatever it can't read becomes "pending" in coverage.md.
set -uo pipefail
repo=${REPO:?} pr=${PR:?} sha=${SHA:?} out=${OUT:?}
wait_s=${WAIT_SECONDS:-600} poll_s=${POLL_SECONDS:-20}
marker='<!-- editrace-coverage -->'
mkdir -p "$out"

# files.md: one line per file with lines added and removed. Lock files, generated code (the same paths CI's
# coverage gate excludes) and files GitHub shows no diff for (binary or too large) are marked skipped.
if files=$(gh api --paginate "repos/$repo/pulls/$pr/files?per_page=100" 2> /dev/null | jq -s 'add // []'); then
  jq -r --arg sha "${sha:0:7}" '
    def skip:
      if (.filename | test("(^|/)(package-lock\\.json|pnpm-lock\\.yaml|yarn\\.lock|uv\\.lock|poetry\\.lock|Cargo\\.lock)$")) then "lock file"
      elif (.filename | test("(^|/)lib/generated/|(^|/)editrace_schema/models\\.py$")) then "generated"
      elif (.patch == null and .status != "removed") then "no diff (binary or too large)"
      else empty end;
    "Changed files at `\($sha)`: \(length)",
    (.[] | "- `\(.filename)` +\(.additions) −\(.deletions) \(.status)"
           + ((skip | " · skip: " + .) // " · review"))
  ' <<< "$files" > "$out/files.md"
else
  echo "Changed files: couldn't be listed. Use \`gh pr diff\`." > "$out/files.md"
fi

# coverage.md: first line "status: measured", "none" or "pending", then CI's sticky Coverage comment (#129) or why
# there's none. CI's coverage job only starts once its web and python jobs finish, so a missing check means "not
# yet" until ci-ok, which always runs last, has finished.
coverage() { printf 'status: %s\n\n%s\n' "$1" "$2" > "$out/coverage.md"; }
deadline=$(( $(date +%s) + wait_s ))
while :; do
  if checks=$(gh api --paginate "repos/$repo/commits/$sha/check-runs?per_page=100" 2> /dev/null \
      | jq -s '[.[].check_runs[]] | sort_by(.started_at)'); then
    cov=$(jq -c '[.[] | select(.name == "coverage")] | last' <<< "$checks")
    ci_done=$(jq -r '[.[] | select(.name == "ci-ok" and .status == "completed")] | length > 0' <<< "$checks")
    if [ "$(jq -r '.status // ""' <<< "$cov")" = completed ]; then
      if [ "$(jq -r .conclusion <<< "$cov")" = skipped ]; then
        coverage none "CI's coverage job was skipped for this commit: there's no web or Python code to measure."; exit 0
      fi
      started=$(jq -r .started_at <<< "$cov")
      # Only github-actions[bot]'s comment counts (a person can paste the marker), and only if this commit's
      # coverage job wrote it: the comment carries no commit, so it must be newer than the job's start.
      body=$(gh api --paginate "repos/$repo/issues/$pr/comments?per_page=100" 2> /dev/null | jq -rs --arg m "$marker" --arg t "$started" '
        [add // [] | .[] | select(.user.login == "github-actions[bot]" and ((.body // "") | startswith($m)))]
        | last | select(. != null and .updated_at >= $t) | .body') || body=""
      if [ -n "$body" ]; then
        coverage measured "$(sed 1d <<< "$body")"
      else
        coverage pending "coverage pending: CI's coverage job finished, but its Coverage comment wasn't updated for this commit."
      fi
      exit 0
    fi
    if [ "$cov" = null ] && [ "$ci_done" = true ]; then
      coverage none "CI finished without a coverage job for this commit."; exit 0
    fi
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    coverage pending "coverage pending: CI's coverage job hadn't finished after $((wait_s / 60)) minutes. See the CI Coverage comment."
    exit 0
  fi
  sleep "$poll_s"
done
