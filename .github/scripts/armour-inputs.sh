#!/usr/bin/env bash
# Writes Editrace Armour's inputs for one PR commit (#125), so Armour quotes them instead of counting or
# estimating: $OUT/files.md (the PR's changed files) and $OUT/coverage.md (CI's coverage numbers).
# ai-review.yml runs the base branch's copy of this script and of coverage-render.sh next to it, never the
# PR's, so a PR can't plant either file.
# Inputs (env): REPO, PR, SHA, GH_TOKEN, OUT (a directory), WAIT_SECONDS (default 600), POLL_SECONDS (default 20).
# Never fails the review: whatever it can't read becomes "pending" in coverage.md.
set -uo pipefail
repo=${REPO:?} pr=${PR:?} sha=${SHA:?} out=${OUT:?}
wait_s=${WAIT_SECONDS:-600} poll_s=${POLL_SECONDS:-20}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"

# files.md: one line per file with lines added and removed. Lock files, generated code (the same paths CI's
# coverage gate excludes) and files GitHub shows no diff for (binary or too large) are marked skipped.
if files=$(gh api --paginate "repos/$repo/pulls/$pr/files?per_page=100" 2> /dev/null | jq -s 'add // []'); then
  jq -r --arg sha "${sha:0:7}" '
    def skip:
      if (.filename | test("(^|/)(package-lock\\.json|pnpm-lock\\.yaml|yarn\\.lock|uv\\.lock|poetry\\.lock|Cargo\\.lock)$")) then "lock file"
      elif (.filename | test("(^|/)lib/generated/|(^|/)editrace_schema/models\\.py$")) then "generated"
      elif (.patch == null and .status != "removed" and (.status != "renamed" or .changes > 0)) then "no diff (binary or too large)"
      else empty end;
    "Changed files at `\($sha)`: \(length)",
    (.[] | "- `\(.filename)` +\(.additions) −\(.deletions) \(.status)"
           + (if .previous_filename then " from `\(.previous_filename)`" else "" end)
           + ((skip | " · skip: " + .) // " · review"))
  ' <<< "$files" > "$out/files.md"
else
  echo "Changed files: couldn't be listed. Use \`gh pr diff\`." > "$out/files.md"
fi

# coverage.md: first line "status: measured", "none", "not-measured" or "pending", then CI's numbers or why there
# are none. The numbers come from the coverage-summary artifact of this commit's CI run, rendered by the same
# coverage-render.sh that writes CI's Coverage comment (#129), so they match the comment but belong to this exact
# commit. CI's coverage job only starts once its web and python jobs finish, so a missing check means "not yet"
# until ci-ok, which always runs last, has finished.
coverage() { printf 'status: %s\n\n%s\n' "$1" "$2" > "$out/coverage.md"; }
summary() { # Prints this commit's coverage summary.json, from its latest CI run.
  local run art
  run=$(gh api "repos/$repo/actions/runs?head_sha=$sha&per_page=100" 2> /dev/null | jq -r '
    [.workflow_runs[] | select(.path == ".github/workflows/ci.yml")] | sort_by(.created_at) | last | .id // empty') \
    && [ -n "$run" ] || return 1
  art=$(gh api "repos/$repo/actions/runs/$run/artifacts?name=coverage-summary" 2> /dev/null \
    | jq -r '[.artifacts[] | select(.expired | not)] | last | .id // empty') && [ -n "$art" ] || return 1
  gh api "repos/$repo/actions/artifacts/$art/zip" > "$out/summary.zip" 2> /dev/null \
    && unzip -p "$out/summary.zip" summary.json && rm -f "$out/summary.zip"
}
deadline=$(( $(date +%s) + wait_s ))
while :; do
  if checks=$(gh api --paginate "repos/$repo/commits/$sha/check-runs?per_page=100" 2> /dev/null \
      | jq -s '[.[].check_runs[]] | sort_by(.started_at)'); then
    cov=$(jq -c '[.[] | select(.name == "coverage")] | last' <<< "$checks")
    ci_done=$(jq -r '[.[] | select(.name == "ci-ok" and .status == "completed")] | length > 0' <<< "$checks")
    tests_failed=$(jq -r '[.[] | select((.name == "web" or .name == "python") and .conclusion == "failure")] | length > 0' <<< "$checks")
    if [ "$(jq -r '.status // ""' <<< "$cov")" = completed ]; then
      case "$(jq -r .conclusion <<< "$cov")" in
        success)
          if json=$(summary) && md=$(printf '%s' "$json" > "$out/summary.json" && "$here/coverage-render.sh" "$out/summary.json"); then
            coverage measured "$(sed 1d <<< "$md")"
          else
            coverage pending "coverage pending: CI's coverage summary for this commit couldn't be read. See the CI Coverage comment."
          fi ;;
        skipped)
          # CI skips its coverage job when there's nothing to measure, and also when the tests failed.
          if [ "$tests_failed" = true ]; then
            coverage not-measured "coverage not measured: CI's web or Python tests failed."
          else
            coverage none "CI's coverage job was skipped for this commit: there's no web or Python code to measure."
          fi ;;
        *) coverage not-measured "coverage not measured: CI's coverage job didn't finish successfully." ;;
      esac
      rm -f "$out/summary.json" "$out/summary.zip"
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
