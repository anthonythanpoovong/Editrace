#!/usr/bin/env bash
# Scores one Armour eval case: did Armour flag the seeded bug?
# Usage: score.sh <head-sha> <expect-regex> < comments.json
#   comments.json: {"issue_comments": [...], "review_comments": [...]}, the PR's issue comments
#   and inline review comments as the GitHub API returns them.
# Prints one line and exits:
#   0  caught: a 🔴 or 🟠 finding matching the regex (case-insensitive)
#   1  missed: Armour reviewed this commit but no 🔴/🟠 finding matches
#   2  not reviewed: no Armour comment (summary or inline) for this commit
#   3  error: the comments JSON or the regex couldn't be read, so there's no score
# Only 🔴/🟠 count: a 🟢 "consider" mention of a security or cost bug isn't catching it.
set -euo pipefail

sha=${1:?head sha}
re=${2:?expect regex}

result=$(jq -r --arg sha7 "${sha:0:7}" --arg sha "$sha" --arg re "$re" '
  def armour: .user.login == "claude[bot]";
  def severe: test("🔴|🟠");
  # Same loose header match as the skip notice in ai-review.yml: first line names Editrace Armour and the commit.
  [.issue_comments[] | select(armour)
    | select((.body | split("\n")[0]) as $h | ($h | contains("Editrace Armour")) and ($h | contains($sha7)))] as $top
  # original_commit_id: the commit the comment was made on (commit_id moves to later commits).
  | [.review_comments[] | select(armour and .original_commit_id == $sha)] as $inline
  # Inline-only still counts: Armour can flag a line and then fail to post its summary.
  | if ($top | length) == 0 and ($inline | length) == 0 then "not reviewed"
    else
      ( [$top[].body | split("\n")[] | select(severe)]
        + [$inline[].body | gsub("\n"; " ") | select(severe)] )
      | map(select(test($re; "i")))
      | if length > 0 then "caught: " + (.[0] | .[0:200]) else "missed" end
    end
') || { echo "error: couldn't score (bad comments JSON or expect regex)"; exit 3; }

echo "$result"
case "$result" in
  caught:*) exit 0 ;;
  missed) exit 1 ;;
  *) exit 2 ;;
esac
