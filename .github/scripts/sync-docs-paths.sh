#!/usr/bin/env bash
# Reads changed file paths on stdin (one per line) and prints a "- <area>" line for each
# large-change area they touch, in a fixed order. Prints nothing when none match.
# Mirrors the "large changes" list in .claude/skills/sync-docs/SKILL.md. Paths are only ever
# pattern-matched here, never executed or interpolated.
set -euo pipefail

schema=0 adr=0 epic=0 skills=0 ci=0
while IFS= read -r path; do
  case "$path" in
    schema/template.schema.json) schema=1 ;;
    docs/decisions/README.md | docs/decisions/0000-template.md) ;;
    docs/decisions/*.md) adr=1 ;;
    docs/epics/README.md | docs/epics/TEMPLATE.md) ;;
    docs/epics/*.md) epic=1 ;;
    .claude/skills/*) skills=1 ;;
    .github/workflows/*) ci=1 ;;
  esac
done

[ "$schema" -eq 1 ] && echo "- the template schema (\`schema/template.schema.json\`)"
[ "$adr" -eq 1 ] && echo "- an ADR (\`docs/decisions/\`)"
[ "$epic" -eq 1 ] && echo "- an epic (\`docs/epics/\`)"
[ "$skills" -eq 1 ] && echo "- Claude Code skills (\`.claude/skills/\`)"
[ "$ci" -eq 1 ] && echo "- CI workflows (\`.github/workflows/\`)"
exit 0
