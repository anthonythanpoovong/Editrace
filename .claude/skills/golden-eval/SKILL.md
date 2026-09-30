---
name: golden-eval
description: Evaluate an Editrace detector or the full analysis pipeline against the golden video dataset (#52) and compare with main — per-element precision/recall with frame tolerance — then report a metrics table on the PR. Use when someone changes a worker/detector, asks "did this make cuts detection better?", "run the golden set", or needs numbers for a #41 exit criterion.
---

# Golden-set eval

Labels in the golden set are **templates in our own schema**, so evaluation is a template-vs-template diff: per element type, precision and recall with a frame tolerance (#52).

## 0. Preflight
- **Golden set (#52):** find the dataset location and the `eval` script. If they don't exist yet, stop and say so. Don't hand-roll a one-off metric that can't be compared later. Offer to help with #52.
- **Labels exist for the element type** being evaluated (cuts, transitions, text, captions, beats, …). If not, report "not evaluable yet".
- The golden videos are **private, consented data**. Never copy them into the repo, PR comments, logs or artifacts.

## 1. Decide what to compare
- **Candidate:** the current branch (or the version the author names).
- **Baseline:** `main`, or the last released worker version.
- **Scope:** one detector (default) or the full pipeline.
- **Tolerance:** use the eval script's default frame tolerance per element type. If you change it, say so in the report, because numbers with different tolerances aren't comparable.

## 2. Run
Use the eval script as #52 defines it, running baseline and candidate on the **same** video set and the same tolerance. Record:
- Precision, recall and F1 per element type
- Number of videos, and any that failed to process (count them; don't silently drop them)
- Runtime and GPU seconds per video (for cost tracking, #50)

## 3. Report
Post (or print) a table:

```
### Golden eval · <detector> · <candidate sha> vs <baseline sha>
Videos: 30 (0 failed) · tolerance: ±2 frames

| Element | P (base → cand) | R (base → cand) | F1 Δ |
|---|---|---|---|
| cuts | 0.91 → 0.94 | 0.88 → 0.90 | +0.025 |

GPU s/video: 4.1 → 3.8
Worst regressions: video_17 (cuts R −0.20): <one-line reason if known>
```
- Flag any metric that **regressed** beyond noise, and any element type that falls below a threshold agreed in #41's exit criteria.
- Link failed or worst videos by their dataset id, never by content.

Post it on the PR: `gh pr comment <n> --body-file <report.md>`.

## Rules
- Same videos, same tolerance, same eval script for baseline and candidate, or the comparison is invalid.
- Never cherry-pick videos. Report failures.
- Don't publish golden-set media or frames anywhere.
