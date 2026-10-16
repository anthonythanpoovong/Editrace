#!/usr/bin/env bash
# Renders the coverage summary (a summary.json from coverage-gate.sh, optionally with an "exemption" object
# added by coverage-decide.sh) as markdown for the job summary and the sticky PR comment (#129).
# Usage: coverage-render.sh summary.json > summary.md. The first line is the marker the comment is found by.
set -euo pipefail
f=${1:?}
j() { jq -r "$1" "$f"; }
# Rounded down, so a failing 79.96% is never shown as 80%.
fmt() { [ "$1" = null ] && echo "n/a" || awk -v p="$1" 'BEGIN { printf "%.1f%%", int(p * 10) / 10 }'; }
fmt_delta() { [ "$1" = null ] && echo "n/a" || awk -v d="$1" 'BEGIN { printf "%+.1f points", d }'; }

status=$(j .status); threshold=$(j .threshold); changed=$(fmt "$(j .changed_percent)")
changed_lines=$(j .changed_lines); missed=$(j .missed_lines)

echo "<!-- editrace-coverage -->"
echo "### Coverage"
echo
case "$status" in
  pass) echo "✅ Changed lines are **$changed** covered (needs $threshold%)." ;;
  exempt) echo "⚠️ Changed lines are **$changed** covered (needs $threshold%), but the owner exempted this commit." ;;
  fail) echo "❌ Changed lines are **$changed** covered; the gate needs $threshold%. Add tests for the lines below." ;;
  no-changed-lines) echo "✅ No changed lines have coverage data (docs, SQL, generated files), so the gate does not apply." ;;
  reported) echo "Coverage on \`main\`." ;;
  *) echo "No coverage reports, so there is nothing to gate yet." ;;
esac
echo
echo "| | |"
echo "|---|---|"
echo "| Overall | $(fmt "$(j .overall)") |"
echo "| Change vs main | $(fmt_delta "$(j .delta)") |"
echo "| Changed lines covered | $changed ($((changed_lines - missed)) of $changed_lines) |"
if [ "$missed" -gt 0 ]; then
  echo
  echo "Uncovered changed lines:"
  jq -r '.files[:15][] | "- `\(.file)` (\(.percent)%): lines \(.missing)"' "$f"
fi
if [ "$status" = exempt ]; then
  echo
  echo "Exempted by $(j .exemption.reviewer) on \`$(j '.exemption.sha[0:7]')\`: $(j .exemption.reason)"
fi
if [ "$status" = fail ] || [ "$status" = exempt ]; then
  jq -r '.exemption.notes[]? | "- \(.)"' "$f"
fi
if [ "$status" = fail ]; then
  echo
  echo "_An owner can exempt this commit: submit a review whose text starts with \`/coverage-exempt <reason>\`, then re-run the failed \`ci-ok\` job. A new push needs a new review; \`/coverage-revoke\` cancels one._"
fi
