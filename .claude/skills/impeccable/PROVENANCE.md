# Provenance (#153 review)

This skill is vendored twice in this repo: here, and at `.github/skills/impeccable/` (for the
GitHub-side agent, whose hook config was `.github/hooks/impeccable.json`, instead of this copy's
`.claude/settings.local.json`). Nothing enforces that the two stay in sync — check both when updating
either.

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
for every contributor and agent, with no version pin or checksum recorded) is removed for the same
reason. One documented exception from the launcher itself: a sandbox with no network egress needs
`impeccable` preinstalled on PATH, since it can neither reach the vendored sibling nor download.
