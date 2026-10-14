#!/usr/bin/env bash
# The final coverage decision, run inside the ci-ok job (#129). coverage-gate.sh only measures; this applies the
# 80% rule and the owner's exemption. It lives in ci-ok because the owner exempts a PR by submitting a
# /coverage-exempt review and then re-running the failed ci-ok job: a re-run of ci-ok re-runs this script, which
# reads the PR's head commit, its reviews and CODEOWNERS live from the API, so it sees the new review (or a
# /coverage-revoke) without a new push. See coverage-exemption.sh for the exemption rules.
#
# Inputs (env): SUMMARY_JSON (from coverage-gate.sh), REPO, PR, GH_TOKEN, BASE_BRANCH (the default branch,
# whose .github/CODEOWNERS is the allowlist; never the PR's copy), OUT_DIR (default coverage-out),
# NO_COMMENT=1 to skip updating the sticky comment.
# Exit 1 when the gate fails and no valid exemption applies.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
summary=${SUMMARY_JSON:?}
out=${OUT_DIR:-coverage-out}
mkdir -p "$out"

status=$(jq -r .status "$summary" 2> /dev/null) || { echo "::error::The coverage summary could not be read. The gate fails closed."; exit 1; }
if [ "$status" != fail ]; then
  echo "Coverage gate: $status"
  exit 0
fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=${REPO:-}; pr=${PR:-}; base=${BASE_BRANCH:-main}
head_sha=""
if [ -n "$repo" ] && [ -n "$pr" ]; then
  head_sha=$(gh api "repos/$repo/pulls/$pr" --jq .head.sha 2> /dev/null) || head_sha=""
  gh api --paginate "repos/$repo/pulls/$pr/reviews" 2> /dev/null | jq -s 'add // []' > "$work/reviews.json" 2> /dev/null || rm -f "$work/reviews.json"
  gh api -H "Accept: application/vnd.github.raw" "repos/$repo/contents/.github/CODEOWNERS?ref=$base" > "$work/CODEOWNERS" 2> /dev/null || rm -f "$work/CODEOWNERS"
fi
exemption=$(REVIEWS_FILE="$work/reviews.json" CODEOWNERS_FILE="$work/CODEOWNERS" HEAD_SHA="$head_sha" "$here/coverage-exemption.sh")

if [ "$(jq -r .exempt <<<"$exemption")" = true ]; then final=exempt; else final=fail; fi
jq --argjson e "$exemption" --arg s "$final" '.status = $s | .exemption = $e' "$summary" > "$out/final.json"
"$here/coverage-render.sh" "$out/final.json" > "$out/final.md"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || cat "$out/final.md" >> "$GITHUB_STEP_SUMMARY"
if [ -z "${NO_COMMENT:-}" ] && [ -n "$repo" ] && [ -n "$pr" ]; then
  REPO=$repo PR=$pr COMMENT_FILE="$out/final.md" "$here/coverage-comment.sh" || true
fi

if [ "$final" = exempt ]; then
  echo "Coverage gate: exempt (reviewer $(jq -r .reviewer <<<"$exemption"), reason: $(jq -r .reason <<<"$exemption"), commit $head_sha)"
  exit 0
fi
echo "::error::Changed lines are $(jq -r .changed_percent "$summary")% covered; the gate needs $(jq -r .threshold "$summary")%."
jq -r '.notes[]? | "::notice::" + .' <<<"$exemption"
exit 1
