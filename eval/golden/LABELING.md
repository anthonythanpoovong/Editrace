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
5. **Dissolve / crossfade / fade to black or white:** **not a cut.** Label it as a `transition` (`dissolve`, `fade_black`, `fade_white`). `fade_black` covers every direction: fading out to black, fading in from black, or dipping through black between two shots (same for white). Label one transition over the whole fade, through the black frames. A fade in at the very start or out at the very end is labeled too; it doesn't split the shot.
6. **Whip transition** (two shots joined behind motion blur): label a `transition` of type `whip`, **and** a cut at the first frame where the new shot is the main content. The cut is still there; it's just hidden by blur.
7. **In-camera whip pan** inside one continuous shot: **not a cut** and not a transition.
8. **Other edited transitions** (wipe, push, slide, zoom, glitch): label a `transition` with that type, or `other` plus `type_detail`. Add a cut only if there's a single frame where the shot switches outright.
   **Stacked transitions** (e.g. a zoom during a fade): label **each** one separately, with its own type and its own range, since they may start and end on different frames. Overlapping transitions count as one change of shot.
9. **Text, stickers, captions or overlays changing over the same footage:** **not a cut.**
10. **Zooms, speed ramps, reframes inside one shot:** **not a cut.**
11. **Split screen / picture-in-picture appearing:** a cut only if the whole frame changes at once. Otherwise list it in `notes`.
   **Picture-in-picture over a background** (e.g. a talking head in a box over still images): the background is the shot. A background change is a cut. Changes inside the box (a new clip, a time skip, the box moving, resizing, appearing or disappearing) are **not**.
12. **Platform end card** (e.g. Instagram's logo card added when a reel is downloaded, with or without a black frame before it): **not part of the edit.** Label nothing from its first frame to the end, not even the black frame (it's not a flash), and add it to the video's `exclude` list in the manifest, `{"start": <first>, "duration": <frames>, "reason": "platform end card"}`, so `score.py` leaves it out of scoring on both sides. Also note it in `notes` (`platform end card: frames <first>-<last>`) for people reading the manifest.
   **Instagram's black frame or the creator's?** Use the watermark, the small Instagram logo and @handle that Instagram stamps on every frame of the creator's video, black frames included. Black frames **with** the watermark are the creator's ending: part of the edit, labeled as usual (a cut to black, or a `fade_black`). The single black frame **without** it, right before the card, is Instagram's and belongs to the end card. Not every download has that black frame, and downloads saved some other way may have no watermark or card at all.
13. **Unsure:** record your best guess and list the frame in the video's `ambiguous` list in the manifest. These get reviewed with a second labeler, and they're reported separately in the results.

## Workflow

Videos are ingested first (`python3.11 eval/golden/ingest.py <originals>`). That writes `videos/vNN.mp4`, the manifest entry and an empty `labels/vNN.json`.

### Labeler (default)

1. Open `eval/golden/labeler.html` in Chrome (double-click it). Pick `videos/vNN.mp4` and check the fps (30 for the current set). The video stays on your computer.
2. Step with `←`/`→` (`Shift` for 10 frames), comparing the previous and current frame side by side. Then mark:

   | Key | Marks |
   |---|---|
   | `C` | a cut at this frame (the first frame of the new shot) |
   | `F` | a flash cut (rule 3) |
   | `T` … `T` | a transition: press on its first frame and again on its last, with the type chosen in the sidebar (rules 5–8) |
   | `A` | toggles ambiguous (`?`) on the marker at this frame (rule 13) |
   | `⌫` | deletes the marker at this frame |

   A whip gets both: a `whip` transition over the blur, and a `C` cut inside it. For stacked transitions, mark each with `T`…`T`, changing the type in between. To delete or flag one of several overlapping markers, click it in the list first (or use its ✕ / ? buttons). Markers autosave in the browser, but **Save** (`S`) is what counts.
3. Save to download `vNN.markers.json`. Labeling time is tracked while you press keys and is saved with it.
4. Convert: `python3.11 eval/golden/markers_to_label.py vNN ~/Downloads/vNN.markers.json`. This fills `labels/vNN.json` (cuts, transitions, and slots derived from them) and the manifest's `notes`, `ambiguous` and `labeling_minutes`. Re-running replaces the previous labels. To keep editing later, load the markers file back into the labeler with **Resume**.
5. Spot-check 2–3 cut frames, then fill in `rights`, `edit_styles` and `music` in `manifest.json` (see below).

### DaVinci Resolve (alternative)

Make a timeline at the video's fps starting at `01:00:00:00` and put **timeline markers** on it, named `cut` (or left at the default), `flash`, a transition type with a **duration** covering it, or `other: <what it is>`. Add `?` to any name for ambiguous. Export with File → Export → Timeline Markers to EDL, then run `markers_to_label.py vNN markers.edl`.

## Manifest fields

`manifest.json` is committed, so it never names or links to the people in the videos.

- **`rights`**: the usage rights for the video, e.g. `"full"` (any use permitted by the owner) or `"self-made"`.
- **`edit_styles`**: tags for the editing in the video, so results can be broken down by style. Use these; add a new tag only if none fit:

  | Tag | Use when |
  |---|---|
  | `fast-cuts` | lots of cuts, under ~1 s per shot |
  | `slow-paced` | few cuts, long shots |
  | `beat-synced` | cuts clearly land on the music |
  | `flash` | has flash cuts |
  | `whip` | has whip transitions |
  | `dissolve` | has dissolves or fades |
  | `jump-cuts` | same framing, skipping ahead in time |
  | `talking-head` | someone talking to camera |
  | `montage` | a sequence of different clips |
  | `text-heavy` | lots of on-screen text or captions |
  | `speed-ramp` | speeds up or slows down within shots |
  | `zoom` | zoom punches or zoom transitions |

- **`music`**: what's on the soundtrack, used by the sound-ID spike (#11):
  - `"released"`: a commercially released song
  - `"original"`: a platform original sound, a remix, or a sped-up/slowed edit
  - `"none"`: no music (speech, ambient sound or silence)
  - `"unknown"`: there's music, but you can't tell which kind

  Don't write the song's name: #11 checks whether the vendors find it on their own.

## After the detectors run

Review every disagreement between labels and detectors. If a label was wrong, fix it, and report how many labels changed alongside the results. Never change a label silently to match a detector.
