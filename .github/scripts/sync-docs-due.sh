#!/usr/bin/env bash
# Prints the body of the "Docs sync due" issue, or nothing when no large-change area changed between
# BASE (the wiki's last Docs-Synced-To commit) and HEAD. Usage: sync-docs-due.sh BASE HEAD, run inside
# a clone of the repo. The areas come from sync-docs-paths.sh, so this and the per-PR nudge agree.
# A bad BASE or HEAD fails the script (nothing is printed), never silently reports "up to date".
set -euo pipefail

base=${1:?usage: sync-docs-due.sh BASE HEAD}
head=${2:?usage: sync-docs-due.sh BASE HEAD}
here=$(dirname "$0")

areas=$(git diff --name-only "$base" "$head" | "$here/sync-docs-paths.sh")
[ -n "$areas" ] || exit 0

commits=$(git rev-list --count --no-merges "$base..$head")
synced_on=$(git log -1 --format=%cs "$base")

cat <<EOF
<!-- sync-docs-due -->
📚 \`main\` has changed since the docs were last synced (\`${base:0:7}\`, ${synced_on}): ${commits} commits, touching

${areas}

Run \`/sync-docs\` to update the README, \`docs/plan.md\` and the wiki. This issue closes itself on the next weekly check once the wiki's \`Docs-Synced-To\` marker has caught up.
EOF
