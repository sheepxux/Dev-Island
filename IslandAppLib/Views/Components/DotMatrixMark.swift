import SwiftUI
import IslandCore

/// Dev Island's smallest visual signature: a fixed 3×3 grid that replaces a
/// generic filled status dot.
///
/// Every state keeps all nine points at the same size and coordinates. Meaning
/// comes only from which points are bright, which remain quietly visible, and
/// how brightness travels through the grid. The footprint never changes, so
/// status transitions stay calm and nearby type remains perfectly stable.
struct DotMatrixMark: View {
    enum Pattern: Hashable, Sendable {
        /// Nine quiet points with a slightly brighter centre.
        case field
        /// Nine visible points prepared for a clockwise perimeter signal.
        case orbit
        /// Nine visible points with a centre-led emphasis.
        case ring
        /// Bright centre/cardinals with four quieter, still-visible corners.
        case plus
        /// Bright diagonals with four quieter, still-visible edge points.
        case cross
    }

    enum MotionStyle: Hashable, Sendable {
        case still
        case orbiting
        case attention
    }

    let color: Color
    var size: CGFloat
    var phase: CGFloat = 0.5
    var motion: MotionStyle = .still
    var pattern: Pattern = .field
    var intensity: Double = 1

    static func opacity(
        pattern: Pattern,
        motion: MotionStyle,
        intensity: Double,
        row: Int,
        column: Int,
        phase: CGFloat
    ) -> Double {
        let density: [Double]
        switch pattern {
        case .field:
            density = [
                0.42, 0.50, 0.42,
                0.50, 0.74, 0.50,
                0.42, 0.50, 0.42,
            ]
        case .orbit:
            density = [
                1.00, 1.00, 1.00,
                1.00, 1.00, 1.00,
                1.00, 1.00, 1.00,
            ]
        case .ring:
            density = [
                0.56, 0.78, 0.56,
                0.78, 1.00, 0.78,
                0.56, 0.78, 0.56,
            ]
        case .plus:
            density = [
                0.34, 0.94, 0.34,
                0.94, 1.00, 0.94,
                0.34, 0.94, 0.34,
            ]
        case .cross:
            density = [
                0.96, 0.34, 0.96,
                0.34, 1.00, 0.34,
                0.96, 0.34, 0.96,
            ]
        }

        let index = row * 3 + column
        let signal = modulation(
            motion: motion,
            row: row,
            column: column,
            phase: phase
        )
        let response = opacityResponse(motion: motion, signal: signal)
        return min(1, density[index] * response * intensity)
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, canvasSize in
            let diameter = max(0.9, min(2.6, size * 0.20))
            let pitch = (min(canvasSize.width, canvasSize.height) - diameter) / 2

            for row in 0..<3 {
                for column in 0..<3 {
                    let center = CGPoint(
                        x: diameter / 2 + CGFloat(column) * pitch,
                        y: diameter / 2 + CGFloat(row) * pitch
                    )
                    let rect = CGRect(
                        x: center.x - diameter / 2,
                        y: center.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    let opacity = Self.opacity(
                        pattern: pattern,
                        motion: motion,
                        intensity: intensity,
                        row: row,
                        column: column,
                        phase: phase
                    )

                    var pointContext = context
                    if pattern != .field {
                        // A point-sized bloom, not an island-sized glow. The
                        // layer's own opacity scales the shadow, so the lit
                        // head reads as emissive while resting points remain
                        // visibly dimmer in the same fixed nine-dot grid.
                        let bloomOpacity = max(0, opacity - 0.24) * 0.52
                        pointContext.addFilter(
                            .shadow(
                                color: color.opacity(bloomOpacity),
                                radius: max(0.65, diameter * 0.52),
                                x: 0,
                                y: 0
                            )
                        )
                    }

                    pointContext.fill(
                        Path(ellipseIn: rect),
                        with: .color(color.opacity(opacity))
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// A restrained per-point light pattern. `phase` is a normalized 0…1
    /// cycle supplied by the shared status timeline.
    private static func modulation(
        motion: MotionStyle,
        row: Int,
        column: Int,
        phase: CGFloat
    ) -> Double {
        guard motion != .still else { return 1 }

        let normalizedPhase = Double(phase) * 2 * Double.pi
        switch motion {
        case .still:
            return 1
        case .orbiting:
            // One bright head with a soft trailing point moves clockwise
            // around the perimeter. Every resting point remains visible and
            // the centre stays as a quiet anchor in the same nine-dot grid.
            let dx = Double(column - 1)
            let dy = Double(row - 1)
            guard dx != 0 || dy != 0 else { return 0 }

            let pointAngle = atan2(dy, dx)
            let headAngle = normalizedPhase - Double.pi / 2
            let headDistance = angularDistance(pointAngle, headAngle)
            let trailDistance = angularDistance(pointAngle, headAngle - Double.pi / 4)
            let head = pow((cos(headDistance) + 1) / 2, 7)
            let trail = pow((cos(trailDistance) + 1) / 2, 7)
            return min(1, 0.06 + head * 0.94 + trail * 0.34)
        case .attention:
            // A centre-out ripple makes the waiting state feel deliberate.
            let dx = Double(column - 1)
            let dy = Double(row - 1)
            let offset = -sqrt(dx * dx + dy * dy) * 1.05
            return (sin(normalizedPhase - offset) + 1) / 2
        }
    }

    private static func angularDistance(_ first: Double, _ second: Double) -> Double {
        abs(atan2(sin(first - second), cos(first - second)))
    }

    /// Converts the animated signal to brightness only. Point diameter is
    /// deliberately absent: all nine dots stay geometrically identical.
    private static func opacityResponse(motion: MotionStyle, signal: Double) -> Double {
        switch motion {
        case .still:
            return 1
        case .orbiting:
            // High contrast between the moving head and resting perimeter is
            // what makes rotation legible at 14pt without hiding any point.
            return 0.34 + signal * 0.66
        case .attention:
            return 0.48 + signal * 0.52
        }
    }
}

// MARK: - Semantic signatures

extension BarState {
    var matrixPattern: DotMatrixMark.Pattern {
        switch self {
        case .idle:           return .field
        case .running:        return .orbit
        case .waiting:       return .ring
        case .completed:     return .plus
        case .failed:        return .cross
        }
    }

    var matrixMotion: DotMatrixMark.MotionStyle {
        switch self {
        case .running: return .orbiting
        case .waiting: return .attention
        case .idle, .completed, .failed: return .still
        }
    }

    var matrixIntensity: Double {
        switch self {
        case .idle:      return 0.88
        case .running:   return 0.97
        case .waiting:   return 1.00
        case .completed: return 0.94
        case .failed:    return 0.99
        }
    }
}

extension TaskStatus {
    var matrixPattern: DotMatrixMark.Pattern {
        switch self {
        case .running:   return .orbit
        case .waiting:   return .ring
        case .completed: return .plus
        case .failed:    return .cross
        }
    }

    var matrixIntensity: Double {
        switch self {
        case .running:   return 0.97
        case .waiting:   return 1.00
        case .completed: return 0.94
        case .failed:    return 0.99
        }
    }

    var matrixMotion: DotMatrixMark.MotionStyle {
        switch self {
        case .running: return .orbiting
        case .waiting: return .attention
        case .completed, .failed: return .still
        }
    }

    func matrixPhase(at time: Date, animated: Bool = true) -> CGFloat {
        guard animated else { return 0.5 }

        let elapsed = time.timeIntervalSinceReferenceDate
        switch self {
        case .running:
            return StatusPhase.cyclePhase(elapsed, period: Motion.runningOrbitPeriod)
        case .waiting:
            return StatusPhase.cyclePhase(elapsed, period: Motion.waitingBreathPeriod)
        case .completed, .failed:
            return 0.5
        }
    }
}

#if PREVIEWS
#Preview("Dot matrix marks") {
    HStack(spacing: 22) {
        DotMatrixMark(color: Palette.stateIdle, size: 14, intensity: 0.88)
        DotMatrixMark(color: Palette.stateRunning, size: 14, phase: 0.2, motion: .orbiting, pattern: .orbit, intensity: 0.97)
        DotMatrixMark(color: Palette.stateWaiting, size: 14, phase: 0.6, motion: .attention, pattern: .ring)
        DotMatrixMark(color: Palette.stateCompleted, size: 14, pattern: .plus, intensity: 0.94)
        DotMatrixMark(color: Palette.stateFailed, size: 14, pattern: .cross, intensity: 0.99)
    }
    .padding(28)
    .background(Palette.notchBlack)
}
#endif
