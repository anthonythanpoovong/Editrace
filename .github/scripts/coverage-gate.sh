#!/usr/bin/env bash
# Measures changed-line coverage for a PR (#129) and writes $OUT_DIR/summary.json and summary.md. It never
# fails the build over low coverage: the decision, including the owner's /coverage-exempt review, is made in
# the ci-ok job by coverage-decide.sh, because the owner exempts a PR by re-running that job (a re-run of ci-ok
# alone does not re-run this one). It exits 1 only when it cannot measure (diff-cover failed): fail closed.
# SQL (migrations, RLS policies) isn't in any coverage report: the two-user RLS harness covers it (#49).
# Generated code is excluded with EXCLUDES.
#
# Inputs (env, all optional):
#   WEB_LCOV       Vitest lcov report. Its paths are relative to web/, so SF: lines get a web/ prefix.
#   PY_XML         pytest-cov Cobertura XML (paths relative to the repo root: see .github/coveragerc).
#   COMPARE_BRANCH what the PR is compared with (default origin/main).
#   FAIL_UNDER     minimum percent of changed lines covered (default 80).
#   EXCLUDES       space-separated globs of files diff-cover ignores (generated code). They must start with a
#                  wildcard, e.g. '**/lib/generated/**': diff-cover matches them against absolute paths.
#   BASELINE_JSON  summary.json from main's last run: gives the "change vs main" number.
#   OUT_DIR        where summary.json and summary.md go (default coverage-out).
#   EVENT_NAME     "pull_request" to measure the diff; any other event only reports the overall number.
# status in summary.json: pass | fail | no-changed-lines | no-data | reported.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)

compare=${COMPARE_BRANCH:-origin/main}
threshold=${FAIL_UNDER:-80}
out=${OUT_DIR:-coverage-out}
event=${EVENT_NAME:-}
[[ "$threshold" =~ ^[0-9]+$ ]] || { echo "FAIL_UNDER must be a whole number" >&2; exit 2; }
mkdir -p "$out"

reports=()
lf=0; lh=0
if [ -n "${WEB_LCOV:-}" ] && [ -s "$WEB_LCOV" ]; then
  sed 's#^SF:#SF:web/#' "$WEB_LCOV" > "$out/web.lcov"
  reports+=("$out/web.lcov")
  lf=$((lf + $(awk -F: '$1 == "LF" { n += $2 } END { print n + 0 }' "$WEB_LCOV")))
  lh=$((lh + $(awk -F: '$1 == "LH" { n += $2 } END { print n + 0 }' "$WEB_LCOV")))
fi
if [ -n "${PY_XML:-}" ] && [ -s "$PY_XML" ]; then
  reports+=("$PY_XML")
  lf=$((lf + $(grep -o 'lines-valid="[0-9]*"' "$PY_XML" | head -n 1 | tr -dc '0-9' | sed 's/^$/0/')))
  lh=$((lh + $(grep -o 'lines-covered="[0-9]*"' "$PY_XML" | head -n 1 | tr -dc '0-9' | sed 's/^$/0/')))
fi

pct() { awk -v a="$1" -v b="$2" 'BEGIN { if (b == 0) print "null"; else printf "%.1f", int(1000 * a / b) / 10 }'; }
overall=$(pct "$lh" "$lf")
baseline=null
if [ -n "${BASELINE_JSON:-}" ] && [ -s "$BASELINE_JSON" ]; then
  baseline=$(jq -r '.overall // "null"' "$BASELINE_JSON" 2> /dev/null || echo null)
  [[ "$baseline" =~ ^[0-9.]+$ ]] || baseline=null
fi
delta=null
if [ "$overall" != null ] && [ "$baseline" != null ]; then
  delta=$(awk -v a="$overall" -v b="$baseline" 'BEGIN { printf "%.1f", a - b }')
fi

# --- changed lines ---
changed_pct=null; changed_lines=0; missed=0; files='[]'
status=no-data
if [ "${#reports[@]}" -gt 0 ] && [ "$event" = pull_request ]; then
  excl=()
  # The globs must reach diff-cover as written, not be expanded by the shell. diff-cover only matches a
  # pattern that starts with a wildcard (e.g. **/lib/generated/**), because it compares absolute paths.
  if [ -n "${EXCLUDES:-}" ]; then
    set -f
    # shellcheck disable=SC2206
    excl=(--exclude ${EXCLUDES})
    set +f
  fi
  # diff-cover cannot mix lcov and XML reports in one run, so run it once per report and add the results up.
  parts=()
  for r in "${reports[@]}"; do
    part="$out/diff-${#parts[@]}.json"
    if ! diff-cover "$r" --compare-branch "$compare" ${excl[@]+"${excl[@]}"} --total-percent-float --format "json:$part" > "$out/diff.txt" 2>&1; then
      # diff-cover itself failed (not a coverage failure: that is judged below). Never pass silently.
      cat "$out/diff.txt" >&2
      echo "::error::diff-cover failed, so changed-line coverage is unknown. The gate fails closed."
      exit 1
    fi
    parts+=("$part")
  done
  jq -s '{total_num_lines: (map(.total_num_lines) | add), total_num_violations: (map(.total_num_violations) | add),
          src_stats: (map(.src_stats) | add)}
         | .total_percent_covered = (if .total_num_lines > 0 then ((.total_num_lines - .total_num_violations) * 100 / .total_num_lines) else null end)' \
    "${parts[@]}" > "$out/diff.json"
  changed_lines=$(jq '.total_num_lines' "$out/diff.json")
  missed=$(jq '.total_num_violations' "$out/diff.json")
  files=$(jq -c '[.src_stats | to_entries[] | select(.value.violation_lines | length > 0)
                  | {file: .key, percent: .value.percent_covered, missing: (.value.violation_lines | map(tostring) | join(", "))}]' "$out/diff.json")
  if [ "$changed_lines" -eq 0 ]; then
    status=no-changed-lines
  else
    changed_pct=$(jq '.total_percent_covered' "$out/diff.json")
    if awk -v p="$changed_pct" -v t="$threshold" 'BEGIN { exit !(p >= t) }'; then status=pass; else status=fail; fi
  fi
elif [ "${#reports[@]}" -gt 0 ]; then
  status=reported
fi

jq -n --arg status "$status" --argjson overall "$overall" --argjson baseline "$baseline" --argjson delta "$delta" \
  --argjson changed_pct "$changed_pct" --argjson changed_lines "$changed_lines" --argjson missed "$missed" \
  --argjson threshold "$threshold" --argjson files "$files" \
  '{status: $status, overall: $overall, baseline: $baseline, delta: $delta, changed_percent: $changed_pct,
    changed_lines: $changed_lines, missed_lines: $missed, threshold: $threshold, files: $files}' \
  > "$out/summary.json"

"$here/coverage-render.sh" "$out/summary.json" > "$out/summary.md"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || cat "$out/summary.md" >> "$GITHUB_STEP_SUMMARY"

if [ "$status" = fail ]; then
  echo "::notice::Changed lines are below $threshold% covered; ci-ok fails unless the owner exempts this commit."
fi
echo "Coverage: $status"
