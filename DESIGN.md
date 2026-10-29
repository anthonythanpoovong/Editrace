---
name: Editrace
description: Bone, Ink and a single red scan line. The Editrace brand system, built from brand/BRAND.md; the coming-soon page currently ships its light register.
colors:
  ink: "#141412"
  bone: "#fbf9f5"
  paper: "#efebe3"
  stone: "#6e6a62"
  rule: "#d3cdc0"
  muted-dark: "#a8a399"
  secondary-dark: "#d6d1c6"
  leader-red: "#d8432e"
  red-on-dark: "#e5553f"
  ui-red: "#c23a26"
  brass: "#a88a55"
  white: "#ffffff"
typography:
  display:
    fontFamily: "Space Grotesk, ui-sans-serif, system-ui, sans-serif"
    fontSize: "clamp(2.5rem, 5vw, 4.5rem)"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "-0.04em"
  lede:
    fontFamily: "Space Grotesk, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 400
    lineHeight: 1.5
  body:
    fontFamily: "Space Grotesk, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.5
  small:
    fontFamily: "Space Grotesk, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "JetBrains Mono, ui-monospace, monospace"
    fontSize: "0.8125rem"
    fontWeight: 500
    letterSpacing: "0.02em"
  note:
    fontFamily: "Space Grotesk, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  sm: "0.5rem"
  pill: "999px"
components:
  button-primary:
    backgroundColor: "{colors.ui-red}"
    textColor: "{colors.white}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "0 2rem"
    height: "4.25rem"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "0 2rem"
    height: "4.25rem"
  input-field:
    backgroundColor: "{colors.white}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "0 1.25rem"
    height: "4.25rem"
  status-badge:
    textColor: "{colors.stone}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0.3rem 0.75rem"
---

# Design System: Editrace

<!-- Scan-mode extraction from site/index.html, built on the accepted Editrace brand kit (brand/BRAND.md, PR #114). BRAND.md is bi-modal by design (a light marketing register and a dark "Ink" register for app/video surfaces); this page currently ships light, flipped from an earlier dark build at the user's request. Dark-register tokens stay documented below since they remain valid brand tokens for a future dark surface, not because this page uses them today. -->

## Overview

**Creative North Star: "The Scan Line"**

Editrace reverse-engineers short-form video: the mark is a 9:16 frame cut by a single horizontal scan line, a video being read layer by layer. The system carries that idea through every surface: Ink and Bone/Paper hold the page like a light table and film stock, Leader Red is the one signal that moves, and JetBrains Mono gives UI chrome a measured, technical register. The voice is precise, calm and engineered. Confident, not loud — no glows, no sparkles, no gradient.

**This page ships light**: Bone background, Ink text, the horizontal logo lockup and footer wordmark in their light-background variants (`logo-horizontal-light.svg`, `wordmark-light.svg`). A dark "Ink" register also exists in the brand kit for app surfaces and video end cards; it is documented here for completeness but not currently in use on this page (its tokens and assets remain in `site/images/brand/` as `*-dark.svg`, ready to swap back in).

**Key Characteristics:**
- Warm off-white and warm near-black, never cool/neutral greys: the palette is ink-and-paper, not slate-and-white.
- One moving accent: red, reserved for the logo's scan line, the primary CTA, focus rings and error states — never decorative. Leader Red for large/graphic use, UI Red for small text and interactive states (the brand's own split, since Leader Red fails AA at small sizes on light backgrounds).
- Two-font system: Space Grotesk for anything a visitor reads, JetBrains Mono for anything the system labels.
- Flat. No shadows, no gradients. Depth from surface value only (white fields on a Bone page).

## Colors

The accepted Editrace brand palette (brand/BRAND.md). This page uses the light-register subset; the dark-register colors (`red-on-dark`, `muted-dark`, `secondary-dark`) stay documented as valid brand tokens for a future dark surface.

