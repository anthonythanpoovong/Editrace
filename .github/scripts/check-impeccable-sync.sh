#!/usr/bin/env bash
# Fails when the two vendored impeccable copies -- .claude/skills/impeccable (Claude Code) and
# .github/skills/impeccable (the GitHub-side agent) -- drift in a way an upstream update is likely to
# cause by accident (#153 review, should-fix #7): a file added to one copy and not the other, or the
# two disagreeing about which upstream engine version they vendor.
#
# This deliberately does NOT diff file contents: the two copies are forks, not plain duplicates --
# PROVENANCE.md documents real, intentional per-runtime differences beyond their own path (e.g. the
# AskUserQuestion tool only exists for .claude's consumer, and CLAUDE.md vs .github/copilot-instructions.md
# is a different convention per runtime), so a content-equality check would fail on correct content.
# ROOTS overrides the two directories to compare (the unit test uses it): "<dir-a> <dir-b>".
set -euo pipefail
cd "$(dirname "$0")/../.."

read -r -a roots <<< "${ROOTS:-.claude/skills/impeccable .github/skills/impeccable}"
a=${roots[0]}
b=${roots[1]}
[ -d "$a" ] && [ -d "$b" ] || { echo "Both $a and $b must exist." >&2; exit 2; }

fail=0

rel_files() { (cd "$1" && find . -type f | sed 's#^\./##' | sort); }
files_a=$(rel_files "$a")
files_b=$(rel_files "$b")

while IFS= read -r f; do
  [ -n "$f" ] || continue
  if ! grep -qxF "$f" <<< "$files_b"; then
    echo "::error::$a/$f has no counterpart at $b/$f."
    fail=1
  fi
done <<< "$files_a"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if ! grep -qxF "$f" <<< "$files_a"; then
    echo "::error::$b/$f has no counterpart at $a/$f."
    fail=1
  fi
done <<< "$files_b"

version_a=$(sed -n 's/^version: *\(.*\)$/\1/p' "$a/SKILL.md" | head -n 1)
version_b=$(sed -n 's/^version: *\(.*\)$/\1/p' "$b/SKILL.md" | head -n 1)
if [ "$version_a" != "$version_b" ]; then
  echo "::error::SKILL.md version differs: $a is $version_a, $b is $version_b. Apply the same upstream update to both."
  fail=1
fi

engine_a=$(cat "$a/scripts/VERSION" 2>/dev/null || echo "")
engine_b=$(cat "$b/scripts/VERSION" 2>/dev/null || echo "")
if [ "$engine_a" != "$engine_b" ]; then
  echo "::error::scripts/VERSION differs: $a is '$engine_a', $b is '$engine_b'. Apply the same upstream update to both."
  fail=1
fi

[ "$fail" -eq 0 ] && echo "$a and $b have the same files and the same skill/engine versions."
exit "$fail"
