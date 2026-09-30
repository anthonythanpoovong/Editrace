---
name: log-interview
description: Record a Sequa customer, design-partner or user conversation as structured evidence in docs/customers/. Use when someone says "log an interview", "I just talked to a creator/editor", "save these call notes", pastes interview notes, or needs evidence for a grill or proposal. Produces tagged, quotable evidence that /grill and /propose-epic cite.
---

# Log a customer interview

Turns a conversation into **evidence** that `/grill` can cite. The most useful part is the person's own words about a real problem. Your paraphrase or your idea isn't evidence.

## 1. Gather

Ask for (or pull from pasted notes):
- **Who:** role and segment, e.g. "freelance short-form editor, ~40 videos/week, uses CapCut + Premiere". **Not their name, email or handle** unless they agreed to be named.
- **Consent:** did they agree to notes being kept? If not, don't log it.
- **When** and **how** (call, DM, in person), and who ran it.
- **What they do today:** their current workflow and tools, step by step.
- **Pains**, in their words: exact quotes where possible.
- **What they asked for** vs. **what we pitched**. Keep these separate. Reacting to our pitch is weaker evidence than a pain they raised themselves.
- **Numbers:** time spent, volume, what they pay for tools.

Push back gently on leading-question notes: "Did they bring up link-pasting themselves, or did we ask?"

## 2. Tag

Add 2–6 tags from the list in `docs/customers/README.md` (e.g. `upload-friction`, `wants-feed`, `refilm`, `editor:capcut`, `pricing`). Add a new tag only if nothing fits, and add it to the README list too.

For each tag, mark the strength:
- **raised:** they brought it up unprompted
- **confirmed:** they agreed when asked
- **rejected:** they said it's not a problem

## 3. Write

- File: `docs/customers/YYYY-MM-DD-<segment>-<short>.md`, e.g. `2026-10-02-travel-creator-capcut.md`, copied from `docs/customers/TEMPLATE.md`.
- Fill in only what was said. Leave unknowns empty; don't invent quotes.
- Link related issues or proposals (`#55`, `docs/epics/...`).
- Show the draft to the author before saving.

## 4. Commit

```sh
git fetch origin main
git checkout -b customers/YYYY-MM-DD-<short> origin/main
git add docs/customers/
git commit -m "Log interview: <segment> (<tags>)"
git push -u origin customers/YYYY-MM-DD-<short>
gh pr create --base main --title "Interview: <segment>" --body "<tags + one-line takeaway>"
```

## 5. Summarize the evidence

After saving, count interviews per tag (`grep -l "tag-name" docs/customers/*.md | wc -l`) and tell the author what changed, e.g. "`upload-friction`: now 3 raised, 1 rejected."

## Rules
- No names, emails, handles, company-confidential details or screenshots without explicit consent. Describe people by role and segment.
- Quotes must be real. Mark paraphrases as paraphrases.
- One file per conversation.
