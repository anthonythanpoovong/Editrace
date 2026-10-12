#!/usr/bin/env bash
# Armour eval (#128): opens each seeded-bug case as a draft PR, waits for Armour, scores caught / missed,
# then closes the PRs and deletes the branches.
#
# Usage: scripts/armour-eval/run.sh            run every case in scripts/armour-eval/cases/
#        scripts/armour-eval/run.sh --cleanup  close leftover eval PRs and delete leftover eval branches
#
# Run it on your own machine with your own `gh` login, never in Actions: PRs opened with GITHUB_TOKEN
# don't trigger other workflows, so Armour would never review them. No token is stored anywhere.
# Each run costs about one Armour review per case from the owner's Claude Pro usage, so run it only
# when .github/armour.md or the Armour model changes.
#
# The PRs target a temporary base branch: origin/main with scripts/armour-eval/ removed. The PR diff then
# holds only the seeded files, and the checkout Armour can browse holds no expected answers. Deleting
# that base branch at the end also closes any eval PR that's still open, so none can ever reach main.
#
# Needs: git, gh (logged in, with push access), jq. Works with macOS's bash 3.2.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
LABEL=armour-eval
PREFIX=armour-eval/
TIMEOUT_MIN=${ARMOUR_EVAL_TIMEOUT_MIN:-30}

die() { echo "armour-eval: $*" >&2; exit 1; }
log() { echo "armour-eval: $*" >&2; }

[ -z "${GITHUB_ACTIONS:-}" ] || die "run this locally with your own gh login; PRs opened from Actions don't trigger Armour."
for c in git gh jq; do command -v "$c" >/dev/null || die "needs $c"; done
gh auth status >/dev/null 2>&1 || die "not logged in to gh (run: gh auth login)"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || die "can't tell which repo this is"

# Closes open eval PRs and deletes eval branches, whatever run left them.
cleanup_leftovers() {
  local prs refs n r
  prs=$(gh api "repos/$REPO/issues?state=open&labels=$LABEL&per_page=100" --paginate \
    --jq '.[] | select(.pull_request) | .number')
  for n in $prs; do
    gh api -X PATCH "repos/$REPO/pulls/$n" -f state=closed >/dev/null && log "closed #$n"
  done
  # Case branches before base branches: deleting a base first would auto-close PRs without us.
  refs=$(gh api "repos/$REPO/git/matching-refs/heads/$PREFIX" --paginate --jq '.[].ref | sub("^refs/heads/"; "")' \
    | sort -r)
  for r in $refs; do
    gh api -X DELETE "repos/$REPO/git/refs/heads/$r" >/dev/null && log "deleted branch $r"
  done
  [ -n "$prs$refs" ] || log "nothing left over"
}

if [ "${1:-}" = "--cleanup" ]; then
  cleanup_leftovers
  exit 0
