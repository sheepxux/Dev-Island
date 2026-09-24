# Dev Island design system

Two layers, taken from the app icon. The island is the black terminal tile:
dark, dense, always on screen. Windows (Settings, History, Welcome) are the
warm off-white base the tile sits on. Both read from one neutral ramp at hue
86°, so color is left for state alone, ranked by urgency. The 3×3 dot matrix
is the signature and the only status indicator.

## The layer rule

Views use role tokens only:

| Need | Island | Windows |
| --- | --- | --- |
| Color | `Palette.*` | `Palette.Window.*` |
| Type | `Typo.island*`, `Typo.bar*` | `Typo.*` (non-island roles) |
| Radius | `NotchMetrics.panelCornerRadius`, `.panelRowRadius` | `Palette.Window.Radius.*` |
| Motion | `Motion.*` | `Motion.*` |

Never in a view: `Sand.*` or `Signal.*` steps, `Color(hex:)`, `.white`/`.black`
literals, or `.font(.system(size:))` for text. Primitives appear only in the
token files that define roles: `OKLCH.swift`, `Colors.swift`,
`WindowPalette.swift`, `Typography.swift`, `Animations.swift`,
`NotchMetrics.swift`. A missing role is added there first, with a comment
saying where it is used; a raw value in a view is a bug. SF Symbol and
monogram glyph sizes are not text and may use `.system(size:)`.

Why: every role encodes a contrast and hierarchy decision (see
[color](docs/design/color.md)). A raw step skips that decision and breaks
Increase Contrast, which only adapts role tokens.

## Rules that apply everywhere

- One primary action per view. Two black capsules means the view has no
  hierarchy.
- Nothing that carries information is set below 11pt.
- State is never color alone: every state also has its own dot pattern.
- Every visible string goes through `L10n` (`IslandAppLib/Localization/
  DevIslandLocalization.swift`) and exists in `en` and `zh-Hans`.
- Casing is presentation: keys are sentence case; no ALL-CAPS keys.
- Glass is not used. System Liquid Glass was tried on the Settings sidebar
  (2026-09-22) and rendered as a cool gray slab over the cream canvas.
- Healthy states are quiet: a mark or line appears when something needs the
  user, not to confirm that nothing does.

## Topics

| File | Covers |
| --- | --- |
| [color](docs/design/color.md) | Sand ramp, Signal, role tokens, contrast numbers |
| [type](docs/design/type.md) | Role scale, floors, mono, tracking |
| [surfaces](docs/design/surfaces.md) | Window surfaces, radii, depth, dividers |
| [buttons](docs/design/buttons.md) | `WindowButtonStyle` and the island button styles |
| [motion](docs/design/motion.md) | Motion tokens, durations, Reduce Motion |
| [island](docs/design/island.md) | Status matrix, rows, request card, compact bar |
| [copy](docs/design/copy.md) | Voice, casing, Chinese conventions |

## Where decisions are recorded

- Welcome is a full-screen tutorial over the real desktop (owner decision,
  2026-09-23; stage redesigned 2026-09-24). The tour window stops at the
  menu bar's lower edge and never paints inside the band, so the menu bar
  is native on every wallpaper. The stage is a see-through wash
  (`stage` → `stageDeep`, Sand s50 · 0.70 → s100 · 0.78) the desktop ghosts
  through; whatever the tour points at sits on one charcoal plate
  (`stagePlate`, s800) that hangs from the band and morphs with the island;
  a 2pt stem in the plate's colour drops to a paper caption card and one
  light pulse (`stageSignal`) travels it on the island's own 1.8s clock.
  The example sessions, approval and question are shown on the real island
  (`IslandCoordinator.tutorialDemo`) and answered there; one caption card
  (eyebrow, title, lead, one primary, a seven-mark ledger) carries all seven
  steps with staged text. No bloom, no ring, no blur. Contract:
  `docs/INTERFACE_CONTRACT.md`, section "Welcome 全屏分步教程".
- The setup steps keep the owner-approved "float" column (2026-09-20): one
  central 520pt column, one title, one sentence, one primary action. The
  island specimen retired on 2026-09-23. Contract: section
  "Welcome 悬浮单轴几何".
- Rejected for Welcome, do not reintroduce: split editorial columns, giant
  step numbers, poster slogans, a floating window, a lookalike island.
- Token values are pinned by tests: `OKLCHPaletteTests`,
  `WindowPaletteTests`, `InterfaceContrastPolicyTests`.
