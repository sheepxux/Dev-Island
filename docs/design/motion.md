# Motion

Source: `IslandAppLib/Theme/Animations.swift`. Anything that animates names a
`Motion` token; inline curves are a bug.

| Token | Value | Use |
| --- | --- | --- |
| `islandMorph` | smooth 0.30s, no bounce | Bar → panel expand |
| `islandCollapse` | smooth 0.22s, no bounce | Panel → bar collapse (exit runs ~25% faster) |
| `layout` | smooth 0.24s | Task-list and row height changes |
| `tourStep` | smooth 0.24s | Welcome step change |
| `contentReveal` | easeOut 0.18s | Content fading in after its surface settles |
| `questionPageReveal` | easeOut 0.14s | The next question page |
| `colorTransition` | easeInOut 0.18s | State color cross-fade |
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
  the morph settles (`IslandPanelActivityTiming.liveEffectsDelay`).
- Attach `.animation(_:value:)` to the narrowest value that changes. An
  animation keyed to a whole model animates everything that model touches.
- Durations stay at or under 0.30s; exits are shorter than entrances.
