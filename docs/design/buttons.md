# Buttons

Source: `IslandAppLib/Theme/WindowSurfaces.swift` (`WindowButtonStyle`),
`Interaction.swift` (island styles), `ActionRequestSurface.swift`
(`ActionDecisionButtonStyle`, private to the request card).

## Window buttons: `.buttonStyle(.window(role, size:))`

Use for every button in Settings, History, Welcome and their sheets.
Navigation rows are not window buttons: Settings sidebar items use
`SettingsSidebarButtonStyle`, and History rows are whole-row
`.buttonStyle(.plain)` buttons with a hover wash.

Roles: `.primary`, `.secondary`, `.quiet`. Sizes: `.regular` (28pt tall),
`.large` (40pt, Welcome only). Nothing else exists; an unlisted role or a
`destructive:` flag is a bug.

- `.primary` — the single next step of the view: the ink capsule. One per
  view. It is also the one that takes `.keyboardShortcut(.defaultAction)`.
- `.secondary` — every other action with a visible edge. This is the
  default: when in doubt, it is `.secondary`.
- `.quiet` — text only, for the least important end of a row (Disconnect,
  View commands, Back, Skip to setup).

Destructive intent comes from the platform: `Button(role: .destructive)`.
The style then switches the label to `Palette.Window.destructive`. Never a
red fill.

```
Is it the one thing the user should do next here?   → .primary (+ .defaultAction)
Is it removal, reset or disconnect?                  → Button(role: .destructive) + .quiet or .secondary
Is it at the far, least important end of a row?      → .quiet
Default                                              → .secondary
```

```swift
// Correct
Button(role: .destructive) {
    apply(.disable)
} label: {
    Text(L10n.string("Disconnect", language: language))
}
.buttonStyle(.window(.quiet))

// Incorrect — a second primary in the pane, and destructive as a style flag
Button(L10n.string("Disconnect", language: language)) { apply(.disable) }
    .buttonStyle(.window(.primary, destructive: true))
```

States are built in: hover (ink `inkHover`, secondary edge `hairlineStrong`),
press (scale 0.96 over `Motion.press`, disabled under Reduce Motion),
disabled (`textPlaceholder` label). Don't restyle states at call sites.

Disabled is always a color role, never `.opacity()`: `textPlaceholder` in
windows, `textTertiary` on the island. Opacity-dimmed labels pass contrast on
one ground and fail on the next.

## Island buttons

| Style | Use |
| --- | --- |
| `ActionDecisionButtonStyle(role: .primary)` | Allow once, Approve plan, Submit / Next — inside the request card only |
| `ActionDecisionButtonStyle(role: .secondary)` | Deny, Reject, Back, Continue in Claude |
| `IslandQuietActionButtonStyle()` | One outlined capsule in an island empty state or command well (Connect an agent, Copy) |
| `IslandIconButtonStyle()` | Header glyph buttons (History, Settings): 28pt circular hit area |
| `PressableButtonStyle()` | Whole-row buttons (task rows) |

The request that owns keyboard shortcuts prints them on its decision buttons
(`⌘↩`, `⌘D`) via `ActionDecisionLabel`; other requests show none, because
their shortcuts would not fire. "Continue in Claude" keeps ⌘O in its tooltip
only: the plan footer has 4pt to spare at 420pt, and the two decisions are
the ones used many times a day.

## Rules

- Hit areas are at least 28pt on the pointer (the macOS toolbar control
  size). A 12pt glyph gets a 28pt frame and `.contentShape`.
- Every icon-only button has `.accessibilityLabel` and `.help` with the same
  words.
- Buttons never grow on hover. Hover changes color or wash; press scales
  down to 0.96.
