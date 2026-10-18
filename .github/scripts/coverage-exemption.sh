#!/usr/bin/env bash
# Decides whether a PR is exempt from the changed-line coverage gate (#129). Prints one JSON object:
#   {"exempt": bool, "reviewer": "...", "reason": "...", "sha": "...", "notes": ["..."]}
# and always exits 0 for a decision, including "not exempt": the gate applies unless every rule holds.
#
# The exemption is a pull request review that GitHub itself records (a label, status or comment can be
# created by any collaborator; a review's author and commit_id are set by GitHub). It counts only when:
#   - its commit_id equals the PR's current head SHA (a new push ends the exemption),
#   - its body starts with /coverage-exempt followed by a reason,
#   - it is not DISMISSED or PENDING, and its author is a human on the allowlist,
#   - it is the allowlisted authors' most recent /coverage-* review on that commit
#     (a later /coverage-revoke wins; "Comment" reviews can't be dismissed, so this is how to revoke).
# The allowlist is the plain @username entries on the single CODEOWNERS line whose pattern is exactly
# /.github/, read from main (the caller passes the file), not from the PR. Team and email entries are
# ignored. Fail closed: a missing or duplicated /.github/ line, no plain usernames, unreadable input or
# a bot author leave the gate in force, and "notes" says why.
#
# Inputs (env): REVIEWS_FILE (JSON array of the PR's reviews, all pages merged), CODEOWNERS_FILE,
# HEAD_SHA (the PR's head commit, read live by the caller).
set -uo pipefail

reviews_file=${REVIEWS_FILE:-}
codeowners_file=${CODEOWNERS_FILE:-}
head_sha=${HEAD_SHA:-}

notes=()
emit() { # exempt reviewer reason
  local n="[]"
  [ "${#notes[@]}" -eq 0 ] || n=$(printf '%s\n' "${notes[@]}" | jq -R . | jq -s .)
  jq -cn --argjson exempt "$1" --arg reviewer "${2:-}" --arg reason "${3:-}" --arg sha "$head_sha" --argjson notes "$n" \
    '{exempt: $exempt, reviewer: $reviewer, reason: $reason, sha: $sha, notes: $notes}'
  exit 0
}
deny() { notes+=("$1"); emit false; }

[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || deny "The PR's head commit could not be read, so no exemption applies."
[ -r "$codeowners_file" ] || deny "CODEOWNERS could not be read from main, so no exemption applies."
[ -r "$reviews_file" ] && jq -e 'type == "array"' "$reviews_file" > /dev/null 2>&1 \
  || deny "The PR's reviews could not be read, so no exemption applies."

# The /.github/ line: exactly one, and its plain @username entries (no teams, no emails).
gh_lines=$(grep -E '^[[:space:]]*/\.github/([[:space:]]|$)' "$codeowners_file" || true)
[ -n "$gh_lines" ] || deny "CODEOWNERS has no /.github/ line, so no exemption applies."
[ "$(grep -c . <<<"$gh_lines")" -eq 1 ] || deny "CODEOWNERS has more than one /.github/ line, so no exemption applies."
allow=$(tr -s '[:space:]' '\n' <<<"$gh_lines" | grep -E '^@[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$' | sed 's/^@//' | tr 'A-Z' 'a-z' || true)
[ -n "$allow" ] || deny "The /.github/ line in CODEOWNERS has no plain @username entries, so no exemption applies."
allow_json=$(jq -R . <<<"$allow" | jq -s .)

# /coverage-* reviews on the current head commit that are real submitted reviews (not dismissed or pending).
decision=$(jq -c --arg sha "$head_sha" --argjson allow "$allow_json" '
  def cmd: (.body // "") | capture("^\\s*(?<c>/coverage-(exempt|revoke))(?<rest>(\\s[\\s\\S]*)?)$") // null;
  def human: (.user.type == "User") and ((.user.login // "") | test("\\[bot\\]$") | not);
  [ .[] | select(.commit_id == $sha and .state != "DISMISSED" and .state != "PENDING" and .submitted_at != null)
        | (cmd) as $c | select($c != null)
        | {id, login: (.user.login // ""), human: human, c: $c.c, rest: $c.rest, at: .submitted_at,
           allowed: (((.user.login // "") | ascii_downcase) as $l | ($allow | index($l)) != null)} ] as $all
  | ($all | map(select(.allowed and .human)) | sort_by([.at, .id]) | last) as $latest
  | {
      latest: $latest,
      ignored: [ $all[] | select((.allowed and .human) | not) | {login, c, human} ]
    }' "$reviews_file") || deny "The PR's reviews could not be read, so no exemption applies."

while read -r line; do
  [ -n "$line" ] || continue
  notes+=("Ignored /coverage-${line#*|} from $(cut -d'|' -f1 <<<"$line"): only a human on the /.github/ CODEOWNERS line on main can exempt a PR.")
done < <(jq -r '.ignored[] | "@\(.login)|\(.c | sub("^/coverage-"; ""))"' <<<"$decision")

latest=$(jq -c '.latest' <<<"$decision")
[ "$latest" != null ] || { notes+=("No /coverage-exempt review from an allowed owner on the current head commit."); emit false; }
[ "$(jq -r '.c' <<<"$latest")" = "/coverage-exempt" ] || { notes+=("The owner's latest review on this commit is /coverage-revoke."); emit false; }

# Reason: the text after the command, one line, no control characters, at most 200 characters.
reason=$(jq -r '.rest' <<<"$latest" | tr '\r\n\t' '   ' | tr -d '\000-\037' | tr -s ' ' | sed -E 's/^ +//; s/ +$//' | cut -c1-200)
[ -n "$reason" ] || { notes+=("The /coverage-exempt review has no reason after the command, so it is ignored."); emit false; }

emit true "@$(jq -r '.login' <<<"$latest")" "$reason"
