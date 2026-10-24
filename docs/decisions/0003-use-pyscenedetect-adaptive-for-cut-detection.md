# 0003: Detect cuts with PySceneDetect's AdaptiveDetector and flag suspect cuts for review

- **Status:** Proposed
- **Date:** 2026-10-23
- **Author:** @calvinkafaiyuen
- **Deciders:** @anthonythanpoovong
- **Related:** #4 (cut detection spike), #7 (production cut worker), #52 (golden dataset), PR #290 (labels and guide), ADR 0002

## Context

Cuts are the backbone of every template: each cut starts a slot, and each slot is a clip the user has to supply. Spike #4 compared PySceneDetect and TransNetV2 on 5 hand-labeled short-form videos (86 cuts, labeled blind per `eval/golden/LABELING.md`). All five were scored on the conformed files whose hashes the manifest records. Predictions were matched one-to-one to labels; Instagram end cards were excluded (rule 12). The exit bar set before the spike was **recall ≥ 0.95 and precision ≥ 0.90 at ±2 frames**.

| Detector | Precision ±2 | Recall ±2 | False cuts | Missed cuts |
|---|---|---|---|---|
| PySceneDetect Adaptive, t=2.0, min_scene_len 1 | 0.806 | **0.965** | 20 | 3 |
| PySceneDetect Adaptive, t=3.0 (default) | 0.835 | 0.942 | 16 | 5 |
| TransNetV2, t=0.5 | **0.908** | 0.802 | 7 | 17 |
| PySceneDetect Content, t=40, min_scene_len 2 | 0.896 | 0.802 | 8 | 17 |
| PySceneDetect Content, t=27 (default threshold), min_scene_len 1 | 0.418 | 0.895 | 107 | 9 |

±1 and ±2 scores are identical: every matched cut was within one frame. **No detector meets the bar.** With 86 cuts, one cut moves recall by about 1.2 points, and the 95% interval on Adaptive t=2.0's recall is roughly 0.90–0.99. The Adaptive thresholds 2.0–3.0 are statistically tied (F1 0.872–0.885); the gap between Adaptive and TransNetV2 on recall (83 vs. 69 cuts found) is the only large, consistent difference.

The failure modes are specific to short-form editing:

