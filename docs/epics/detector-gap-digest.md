# Epic proposal: Detector gap digest (stories for #40)

- **Status:** Proposed
- **Date:** 2026-09-30
- **Author:** @anthonythanpoovong
- **Owner(s):** @anthonythanpoovong, @calvinkafaiyuen, @sktchan (proposed; CV owners not yet consulted)
- **Phase:** 1 (record + digest) · 2 (gated agent)
- **Related:** #40 Engineering foundations (parent epic), #50 observability, #53 worker base, #13 OCR, #14 beats + sound ID, #23 transition classification, #2 codegen, #49 migrations + RLS
- **Epic issue:** Not a new epic. These are new stories under **#40**.

## Problem

Editrace's analysis pipeline is designed so that **partial failure still yields a usable template** (#41 principle). A detector that can't be confident (a song it can't identify, a font it can't match) doesn't crash; it leaves a low-confidence or missing part. Error tracking (#50) catches crashes, so **these limitations are invisible to the team**. Nobody learns which songs, fonts or text styles the detectors fail on most, so there's no evidence for which detector to improve first.

**Evidence:** none logged yet (`docs/customers/` is empty), and there's no production traffic in Phase 0. The need follows from the design above; the data will come from the design-partner beta (#55).

## Goal

The team sees, once a week in a Discord channel, **which detector limitations happen most**, so detector improvements are chosen from real counts instead of guesses. Internal only: no new user-facing notices or screens. Low-confidence elements follow the plan's existing rule (kept with their confidence, shown in the UI and passed to adapters); this epic doesn't change how they're presented.

## Exit criteria

- Detectors report **gaps** through one shared API, stored in a backend-only table
- A weekly digest posts counts by reason and detector to a Discord channel
- A coverage check shows what share of incomplete-template jobs have a gap record
- A delivery monitor notices when a digest doesn't arrive
- (Phase 2, gated) an agent drafts backlog issues from the aggregated gaps

## Success metric

By the **Phase 1 gate + 8 weeks**:
- **(a) Coverage:** at least **95%** of jobs that finish with an **incomplete template** (defined in "Incomplete template" below, independently of gap reporting) have at least one gap record
- **(b) Action:** at least **3 detector improvements** (issues opened or closed) trace back to the digest

## Gap vs. error

