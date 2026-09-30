# Epic proposal: Footage Match & Format Benchmark (stories for #41)

- **Status:** Accepted (2026-09-30, via #98)
- **Date:** 2026-09-30
- **Author:** @anthonythanpoovong
- **Owner(s):** @sktchan, @calvinkafaiyuen, @anthonythanpoovong (proposed; not yet confirmed with CV owners)
- **Phase:** 3 (Depth & scale)
- **Related:** #41 Video analysis pipeline (parent epic), #26 Format Match Score v1, #52 golden dataset, #56 terms/privacy, #21 legal
- **Epic issue:** Not a new epic. Stories under **#41**: #99 (1), #100 (2), #101 (3), #102 (4), #103 (5), #104 (6), #105 (7)

## Problem

A user recreating a template uses their own footage. For example, their trip to Japan won't match the inspiration's camera quality, lighting or angles. Today they only find out after editing, when the result "doesn't land". #26 scores the **finished** recreation against the original, but by then the chance to re-shoot may be gone.

**Evidence:** author's assumption so far. No customer interview or metric yet (see Open questions).

## Goal

Before editing, a user can put their own clips into a template's slots and see, **per slot**, how well each clip matches the original shot (framing, angle, motion, lighting), with a clear "re-film this" suggestion. They can also see how the template's format compares with other videos in their chosen niche.

## Exit criteria

- A user can put clips into slots and get a per-slot match result with sub-scores, a confidence level and a reason
- The user picks a niche and sees format benchmark stats (e.g. cuts/sec, average shot length) from the curated set
- Scoring cost is bounded by the caps below, and GPU seconds per run are logged
- A measurement of Format Match Score lift is in place

## Success metric

**Average Format Match Score (#26) of recreations made with footage-match feedback is ≥ 1.5 points higher than without**, measured at **Phase 3 exit** (A/B or before/after cohort).

## Out of scope

- **Virality scoring.** There's no legitimate engagement data, and it would present a guess as a fact. Replaced by the format benchmark.
- **Scraped trending/discovery feed.** It conflicts with upload-first and the platforms' terms (#21 unresolved), and there's no user evidence for it. A future separate proposal; an embed-only (oEmbed) feed is an option.
- **"Send to Sequa" / link input.** It needs #21 guidance and an ADR replacing upload-first. A future separate proposal.
- **Automatic niche classification.** Users pick the niche.
- **Benchmarking on other users' uploads.** Only after #56 covers it.

## Alternatives considered

- **Do nothing (keep #26 post-edit only):** cheaper, but the feedback comes after the reshoot window has closed.
- **Virality grade:** rejected. No ground truth without a scraped engagement dataset.
- **Scrape platforms for a trend corpus:** rejected. Legal/TOS risk, and it conflicts with upload-first.

## Stories

### 1. Per-slot shot descriptors in the template schema
- **Labels:** `story`, `type:build`, `area:backend`, `platform`
- **Owner:** TBD · **Phase:** 3
- **Context:** footage match needs something to compare user clips against, for each slot.
- **Scope:** add **optional, additive** per-slot descriptors to `schema/template.schema.json`: shot type, camera angle, motion (static/handheld/pan/zoom), lighting (key direction, exposure, color temperature). Regenerate the TS, Pydantic and Zod code.
- **Acceptance criteria:**
  - [ ] Existing templates still validate unchanged
  - [ ] Generated types updated via codegen, with no hand-written types
  - [ ] Examples in `schema/` include the descriptors
- **Depends on:** #1, #2

### 2. Extract framing, angle and motion descriptors
- **Labels:** `story`, `type:build`, `area:worker`, `ml`
- **Owner:** @calvinkafaiyuen (proposed) · **Phase:** 3
- **Context:** fills the story 1 fields for a template's source video, and for user clips.
- **Scope:** a worker that outputs shot type, angle and motion per slot and per clip, with confidence and provenance.
- **Acceptance criteria:**
  - [ ] Agreement with labels on the golden dataset (#52) at a target agreed with CV 1
  - [ ] Runs on downsampled input (2 fps, 720p)
- **Depends on:** story 1, #53, #7

### 3. Footage match scorer
- **Labels:** `story`, `type:build`, `area:worker`, `ml`
- **Owner:** @sktchan (proposed) · **Phase:** 3
- **Context:** compares each slotted user clip with its slot and decides whether to suggest a re-film.
- **Scope:** lighting and color descriptors for user clips; a per-slot match score with sub-scores (framing, angle, motion, lighting); "re-film" flags with a confidence level and a human-readable reason. Uses the same sub-score definitions as #26, so the two scores are consistent.
- **Acceptance criteria:**
  - [ ] Flags agree with editor judgment on a labeled set of clip/slot pairs (target set with CV 2)
  - [ ] Every flag includes a reason and a confidence level
  - [ ] Video-only: the scorer never reads the audio track (stripped at ingest; see Security & data)
- **Depends on:** story 2, #24, #26

### 4. Cost guardrails for user footage
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** TBD · **Phase:** 3
- **Context:** raw footage can be far larger than a finished short-form video.
- **Scope:**
  - **Per run:** score **only clips placed in a slot**; trim each clip to its slot length + 2 s of margin; downsample to 2 fps / 720p; **total scored footage ≤ the template's source duration**, with a **hard 3-minute ceiling** stored as a config value.
  - **Per user:** a **per-plan quota of scored footage minutes per billing period**, enforced through entitlements (#19). Values are set with billing (TBD), stored as config and checked **before** any GPU work.
  - **Caching:** results keyed by **clip content hash + slot id + worker version**, following the worker base's idempotency (#53). Re-scoring the same clip for the same slot is a cache hit and doesn't count against the quota.
  - **Retries:** use the worker base's bounded retry policy (#53): capped attempts with exponential backoff and jitter. **No retries** on validation, cap or quota errors. Failed attempts are logged, and retries after a system error don't count against the user's quota.
  - Log GPU seconds per run.
- **Acceptance criteria:**
  - [ ] Runs over the per-run cap or the user's quota are rejected before GPU work, with a clear message
  - [ ] Scoring an unchanged clip in the same slot again is a cache hit (no GPU time, no quota)
  - [ ] Retries back off and stop at the attempt limit; cap and quota errors are never retried
  - [ ] GPU seconds, cache hit rate, quota usage and cap hits are visible in observability (#50)
- **Depends on:** story 3, #50, #53, #19

### 5. Curated niche benchmark set
- **Labels:** `story`, `type:build`, `area:worker`, `ml`, `risk:research-heavy`
- **Owner:** @sktchan (proposed; curation owner TBD) · **Phase:** 3
- **Context:** the format benchmark ("travel videos average 2.8 cuts/sec") needs a consented source.
- **Scope:** extend the golden dataset (#52) with niche labels. Compute per-niche format stats (cuts/sec, average shot length, transition mix, text density) from **features only**. User uploads are excluded until #56.
- **Acceptance criteria:**
  - [ ] A documented niche list, with a minimum number of videos per niche (TBD)
  - [ ] Stats are recomputed when the set changes; no media is stored beyond #52's rules
- **Depends on:** #52, #56 (only for any future use of user uploads)

### 6. Footage match and benchmark UI
- **Labels:** `story`, `type:build`, `area:frontend`, `product`
- **Owner:** @anthonythanpoovong (proposed) · **Phase:** 3
- **Context:** the breakdown page is where users see slots.
- **Scope:** put clips into slots; show per-slot results, sub-scores and re-film flags with their reasons; a niche picker; benchmark comparison ("your template: 2.1 cuts/sec · travel average: 2.8"). Never uses "viral" wording.
- **Acceptance criteria:**
  - [ ] Flags are phrased as suggestions and show a confidence level
  - [ ] Works within the story 4 caps, with clear errors
- **Depends on:** stories 3, 4, 5, #16 (upload flow), #18 (breakdown page)

### 7. Measure Format Match Score lift
- **Labels:** `story`, `type:build`, `area:backend`, `product`
- **Owner:** @anthonythanpoovong (proposed) · **Phase:** 3
- **Context:** the success metric needs a comparison group.
- **Scope:** record whether a recreation used footage-match feedback, and compare #26 scores for the with-feedback and without-feedback groups (A/B flag or before/after cohort). Report it in product analytics (#51).
- **Acceptance criteria:**
  - [ ] A dashboard or query shows average Format Match Score for each group
  - [ ] Enough sample size, or a documented method, to judge the +1.5 target at Phase 3 exit
- **Depends on:** #26, #51, story 6

## Risks & costs

| Risk / cost | Likelihood / size | Mitigation |
|---|---|---|
| Wrong "re-film" advice costs a user a real reshoot | Medium | Show confidence and reason; phrase as a suggestion; validate on a labeled set |
| GPU cost from raw footage | High without caps | Story 4: per-run caps, per-plan quota, caching by clip + slot, bounded retries with backoff; GPU seconds logged |
| Benchmark too small to be meaningful | Medium | Minimum videos per niche; hide stats below the threshold |
| No real user demand for pre-edit feedback | Unknown | Validate with design partners (#55) before Phase 3 build |

Infra cost estimate at 100 / 10k users: TODO (CV owners to estimate GPU seconds per scored minute at 2 fps / 720p).

## Security & data

Additive, optional schema fields (a two-way door, no ADR). User clips follow the existing upload storage and retention rules.

**Audio:** footage match is **video-only**. Framing, angle, motion and lighting need no sound. The audio track of a user's clip is **stripped at ingest for scoring** and never decoded, stored, fingerprinted or returned by footage match. This follows the Key Decision that copyrighted audio is never kept: a clip may have music playing in the background. The benchmark uses curated, consented videos and stores features only. No other user's data is used until #56 covers it.

## Open questions

- **Evidence:** do users actually want pre-edit re-film feedback? Ask design partners (#55). Owner: @anthonythanpoovong.
- **Ownership:** confirm story owners with @calvinkafaiyuen and @sktchan. Owner: @anthonythanpoovong.
- **Benchmark curation:** who labels niches, and how many videos per niche? Owner: TBD.
- **Cap check:** confirm the current Reels/TikTok length limits before fixing the 3-minute ceiling.

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ | Author's assumption; validate with #55 |
| Smallest valuable version | ✅ | Slotted clips, curated benchmark, user-picked niche |
| Alternatives | ✅ | Feed, virality score and post-edit-only considered |
| Fit with Key Decisions | ✅ | Upload-first unchanged; features only |
| Data & schema | ✅ | Optional additive slot fields |
| Security & privacy | ✅ | Curated set; no cross-user use before #56 |
| Cost | ✅ | Slot-only, trim, 2 fps/720p, 3-min ceiling |
| Failure modes | ✅ | Confidence + reason on flags |
| Reversibility | ✅ | Two-way door |
| Observability | ✅ | GPU s, flags acted on, cap hits |
| Success metric | ✅ | FMS lift +1.5 by Phase 3 exit |
| Effort & ownership | ⚠️ | CV owners not yet consulted |

</details>
