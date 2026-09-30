---
name: spike
description: Plan, run and close a time-boxed Editrace spike that answers one technical or product unknown. Use when /grill's verdict is "Needs a spike first", someone says "spike this", "prototype to find out", "is X even possible", or to close out an open type:spike issue (e.g. #29) with findings and a recommendation.
---

# Spike: answer one unknown, cheaply

A spike exists to **answer a question**, not to ship code. It has a timebox, an exit condition and a recommendation. Spike code is thrown away unless a later story adopts it.

## Mode A: open a spike

1. **One question, stated so it can be answered.** "Can the Resolve free edition's scripting API build a timeline with speed ramps?" works. "Explore Resolve" doesn't. If there are several questions, open several spikes.
2. **Why it matters:** which proposal, ADR or story is blocked on the answer.
3. **Timebox:** in days (usually 1–3). Past the timebox, you stop and report what you know.
4. **Approach:** the smallest experiment that answers the question: a script, a throwaway branch, reading docs or terms, a call.
5. **Exit:** what result means "yes", "no" or "yes, but…". Decide this **before** starting.
6. **Owner.**

Check it doesn't already exist: `gh issue list --label type:spike --state all`. Then, after the author confirms:

```sh
gh issue create --title "Spike: <question>" \
  --label type:spike,risk:research-heavy,<area:*>,<ml|platform|product> \
  --body "<Question / Why it matters / Timebox / Approach / Exit / Owner>"
```
If it belongs to an epic, link it as a sub-issue (see `propose-epic` for the `sub_issues` API call).

## Mode B: run it

- Work on a throwaway branch `spike/<n>-<slug>`. **Don't merge spike code.** Push the branch only if the evidence is worth keeping.
- Record facts as you go: commands run, versions, links to docs or terms, measurements. Note assumptions you couldn't check.
- Stop at the timebox even if it's unfinished. "We don't know yet, because…" is a valid finding.

## Mode C: close it

1. Post a findings comment on the spike issue:
   ```
   ## Findings
   **Answer:** yes / no / yes, but … (one line)
   **Evidence:** bullet list: what we tried, versions, measurements, links
   **Surprises / risks:**
   **Recommendation:** what to do next
   **Time spent:** X of Y days
   ```
2. Hand off based on the answer:
   - It settles a technical decision → `/propose-adr` (link the spike as evidence)
   - It unblocks a body of work → `/propose-epic`, or update the blocked story
   - It kills the idea → say so. Update `docs/plan.md` Open Questions via `/sync-docs`.
3. Close the issue: `gh issue close <n> --reason completed`.

## Rules
- One question per spike. No production code, and no merging spike branches into `main`.
- Never extend the timebox silently. Ask the author, and record the new date on the issue.
- Legal and terms questions go to #21, not a code spike.
