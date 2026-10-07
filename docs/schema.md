# Template schema

`schema/template.schema.json` is the single source of truth for the Editrace template format (JSON Schema 2020-12). Workers write templates; exporters, the MCP servers, the editor ontology and the assistant read them. TypeScript, Pydantic and Zod types are generated from the schema, never hand-written.

A template is a reverse-engineered edit: cuts, pacing, motion, transitions, text, captions, beats and color. It holds **slots** where the user's own footage goes. It never contains source media or audio.

Time and versioning decisions are recorded in [ADR 0002](decisions/0002-time-representation-and-schema-versioning.md). Examples are in [`schema/examples/`](../schema/examples/); fixtures that must be rejected are in `schema/examples/invalid/`.

## Time

Time is **integer frames on one rational timebase**, never float seconds.

- `source.fps` is the timebase, a rational `{num, den}`. 29.97 fps is `30000/1001`; 30 fps is `30/1`.
- Every position, duration and offset in the document is a whole number of frames at that rate.
- A reference with a variable frame rate is conformed to a constant rate at ingest. `source.vfr` and `source.original_fps` record that it happened.
- To get seconds, divide: `seconds = frames × den / num`. Do this only for display.

### Rescaling to the user's timeline

A slot's `range` says where it sits on the **output timeline**. When an adapter applies a template to an editor project whose timeline fps differs from `source.fps`, it rescales to the **timeline** fps, not the fps of the user's footage (the editor conforms the footage).

The rule is a requirement for every adapter:

1. Convert each **absolute boundary** once: `boundary × target_fps / source_fps`.
2. Round to the nearest frame, with halves rounding up.
3. Derive each duration as the difference between rounded boundaries.

Rounding each duration separately drifts. Three 10-frame slots at 30 fps rescaled to 25 fps:

| | boundaries | durations |
|---|---|---|
| Source (30 fps) | 0, 10, 20, 30 | 10, 10, 10 |
| Exact × 25/30 | 0, 8.33, 16.67, 25 | |
| Wrong: round each duration | 0, 8, 16, 24 | 8, 8, 8 (one frame short) |
| Right: round each boundary | 0, 8, 17, 25 | 8, 9, 8 |

Every adapter's contract tests run this case.

## Versioning

`schema_version` is semver (`MAJOR.MINOR.PATCH`). Minor versions are additive only: new optional fields, new optional sections, new enum values. Anything else is a major bump, which needs an ADR and a migration script. Version `0.x` follows the same rules as `1.x`.

| A consumer sees | It does |
|---|---|
| Same major, higher or lower minor | Accepts; ignores unknown optional fields |
| Higher major | Rejects with an error naming both versions |
| Lower major | Rejects unless a migration exists, then loads through it |
| Unknown enum value | Treats it as unsupported; the adapter reports the element as skipped and never fails the whole template |

### Strict for writers, tolerant for readers

Enums in the schema are strict: workers validate their output before saving, so they only emit values their own schema version knows. Generated union types therefore look exhaustive, but readers must not rely on that. A template written by a newer minor version can contain an enum value the reader has never seen, and the reader must handle it at runtime.

Two places use an escape hatch: transition `type` has `"other"` plus `type_detail`, and track `kind` is a free string so unknown kinds are skipped.

Objects are open (unknown fields are allowed) so a newer minor still passes an older validator. The one exception is `sound_ref`, which is closed so audio fields cannot be added.

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
| `vfr` | boolean | no | True if the reference was variable-frame-rate and was conformed. Default false. |
| `original_fps` | `Rational` | no | Nominal rate before conforming. Provenance only; set when `vfr` is true. |
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
```

CI runs the same checks. To change the schema, use `/schema-change`.
