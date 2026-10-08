# Template schema

`schema/template.schema.json` is the single source of truth for the Editrace template format (JSON Schema 2020-12). Workers write templates; exporters, the MCP servers, the editor ontology and the assistant read them. TypeScript, Pydantic and Zod types are generated from the schema, never hand-written.

A template is a reverse-engineered edit: cuts, pacing, motion, transitions, text, captions, beats and color. It holds **slots** where the user's own footage goes. It never contains source media or audio.

Time and versioning decisions are recorded in [ADR 0002](decisions/0002-time-representation-and-schema-versioning.md). Examples are in [`schema/examples/`](../schema/examples/); fixtures that must be rejected are in `schema/examples/invalid/`.

## Time

Time is **integer frames on one rational timebase**, never float seconds.

Three different rates are in play. Keep them apart:

| Term | What it is | Who owns it |
|---|---|---|
| **Template timebase** | The rational `source.fps`. Every frame count in a template is on this rate. | The template |
| **Target timeline timebase** | The frame rate of the editor project a template is applied to. | The user's project; the adapter reads it at apply time |
| **Footage rate** | The frame rate of the user's own clip in a slot. | The editor conforms it; templates never rescale to it |

- `source.fps` is the template timebase, a rational `{num, den}`. 29.97 fps is `30000/1001`; 30 fps is `30/1`.
- Frame 0 is the first frame of the reference. A range `{start, duration}` covers frames `start` up to but not including `start + duration`.
- Every position, duration and offset in the document is a whole number of frames at that rate.
- To get seconds, divide: `seconds = frames × den / num`. Do this only for display.

### Rescaling to the target timeline

A slot's `range` says where it sits on the **output timeline**. When an adapter applies a template to a project whose timeline fps differs from `source.fps`, it rescales to the **target timeline** fps, not the fps of the user's footage. This is a requirement for every adapter.

With template rate `num_s/den_s`, target rate `num_t/den_t`, and `f` a boundary in template frames:

1. **Rescale each absolute boundary once**, with integer arithmetic only:
   `rescale(f) = floor((2·f·num_t·den_s + num_s·den_t) / (2·num_s·den_t))`.
   This is `f × target_fps / template_fps` rounded to the nearest integer, **halves rounding up**.