- **Jump cuts** (same framing, time skip) are the hardest. TransNetV2 missed all six (v01 469, 901; v02 523, 584, 718, 732); Adaptive t=2.0 missed three of them (v02 523, 718, 732), and those are all of its misses.
- **Punch-ins and punch-outs** (a crop inside one shot) are detected as cuts (v02 532, 550).
- **Split screens and picture-in-picture**: each tile change fires Adaptive, giving bursts of false cuts (10 in v02's split screen, frames 128–271).
- **Cuts inside zoom and slide transitions** get low TransNetV2 confidence (0.15–0.40) and fall under its threshold (all 10 cuts in v05).

#7 is blocked on this choice, and Phase 0's gate needs a detected cut timeline an editor can review.

## Options considered

### Option A: PySceneDetect AdaptiveDetector (t≈2.0), suspect cuts flagged
- Frame-difference detector with a rolling average, on CPU. Every detected cut is kept; cuts that look suspect are flagged for the user to review.
- ✅ Highest recall (0.965): it misses almost no cuts, including jump cuts TransNetV2 can't see in v01 and transition-masked cuts in v05
- ✅ No model weights or GPU; ~2 s for a 35 s 720p video on a laptop CPU (about 17× real time)
- ❌ About 1 false cut per 5 real ones, arriving in bursts on split screens and punch-ins
- Cost / effort: low; pure Python, CPU worker

### Option B: TransNetV2 (t=0.5)
- Neural shot-boundary model, CPU or GPU.
- ✅ Highest precision (0.908); ignores camera motion and most split-screen changes
- ❌ Misses about 1 cut in 5: jump cuts and cuts inside zoom/slide transitions
- ❌ Model weights to ship and version; ~8 s for a 35 s video on CPU, so likely wants a GPU
- Cost / effort: medium

### Option C: Neither yet; build a better detector first
- Block #7 on a follow-up: fine-tune a model, or add jump-cut and punch-in handling, until the original bar is met.
- ✅ Ships a detector that meets the bar
- ❌ Blocks #7 and the Phase 0 gate for an unknown time.
- ❌ **Combining these two detectors can't get there.** TransNetV2 finds none of the 3 cuts Adaptive misses, so a union adds only false cuts. And TransNetV2's confidence doesn't separate Adaptive's real cuts from its false ones: false cuts score 0.00–0.96 (punch-ins 0.95), real cuts as low as 0.00 (jump cuts). Keeping only Adaptive cuts that TransNetV2 also scores trades one metric for the other: a gate of 0.02 gives precision 0.808 / recall 0.930, a gate of 0.3 gives 0.904 / 0.872. No gate reaches both bars (`run.py combine`). Both detectors measure frame-to-frame change, so they share the same blind spots; closing the gap needs different signals (below).

## Decision

We will build #7 on **PySceneDetect's AdaptiveDetector (adaptive_threshold 2.0, min_scene_len 1)**, keep every detected cut, and **flag suspect cuts for the user to review** instead of filtering them.

This departs from #4's pre-set exit criteria. Since nothing passed, the spike's outcome is "No", which said #7 should wait for a different approach. We proceed anyway with a lower precision floor (below) because Adaptive already clears the recall bar, the remaining errors are a kind the user can fix cheaply, and blocking #7 would also block the Phase 0 gate. Reaching precision 0.90 becomes a follow-up rather than a precondition.

Threshold 2.0 is chosen over the default 3.0 for recall, not because it scores best overall: the two are tied on F1, and 2.0 finds 2 more cuts at the price of 4 more false ones. The deciding trade-off is which mistake costs the user more. A false cut adds a slot, and the fix is a merge that needs no new footage. A missed cut removes a slot, and the fix means finding the frame, adding the cut, and shooting or finding another clip that may not exist. Adaptive makes the cheap mistake; TransNetV2 makes the expensive one. Flagging keeps the user in control and stays transparent about uncertainty, without hiding real fast cuts (v03 has cuts 10 frames apart) the way a minimum-gap filter would.

## Consequences

- **Good:** #7 is unblocked with a CPU-only, dependency-light detector that rarely drops a cut. No schema change: cuts already carry `confidence` and `provenance`.
- **Bad / accepted trade-offs:** about 1 false cut per 5 real ones. Split screens and punch-ins produce bursts that can look like a fast-cut section until the user merges them. Jump cuts are still occasionally missed.
- **One-way or two-way door:** two-way. The detector lives inside #7's worker; swapping it changes no schema, API or stored data. Reversing costs a worker change and a golden-set rerun.
- **Follow-up work:**
  - #7: pin `scenedetect` to the evaluated version (0.7.2), since detector output can change between releases, and log review edits (below). A PySceneDetect scene start is already the first frame of the new shot, the same convention as `cuts[].frame`. Two acceptance criteria this decision depends on:
    - **The flagging rule is defined and its flag rate measured on the golden set**: how many false cuts it flags, and how many real cuts. The 0.75 precision floor is acceptable only because suspect cuts are flagged. Detector confidence alone may not work as the flag, since TransNetV2's confidence didn't separate real from false cuts here.
    - **p95 latency and cost per video are measured on Modal**, against the < 60 s target for a 60 s 1080p video. If it misses, the fallback is to detect on a 720p downsample, where the spike ran at about 17× real time.
  - #52: the eval needs a machine-readable exclusion for platform end cards. Today they're free-text `notes` (`platform end card: frames a-b`) that the spike parses with a regex.
  - #52: grow the golden set to 30 videos, chosen to stress the failure modes, not to look typical. The current five give 86 cuts and a recall interval of about 0.90-0.99; the new videos should narrow that interval and test the weak spots.
    - **Cover the known failure modes, several videos each:**
      - Jump cuts (talking head, same framing, time skip): the hardest case for both detectors, and where Adaptive still misses cuts. Aim for 5-6.
      - Split screens, picture-in-picture, grids and reaction layouts: the source of about half the false cuts. Aim for 4-5.
      - Punch-ins and punch-outs, and zoom-in "emphasis" edits: common in creator content. Aim for 3-4.
      - Cuts inside transitions (zoom, slide, whip, glitch): the v05 pattern. Aim for 4-5.
      - Fast montage with cuts under 10 frames apart: tests whether flagging deletes real cuts, as v03 does.
      - Text-heavy and animated overlays, screen recordings, and lighting flicker or strobe: likely false-cut sources nobody has measured yet.
    - **Include easy videos:** 4-5 with clean hard cuts, slow pacing and a talking head or static scene. Without them the eval can't show whether Adaptive degrades on ordinary content, and the precision number will look worse than real uploads would.
    - **Vary the inputs, not just the editing:**
      - Different source platforms (the current set has Instagram end cards) and different creators, so no style is dominated by one person.
      - Different frame rates, including 24 and 60 fps, and at least one variable-frame-rate file (the manifest already tracks `vfr`).
      - Different resolutions and aspect ratios, plus some horizontal video if the product will accept it.
      - Lengths from about 15 s to 60 s, since the latency target is for a 60 s video.
    - **Tag and split:** record each video's `edit_styles` so the mix can be checked, and hold out about 10 as a test set nobody tunes on.
  - A later story targets the shared blind spots with new signals, toward the 0.90 precision target: jump cuts (same subject, discontinuous pose or position), punch-ins (new frame is a scaled crop of the previous one), split screens (only part of the frame changes).
- **Affected:** #7 worker and its regression test. Schema, DB, RLS and MCP contracts are unchanged.
- **Reproducing:** spike code and cached predictions are at tag `spike-4-detectors`, which outlives the `spike/4-detectors` branch. In `eval/cuts_spike/run.py`, `detect` reruns the detectors and needs the private videos; `score` and `combine` read the cached predictions in `eval/cuts_spike/predictions/`, so anyone can rerun them. Versions: scenedetect 0.7.2 (OpenCV backend), transnetv2-pytorch 1.0.5 on CPU, frames decoded with OpenCV.

## How we'll know

- **Regression floor for #7:** recall ≥ 0.95 and precision ≥ 0.75 at ±2 frames on the golden set, end cards excluded. Target: precision ≥ 0.90, the original bar.
- **Production check:** per template, count cuts the user **merges** (false cuts), cuts they **add** (missed cuts), and flagged cuts kept vs. merged. This depends on the review UI logging those edits; edits made later inside an editor aren't visible.
- **Revisit if** users add cuts often (Adaptive misses more on real uploads than on 5 videos), or if flagged cuts are almost always merged (flags are reliable enough to filter automatically).

## Open questions

- **Runtime on Modal:** not measured. Only local CPU at 720p is known. #7 measures 1080p on Modal CPU against its < 60 s target for a 60 s video. Owner: @calvinkafaiyuen (#7).
- **"False cuts are cheaper to fix" is the author's reasoning, not user evidence.** The Phase 0 editor review is the first test. Owner: @calvinkafaiyuen.
- **Thresholds tuned on 5 videos will overfit.** #7 re-checks them on the full golden set (#52), tuning on the non-held-out videos only.

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ weak | Spike data is solid; "false cuts are cheaper" is unvalidated reasoning |
| Smallest version | ✅ | Adaptive t=2.0 as is, with flags; no filters or ensembles |
| Alternatives | ✅ | TransNetV2, defer for a better detector, Content detector; all measured |
| Key Decisions | ✅ | Fits deterministic-first and frames + rational fps; nothing changes |
| Data & schema | ✅ | Uses existing per-cut `confidence` and `provenance` |
| Security & privacy | ✅ n/a | Same upload-and-analyze path as any worker |
| Cost | ⚠️ weak | Local CPU only; Modal and 1080p open for #7 |
| Failure modes | ✅ | Jump cuts, punch-ins, split screens named; handled by flagging |
| Reversibility | ✅ two-way | Detector is internal to #7's worker |
| Observability | ✅ | Merge/add/flag counts, dependent on review UI logging |
| Success metric | ✅ | Floor R ≥ 0.95, P ≥ 0.75; target P ≥ 0.90 |
| Effort & ownership | ✅ | @calvinkafaiyuen owns #7; Phase 1 |

</details>
