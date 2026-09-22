# Island

Source: `IslandAppLib/Views/NotchBar/`, `Views/NotchPanel/`,
`Views/Components/DotMatrixMark.swift`, `AnimatedDotMatrixMark.swift`.

## The status matrix

A fixed 3×3 grid; the footprint never changes. State is carried by pattern
and color together, so it survives color blindness and Reduce Motion:

| State | Pattern | Motion | Color |
| --- | --- | --- | --- |
| Idle | `.field`, all quiet | still | `stateIdle` |
| Running | `.orbit` | a bright point orbits (1.8s) | neutral `stateRunning` |
| Waiting | `.ring`, centre-led | ripple (1.4s), trough stays lit | `stateWaiting`, most vivid |
| Completed | `.plus` | still | `stateCompleted` |
| Failed | `.cross` | still | `stateFailed` |

Use `StatusDot(state:)` for bar states and `AnimatedDotMatrixMark` for
looping marks inside the panel (`isAnimated: isLive && !reduceMotion`). A
static mark is `DotMatrixMark(color:size:phase:motion:pattern:intensity:)`
(labels in that order; all but `color` and `size` have defaults); a static
waiting mark passes `motion: .still`, because a frozen ripple frame is too
dim. Never a plain `Circle()` status dot. On a window, pass
`status.windowColor`.

## Compact bar (Mac without a notch)

`[StatusDot] [title] [n sessions]`. The title is `warmWhite` only when the
foreground state is waiting or failed, otherwise `textSecondary`: it gets
brighter only when the user is needed. The count is `textTertiary` and
counts all sessions. No divider between title and count.

## Panel

- Header: `[state matrix] [state word] [count] · [n sessions]`. The state
  word names what the count counts: Needs you / Failed / Completed /
  Running; No sessions when idle, with no count. Beside a hardware notch the
  wing is 88–120pt, so `ViewThatFits` drops the total, then the word; it
  never truncates. VoiceOver always hears the full summary.
- The connection mark appears only while a transport is reconnecting or
  broken. A healthy connection shows nothing.
- Rows: status matrix 12pt, vendor mark 20pt, then title (`islandTitle`,
  `warmWhite`) over `agent · branch · phase · time` (`islandMeta`,
  `textSecondary`). State leads the row; the logo identifies. Leading
  marks, the header mark and receipts share one column
  (`TaskCardMetrics.horizontalPadding`). The row the island opened for has a
  `hairline` ring as well as a tint; a tint alone is indistinguishable from
  hover.
- Empty state: the header already names the state; the body is one
  sentence plus "Connect an agent", aligned under the header text.

## Request card

The one thing in the panel that asks for something, raised as a card
(`islandRaised`, `hairline` ring, radius 12):

1. One header line: `[waiting mark] Approval · Codex · <task title>  1:30`.
   When the title does not fit, it moves to a second line under the label
   rather than shrinking. The kind label is the only amber text on the card.
   A hash-style session reference replaces the task title only when the
   request's row is not in the panel. "+N queued" sits on its own line above
   the actions.
2. The question (`islandHeadline`, `warmWhite`), then the message
   (`islandBody`, `textSecondary`).
3. The command in an `islandWell`, at full strength: it is what is being
   approved.
4. Actions on the right: secondary, then primary. The request that owns
   shortcuts shows `⌘D` / `⌘↩` on its buttons.

```swift
// Correct — kind label once, context from the task
Text(headerLabel).font(Typo.islandLabel).foregroundStyle(Palette.stateWaiting)

// Incorrect — uppercase mono eyebrow below the floor
Text("APPROVAL").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(0.8)
```

## Welcome specimen

The Welcome island is the real island at specimen scale: compact capsule
44pt tall, request state at the panel's 22pt radius, built from the same
tokens and marks. The label above it always says whether it shows an
example (steps 1 and 3) or live state (steps 2 and 4).
