# Golden-set labeling guide

How to hand-label cuts and transitions in the golden videos (#4, #52). Settle edge cases here **before** labeling, not while looking at a video.

## Setup

- Label the **conformed** constant-frame-rate file (`eval/golden/videos/vNN.mp4`), never the original upload. Labels and detectors use the same file.
- Label **blind**, before running or looking at any detector output.
- Record roughly how long each video took in the manifest. That tells #52 what 30 videos will cost.

## What to label

Labels are schema templates (`schema/template.schema.json`) with one video track. Every hand label has `"confidence": 1` and `"provenance": {"detector": "manual", "version": "1"}`.

| Element | Field | Frame to record |
|---|---|---|
| Hard cut | `cuts[].frame` | The **first frame of the new shot** |
| Transition | `transitions[]` with `type` and `range` | `range.start` is the first frame that's visibly mid-transition. `duration` runs to the first clean frame of the new shot |

## Rules

1. **Hard cut:** the picture changes to a different shot from one frame to the next. Label it.
2. **Jump cut** (same framing, time skip): a cut. Label it.
3. **Flash frame** (1–3 frames of a solid white/black frame or a different shot inserted between two shots): label **two cuts**, one at the first flash frame and one at the first frame after it. Write `flash` in the video's `notes` so it can be scored with and without flashes.
4. **Brightness flash over continuous footage** (an exposure or glow effect on the same shot): **not a cut**.
5. **Dissolve / crossfade / fade to black or white:** **not a cut.** Label it as a `transition` (`dissolve`, `fade_black`, `fade_white`).
6. **Whip transition** (two shots joined behind motion blur): label a `transition` of type `whip`, **and** a cut at the first frame where the new shot is the main content. The cut is still there; it's just hidden by blur.
7. **In-camera whip pan** inside one continuous shot: **not a cut** and not a transition.
8. **Other edited transitions** (wipe, push, slide, zoom, glitch): label a `transition` with that type, or `other` plus `type_detail`. Add a cut only if there's a single frame where the shot switches outright.
9. **Text, stickers, captions or overlays changing over the same footage:** **not a cut.**
10. **Zooms, speed ramps, reframes inside one shot:** **not a cut.**
11. **Split screen / picture-in-picture appearing:** a cut only if the whole frame changes at once. Otherwise list it in `notes`.
12. **Unsure:** record your best guess and list the frame in the video's `ambiguous` list in the manifest. These get reviewed with a second labeler, and they're reported separately in the results.

## Workflow (DaVinci Resolve)

Videos are ingested first (`python3.11 eval/golden/ingest.py <originals>`). That writes `videos/vNN.mp4`, the manifest entry and an empty `labels/vNN.json`.

1. Make a new timeline at the video's fps (30 for the current set), starting at `01:00:00:00` (Resolve's default), and drop `vNN.mp4` on it.
2. Step through with the arrow keys (one frame per press). Put **timeline markers** (`M` with nothing selected) and name them:

   | Marker name | Becomes |
   |---|---|
   | leave the default (`Marker 1`), or `cut` | a cut at that frame (the first frame of the new shot) |
   | `flash` | a cut, noted as a flash (rule 3) |
   | `dissolve`, `fade_black`, `fade_white`, `wipe`, `push`, `slide`, `zoom`, `whip`, `glitch` | a transition. Give the marker a **duration** covering the transition (rule 5–8) |
   | `other: <what it is>` | a transition of type `other` |
   | add `?` to any name, e.g. `cut?` | kept, and listed as ambiguous (rule 12) |

   A whip gets two markers: a `whip` duration marker over the blur, and a `cut` marker inside it.
3. Export: File → Export → Timeline Markers to EDL.
4. Convert: `python3.11 eval/golden/edl_to_template.py vNN markers.edl`. This fills `labels/vNN.json` (cuts, transitions, and slots derived from them) and the manifest's `notes`/`ambiguous`. Re-running replaces the previous labels.
5. Spot-check 2–3 cut frames by eye, then fill in `rights`, `edit_styles`, `has_music` and `labeling_minutes` in `manifest.json`.

## After the detectors run

Review every disagreement between labels and detectors. If a label was wrong, fix it, and report how many labels changed alongside the results. Never change a label silently to match a detector.
