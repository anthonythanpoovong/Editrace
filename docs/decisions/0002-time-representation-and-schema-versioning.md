# 0002: Represent template time as integer frames on one rational timebase, and version the schema with semver

- **Status:** Proposed
- **Date:** 2026-10-07
- **Author:** @anthonythanpoovong
- **Deciders:** @anthonythanpoovong
- **Related:** #1 (template schema v0), #2 (codegen), #52 (golden dataset), Key Decisions in `docs/plan.md`

## Context

`schema/template.schema.json` is the single source of truth. Workers write it; exporters, the MCP servers, the editor ontology and the assistant read it. Editors use rational time (FCPXML especially), and float drift causes off-by-one cuts. Time representation and versioning are the choices that are hardest to change once consumers exist, so we decide them before the schema ships.

A slot's range describes a shot in the reference video, which has one known fps. The user's own clip doesn't exist until the Bridge applies the template, so its fps is unknown at analysis time.

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

**Time**
- Every position and duration is an integer frame count on the template timebase `source.fps` (`{num, den}`; 29.97 is 30000/1001). Float seconds never appear.
- Variable-frame-rate references are conformed to a constant rate at ingest. `source` keeps the original fps and a `vfr` flag for provenance.
- Adapters rescale to the target **timeline** fps (the editor project's rate, not the footage's) by rounding each **absolute boundary once** (round-half-up) and deriving durations as differences between rounded boundaries. This keeps cuts consistent and total length correct (for example, three 10-frame slots at 30 fps become boundaries 0, 8, 17, 25 at 25 fps).
- The rule is a requirement. Every adapter must pass a shared rescale test vector in its contract tests.

**Versioning**
- `schema_version` is semver. Minor versions are additive only; a major bump requires a new ADR and a migration script.

| Consumer sees | Behaviour |
|---|---|
| Same major, higher or lower minor | Accept; ignore unknown optional fields |
| Higher major | Reject with an error naming both versions |
| Lower major | Reject unless a migration exists; load through the migration |
| Unknown enum value (reader side) | Treat as unsupported; adapter reports the element as skipped. Never fail the whole template |

Schema enums are strict for writers: workers validate their output before saving, and adding an enum value is a minor bump. Readers must not rely on enum exhaustiveness and must handle unknown values at runtime, even though generated union types look exhaustive.

Objects are open (unknown fields allowed) so a newer minor passes an older validator, except `sound_ref`, which is closed so audio fields can't be added.

## Consequences

- **Good:** one coherent timeline per file; no float drift; frame-exact cuts; clear version rules for every consumer.
- **Bad / accepted trade-offs:** adapters carry the rescaling logic; reader code needs a default branch for unknown enum values; VFR references lose their original timing at ingest.
- **One-way or two-way door:** one-way. Reversing means a major version bump, an ADR and a migration of every stored template.
- **Follow-up work:** the schema PR (#1) and codegen (#2); a shared rescale test vector for adapters, plus an unknown-transition-type case that must come back as "skipped"; ingest-time VFR conformance in the worker framework; production measurement of cut accuracy via the golden set (#52).
- **Affected:** schema, exporters, Bridge adapters, MCP contracts, docs (`docs/schema.md`).

## How we'll know

- Every adapter passes the shared rescale test vector, with zero off-by-one boundaries.
- All schema examples validate in CI on every PR.
- No schema change merges that breaks an existing example without a new ADR.

Revisit if we need a template with genuinely mixed frame rates, or if golden-set cut recall on VFR references drops noticeably after normalisation.

## Open questions

- Detection accuracy cost near cuts from conforming VFR at ingest (owner: ingest worker).

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
| Observability / metric | ✅ | Test vector, CI validation, no breaking change without ADR |
| Ownership | ✅ | Schema owners; ingest worker owns VFR |

</details>