fi
[ $# -eq 0 ] || die "unknown argument: $1 (only --cleanup)"

[ -z "$(gh api "repos/$REPO/git/matching-refs/heads/$PREFIX" --jq '.[].ref')" ] \
  || die "eval branches from an earlier run still exist; run: $0 --cleanup"

run=$(date -u +%Y%m%d-%H%M%S)
base=${PREFIX}${run}/base
tmp=$(mktemp -d)
wt=$tmp/wt
prs="" branches=""

# Runs on every exit, including errors and Ctrl-C: eval PRs are never left open.
cleanup() {
  local code=$? n b
  trap - EXIT INT TERM
  for n in $prs; do
    gh api -X PATCH "repos/$REPO/pulls/$n" -f state=closed >/dev/null 2>&1 || log "couldn't close #$n"
  done
  for b in $branches; do   # case branches first, base last (it was added first, so it's at the end)
    gh api -X DELETE "repos/$REPO/git/refs/heads/$b" >/dev/null 2>&1 || log "couldn't delete branch $b"
  done
  git -C "$here" worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$tmp"
  [ "$code" -eq 0 ] || log "stopped (exit $code); eval PRs closed and branches deleted. If any are left: $0 --cleanup"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

git -C "$here" fetch -q origin main
git -C "$here" worktree add -q --detach "$wt" origin/main
main_sha=$(git -C "$wt" rev-parse HEAD)
model=$(grep -o -- '--model [^ ]*' "$wt/.github/workflows/ai-review.yml" | head -n1 | cut -d' ' -f2)
rules=$(git -C "$wt" log -1 --format=%h -- .github/armour.md)

gh api "repos/$REPO/labels" -f name="$LABEL" -f color=8a8a8a \
  -f description="Armour eval PR (#128): never merge, closed automatically" >/dev/null 2>&1 || true

# Base branch: main without the eval set.
# --ignore-unmatch and --allow-empty: before this lands on main there is nothing to remove.
git -C "$wt" rm -r -q --ignore-unmatch scripts/armour-eval
git -C "$wt" commit -q --no-verify --allow-empty -m "Armour eval base: main without scripts/armour-eval"
git -C "$wt" push -q origin "HEAD:refs/heads/$base"
branches=$base
base_sha=$(git -C "$wt" rev-parse HEAD)

cases=""
for d in "$here"/cases/*/; do [ -d "$d" ] && cases="$cases $(basename "$d")"; done
[ -n "$cases" ] || die "no cases in $here/cases"

shas=""
for c in $cases; do
  dir=$here/cases/$c
  title=$(cat "$dir/title")
  branch=${PREFIX}${run}/$c
  git -C "$wt" checkout -q --detach "$base_sha"
  cp -R "$dir/files/." "$wt/"
  git -C "$wt" add -A
  git -C "$wt" commit -q --no-verify -m "$title"
  git -C "$wt" push -q origin "HEAD:refs/heads/$branch"
  branches="$branch $branches"
  n=$(gh api "repos/$REPO/pulls" -f title="$title" -f head="$branch" -f base="$base" -F draft=true \
    -f body="Automated Armour eval run \`$run\` (#128). Never merge: it's closed and its branch deleted automatically." \
    --jq .number)
  prs="$prs $n"
  gh api "repos/$REPO/issues/$n/labels" -f "labels[]=$LABEL" >/dev/null
  shas="$shas $(git -C "$wt" rev-parse HEAD)"
  log "opened #$n for $c"
done

# Wait for the skip-notice job on each commit: it runs after the review job, so by then Armour has
# posted everything it's going to post for that commit.
log "waiting for Armour (up to $TIMEOUT_MIN min)..."
deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
for sha in $shas; do
  until [ "$(gh api "repos/$REPO/commits/$sha/check-runs?check_name=Armour%20skip%20notice" \
      --jq '.check_runs[0].status // "none"')" = completed ]; do
    [ "$(date +%s)" -lt "$deadline" ] || die "timed out after $TIMEOUT_MIN min waiting for Armour on ${sha:0:7}"
    sleep 20
  done
done

caught=0 total=0 unreviewed=0
rows=""
# shellcheck disable=SC2086 # split the PR numbers into $1, $2, ... in case order
set -- $prs
for c in $cases; do
  n=$1; shift
  sha=$(gh api "repos/$REPO/pulls/$n" --jq .head.sha)
  json=$(jq -n \
    --argjson i "$(gh api "repos/$REPO/issues/$n/comments" --paginate | jq -s 'add // []')" \
    --argjson r "$(gh api "repos/$REPO/pulls/$n/comments" --paginate | jq -s 'add // []')" \
    '{issue_comments: $i, review_comments: $r}')
  code=0
  result=$(printf '%s' "$json" | "$here/score.sh" "$sha" "$(cat "$here/cases/$c/expect")") || code=$?
  total=$((total + 1))
  case $code in
    0) caught=$((caught + 1)); mark="✅ caught" ;;
    1) mark="❌ missed" ;;
    *) unreviewed=$((unreviewed + 1)); mark="⚠️ not reviewed" ;;
  esac
  detail=${result#caught: }
  [ "$code" -eq 0 ] || detail=""
  rows="$rows| \`$c\` | #$n | $mark | $(printf '%s' "$detail" | tr '|' '/') |
"
done

summary="### Armour eval: $caught/$total caught

Run \`$run\` · model \`$model\` · rules \`.github/armour.md\` at \`$rules\` · main \`${main_sha:0:7}\` · target ≥ 4/5

| Case | PR | Result | Matching finding |
|---|---|---|---|
$rows"
[ "$unreviewed" -eq 0 ] || summary="$summary
**Not a valid score:** Armour didn't review $unreviewed case(s) (usage limit, error or timeout). Re-run later."

printf '%s\n' "$summary"
[ "$unreviewed" -eq 0 ] || exit 2
