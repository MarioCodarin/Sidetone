# Sidetone UI audit

Stack: SwiftUI menu-bar agent app (`MenuBarExtra` window style, `LSUIElement`), built with SwiftPM + `build.sh`
(no Xcode project). Installed before this work: `/Applications/Sidetone.app`, v1.0 (build 1), ad-hoc signed.

Screens captured with `swift run SidetonePreview <dir>` (real views, fixture data, light + dark, window-only
screenshots). Sidetone has no resizable document window: the panel is a fixed 340 pt popover and Settings a fixed
420 pt window, so "small window" is covered by the *states* (empty, long titles, permissions) instead.

Criteria that do not apply to a menu-bar agent (sidebar, unified toolbar, full screen, state restoration) are scored
on what *can* apply and called out.

## Round 0 — baseline

| # | Criterion | Score | Problems |
|---|-----------|:----:|----------|
| 1 | Launch experience | 6 | No window by design, panel opens instantly, no splash. But meetings/recordings are re-fetched on open, so lists can jump after first paint; permission prompts fire at launch with no lead-in. |
| 2 | App icon | 5 | Artwork fills the whole 1024 canvas (no Apple-grid margin) so it renders larger than every neighbour in the Dock. Three saturated colours (green/blue/red) plus gradient; at 16 px it is a muddy blob. Menu-bar glyph is a proper SF Symbol (fine). |
| 3 | Visual design | 5 | Five full-width dividers in one 340 pt panel; five font styles for one hierarchy; paddings 3/4/6/8/12 and radii 6/8 with no scale; hard-coded green/blue/red/orange; heavy filled grey rows for every recording; dead space between the list and the footer (height estimate is off). |
| 4 | Native feel | 6 | Correct popover + Settings window, Cmd+, / Cmd+Q / Cmd+R exist. Footer buttons are default `.borderless` label+icon buttons that look dated; Settings is a stock grouped Form with hint text stranded in its own row. |
| 5 | Dark mode / accent | 7 | System colours for text and fills, but meters, tint and banners use fixed hues and fixed opacities; Save button is hard-coded blue (ignores the user's accent). |
| 6 | Interaction & motion | 4 | No hover or pressed feedback on rows; state changes (idle → recording) swap content with no transition; only the meters animate; nothing consults Reduce Motion. |
| 7 | UX flow | 6 | Primary action is clear. "Tags this recording as “Weekly product sy…”" + a tiny "Without meeting" link is cramped and truncates. Every meeting row repeats a red record glyph. Empty state is one grey line. |
| 8 | Accessibility | 6 | Most controls have labels. `.focusEffectDisabled()` hides keyboard focus on the panel; 10 pt `caption2` text is used for meaningful content; colour alone separates "Them" and "You" meters. |

Screenshots: `base/` (not committed).

## Round 1 → 2 — design system, panel rebuild, icon, Settings

What changed: `Support/Design.swift` (spacing 4/8/12/16, radii 6/8/10, type 13/11 + 22 timer, palette, motion,
button styles, hover helper); panel rebuilt around one primary action with quiet hover-revealed chrome, a single
hairline, section headers instead of dividers, relative dates, "Now · until" on the live meeting, spinner while
mixing; new icon from `Assets/icon.svg`; Settings regrouped with footers and a real slider.

Verification done (not just looked at):
- 13 scenarios × light/dark captured from the real views (`swift run SidetonePreview`), reviewed twice.
- Hover fill checked with the real pointer (`hover-*.png`).
- Accessibility tree dumped through the macOS AX API: every button has a spoken label, meters expose "Them, system
  audio level", section titles are headings. Found and fixed one real defect (VoiceOver read the warning icon as
  "Exclamation Mark In A Filled Circle").
- Settings window: ⌘W and Esc close it, and its frame is saved (driven with real key events).
- Launch: menu-bar item present 0.20 s after `open` (release build, 3 runs; first cold run 0.74 s).
- `swift run SidetoneCheck`: 178 passed, 0 failed. Release build: no new warnings (the two pre-existing
  `ld: search path … not found` lines are unchanged).

| # | Criterion | Before | After | Notes |
|---|-----------|:----:|:----:|-------|
| 1 | Launch experience | 6 | 8 | 0.2 s to menu-bar item, no window, splash or flash. List height is measured with an estimate for frame one. Not verifiable: first open of the real popover (see below). |
| 2 | App icon | 5 | 9 | Apple-grid margin, one colour + white, bold split-circle, legible at 16 px; SVG source + script + full `.icns`. Menu-bar glyph stays a template-style SF Symbol. |
| 3 | Visual design | 5 | 8 | One hairline instead of five dividers, two text sizes + one timer, 4 pt grid, three radii, one accent. Rows are quiet at rest. |
| 4 | Native feel | 6 | 8 | Material popover, standard Settings window, ⌘R/⌘,/⌘Q shown in tooltips/UI, ⌘W + Esc in Settings, remembered position. Gap: Esc does not dismiss the popover (not changed: can't verify it in the real popover). |
| 5 | Dark mode / accent | 7 | 8 | Semantic colours throughout; Save and meters follow the user's accent; only red (recording) and orange (needs attention) are fixed. |
| 6 | Interaction & motion | 4 | 8 | Hover + pressed on every control, 150 ms feedback, breathing record dot, fades between states, all gated on Reduce Motion. Pressed state and fades checked in code only (screenshots are static). |
| 7 | UX flow | 6 | 8 | One red Record button with ⌘R hint; "Named “…”" + "Without meeting" on one line; "Now · until 13:10"; mixing spinner and saved check; plain-language errors in a tinted card. Empty state is still a single line. |
| 8 | Accessibility | 6 | 8 | Verified AX labels, headings, meter values; ≥ 11 pt text; focus ring no longer suppressed; Reduce Motion honoured. VoiceOver itself was not run. |

Remaining, honestly: the real popover could not be driven in this session (the menu-bar item sits behind a
full-screen Space and an AX press opened nothing), so first-open sizing and popover Esc are unverified there.
A long list ends in a hard clip rather than a fade.
