# Surfaces

Source: `IslandAppLib/Theme/WindowSurfaces.swift`, `WindowPalette.swift`
(`Radius`), `NotchMetrics.swift`.

## Windows

A window is one flat sheet, `WindowCanvas()`. Nothing is painted behind
content. Grouped content lifts off it with `.windowSurface(radius:tone:)`.
Tones: `sidebar`, `raised`, `inset`, `attention`. Nothing else exists.

- `raised` — grouped rows and cards (Settings groups, History list, Welcome
  chips). This is the default. White paper, a 0.75pt ring, and a two-layer
  shadow.
- `sidebar` — the Settings navigation pane. One flat step deeper, no edge.
- `inset` — a well nested inside raised paper (the expanded Agent row).
- `attention` — the one group that asks for something (Needs action,
  a reporting notice). Amber wash plus an amber ring. At most one per view.

```
Is it navigation beside the content?           → sidebar
Does it ask the user to act?                   → attention (one per view)
Is it nested inside another raised surface?    → inset
Default                                        → raised
```

```swift
// Correct
agentRows(entry.descriptors)
    .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)

// Incorrect — hand-built card: solid stroke plus fill, no shared depth
agentRows(entry.descriptors)
    .background(RoundedRectangle(cornerRadius: 8).fill(.white).overlay { … .stroke(…) })
```

One depth cue per surface. Raised paper already has its ring and shadow;
never add a border, a second shadow or a gradient on top.

## Settings panes

`SettingsView` hosts every pane: it owns the canvas, the sidebar, the
`ScrollView`, and the pane header (title from `SettingsPane.title`,
description from `SettingsPane.detail`). A pane returns only its groups; it
never adds a canvas, a scroll view or outer padding.

| Space | Value |
| --- | --- |
| Pane insets (set by the host) | 26 leading, 32 trailing, 44 top, 28 bottom |
| Pane header to first group | 22 |
| Between groups | 18 |
| Group label to its group | 7 |
| Single-control row padding (`SettingsToggleRow`) | 16 |
| Agent row padding | 14 horizontal, 10 vertical |
| Divider inset | to the row's text column: 16, or 54 after a 24pt tile |

A switch row is `SettingsToggleRow(title:subtitle:isOn:)`: the system
`.switch` tinted `Palette.Window.ink`, label hidden, the row supplying title
(`bodyStrong`) and subtitle (`caption`, `textSecondary`). A notice that asks
for something is an `.attention` group with a `.window(.secondary)` action;
it never takes the pane's primary.

## Radii

Chosen per layer, derived where layers nest (inner = outer − padding):

| Layer | Radius |
| --- | --- |
| Settings sidebar pane | `Radius.pane` 18 |
| Group, chip, choice tile | `Radius.group` 14 |
| Well inside a group | `Radius.inset` 10 |
| Icon tile | `Radius.tile` 8 |
| Window buttons, fields | Capsule |
| Island panel | `NotchMetrics.panelCornerRadius` 22 |
| Island row, request card | `NotchMetrics.panelRowRadius` 12 (22 − 10 inset) |
| Command well in a card | `NotchMetrics.panelWellRadius` 8 |

Stroked capsules use `Capsule()` (circular). `.continuous` capsules carry a
short straight segment at each end that a thin stroke draws as a crisp tick.

## Island

Shadows vanish on black, so the island separates by tone and ring:
`islandTop` panel → `islandRaised` card with a `hairline` ring →
`islandWell` for commands. Rows are transparent until hovered
(`warmWhite` at 4.5%). The row the island opened for adds a 6% tint and a
`hairline` ring. No left rails.

## Rules

- Row separators are `WindowDivider()`: one physical pixel (0.5pt on
  Retina), `Palette.Window.divider`. Spacing separates groups; don't add
  a divider between things that already have space between them.
- The Welcome canvas paints one thing: a soft glow centered on the island
  specimen (`Palette.Window.glow`), plus the specimen's own two-layer
  contact shadow (`Palette.Window.shadow`). No other gradients, blobs or
  arcs.
- Offscreen snapshots (`cacheDisplay`) draw thin ticks at the ends of
  stroked capsules. Live windows do not; judge edges in a real window.