- A **crash or error** (worker died, timeout) goes to error tracking (#50). It's not a gap.
- A **gap** is a detector that **finishes but can't produce a confident answer**: the job succeeds and the template is incomplete.

### Reason codes (v1)

| Reason code | Meaning |
|---|---|
| `sound_not_identified` | No fingerprint match, or confidence below the threshold |
| `font_unrecognized` | Text found by OCR, but no font match |
| `text_low_confidence` | OCR or captions are unreliable (blur, stylized text) |
| `transition_unclassified` | A cut or transition found, but its type is unknown (#23) |
| `input_unsupported` | Too long, corrupt, or unusual format |

### What a gap record holds

Reason code, detector name and version, an `occurrences` count (how many elements in the job were affected), the **lowest** confidence among them, the `job_id`, and a timestamp. For `font_unrecognized`, the normalized size of the **largest** affected box and the **lowest** font-match score among the affected text (numbers only). **One row summarizes every affected element for that job, detector and reason**; per-element rows are out of scope, because they'd multiply storage and drift toward storing content. **No text of any kind is stored**, because OCR and caption text can contain names, handles or emails.

### What is never recorded

Audio, video frames, fingerprints that could recover audio, **any text from the video (OCR or captions)**, or any user identifier. The internal `job_id` is the only identifier stored, and it is never shown in the digest or given to the agent. The Discord digest shows **counts by reason and detector only**.

## Incomplete template (the denominator for metric a)

Metric (a) checks that detectors report their limits, so "incomplete" **can't be decided by the detectors' own gap reports or thresholds**. It's computed from the **merged template** by a separate **completeness check** at merge time, which never reads the gap table. A job is incomplete if the merged, schema-valid template has any of:

- an element **from a participating detector** (below) whose `confidence` is below **one global low-confidence threshold** (`T_low`, set once in the merge validator with the CV owners, not per detector)
- **no `sound_ref`** although a **beat track was detected** (music is evidently present, so an unidentified song is expected to produce a gap)

**Participating detectors (v1)** are only the ones that report gaps: beats + sound ID (#14), OCR (#13), captions (#12) and transition classification (#23). Elements from other detectors (cuts #7, motion #8, color #24) have no reason code yet, so they're **outside** the completeness rule and don't make a job incomplete for this metric. Adding one later means adding its reason code and listing it here.

**Empty output alone never counts.** A video with no on-screen text or no music legitimately yields empty OCR or sound output, so "empty" isn't a signal. To keep limits visible, detectors **keep a low-confidence element in the template (with its confidence) instead of omitting one they're unsure about** (story 3), which is what the plan already specifies, so this epic doesn't change what users or exporters receive, so a real limitation shows up as a low-confidence element rather than as silence.

The result is stored on the job record (an `incomplete` flag plus which rule fired). **Coverage = incomplete jobs with at least one gap record ÷ all incomplete jobs, computed per digest week over that week's jobs** (when both the gap rows and the `incomplete` flags are still within retention). **Each week's value is posted in the digest, so the history lives in the digests, not in rows that get purged**, and coverage can't drift down as old gap rows expire. A detector that fails to report shows up as uncovered, and gap rows on jobs that weren't flagged incomplete are counted separately.

**Detector thresholds can't be looser than `T_low`.** A detector reports a gap when an element falls below its own gap threshold, while `T_low` flags the job as incomplete. If a detector's threshold were lower than `T_low`, an element between the two would make the job incomplete with no gap record, and the 95% target would be unreachable. So **every detector's gap threshold must be at least `T_low`** (a detector may report more gaps than the completeness check flags, never fewer), and the sound detector **must report `sound_not_identified` whenever a beat track was detected but no `sound_ref` was produced**. `T_low` is one shared config value that detectors read, not a copy.

**`input_unsupported` jobs are outside metric (a).** A video rejected before analysis (too long, corrupt, unusual format) never produces a merged template, so it can't be "incomplete". Its gap records still appear in the digest's counts, but those jobs are excluded from the coverage denominator, like failed workers.

**Failed workers aren't incomplete jobs.** A worker that crashed or timed out is an error (#50), not a gap. The completeness check reads each worker's **status**: a job with a failed worker is **excluded from the denominator** (it belongs to error tracking), and the digest shows how many jobs were excluded so they stay visible.

## Out of scope

- **Per-alert pings** (each failure posts to Discord). (a) wants patterns, not events, and pings would be noise.
- **User-facing notices** about gaps. This is internal only.
- **An LLM deciding what a gap is.** Detection stays deterministic.
- **Crash alerting.** That's #50.
- **Storing media, audio, fingerprints or user identifiers.**
- **Auto-fixing gaps,** and dashboards beyond the digest.
- **The agent filing issues itself.** It drafts only.

## Alternatives considered

- **Do nothing:** limitations stay invisible; detector work is guesswork.
- **Error tracker only:** catches crashes, but not handled limitations.
- **Instant Discord pings:** noisy, and they show cases rather than patterns.
- **An LLM agent from day one:** costs money and adds unpredictability with no data to reason over. It comes later, gated.

## Stories

### 1. Gap reporting API in the worker base
- **Labels:** `story`, `type:build`, `area:worker`, `ml`
- **Owner:** @calvinkafaiyuen (proposed) · **Phase:** 1
- **Context:** every detector needs one way to say "I finished but couldn't be confident".
- **Scope:**
  - Define the gap record in a new **`schema/detector-gap.schema.json`** (reason-code enum from the table above, detector, version, confidence, `occurrences`, `job_id`, timestamp; for fonts only a normalized box size and a font-match score; each row aggregates a job's affected elements: lowest confidence, count, largest box, lowest match score). **No free-text fields.** Types are **generated** by codegen (#2), never hand-written
  - Add `report_gap(reason, confidence, ...)` to the worker base (#53). It is **idempotent: one row per job + detector + reason**; a repeated call **overwrites** that row's `occurrences` with the value just computed (it never increments), so a retry that recomputes the same total leaves the same row and the same count
  - Reject fields outside the schema (so audio, frames or identifiers can't be added by accident)
- **Acceptance criteria:**
  - [ ] Reason codes and record shape come from the generated types
  - [ ] Reporting the same gap twice for a job stores one record
  - [ ] A record containing an unknown field is rejected
- **Depends on:** #53, #2

### 2. Gap store
- **Labels:** `story`, `type:build`, `area:backend`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 1
- **Context:** the digest and the later agent need queryable history.
- **Scope:** a `detector_gaps` table with a unique key on (`job_id`, detector, reason), **written as an upsert that overwrites** `occurrences` (never increments it). Backend access only: **RLS on, no user policies**, written by the workers' service role. **`job_id` is a foreign key with `ON DELETE CASCADE`, so deleting a job (or a user's data) deletes its gap rows.** Rows are purged after a **configurable retention period (at least 8 weeks, so the full metric window can be re-audited), with a proposed default of 90 days until #56 (terms, privacy policy and data retention) sets the final value**. #56 tunes it; it doesn't block this story. Migration through `/db-migration`.
- **Acceptance criteria:**
  - [ ] The two-user RLS test shows an authenticated user cannot read any gap row
  - [ ] Reporting the same gap again (for example on a retry) leaves one row with the same `occurrences`; it never adds a row or increments the count
  - [ ] Deleting a job deletes its gap rows
  - [ ] Rows older than the configured retention (default 90 days until #56 sets it) are purged
- **Depends on:** #49, story 1 (#56 sets the final retention value later; not a blocker)

### 3. Detectors report their gaps
- **Labels:** `story`, `type:build`, `area:worker`, `ml`
- **Owner:** the detector owners, @calvinkafaiyuen and @sktchan (proposed) · **Phase:** 1 (2 for transitions)
- **Context:** only the detectors know when they aren't confident.
- **Scope:** each detector calls the gap API with its documented threshold, and **keeps a low-confidence element (with its confidence) instead of omitting one it's unsure about**, as the plan already specifies:
  - [ ] Beat + sound ID (#14): `sound_not_identified`
  - [ ] OCR (#13): `font_unrecognized`, `text_low_confidence`
  - [ ] Captions (#12): `text_low_confidence`
  - [ ] Orchestrator / upload (#16): `input_unsupported`
  - [ ] Transition classification (#23): `transition_unclassified` (joins when #23 lands, Phase 2)
  - Each detector documents its confidence threshold for "gap" in its own page on the wiki
- **Acceptance criteria:**
  - [ ] A test video that trips each case produces exactly one gap record with the right reason
  - [ ] Each detector's gap threshold is at least `T_low` (a unit test reads `T_low` from the shared config), and an element just below `T_low` always produces a gap
  - [ ] A beat track with no `sound_ref` always produces `sound_not_identified`
  - [ ] A job that finishes with an incomplete template has a gap record (measured for metric (a) in story 5)
- **Depends on:** story 1, story 2, #12, #13, #14, #16

### 4. Weekly digest to Discord
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 1
- **Context:** the team needs patterns once a week, not events.
- **Scope:**
  - A scheduled job (weekly, e.g. Monday morning) that counts the past 7 days by **reason and detector**, plus total jobs, incomplete jobs, and the change vs. the previous week. Top 5 only; one short embed that links out
  - Posts to a Discord channel through a **channel webhook**. The webhook URL is a secret in GitHub/Modal/Vercel secrets, never in the repo (gitleaks enforces it)
  - **No user data in messages:** counts and codes only, no emails, names, media or job lists
  - A `from-digest` label, and a line in the digest explaining how to file a detector issue from it (used to count metric (b))
  - Documented on the wiki (how to read the digest, who acts on it)
- **Acceptance criteria:**
  - [ ] A test run posts a correct digest from seeded gap records
  - [ ] An empty week posts "no data", not an error
  - [ ] The digest contains no identifiers or media
- **Depends on:** story 2, #50, #48

### 5. Coverage check + delivery monitor
- **Labels:** `story`, `type:build`, `area:infra`, `platform`
- **Owner:** @anthonythanpoovong · **Phase:** 1
- **Context:** the digest is only trustworthy if gaps are actually being recorded and the digest actually arrives.
- **Scope:**
  - **Completeness check (at template merge, independent of gap reporting):** flag a job `incomplete` using only the merged template, per "Incomplete template" above (an element from a participating detector below the global `T_low`, or no `sound_ref` although a beat track was detected). Empty output alone never counts, and jobs with a crashed or timed-out worker are excluded. It never reads the gap table. Store the flag and which rule fired on the job record.
  - **Coverage check (metric a):** incomplete jobs that have at least one gap record ÷ all incomplete jobs; show the coverage % in the digest, and list (by reason count only) which rules fired on uncovered jobs
  - **Delivery monitor:** if a digest hasn't been posted by a set time, alert through a **different channel** than Discord (for example the scheduled workflow's failure notification or email), because Discord being down is one of the failure cases
- **Acceptance criteria:**
  - [ ] The digest shows a coverage %, and a seeded uncovered job lowers it
  - [ ] A job whose merged template has a low-confidence element but **no** gap record is flagged incomplete and counted as uncovered
  - [ ] The completeness check gives the same result with the gap table empty (it doesn't depend on it)
  - [ ] A job with a crashed or timed-out worker is excluded from the coverage denominator, and the digest counts how many were excluded
  - [ ] An `input_unsupported` job (no merged template) is excluded from the denominator too, but still appears in the digest's gap counts
  - [ ] Each digest posts that week's coverage value, and the value doesn't change when older gap rows are purged
  - [ ] A video with no text and no music (legitimately empty output) is **not** flagged incomplete
  - [ ] A simulated Discord outage triggers the delivery alert within a day
- **Depends on:** stories 3, 4, and #53 (the orchestrator's merge step)

### 6. Gap triage agent (gated)
- **Labels:** `story`, `type:research`, `area:infra`, `platform`, `risk:blocked`
- **Owner:** @anthonythanpoovong · **Phase:** 2
- **Context:** once there's data, an LLM can turn recurring gaps into draft backlog issues faster than a person can.
- **Gate (must all hold before anyone builds this):** at least **4 weeks of digests**, at least **100 gap records** (value TBD), the coverage check (story 5) at or above 95%, and the digest already producing action (metric b progressing).
- **Scope:**
  - Reads the **aggregated gap table only**: reason codes, counts, detector versions, confidence buckets. **No user media, no identifiers, no text from videos.**
  - The gap table holds **no user-derived text at all** (no OCR or caption text, no identifiers), so there's no prompt-injection path from user content. If a later version ever adds any, it must be passed as quoted data with no tool access.
  - Output is **drafts only**: a markdown file or Discord message for the owner to file or discard. **It never files issues itself**, and has no tools beyond reading the aggregate and writing the draft.
  - **Cost cap:** one call a week with a hard token limit.
- **Acceptance criteria:**
  - [ ] The gate is met and recorded on the issue before work starts
  - [ ] A test confirms the data the agent receives has no free-text fields from users
  - [ ] The agent has no write access to issues, code or the database
  - [ ] Spend stays within the weekly cap
- **Depends on:** stories 4, 5, plus the gate above

## Risks & costs

| Risk / cost | Likelihood / size | Mitigation |
|---|---|---|
| Detectors don't report their gaps, so the digest under-counts | Medium | Coverage check in every digest (story 5); metric (a) |
| Retries inflate counts | Medium | Unique key per job + detector + reason |
| Discord down, or the webhook revoked, and nobody notices | Medium | Delivery monitor through a different channel (story 5) |
| Gap data leaks user information | Low | Schema-enforced fields, no identifiers or media, counts-only digest |
| Webhook URL leaked | Low | Secret in the platform secret stores; gitleaks; rotate if exposed |
| Metric (a) audits the detectors using their own thresholds | Medium | "Incomplete" is computed from the merged template by a separate completeness check, never from gap records (story 5) |
| Digest noise leads to it being ignored | Medium | Top 5 only, week-over-week deltas, one short message |
| Extra work for every detector owner | Medium | One shared API; reporting is a few lines per detector |

Cost: $0 for the digest (existing infra, a free webhook). The agent (Phase 2) is at most one capped LLM call a week.

## Security & data

New additive schema file (`schema/detector-gap.schema.json`) and a `detector_gaps` table with RLS enabled and **no user policies** (backend only). No template schema change. **No audio, frames, fingerprints, OCR or caption text, or user identifiers are stored**; only codes, counts and numeric scores. Gap rows are **deleted with their job** (`ON DELETE CASCADE`) and follow the retention period from #56. The Discord webhook is a secret.

## Open questions

- **Discord setup:** which server and channel, who creates the webhook, and how it's rotated.
- **Digest timing:** day and time, and whether a minimum number of jobs is needed before posting.
- **Confidence thresholds** that define a gap for each detector: owned by the detector owners.
- **`T_low`**, the single low-confidence threshold used by the completeness check: set once with the CV owners.
- **More detectors in the metric:** cuts (#7), motion (#8) and color (#24) join once they have reason codes. Until then they're outside the completeness rule.
- **Presentation of elements below `T_low`** (hidden, flagged, or approximated in the UI, exporters and the Bridge): decided in the breakdown-page and adapter stories (#18, #33–#36). This epic doesn't change it.
- **Retention period** for gap rows: set with terms/privacy/retention (#56).
- **Agent gate values:** the exact number of gap records and weeks (proposed: 100 and 4).
- **Evidence:** no interviews yet; the first real data arrives with the design-partner beta (#55).
- **Ownership:** @calvinkafaiyuen and @sktchan haven't been told, and this adds work for each detector.

<details><summary>Grill scorecard</summary>

| Area | Verdict | Note |
|---|---|---|
| Problem & evidence | ⚠️ | No production data yet; follows from the partial-failure design |
| Smallest valuable version | ✅ | Deterministic weekly digest; agent gated |
| Alternatives | ✅ | Do nothing, error tracker, per-alert pings, agent-first: rejected |
| Fit with Key Decisions | ✅ | Deterministic first; no audio stored; generated types |
| Data & schema | ✅ | New additive schema file and table |
| Security & privacy | ✅ | Backend-only, no PII, media or text; cascade delete + #56 retention |
| Cost | ✅ | $0 digest; ≤1 capped call/week later |
| Failure modes | ✅ | Delivery monitor, unique key, counts-only |
| Reversibility | ✅ | Two-way door |
| Observability | ✅ | Coverage % and delivery monitor |
| Success metric | ✅ | 95% coverage + 3 improvements by the Phase 1 gate + 8 weeks |
| Effort & ownership | ⚠️ | CV owners not yet consulted |

</details>
