# Motion

Source: `IslandAppLib/Theme/Animations.swift`. Anything that animates names a
`Motion` token; inline curves are a bug.

| Token | Value | Use |
| --- | --- | --- |
| `islandMorph` | smooth 0.30s, no bounce | Bar → panel expand |
| `islandCollapse` | smooth 0.22s, no bounce | Panel → bar collapse (exit runs ~25% faster) |
| `layout` | smooth 0.24s | Task-list and row height changes |
| `tourStep` | smooth 0.24s | Welcome step change (card, plate, stem); the plate, stem and card share one curve, and ride `islandMorph` when the island itself moved |
| `tourExit` | easeIn 0.12s | Outgoing Welcome card lines; they fade in place, no offset |
| `tourRetract` | smooth 0.18s | The Welcome plate leaving into the menu-bar band when a step has no target |
| `guideDraw` | easeOut 0.22s | The Welcome stem being drawn from the plate toward the card |
| `stagedReveal` + `stagedRevealStep` | easeOut 0.22s, +0.06s per line | Welcome card lines following the card in |
| `guideLoopDelay` | `tourStepDuration` + 0.04s | Welcome loops start only after the plate and card settle (the Welcome twin of `IslandPanelActivityTiming.liveEffectsDelay`) |
| `guideTravelDwell` | 0.25 of the period | The Welcome pulse rests hidden for the last quarter of each pass; it runs on `runningOrbitPeriod`, sharing the island's wall-clock phase through `StatusPhase.cyclePhase` (TimelineView; rests at the card under Reduce Motion) |
| `contentReveal` | easeOut 0.18s | Content fading in after its surface settles |
| `questionPageReveal` | easeOut 0.14s | The next question page |
| `colorTransition` | easeInOut 0.18s | State color cross-fade; the Welcome eyebrow and ledger marks |
| `hoverHighlight` | easeOut 0.10s | Row and button hover wash |
| `hover` | smooth 0.16s | The collapsed island widening under the pointer, and nothing else |
| `press` | easeOut 0.12s | Press scale to 0.96 |
| `runningOrbitPeriod` / `waitingBreathPeriod` | 1.8s / 1.4s | Status matrix loops (Core Animation) |

Use `Motion.islandMorph(expanding:)` and `Motion.islandMorphDuration(expanding:)`
wherever the direction of the morph is known.

## Reduce Motion

Read `@Environment(\.accessibilityReduceMotion)` in views and
`Motion.systemPrefersReducedMotion` in AppKit code.

- Geometry (size, offset, scale) does not move: check
  `Motion.allowsSpatialFeedback(reduceMotion)` and snap.
- Opacity and color keep a short fade:
  `Motion.respectingReducedMotion(reduceMotion, preferred:)` falls back to
  easeOut 0.14s, following Apple's guidance to replace motion with dissolves.
- Status matrices stop looping and rest on their full pattern, never on one
  dim frame of the loop.

```swift
// Correct
withAnimation(Motion.respectingReducedMotion(reduceMotion, preferred: Motion.contentReveal)) {
    liveSignal = latched
}

// Incorrect — inline curve, and it still moves under Reduce Motion
withAnimation(.easeInOut(duration: 0.4)) { liveSignal = latched }
```

## Rules

- Nothing animates on a keyboard shortcut result or on arrow-key navigation.
- Hover never animates geometry, with one exception: the collapsed island
  widens slightly under the pointer (`Motion.hover`) to show it is clickable.
  Buttons, rows and cards never grow on hover.
- Continuous loops run only while visible: pass `isLive` and stop at
  `paused: !isLive` or `isAnimated: false`. The panel starts loops only after
  the morph settles (`IslandPanelActivityTiming.liveEffectsDelay`). The
  Welcome pulse is the stage's only loop; it shares `runningOrbitPeriod` with
  the island's orbiting dots and never resets its phase on a step change,
  only pauses for `guideLoopDelay`.
- Attach `.animation(_:value:)` to the narrowest value that changes. An
  animation keyed to a whole model animates everything that model touches.
- Durations stay at or under 0.30s; exits are shorter than entrances.
