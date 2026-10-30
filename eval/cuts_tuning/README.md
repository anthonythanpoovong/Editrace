# Cut detection: recall tuning (#7)

Can changing AdaptiveDetector's settings close #7's recall gap (ADR 0003's floor is recall ≥ 0.95)? **Not in a way
that holds up on videos it wasn't tuned on.** The worker's settings are unchanged.

## How it works

`run.py` decodes each labeled golden video once with the worker's settings and caches every frame's `content_val`.
It then replays AdaptiveDetector's rule offline, checked to reproduce the worker's cuts exactly on every video, so a
sweep needs no more decoding. Scoring uses `eval/golden/score.py` (±2 frames, `exclude` ranges).

```
python eval/cuts_tuning/run.py [--golden eval/golden] [--cache DIR]
```

The cache defaults to the system temp folder. It holds numbers derived from the private videos, so it isn't committed.

## Results (2026-10-29)

14 videos, labels from #323 at `e12b998` (v11 left out: the local file isn't the labeled video). Windows; results can
differ by a cut on other platforms (see `workers/cuts/test_golden.py`).

| Setting | Precision | Recall |
|---|---|---|
| The worker: t=2.0, window 2 | 0.881 | 0.925 |
| t=1.7, window 3 | 0.852 | 0.958 |
| t=2.0, or any frame with content ≥ 60 | 0.834 | 0.966 |
| Ratio against the quieter side of the window, t=2.0 | 0.743 | 0.958 |

**Leave-one-video-out:** choosing the setting with the best recall at precision ≥ 0.85 on 13 videos and scoring the
14th, for each video, gives **P 0.837 / R 0.932**, against the worker's 0.881 / 0.925. The gains above come from
fitting the videos they're scored on, and each failure mode appears in only one video:

- **Flash burst**, v12 265–281: 7 of the worker's 20 misses. The rolling average rises during the burst, so each cut
  stops standing out. v10's strobe is already caught in full.
- **1-frame shots**, v14 70 and 88: caught by a wider window.
- **Lighting flashes over the same footage**, v13: where most of the new false cuts appear.

## Next

A fix for each of these needs more than one example to be tested on. #52's next golden videos should include flash
bursts, 1-frame shots and lighting flashes; rerun this then.
