#!/usr/bin/env bash
# Works out who to ping because a comment @mentioned them or replied to them (#177).
# Inputs (env): TEXTS (JSON array of comment/review bodies to scan for @logins),
# USER_MAP (JSON: GitHub login -> Discord user ID).
# Optional (env): REPLIED_TO (JSON array of logins whose comments were replied to; default []),
# EXCLUDE (JSON array of logins never to ping, e.g. the commenter and the PR author; default []).
# Prints a JSON array of at most 5 GitHub logins, mentions first, each at most once.
# Only people in USER_MAP count, so outsiders, teams and made-up logins are skipped silently.
# "@" inside code blocks, inline code, quoted lines (">") and HTML comments does not count.
# The text is untrusted: it is only matched, never echoed or executed.
set -euo pipefail

jq -e 'type == "array"' <<<"${TEXTS:?}" > /dev/null || { echo "TEXTS must be a JSON array" >&2; exit 1; }
for v in "${REPLIED_TO:-[]}" "${EXCLUDE:-[]}"; do
  jq -e 'type == "array"' <<<"$v" > /dev/null || { echo "REPLIED_TO and EXCLUDE must be JSON arrays" >&2; exit 1; }
done

jq -n \
  --argjson texts "$TEXTS" \
  --argjson replied "${REPLIED_TO:-[]}" \
  --argjson exclude "${EXCLUDE:-[]}" \
  --arg map "${USER_MAP:-}" '
  def clean:
    gsub("<!--[\\s\\S]*?-->"; "")
    | gsub("(```|~~~)[\\s\\S]*?(```|~~~)"; "")
    | split("\n") | map(select(test("^\\s*>") | not)) | join("\n")
    | gsub("`[^`\n]*`"; "");
  def mentions:
    [ match("(?<![A-Za-z0-9_/.@-])@([A-Za-z0-9][A-Za-z0-9-]{0,38})(?![A-Za-z0-9_/-])"; "g").captures[0].string ];
  (try ($map | fromjson) catch {}) as $m
  | (if ($m | type) == "object" then $m else {} end) as $map
  | ($map | keys) as $known
  | def canon($l): ($known | map(select(ascii_downcase == ($l | ascii_downcase))) | .[0]);
    ($exclude | map(ascii_downcase)) as $skip
  | ( [ $texts[] | select(type == "string") | clean | mentions[] ] + [ $replied[] | select(type == "string") ] )
  | map(canon(.) | select(. != null))
  | map(select((. | ascii_downcase) as $l | $skip | index($l) | not))
  | map(select($map[.] | type == "string" and test("^[0-9]{17,20}$")))
  | reduce .[] as $l ([]; if index($l) then . else . + [$l] end)
  | .[:5]'