### Primary
- **UI Red** (`#c23a26`): Fill for the one primary commitment action (the signup submit button), white text — the brand's "white on UI Red" pairing (5.35:1). Also every small-scale interactive/error signal on this page: focus rings, invalid field borders, error text. Leader Red fails AA for small text on light backgrounds (documented in BRAND.md), so UI Red — not Leader Red — is this page's "something needs attention" color.

### Secondary
- **Leader Red** (`#d8432e`): The logo's own scan line, and the hero headline's trailing full stop — BRAND.md's explicitly approved "red full stop" accent. Reserved for graphics and large display text only; never small text (3.71:1 on light backgrounds, below AA for body copy).

### Tertiary
- **Brass** (`#a88a55`): Reserved by the brand for keyframes and secondary markers. Not used on this page; carried here so a future surface doesn't reach for an unapproved accent.

### Neutral
- **Bone** (`#fbf9f5`): This page's background — the brand's brighter light surface ("app screens"), chosen over Paper specifically because it pushes UI Red to 5.09:1, clearing AA for small error text where Paper (4.497:1) falls just short.
- **Ink** (`#141412`): All primary text, the light-logo frame colour, and the secondary button's outline/fill.
- **Stone** (`#6e6a62`): Every secondary/muted role on this page — the lede, feature copy, field labels, status badge, tools line, footer credit, cancel link. The brand's light-background palette offers one secondary tone, not two, so it does double duty here.
- **Rule** (`#d3cdc0`): Input/select borders and section hairlines (above the feature list, above the footer) — used directly, exactly as BRAND.md names it for light backgrounds.
- **White** (`#ffffff`): Input/select fill (one step brighter than the Bone page background) and button text on UI Red.
- **Paper** (`#efebe3`), **Muted · on dark** (`#a8a399`), **Secondary text · on dark** (`#d6d1c6`), **Red · on dark** (`#e5553f`): Dark-register tokens, not used on this page today. Kept here so a future dark surface (or this page, if flipped back) has its tokens ready without re-deriving them.

### Named Rules
**The Scan-Line Rule.** Red is the only accent on this page. It appears exactly four ways: the logo's own scan line, the primary CTA fill, the focus ring, and error state. It never decorates.

**The Two-Red Rule.** Leader Red is for graphics and large display text only. UI Red is for every small-scale interactive or error signal. Using Leader Red for small text is an accessibility regression, not a stylistic choice — BRAND.md documents the exact contrast failure.

**No Recolouring the Logo Rule.** The logo and wordmark ship only as the brand's own supplied SVG/PNG files (`brand/logo/svg/...`, mirrored into `site/images/brand/` for deployment). Never retype "Editrace" in a font, recolour the mark, or rebuild the lockup — BRAND.md's own Don'ts, binding here.

## Typography

**Display Font:** Space Grotesk (with `ui-sans-serif, system-ui, sans-serif` fallback)
**Body Font:** Space Grotesk
**Label/Mono Font:** JetBrains Mono (with `ui-monospace, monospace` fallback)

**Character:** Space Grotesk carries every reading surface — headline, lede, feature copy — with a geometric, slightly technical warmth. JetBrains Mono is reserved for the system's own voice: labels, the status pill, timecode-style microcopy, never body prose. The pairing is the brand's own, specified down to the weight: 600 for headings, 500 for subheads, 400 for body, 400/500 for mono UI chrome.

Both are loaded from Google Fonts per BRAND.md's own embed snippet (`fonts.googleapis.com/css2?family=Space+Grotesk...&family=JetBrains+Mono...`).

### Hierarchy
- **Display** (600, `clamp(2.5rem, 5vw, 4.5rem)`, line-height 1, tracking -0.04em): The headline only. Its final full stop is set in Leader Red — BRAND.md's own approved accent move.
- **Lede** (400, 1.125rem, line-height 1.5, Stone): The supporting promise. Max 42ch.
- **Body** (400, 1rem, line-height 1.5, Stone): Feature copy.
- **Small** (400, 0.9375rem, Stone): The tools line ("Planned for Premiere Pro...").
- **Note** (400, 0.875rem): The signup status line and per-field error text; colour switches by state (Stone at rest, UI Red for error, Ink for success).
- **Label** (500, JetBrains Mono, 0.8125rem, letter-spacing 0.02em, Stone): Field labels, the status badge, the cancel link, footer credit.

