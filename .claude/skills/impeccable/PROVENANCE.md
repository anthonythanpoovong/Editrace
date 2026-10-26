# Provenance (#153 review)

This skill is vendored twice in this repo: here, and at `.github/skills/impeccable/` (for the
GitHub-side agent). The two are not a plain copy of each other -- they're forks, each adapted to what
its own consumer can actually do, so **don't try to make them byte-identical**:

- This copy is read by `.claude/agents/impeccable-*.md` plus the `/impeccable` skill itself for
  interactive sessions, invoked via `.claude/settings.local.json`. Its reference files call the
  `AskUserQuestion` tool to clarify, and point at `CLAUDE.md` for project memory.
- `.github/skills/impeccable/` is read by `.github/agents/impeccable-*.agent.md`, the GitHub-side
  agent definitions. They have no `AskUserQuestion` tool, so their reference files (e.g.
  `reference/bolder.md`) say "ask the user directly to clarify" instead, and point at
  `.github/copilot-instructions.md` for project memory (e.g. `reference/critique.md`) instead of
  `CLAUDE.md`.

What IS expected to stay identical between the two: every other file's content (the parts that aren't
runtime-specific), which relative paths exist in each copy, the `SKILL.md` frontmatter `version`, and
the engine `scripts/VERSION` -- `.github/scripts/check-impeccable-sync.sh` checks exactly those three
things in CI (not full content equality, which would fail on the intentional differences above) and
fails if applying an upstream update to one copy and not the other leaves them out of step.

- Skill version (`SKILL.md` frontmatter): 4.5.0
- Scripts `VERSION`: 0.1.11
- Upstream source: `https://github.com/pbakaus/impeccable`, releases tagged `engine-v<VERSION>` —
  found by reading `scripts/impeccable`'s own download fallback (`IMPECCABLE_DOWNLOAD_BASE`), not
  recorded anywhere else in this repo before this fix.

**Fix applied (#153 review, Anthony's suggestion):** the vendored `scripts/bin/windows-x64/impeccable.exe`
(previously sha256 `605b5b442d2a65d270ef989de13371444849526249f511d397ca7424c184db49`, 17,096,584 bytes,
byte-identical to the `.github/skills/impeccable/` copy) is removed from the repo and gitignored.
`scripts/impeccable` already supports running with no sibling binary: it falls back to
`~/.impeccable/bin/<version>/impeccable`, and failing that, downloads that exact version from the
upstream release above into that cache, verifying it against the release's `.sha256` sidecar before
exec'ing it. The committed `.github/hooks/impeccable.json` (which auto-ran the binary after every edit,
for every contributor and agent, with no version pin or checksum recorded) was removed for the same
reason -- the `.github/` copy now has no hook of its own; it's read on demand by the
`.github/agents/impeccable-*` definitions instead. One documented exception from the launcher itself: a
sandbox with no network egress needs `impeccable` preinstalled on PATH, since it can neither reach the
vendored sibling nor download.
