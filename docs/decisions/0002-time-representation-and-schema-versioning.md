# 0002: Represent template time as integer frames on one rational timebase, and version the schema with semver

- **Status:** Accepted
- **Date:** 2026-10-07 · Accepted: 2026-10-09 (#175 merged)
- **Author:** @anthonythanpoovong
- **Deciders:** @anthonythanpoovong
- **Related:** #1 (template schema v0), #2 (codegen), #52 (golden dataset), Key Decisions in `docs/plan.md`

## Context

`schema/template.schema.json` is the single source of truth. Workers write it; exporters, the MCP servers, the editor ontology and the assistant read it. Editors use rational time (FCPXML especially), and float drift causes off-by-one cuts. Time representation and versioning are the choices that are hardest to change once consumers exist, so we decide them before the schema ships.

A slot's range describes a shot in the reference video, which has one known fps. The user's own clip doesn't exist until the Bridge applies the template, so its fps is unknown at analysis time.

## Terminology

Three different rates are in play. Mixing them up is the bug this ADR exists to prevent.

| Term | What it is | Where it lives | Who owns it |
|---|---|---|---|
| **Template timebase** | The rational `source.fps`. Every frame count in a template is on this rate. | The template | The analysis pipeline |
| **Target timeline timebase** | The frame rate of the editor project the template is applied to. | The editor, read by the adapter at apply time | The user's project |
| **Footage rate** | The frame rate of the user's own clip placed in a slot. | The user's media | The editor conforms it; the template never rescales to it |

A **boundary** is an absolute frame position (a slot start, a slot end, a cut, a transition edge). A **duration** is always the difference between two boundaries.

## Options considered

### Option A: One template timebase, bare integer frames
- `source.fps` is a rational `{num, den}`, stored once. Every position and duration is an integer frame count against it.
- ✅ Compact; one place to validate; two timebases can't be mixed in one file.
- ❌ Mixed rates become an apply-time concern for adapters. Needs a rounding rule.
- Cost / effort: low.

### Option B: Per-timestamp `{frames, rate}` (OTIO style)
- Every timestamp declares its own rate.
- ✅ Self-describing; matches OTIO and FCPXML natively.
- ❌ Repeats the rate in every field; a buggy detector can mix rates in one file and consumers must reconcile them.

### Option C: Integer milliseconds
- ✅ Simple and unit-agnostic.
- ❌ Can't represent 29.97 or 23.976 fps exactly; rounding to ms at export is a source of off-by-one frame errors.

## Decision

We will use **Option A**, and version the schema with **semver**.

### Time in the template

- Every position and duration is an integer frame count on the template timebase `source.fps` (`{num, den}`; 29.97 is 30000/1001). Float seconds never appear.
- Frame 0 is the first frame of the reference. A range `{start, duration}` covers frames `start` up to but not including `start + duration`.
- Templates store frames only. They never contain timecode strings (see Timecode below).

### Rescaling to the target timeline

Adapters convert from the template timebase to the target timeline timebase. This is an adapter responsibility and a requirement, not advice.

**Definitions.** Template rate `rs = num_s/den_s`; target rate `rt = num_t/den_t`; `f` a boundary in template frames.

1. **Rescale each absolute boundary once**, using integer arithmetic only (no floats):
   `rescale(f) = floor((2·f·num_t·den_s + num_s·den_t) / (2·num_s·den_t))`
   This is `f × rt / rs` rounded to the nearest integer, **halves rounding up**.
2. **Add the timeline offset after rescaling.** Editors often start a timeline at a non-zero frame (for example 01:00:00:00). The adapter reads that start offset, in target frames, from the project and computes `target_frame = offset + rescale(f)`. The offset never enters the template and is never rescaled.
3. **Derive every duration as a difference** of rescaled boundaries: `duration' = rescale(start + duration) − rescale(start)`. Never rescale a duration on its own.
4. **Offsets inside an element** (for example a zoom/pan keyframe's `frame`, which is relative to its slot) are rescaled as absolute positions and then re-based: `rescale(slot.start + k) − rescale(slot.start)`.
5. **Clamp collapsed ranges.** If a non-empty range rescales to zero frames (a big downscale), the adapter sets its duration to 1 frame and lists the element as *approximated* in its report.
6. **Do not rescale** `speed` (a ratio, unaffected by timebase), `source_range` (reference-video metadata, not applied to the user's footage), or anything that is not a frame count.

**Worked examples** (these are the shared test vectors; see Contract tests):

| Case | Template → target | Input | Result |
|---|---|---|---|
| Boundary drift | 30/1 → 25/1 | boundaries 0, 10, 20, 30 | 0, 8, 17, 25 (durations 8, 9, 8; rounding durations alone gives 8, 8, 8 and ends a frame short) |
| Half rounds up | 30/1 → 15/1 | 1 and 3 | 1 and 2 |
| Exact rational | 30000/1001 → 24000/1001 | 100 | 80 |
| Timeline offset | 30/1 → 25/1, offset 90000 | 10 | 90008 |
| Keyframe offset | 30/1 → 25/1 | slot start 10, keyframe `frame` 5 | 13 − 8 = 5 |
| Collapse | 60/1 → 24/1 | `{start: 10, duration: 1}` | `{start: 4, duration: 1}`, reported as approximated |
| Identity | any → same rate | any `f` | `f` (plus offset) |

### Variable frame rate is a lossy conformance

Variable-frame-rate references are conformed to a constant rate at ingest. This transform is **lossy**: frames are duplicated or dropped, so a conformed frame time can differ from the original presentation time by up to half a conformed frame interval, and detections near a cut can move by about one frame.

Provenance behavior:
- `source.vfr` is `true` and `source.original_fps` records the nominal original rate.
- The conform step records who did it, using the same `{detector, version}` shape as detections, in a `source.conform` object. It is required whenever `vfr` is true. (This is a schema addition for #1.)
- Conformance does not change any element's `confidence`; the loss is recorded once, on `source`, not spread across every element.
- Consumers must treat times from a conformed reference as accurate to roughly one frame, never sample-exact, and adapters must say so in their apply report when `vfr` is true.
- The original is never re-derived from the template. If exact timing matters, the reference must be re-analysed.

### Timecode, SMPTE and drop-frame

Timecode is a labelling scheme for frames, not a different time. The template stores none of it.

- Frame counts are authoritative. **Drop-frame timecode skips timecode labels, never frames**, so it has no effect on any frame count in the template.
- Drop-frame versus non-drop-frame is a property of the **target timeline**, read by the adapter. It never appears in the template. It applies only at 29.97 and 59.94; 23.976 has no drop-frame form.
- When an adapter must produce or consume timecode, it converts frames to and from timecode using the target timeline's drop-frame setting. At 29.97 drop-frame, labels `;00` and `;01` are skipped at the start of every minute except every tenth.
- Timecode start offsets (such as 01:00:00:00) are timeline offsets handled in step 2 of rescaling, not template data.
- Readers never accept timecode strings in a template.

### Versioning

`schema_version` is semver `MAJOR.MINOR.PATCH`. Version `0.x` follows the same rules as `1.x`.

**What each kind of change is:**

| Change | Version bump |
|---|---|
| New optional field, new optional section, new enum value, new track kind | Minor |
| Loosening a constraint (a larger maximum, a wider pattern) | Minor |
| Description, documentation or example changes; fixing a bug in the schema that accepts the same valid documents | Patch |
| Removing or renaming a field or section | Major |
| Making an optional field required, or adding a required field | Major |
| Tightening a constraint (a smaller maximum, a stricter pattern), changing a default, a type, a unit or the meaning of a value | Major |

A major bump needs a new ADR and a migration script. A field is marked deprecated in its description for at least one minor release before a major removes it.

**What each consumer does:**

| Consumer sees | Behaviour |
|---|---|
| Same major, higher or lower minor | Accept; ignore unknown optional fields |
| Any patch difference | Accept; patch is never inspected |
| Higher major | Reject with an error naming both versions |
| Lower major | Reject unless a migration exists; load through the migration |
| Unknown enum value or track kind (reader side) | Treat as unsupported; the adapter reports the element as skipped. Never fail the whole template |

**Rules for writers and tools:**
- Workers validate their output against the schema before saving. Enums are strict for writers.
- A tool that reads and rewrites a template must **preserve unknown fields** it doesn't understand, so a template from a newer minor isn't silently stripped.
- When partial templates from several workers are merged, they must share a major version, and the merged `schema_version` is the highest minor among them.
- Readers must not rely on enum exhaustiveness, even though generated union types look exhaustive.

Objects are open (unknown fields allowed) so a newer minor passes an older validator, except `sound_ref`, which is closed so audio fields can't be added.

### Contract tests

These are required, not optional. They live in a shared fixture set (`schema/test-vectors/`, a follow-up to #1) so every adapter and reader runs the same cases.

**Every adapter must pass:**
1. All rescale vectors in the table above, including the offset, keyframe, collapse and half-up cases.
2. A drop-frame case at 29.97: frame 1799 ↔ 00:00:59;29, frame 1800 ↔ 00:01:00;02, frame 17982 ↔ 00:10:00;00, and the same frames at non-drop-frame.
3. Applying a template with `vfr: true` reports approximate timing.
4. An element with an unknown enum value or track kind comes back as "skipped", and the rest of the template still applies.

**Every reader (MCP servers, web app, assistant, exporters) must pass:**
5. The version table: accept a higher minor, accept a patch difference, reject a higher major with both versions named, reject a lower major without a migration.
6. A template with unknown optional fields round-trips with those fields preserved.
7. A template that fails `additionalProperties` on `sound_ref` (for example an `audio` field) is rejected.

**CI** validates the schema and all examples on every PR, and rejects fixtures that must be invalid, for the stated reason.

## Consequences

- **Good:** one coherent timeline per file; no float drift; frame-exact cuts; clear version rules for every consumer; the three rates can't be confused.
- **Bad / accepted trade-offs:** adapters carry the rescaling and timecode logic; reader code needs a default branch for unknown enum values; VFR references lose their original timing at ingest; the contract tests are more work than a slogan.
- **One-way or two-way door:** one-way. Reversing means a major version bump, an ADR and a migration of every stored template.
- **Follow-up work:** the schema PR (#1), including `source.conform`; codegen (#2); the shared fixtures in `schema/test-vectors/`; ingest-time VFR conformance in the worker framework; production measurement of cut accuracy via the golden set (#52).
- **Affected:** schema, exporters, Bridge adapters, MCP contracts, docs (`docs/schema.md`).

## How we'll know

- Every adapter passes the shared test vectors with zero off-by-one boundaries.
- Every reader passes the version and round-trip tests.
- All schema examples validate in CI on every PR.
- No schema change merges that breaks an existing example without a new ADR.

Revisit if we need a template with genuinely mixed frame rates, or if golden-set cut recall on VFR references drops noticeably after normalisation.

## Open questions

- Detection accuracy cost near cuts from conforming VFR at ingest (owner: ingest worker).
- Whether to deprecate-then-remove (one minor of warning) is enough notice once there are external consumers.

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ✅ | Ticket #1 and Key Decisions; no interviews needed for a foundation decision |
| Smallest version | ✅ | Time model and versioning rules only |
| Alternatives | ✅ | Per-timestamp rate, integer ms, template-wide timebase |
| Fit with Key Decisions | ✅ | Implements "frames + rational fps" |
| Data & schema | ✅ | Version table, closed `sound_ref`, major bump = ADR + migration |
| Security & privacy | ✅ | `sound_ref` is closed so no audio fields |
| Cost | n/a | No GPU, LLM or storage impact |
| Failure modes | ✅ | Boundary drift, VFR and newer majors are covered |
| Reversibility | ✅ | One-way door; major bump plus migration |
| Observability / metric | ✅ | Test vectors, CI validation, no breaking change without ADR |
| Ownership | ✅ | Schema owners; ingest worker owns VFR |

</details>
