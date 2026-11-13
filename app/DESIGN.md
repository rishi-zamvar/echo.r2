# echo.r2 design direction

Mode: **Operate.** Rishi opens echo to see what his Claude sessions are doing and tell one what to do next, often one-handed, often outdoors. Scanability and calm beat expression. Brand lives in the details: the serif voice, the paper, the sage.

This is a refinement of the incumbent apothecary language (shared with WorkoutCoach), not a new world. Tokens live in `app/EchoR2/DesignSystem/`. Views use tokens only: no raw colours, no `.spring(...)` literals, no `UIFeedbackGenerator` calls in `Views/`.

## Colour

Light only. The app sets `UIUserInterfaceStyle = Light`; there are **no black surfaces** anywhere, including system-drawn ones (nav bars, sheets, forms, keyboards inherit light). Dark-mode phones still get paper and lavender. The terminal's dark theme is an opt-in toggle, never the default.

| Role | Token | Use |
|---|---|---|
| Room | `Palette.canvas` via `BackgroundAtmosphere` | Behind every screen, including inside the navigation stack (`.screenBackground()`) |
| Page | `Palette.paper` | Cards, rows, sheets, fields |
| Ink | `Palette.ink` | Titles, values, body |
| Secondary | `Palette.textSecondary` | Summaries, labels |
| Muted | `Palette.textMuted` | Metadata (time, origin). Still AA |
| Brand | `Palette.primaryDeep` | Primary button fill, tint, links |
| Running | `Palette.running` | Live session: dot, chip, title stays ink |
| Needs you | `Palette.needsYou` | Waiting on Rishi: chip + title colour; sorted first |
| Idle | `Palette.idle` | Done, stopped, watching: quiet, never alarming |
| Danger | `Palette.danger` | Errors, destructive actions only |

Chips are tinted fills (`role.opacity(0.14)`) with text in the role colour, so state reads from colour **and** word. "stopped" is idle, not danger: a stopped session is normal.

Contrast (WCAG, measured on paper / canvas): ink 13.3 / 12.6, textSecondary 7.4 / 7.0, textMuted 5.2 / 4.9, running 6.2 / 5.9, needsYou 6.0 / 5.6, danger 6.0 / 5.7. All body text passes AA 4.5:1. `primaryDeep` was deepened one step (0.36/0.50/0.42 to 0.32/0.46/0.38) so the paper label on the primary button is 5.0:1 (was 4.3).

## Type

- **Display (serif)**: screen titles via the navigation bar (New York, regular), the `echo` wordmark. One serif moment per screen.
- **Body (SF Rounded)**: everything you read in a row or card. `heading` for row titles, `callout` for summaries and labels, `caption` for metadata.
- **Mono**: only for paths, hosts, codes and build ids. Never as decoration.
- Every style is a Dynamic Type text style (`.headline`, `.subheadline`, ...), so text scales to XXL. Row titles wrap up to two lines and state chips never truncate (they sit above the time line at accessibility sizes).

## Spacing and anatomy

4 pt grid (`Spacing`). Screens inset 16; cards pad 16; 12 between rows; 24 between groups.

**Session row** (a paper card, whole card tappable, one VoiceOver element):
1. Title (heading, ink or needsYou) + state chip, chip right-aligned, top-aligned.
2. Summary, one line, secondary (two at XXL).
3. Metadata: running dot / origin ("Terminal", "Even Terminal/SDK") left, relative time right, muted.

**Settings group**: a serif group title outside the card, label/value rows inside separated by hairline dividers, values right-aligned and allowed to wrap.

No eyebrows above headings, no nested cards, no coloured side borders.

## Motion

Springs everywhere, from `Motion`:

| Token | Feel | Used for |
|---|---|---|
| `Motion.snappy` | 0.30 s, crisp | Press states, chips, toggles, disclosure chevrons |
| `Motion.list` | 0.42 s | List insert, remove and reorder (keyed by session id), Other section |
| `Motion.gentle` | 0.50 s | Pairing to list, banners, empty/loading/error swaps |

- Navigation pushes and sheets use the system transitions. No custom push animations.
- Apply via `.motion(Motion.x, value:)` or `Motion.animate(Motion.x) { ... }`. Both swap to a 0.2 s ease-in-out cross-fade when Reduce Motion is on; repeating pulses stop.
- Nothing jumps: loading, empty and error states occupy the same frame and cross-fade.

## Haptics

One semantic API (`Haptics`), mapped per D-12:

| Moment | Call | Generator |
|---|---|---|
| Send a message, start a session | `Haptics.send()` | medium impact |
| Message or state arrives | `Haptics.arrival()` | light impact |
| A session changes state | `Haptics.stateChange()` | soft impact |
| Pull to refresh | `Haptics.refresh()` | rigid impact |
| Toggle, disclosure, picker choice | `Haptics.toggle()` | selection |
| Destructive confirm opens / fires | `Haptics.destructive()` | warning notification |
| Any failure shown to the user | `Haptics.failure()` | error notification |
| Pairing succeeds | `Haptics.paired()` | success notification |

## States

- **Loading**: skeleton rows in the real row shape (paper, muted bars), never a bare spinner on an empty screen.
- **Empty**: a sentence that says what to do and the one action that does it ("Start a session").
- **Error / unreachable**: `ConnectionBanner` on paper with a coloured dot and a Retry button; the list stays readable underneath (dimmed), never replaced.
- **Inline errors**: under the field that caused them, in `danger`, naming the problem and the fix.

## Accessibility

- AA contrast for all text (numbers above).
- Every control has an `accessibilityLabel`; icon-only buttons always.
- Rows are one element: "title, state, summary, time", with the hint "Opens the session".
- Dynamic Type to XXL with no truncation of titles, state, or errors.
- 44 pt minimum tap targets. Reduce Motion honoured by `Motion`.
- Accessibility identifiers from 05-02 are part of the contract; never rename them.
