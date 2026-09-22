# Type

Source: `IslandAppLib/Theme/Typography.swift`. SF Pro for reading, SF Mono
only where characters must line up: counts, clocks, commands. Every text
size comes from a role; `.font(.system(size:))` is for SF Symbol glyphs only.

## Window roles

| Role | Size / weight | Use |
| --- | --- | --- |
| `display` + `displayTracking` | 30 semibold, −0.8 | Welcome headline, one per step |
| `title` + `titleTracking` | 22 semibold, −0.4 | Settings pane title, sheet title |
| `headline` | 15 semibold | Standalone group heading |
| `lead` | 14 | The one sentence under a Welcome headline |
| `body` / `bodyStrong` | 13 / 13 semibold | Pane description, paragraphs / row names |
| `callout` / `calloutStrong` | 12 / 12 medium | Status lines, subtitles / group labels |
| `caption` | 11 | Footnotes and hints. The floor |
| `control` / `controlStrong` / `controlLarge` | 12.5 medium / 12.5 semibold / 14 semibold | Set by `WindowButtonStyle`, not by call sites |
| `mono` / `numeric` | 12 mono / 12 medium mono | Commands / figures |

## Island roles

| Role | Size / weight | Use |
| --- | --- | --- |
| `islandHeadline` | 13 semibold | Panel header, the question a request asks |
| `islandTitle` | 13 medium | Session title in a row |
| `islandBody` | 12 | Request message, empty-state sentence |
| `islandMeta` | 11 | Agent · branch · phase line. The floor |
| `islandLabel` | 11 semibold | "Approval", "Question 1 of 2" |
| `islandNumeric` | 11 medium mono | Counts and countdowns |
| `islandCode` | 11.5 mono | Commands and plan code |
| `islandControl` | 12 semibold | Island buttons |
| `barTitle` / `barCount` | 12 medium / 11 medium mono | Compact bar |

```swift
// Correct
Text(snapshot.detail).font(Typo.islandMeta).foregroundStyle(Palette.textSecondary)

// Incorrect — off-scale size below the floor, quieted with opacity
Text(snapshot.detail).font(.system(size: 10.5)).foregroundStyle(Palette.textSecondary.opacity(0.82))
```

## Rules

- Floor: 11pt for anything that carries information. 9–10pt survives only
  on SF Symbol glyphs.
- Changing numbers get `.monospacedDigit()`: timers, counts, percentages.
  Proportional digits shift their neighbors on every tick.
- Hierarchy comes from role, weight and color. Never change weight on hover
  or selection; the text reflows by a pixel. Selection changes color only.
- Tracking: `Font` cannot carry it, so write `.tracking(Typo.titleTracking)`
  or `.tracking(Typo.displayTracking)` next to those two roles, and no other
  tracking. Small labels are sentence case at normal tracking; no uppercase
  mono eyebrows.
- Changing numbers do not animate. `.monospacedDigit()` is enough to keep
  them from shifting.
- Wrapping: headlines and Welcome copy use `.multilineTextAlignment(.center)`
  plus `.fixedSize(horizontal: false, vertical: true)`; single-line labels use
  `.lineLimit(1)` with `.truncationMode(.tail)` and an accessibility label
  carrying the full text.
- Use `…` (one character), never three periods. Verbatim commands use
  `Text(verbatim:)` and are never localized.