2. **Add the timeline offset after rescaling.** If the target timeline starts at a non-zero frame (for example 01:00:00:00), `target_frame = offset + rescale(f)`. The offset is in target frames, comes from the project, and never enters the template.
3. **Derive every duration as a difference**: `duration' = rescale(start + duration) − rescale(start)`. Never rescale a duration on its own.
4. **Offsets inside an element**, such as a zoom/pan keyframe's `frame`, are rescaled as absolute positions and re-based: `rescale(slot.start + k) − rescale(slot.start)`.
5. **Clamp collapsed ranges.** If a non-empty range rescales to zero frames, set its duration to 1 frame and report the element as *approximated*.
6. **Do not rescale** `speed` (a ratio), `source_range` (reference-video metadata, not applied to the user's footage), or anything that is not a frame count.

Worked examples (these become the shared test vectors):

| Case | Template → target | Input | Result |
|---|---|---|---|
| Boundary drift | 30/1 → 25/1 | boundaries 0, 10, 20, 30 | 0, 8, 17, 25 (durations 8, 9, 8) |
| Half rounds up | 30/1 → 15/1 | 1 and 3 | 1 and 2 |
| Exact rational | 30000/1001 → 24000/1001 | 100 | 80 |
| Timeline offset | 30/1 → 25/1, offset 90000 | 10 | 90008 |
| Keyframe offset | 30/1 → 25/1 | slot start 10, keyframe `frame` 5 | 13 − 8 = 5 |
| Collapse | 60/1 → 24/1 | `{start: 10, duration: 1}` | `{start: 4, duration: 1}`, reported as approximated |
| Identity | any → same rate | any `f` | `f` (plus offset) |

Rounding each duration separately drifts. Three 10-frame slots at 30 fps rescaled to 25 fps:

| | boundaries | durations |
|---|---|---|
| Source (30 fps) | 0, 10, 20, 30 | 10, 10, 10 |
| Exact × 25/30 | 0, 8.33, 16.67, 25 | |
| Wrong: round each duration | 0, 8, 16, 24 | 8, 8, 8 (one frame short) |
| Right: round each boundary | 0, 8, 17, 25 | 8, 9, 8 |

### Variable frame rate is a lossy conform

A reference with a variable frame rate is conformed to a constant rate at ingest. This is **lossy**: frames are duplicated or dropped, so a conformed time can differ from the original presentation time by up to half a conformed frame, and detections near a cut can move by about one frame.

- `source.vfr` is `true`, and `source.original_fps` records the nominal original rate.
- `source.conform` (`detector`, `version`) records which tool conformed it. It is **required whenever `vfr` is true**.
- Conformance does not change any element's `confidence`. The loss is recorded once, on `source`.
- Treat times from a conformed reference as accurate to roughly one frame, never sample-exact. Adapters say so in their apply report.
- The original timing is never re-derived from the template. If exact timing matters, re-analyse the reference.

### Timecode, SMPTE and drop-frame

Timecode is a labelling scheme for frames, not a different time. **Templates store no timecode** and readers never accept timecode strings.

- Frame counts are authoritative. Drop-frame timecode skips timecode *labels*, never frames, so it has no effect on any frame count in a template.
- Drop-frame versus non-drop-frame is a property of the **target timeline**, read by the adapter and never stored in the template. It exists only at 29.97 and 59.94; 23.976 has no drop-frame form.
- When an adapter produces or reads timecode, it converts using the target timeline's setting. At 29.97 drop-frame, labels `;00` and `;01` are skipped at the start of every minute except every tenth. For example, frame 1799 is `00:00:59;29`, frame 1800 is `00:01:00;02`, and frame 17982 is `00:10:00;00`.
- Timecode start offsets such as 01:00:00:00 are timeline offsets (step 2 of rescaling), not template data.

## Versioning

`schema_version` is semver (`MAJOR.MINOR.PATCH`). Version `0.x` follows the same rules as `1.x`.

| Change | Bump |
|---|---|
| New optional field, new optional section, new enum value, new track kind | Minor |
| Loosening a constraint (a larger maximum, a wider pattern) | Minor |
| Description, documentation or example changes; a schema bug fix that accepts the same valid documents | Patch |
| Removing or renaming a field or section | Major |
| Making an optional field required, or adding a required field | Major |
| Tightening a constraint, changing a default, a type, a unit or the meaning of a value | Major |

A major bump needs an ADR and a migration script. A field is marked deprecated in its description for at least one minor release before a major removes it.

| A consumer sees | It does |
|---|---|
| Same major, higher or lower minor | Accepts; ignores unknown optional fields |
| Any patch difference | Accepts; patch is never inspected |
| Higher major | Rejects with an error naming both versions |
| Lower major | Rejects unless a migration exists, then loads through it |
| Unknown enum value or track kind | Treats it as unsupported; the adapter reports the element as skipped and never fails the whole template |

Rules for writers and tools:

- Workers validate their output before saving. Enums are strict for writers.
- A tool that reads and rewrites a template **preserves unknown fields** it does not understand, so a template from a newer minor is not silently stripped.
- When partial templates from several workers are merged, they must share a major version, and the merged `schema_version` is the highest minor among them.
- Readers must not rely on enum exhaustiveness. Generated union types look exhaustive, but a template from a newer minor can hold a value the reader has never seen.

Two places use an escape hatch: transition `type` has `"other"` plus `type_detail`, and track `kind` is a free string so unknown kinds are skipped. Objects are open (unknown fields allowed) so a newer minor still passes an older validator. The one exception is `sound_ref`, which is closed so audio fields cannot be added.

### Contract tests

Required for every adapter and reader. The shared fixtures are in [`schema/test-vectors/`](../schema/test-vectors/):

| File | What it pins down |
|---|---|
| `rescale.json` | The rescale algorithm: boundary drift, half-up, exact rationals, timeline offset, collapsed ranges, keyframe re-basing |
| `timecode.json` | Frame to timecode at 29.97 and 59.94 drop-frame, non-drop-frame, and 23.976 |
| `versions.json` | What a reader does with each `schema_version`, including migrations |
| `forward-compat.json` | A newer-minor template with an unknown field, enum value and track kind: accepted, skipped, preserved |

`schema/check-vectors.sh` runs a small reference implementation against them in CI, so the fixtures cannot drift from this document. Adapters and readers in other languages must reproduce the same results.

- **Adapters:** all rescale vectors above; the 29.97 drop-frame and non-drop-frame cases; an apply report that flags approximate timing when `vfr` is true; an unknown enum value or track kind comes back as "skipped" while the rest of the template applies.
- **Readers** (MCP servers, web app, assistant, exporters): the version table; unknown optional fields survive a round trip; an `audio` field on `sound_ref` is rejected.

## Conventions

- **Ids** (`id`): lowercase letters, digits, hyphen and underscore, up to 64 characters, unique within the document.
- **Detected elements** carry `confidence` (0 to 1) and `provenance` (`detector`, `version`). Hand-authored elements use `confidence: 1` and the detector name `"manual"`.
- **Normalized coordinates** are fractions (0 to 1) of frame width and height, with the origin at the top-left.
- **Slots, not media:** no field holds footage, audio, or a URL to the user's media. A LUT or sound is referenced by name or link only.

## Field reference

"Req." means required. Types named in `code` are defined under [Shared types](#shared-types).

### Top level

| Field | Type | Req. | Description |
|---|---|---|---|
| `schema_version` | string | yes | Semver of the schema the document was written against. |
| `source` | `Source` | yes | The reference video, described but never embedded. |
| `tracks` | array of `Track` | yes | Ordered tracks, bottom to top. |
| `beats` | `Beats` | no | Beat grid of the reference soundtrack. |
| `sound_ref` | `SoundRef` | no | Pointer to the sound used; present only when identified. |

### Source

| Field | Type | Req. | Description |
|---|---|---|---|
| `duration` | integer ≥ 1 | yes | Length of the reference in frames at `fps`. |
| `fps` | `Rational` | yes | The template timebase. Constant. |
| `vfr` | boolean | no | True if the reference was variable-frame-rate and was conformed (a lossy step). Default false. |
| `original_fps` | `Rational` | no | Nominal rate before conforming. Provenance only; set when `vfr` is true. |
| `conform` | `Provenance` | when `vfr` is true | Which tool conformed a variable-frame-rate reference, and its version. |
| `resolution.width` | integer ≥ 1 | yes | Width in pixels. |
| `resolution.height` | integer ≥ 1 | yes | Height in pixels. |
| `aspect_ratio` | `Rational` | yes | Display aspect ratio, e.g. `9/16` for vertical video. |
| `content_hash` | string | yes | `sha256:` plus 64 hex characters, of the reference file. Used to cache and de-duplicate analysis. |

### Track

A layer holding one kind of element. A track's `kind` decides which element array it must have.

| Field | Type | Req. | Description |
|---|---|---|---|
| `id` | `Id` | yes | Track id. |
| `kind` | string | yes | `video` (needs `slots`), `text` (needs `text_overlays`), `captions` (needs `captions`). Unknown kinds are skipped. |
| `name` | string | no | Human-readable label, up to 128 characters. |
| `slots` | array of `Slot` | per kind | Video tracks: placeholders for the user's footage. |
| `cuts` | array of `Cut` | no | Video tracks: hard cuts between slots. |
| `transitions` | array of `Transition` | no | Video tracks: transitions between slots. |
| `text_overlays` | array of `TextOverlay` | per kind | Text tracks: on-screen text. |
| `captions` | array of `Caption` | per kind | Caption tracks: spoken-word captions. |

### Slot

A placeholder for one shot of the user's footage. Also carries `confidence` and `provenance`.

| Field | Type | Req. | Description |
|---|---|---|---|
| `id` | `Id` | yes | Slot id. |
| `range` | `FrameRange` | yes | Where the slot sits on the output timeline. |
| `source_range` | `FrameRange` | no | Where the shot sits in the reference video, when different from `range` (trimmed or reordered references). |
| `speed` | `Rational` | no | Playback speed as an exact ratio: `1/1` normal, `2/1` double, `1/2` half. Default `1/1`. |
| `zoom_pan` | array of `ZoomPanKeyframe` | no | Zoom and pan keyframes in time order. |
| `color` | `Color` | no | Per-shot color treatment. |

### ZoomPanKeyframe

The framing at one moment inside a slot. Values between keyframes follow the easing of the earlier one.

| Field | Type | Req. | Description |
|---|---|---|---|
| `frame` | integer ≥ 0 | yes | Offset in frames from the **start of the slot**. |
| `scale` | number > 0 | yes | Zoom factor: `1` full frame, `2` a 2× punch-in. |
| `center.x` | number 0–1 | yes | Horizontal position of the view center. |
| `center.y` | number 0–1 | yes | Vertical position of the view center. |
| `easing` | enum | no | `linear` (default), `ease_in`, `ease_out`, `ease_in_out`, `hold`. How to move to the next keyframe. |

### Color

Relative adjustments; omitted means unchanged.

| Field | Type | Req. | Description |
|---|---|---|---|
| `brightness` | number −1 to 1 | no | Darker to brighter. |
| `contrast` | number −1 to 1 | no | Flatter to punchier. |
| `saturation` | number −1 to 1 | no | Monochrome to vivid. |
| `temperature_k` | integer 1000–40000 | no | White balance in kelvin. |
| `tint` | number −1 to 1 | no | Green to magenta. |
| `lut` | string | no | Name of a look-up table. A name only; the table is never embedded. |

### Cut

Also carries `confidence` and `provenance`.

| Field | Type | Req. | Description |
|---|---|---|---|
| `id` | `Id` | yes | Cut id. |
| `frame` | integer ≥ 0 | yes | First frame of the shot after the cut, on the output timeline. |

### Transition

Also carries `confidence` and `provenance`.

| Field | Type | Req. | Description |
|---|---|---|---|
| `id` | `Id` | yes | Transition id. |
| `type` | enum | yes | `dissolve`, `fade_black`, `fade_white`, `wipe`, `push`, `slide`, `zoom`, `whip`, `glitch`, `other`. |
| `type_detail` | string | no | Free-text description when `type` is `other`. |
| `range` | `FrameRange` | yes | Frames the transition covers on the output timeline. |
| `from_slot` | `Id` | no | Outgoing slot. |
| `to_slot` | `Id` | no | Incoming slot. |

### TextOverlay

On-screen text. Also carries `confidence` and `provenance`.

| Field | Type | Req. | Description |
|---|---|---|---|
| `id` | `Id` | yes | Overlay id. |
| `text` | string | yes | The text shown, 1–2000 characters. |
| `bbox` | `NormalizedBBox` | yes | Where it sits in the frame. |
| `range` | `FrameRange` | yes | Frames during which it is visible. |
| `style` | `TextStyle` | no | Hints for reproducing the look; editors approximate them. |

### TextStyle

| Field | Type | Req. | Description |
|---|---|---|---|
| `font_family` | string | no | Best-guess font family. |
| `font_size` | number 0–1 | no | Cap height as a fraction of frame height. |
| `weight` | integer 100–900 | no | CSS-style font weight. |
| `color` | string | no | Text color as `#RRGGBB`. |
| `alignment` | enum | no | `left`, `center`, `right`, inside the bbox. |
| `background_color` | string | no | Box behind the text as `#RRGGBB`, if any. |

### Caption

A caption block made of lines of timed words. Also carries `confidence` and `provenance`.

| Field | Type | Req. | Description |
|---|---|---|---|
| `id` | `Id` | yes | Caption id. |
| `range` | `FrameRange` | yes | Frames the whole block is on screen. |
| `language` | string | no | BCP 47 tag, e.g. `en` or `pt-BR`. |
| `lines` | array | yes | Lines in display order (at least one). |
| `lines[].words` | array of word | yes | Words in spoken order (at least one). |
| `lines[].words[].text` | string | yes | The word as displayed. |
| `lines[].words[].range` | `FrameRange` | yes | Frames during which the word is spoken or highlighted. |

### Beats

Markers only; no audio. Also requires `confidence` and `provenance`.

| Field | Type | Req. | Description |
|---|---|---|---|
| `bpm` | number | yes | Tempo, greater than 0 and at most 400. |
| `beat_frames` | array of integer | yes | Frame of every beat, ascending, unique. Includes downbeats. |
| `downbeat_frames` | array of integer | yes | Frame of every downbeat (first beat of a bar), ascending, unique. |

### SoundRef

Identification only; audio is never stored or exported. This object is closed.

| Field | Type | Req. | Description |
|---|---|---|---|
| `id` | string | yes | Identifier at the provider that identified the sound. |
| `title` | string | yes | Track title. |
| `artist` | string | yes | Artist name. |
| `link` | string | yes | `https` link to the sound at its source. |
| `confidence` | `Confidence` | yes | Identification confidence. |
| `provenance` | `Provenance` | yes | Which detector identified it. |

## Shared types

| Type | Shape | Description |
|---|---|---|
| `Id` | string | See [Conventions](#conventions). |
| `Rational` | `{ num, den }`, integers ≥ 1 | An exact ratio: fps, speed, aspect ratio. `num` is the numerator, `den` the denominator. |
| `FrameRange` | `{ start, duration }`, `start` ≥ 0, `duration` ≥ 1 | A span of frames: first frame and length. |
| `Confidence` | number 0–1 | How sure the detector is. |
| `Detection` | `{ confidence, provenance }`, both required | Mixed into every detected element (slots, cuts, transitions, text overlays, captions, beats). |
| `CaptionWord` | `{ text, range }` | One timed word inside a caption line; see [Caption](#caption). |
| `Provenance` | `{ detector, version }`, non-empty strings up to 64 characters | Which detector and version produced an element. |
| `NormalizedBBox` | `{ x, y, w, h }` | Top-left corner and size as fractions of the frame; `x`, `y` in 0–1, `w`, `h` in (0, 1]. `x + w` and `y + h` must not exceed 1; consumers check this, the schema does not. |

## Validating

```sh
pip install check-jsonschema
check-jsonschema --check-metaschema schema/template.schema.json
check-jsonschema --schemafile schema/template.schema.json schema/examples/*.json
schema/check-invalid.sh     # fixtures that must be rejected, for the stated reason
schema/check-docs.sh        # every schema field is documented here
schema/check-vectors.sh     # the shared test vectors match the reference implementation
```

CI runs the same checks. To change the schema, use `/schema-change`.
