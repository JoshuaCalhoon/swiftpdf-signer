# Design system — SwiftPDF

**Status:** APPROVED for v1 (accent + dark-mode behavior signed off; KwikShip brand colors sourced from the logo SVG).

The app's visual content is dominated by the PDF being rendered — app chrome (title bar, action buttons, field overlays) is intentionally minimal so the form reads cleanly. Brand expression lives in the PDF itself, with subtle reinforcement in the app's accent color.

Visual ethos (from kwikship.com): industrial-meets-approachable, utility-focused with personality. Honest, no-nonsense, professionally precise. The app should feel like a workhorse tool, not a consumer signing app.

## Current design system

### Colors
Brand palette pulled from the KwikShip logo SVG (`#ff5100`, `#3d3935`, `#30261d`, `#fff`):

- **Primary accent**: `#FF5100` — KwikShip brand orange. Used for: primary action buttons ("Done"), active field outlines, success-state accents, focus indicators.
- **Warm dark**: `#3D3935` — used sparingly for emphasized text on light backgrounds (e.g. signed-form preview title) and for the inactive tab in any segmented control.
- **Deep brown**: `#30261D` — reserved for high-contrast strokes; rarely used in chrome.
- Background: system adaptive (`Color(.systemBackground)`) — light/dark follows iPadOS appearance
- Surface (cards, sheets): `Color(.secondarySystemBackground)`
- Text (primary): `Color(.label)` — adapts to dark mode
- Text (muted): `Color(.secondaryLabel)`
- Field outline (idle): `Color(.separator)`
- Field outline (active): primary accent (`#FF5100`)
- Error: `Color(.systemRed)`
- Success: primary accent on a green check icon (avoid double-tone — orange owns the brand)

### Typography
- All chrome uses **system font** (San Francisco) — default weights, Apple's Dynamic Type respected
- Title bar (form name): `.title2`, `.semibold`
- Body text in app chrome: `.body`
- Field overlay placeholder hints: `.callout`, `Color(.tertiaryLabel)`
- Action button labels: `.body`, `.semibold`

### Spacing
- Base unit: 8pt (Apple standard)
- Scale: 4, 8, 12, 16, 24, 32, 48
- Field overlay padding: 12pt inside the tap target
- Action button height: 56pt for clear thumb target

### Radii & shadows
- Field overlay corner radius: 8pt
- Action button corner radius: 12pt (iOS-standard for prominent buttons)
- No drop shadows on chrome — keep it flat against the PDF surface

### Components
- **Action button** (primary): filled rectangle, accent color background, white text, 12pt radius, 56pt height. iOS-standard "borderedProminent" style with `.tint(accent)`.
- **Field overlay**: tappable rectangle over a region of the PDF. Idle: 1pt separator-color outline, transparent fill. Active: 2pt accent-color outline, very subtle tinted fill. Tapping focuses iPad keyboard.
- **Signature canvas**: PencilKit `PKCanvasView` constrained to the signature-line region of the PDF. Pencil + finger both enabled. Toolbar hidden — single ink color (black), single tool (pen).
- **Status banner**: ephemeral top-of-screen pill showing "Uploaded to Dropbox" (success, green) or "Upload failed — will retry" (error, red). Auto-dismisses after 2s on success.

### Motion
- Default transition: 0.2s, ease-out
- Field focus animation: outline color cross-fade, 0.15s
- Reset to blank form after successful upload: 0.3s cross-dissolve
- No bouncy springs in chrome — keep it calm and professional

### Icon set
- SF Symbols only — no custom SVG in v1. Likely used: `pencil.tip`, `signature`, `checkmark.circle.fill`, `arrow.up.circle`, `xmark`.

## Open questions
1. **Launch screen / app icon**: bundle the KwikShip mark, or keep the app icon generic? (Defer until v1 ships and a real iPad install needs an icon.)

## Decision log (append-only)

### 2026-05-11 — Initial design proposal seeded
**Change:** First draft of the design system, written before any UI code exists.
**Why:** Project-memory workflow requires `design.md` to exist and be approved before UI work begins. Brief was vague on visual direction; tokens proposed based on the form's KwikShip brand color (orange) and iPadOS conventions. Awaiting user approval on accent + dark-mode + branding questions above.

### 2026-05-11 — KwikShip orange #FF5100 accent + adaptive dark mode approved
**Change:** Primary accent locked to `#FF5100` (sourced from the live `KwikShip_Logo.svg`, not the `#E97132` originally lifted from the Word doc's "orange accent" style). Added supporting darks `#3D3935` and `#30261D` from the same SVG. Adaptive dark-mode behavior approved.
**Why:** User asked to inspect kwikship.com for the design ethos. The live logo SVG yields the true brand color (`#ff5100` — bright industrial orange), distinct from Word's default orange accent (`#e97132`) used on the Effective-Date doc title. Site's visual ethos read as "industrial meets approachable, utility-focused with personality" — informs the choice to keep app chrome minimal and let the accent do the brand work.
