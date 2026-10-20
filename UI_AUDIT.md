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
