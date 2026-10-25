#!/usr/bin/env bash
# Lists the issues a merged PR closes, one number per line, sorted and unique.
# Inputs (env): PR_BODY (untrusted text, only ever grepped), CLOSING (whitespace-separated issue numbers
# from GitHub's closingIssuesReferences). Only closing keywords count (close/fix/resolve), at the start of
# a line, like ticket-sync.yml; "Part of #n" and bare "#n" do not.
set -euo pipefail
kw='(close[sd]?|fix(e[sd])?|resolve[sd]?)'
{
  printf '%s\n' "${PR_BODY:-}" \
    | grep -oiE "^[ >*-]*$kw:? +#[0-9]+( *(,|and|&) *#[0-9]+)*" | grep -oE '[0-9]+' || true
  printf '%s\n' "${CLOSING:-}" | tr -s '[:space:]' '\n' | grep -E '^[0-9]+$' || true
} | sort -un