### Named Rules
**The Two-Voice Rule.** Space Grotesk reads; JetBrains Mono operates. A sentence is never set in mono, and a label, badge, or timecode-style value is never set in Space Grotesk.

**The Approved Full Stop.** A hero headline's trailing period may be set in Leader Red. This is the brand's only sanctioned full-word-level colour break; it is not a general licence to recolour individual characters elsewhere.

## Layout

A single centred column, 60rem max width, 1rem side gutter at every size. Vertical stack: header (logo + status badge), main (headline, lede, tools line, signup teaser, feature grid, signup panel), footer (wordmark + credit). Feature content moves from one column to three at 40rem. The signup grid moves from one column to two at 30rem.

## Elevation & Depth

Flat. No shadows anywhere. Depth comes from surface value: white input fields one step brighter than the Bone page.

## Shapes

0.5rem radius on buttons and fields, full pill (999px) on the status badge, 1px Rule hairlines for dividers.

## Components

### Buttons
- **Shape:** 0.5rem radius, 4.25rem height, horizontal padding 2rem, Space Grotesk 600.
- **Primary** (`.btn-primary`): UI Red fill, white text. The form's actual commitment ("Notify me at launch") — the one obligation on the page.
- **Secondary** (`.btn-secondary`): Ink fill, Bone text — BRAND.md's own "Paper on Ink: default primary buttons ('Follow')" pairing. Used for the lower-commitment teaser ("Get notified") that only reveals the form; both buttons are solid filled blocks against the page, differentiated by colour (red = the one commitment, ink = default) rather than by fill-vs-outline weight.
- **Hover / Focus:** Both buttons drop opacity to 0.88 on hover. Keyboard focus on every control shows a 2px UI Red outline, 2px offset.

### Inputs / Fields
- **Style:** White background, 1px Rule border, 0.5rem radius, 4.25rem height, 1.25rem horizontal padding. Persistent visible mono label above every field, 0.5rem gap.
- **Focus:** 2px UI Red outline, 2px offset.
- **Error:** Border shifts to UI Red; a per-field error message in UI Red appears below the field, plus a shared status line below the form.

### Navigation
Minimal header: the horizontal logo lockup (`logo-horizontal-light.svg`, clamp(7.5rem, 24vw, 10rem) wide — above the brand's 120px digital minimum at every size) on the left, the status pill on the right. No nav links.

### Status Badge
JetBrains Mono pill, 1px Stone border, Stone text — the brand's own "small caps-style tag" role for UI chrome on light backgrounds.

### Footer wordmark
`wordmark-light.svg` at 7.5rem wide (well above the brand's 90px minimum), beside a mono credit line. Per BRAND.md, the standalone wordmark is for exactly this case: "where space is very wide and short."

## Do's and Don'ts

### Do:
- **Do** keep red to exactly four jobs: the logo's scan line, the primary CTA, focus rings, error state.
- **Do** use UI Red (not Leader Red) for any small-scale text or interactive state — Leader Red fails AA at small sizes on light backgrounds.
- **Do** use the brand's own logo/wordmark SVG files, never retyped text.
- **Do** keep Space Grotesk for anything a visitor reads, JetBrains Mono for anything the system labels.
- **Do** give every form field a persistent visible mono label; a placeholder is an example value, never the only label.

### Don't:
- **Don't** recolour, rotate, skew, or rebuild the logo lockup.
- **Don't** add a second accent colour outside the approved palette.
- **Don't** use shadows or gradients to create depth.
- **Don't** set UI chrome (labels, badges, timecodes) in Space Grotesk, or body prose in JetBrains Mono.
- **Don't** link a social or external account that doesn't exist yet. Omit the row until it does.
