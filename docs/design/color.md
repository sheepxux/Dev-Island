# Color

Source: `IslandAppLib/Theme/OKLCH.swift` (primitives), `Colors.swift`
(island roles), `WindowPalette.swift` (window roles). Views use roles only
(see the layer rule in `DESIGN.md`).

## Primitives

`Sand` is the one neutral ramp: 16 steps, `s0` (L 0.992) to `s1000`
(L 0.150), all at hue 86° with chroma ≤ 0.016. Windows read from the light
end, the island from the dark end. Dark and light are the same ramp read from
opposite ends, not two palettes.

`Signal` holds the state hues. Chroma ranks urgency; it is not equalized:

| State | Island (`…OnDark`) | Windows (`…OnLight`) | Chroma rank |
| --- | --- | --- | --- |
| Waiting (needs you) | `#E5B476` | `#7B5D37` | 1, most vivid |
| Failed | `#E49C90` | `#9E4336` | 2 |
| Completed | `#A6C8AA` | `#4C6D50` | 3, barely tinted |
| Running | `Sand.s50` (neutral) | `Sand.s700` (neutral) | none |

Running has no hue on purpose: it is the most common state, and its orbiting
dots already say "working". Giving it a color would make every busy menu bar
compete with the amber of a waiting request.

New colors are authored as `OKLCH(l, c, h)`. To fix contrast, move `l` only.
A new neutral takes hue 86 and chroma ≤ 0.016, or the ramp drifts.

## Island roles (`Palette`)

| Role | Value | On `islandTop` |
| --- | --- | --- |
| `warmWhite` (primary text, titles) | `s50` | 16.9:1 |
| `textSecondary` (meta, messages) | `s300`, Increased `s200` | 9.8:1 |
| `textTertiary` (counts, separators, clocks) | `s400`, Increased `s300` | 6.8:1 |
| `stateIdle` | `s500`, Increased `s400` | 4.8:1 |
| `hairline` / `islandBorder` | `s50` at 10% / 8%, Increased 24% / 26% | rules only |
| `notchBlack` | `#000000` | must match the hardware notch |
| `islandTop` / `islandRaised` / `islandWell` | `s950` / `s900` / `s1000` | panel / card / code well |

Which text color on the island?

```
Is it the title of a row, card or header?        → warmWhite
Is it a message, agent · branch line, or label?  → textSecondary
Is it a count, clock, separator or queued note?  → textTertiary
Is it a state word ("Approval", "Needs you")?    → the state color (stateWaiting, …)
```

Never apply `.opacity()` to a text role to make it quieter; pick the next
role. Opacity drops contrast below the numbers above, which is how the old
11pt meta line fell to about 4.2:1.

## Window roles (`Palette.Window`)

| Role | Value | Contrast on `canvas` |
| --- | --- | --- |
| `ink` | `s900` | 15.4:1 |
| `textSecondary` | `s700`, Increased `s800` | 6.7:1 |
| `textTertiary` | `s600`, Increased `s700` | 4.9:1 |
| `textPlaceholder` | `s500` | placeholders and disabled labels only |
| `attentionText` / `destructive` | `Signal.*OnLight` | ≥ 4.5:1 |
| `stage` / `stageDeep` | `s50` · 0.96 / `s150` · 0.97 | Welcome wash; `ink` ≥ 7:1 and `textSecondary` ≥ 4.5:1 on both opaque stops (`WindowPaletteTests`) |
| `stageBloom` | `s0` | the one highlight on the wash |
| `guide` | `s900` · 0.55, Increased 0.85 | Welcome ring and connector marks, never text |

Which window text color?

```
Titles, row names, control labels         → ink
Descriptions, subtitles, status lines     → textSecondary
Footnotes, counts, timestamps             → textTertiary
Something asks for the user               → attentionText
Destructive action label                  → destructive (via Button role)
Disabled label, placeholder               → textPlaceholder
```

State marks drawn on a window use `TaskStatus.windowColor` /
`BarState.windowColor`. `.color` is tuned for black: its neutral running
white vanishes on paper.

```swift
// Correct — History row status mark on paper
DotMatrixMark(color: task.status.windowColor, size: 9, pattern: task.status.matrixPattern)

// Incorrect — the island's running white is invisible on a window
DotMatrixMark(color: task.status.color, size: 9, pattern: task.status.matrixPattern)
```

## Increase Contrast

On the island, quiet roles step one ramp step brighter and rules gain
alpha. In windows, quiet ink steps one step darker. Both read the same
system switch (`InterfaceContrastPolicy.systemPrefersIncreasedContrast`).
Only role tokens adapt, which is the practical reason for the layer rule.
