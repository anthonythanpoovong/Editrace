---
name: editor-adapter
description: Build or extend an Editrace Bridge editor adapter (DaVinci Resolve, Premiere Pro, Final Cut Pro, CapCut) implementing detect / capabilities / plan / apply → report, with contract tests against a fake adapter and version-pinned fixtures. Use for #33–#36 or when adding support for a template element in an editor.
---

# Editor adapter

Each editor gets the best mechanism it supports: **live where possible, file handoff otherwise** (Key Decision). Every adapter implements the **same interface** so the Bridge treats them all alike (#32):

| Method | Does | Must not |
|---|---|---|
| `detect()` | Is the editor installed or running? Which version and edition? | Launch or modify anything |
| `capabilities()` | Which template elements it can apply, approximate or not do, for this version | Guess. Base it on the tested version matrix. |
| `plan(template)` | **Dry run:** the list of actions, and what would be approximated or skipped | Touch the editor or the file system |
| `apply(template, opts)` | Performs the plan, then returns a **report** | Silently drop elements |

**Report:** applied / skipped / approximated, each with a reason, e.g. "speed ramp converted to 3 linear segments".

## 0. Preflight
- The Bridge core and adapter interface exist (#32), with the language decided in #29. If not, stop. Point to #29 and #32.
- The fake adapter and contract tests exist (#32 acceptance criterion). A new adapter must pass the same contract tests.
- Check the editor's row in the wiki `Editor-Integrations-and-Exports` page for its mechanism and main risk.

| Editor | Mechanism | Story |
|---|---|---|
| DaVinci Resolve | Python scripting API (live); OTIO/FCPXML fallback | #33 |
| Final Cut Pro | FCPXML handoff | #34 |
| Premiere Pro | UXP panel ↔ Bridge over local WebSocket (live); Premiere XML fallback | #35 |
| CapCut | Draft written to local drafts folder | #36 |

## 1. Scope the change
- Which template elements (cuts, transitions, text, captions, markers, speed, zoom/pan, color) are in scope, and for which **editor versions and editions** (e.g. Resolve Free vs Studio).
- For each element: **native**, **approximated** (say how) or **unsupported**. This becomes `capabilities()`.
- Prefer reusing the exporters (`exporters/`, OTIO/FCPXML, CapCut writer) for handoff modes. Don't build a second serializer.

## 2. Implement
- Time from template frames + rational fps into the editor's time base. **Convert exactly once**, using rational arithmetic, with no float drift.
- Clips are **slots**. Reference the user's media or placeholders, never media from the source video.
- Beats and sound: markers and a link only, never audio (Key Decision).
- `plan` and `apply` share one code path: `apply` executes exactly what `plan` listed.
- Errors mid-apply: stop cleanly and report what was applied so far. Don't leave half-built timelines without saying so.
- Log structured, local-only diagnostics for support (#32).

## 3. Test
- **Contract tests** (shared with the fake adapter): `plan` has no side effects; `apply` matches `plan`; the report accounts for every element.
- **Version-pinned fixtures:** expected FCPXML, drafts or API call sequences for the example templates in `schema/examples/`.
- Round trip where possible: export, re-import and compare cuts and timing within frame tolerance.
- A manual check in the real editor, on the pinned version(s). Record the versions in the PR.

## 4. PR
The body includes the element support matrix (native / approximated / unsupported), tested editor versions, a sample report, and test output. After merge, `/sync-docs` updates the wiki `Editor-Integrations-and-Exports` page and `docs/plan.md` → Editor Integrations.

## Rules
- Never claim a capability that isn't covered by a test on a pinned version.
- CapCut's draft format is undocumented and version-sensitive. Pin versions and fail loudly on unknown ones.
