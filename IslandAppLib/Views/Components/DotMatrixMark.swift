import SwiftUI
import IslandCore

/// Dev Island's smallest visual signature: a circular signal expressed as a
/// 3×3 field of points instead of a generic filled dot.
///
/// Corner points are quieter than the centre and cardinal points, so the
/// matrix reads as a soft circle at a glance while keeping its pixel-grid
/// character up close. Active states animate *inside* the mark; the overall
/// footprint remains still, which avoids the default "pulsing status dot"
/// look and keeps nearby type perfectly stable.
struct DotMatrixMark: View {
    enum Pattern: Equatable {
        /// A complete circular-density field for neutral and active work.
        case field
        /// Hollow perimeter used by the running state's rotating signal.
        case orbit
        /// Bright perimeter with a quieter centre for attention.
        case ring
        /// Resolved, centred plus for successful completion.
        case plus
        /// Broken diagonal cross for failure.
        case cross
    }

    enum MotionStyle: Equatable {
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

    private var density: [Double] {
        switch pattern {
        case .field:
            return [
                0.58, 0.86, 0.58,
                0.86, 1.00, 0.86,
                0.58, 0.86, 0.58,
            ]
        case .orbit:
            return [
                0.78, 1.00, 0.78,
                1.00, 0.12, 1.00,
                0.78, 1.00, 0.78,
            ]
        case .ring:
            return [
                0.72, 1.00, 0.72,
                1.00, 0.34, 1.00,
                0.72, 1.00, 0.72,
            ]
        case .plus:
            return [
                0.08, 0.82, 0.08,
                0.82, 1.00, 0.82,
                0.08, 0.82, 0.08,
            ]
        case .cross:
            return [
                0.92, 0.08, 0.92,
                0.08, 1.00, 0.08,
                0.92, 0.08, 0.92,
            ]
        }
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, canvasSize in
            let diameter = max(0.9, min(2.6, size * 0.20))
            let pitch = (min(canvasSize.width, canvasSize.height) - diameter) / 2

            for row in 0..<3 {
                for column in 0..<3 {
                    let index = row * 3 + column
                    let signal = modulation(row: row, column: column)
                    let response = visualResponse(signal: signal)
                    let pointDiameter = diameter * response.scale
                    let center = CGPoint(
                        x: diameter / 2 + CGFloat(column) * pitch,
                        y: diameter / 2 + CGFloat(row) * pitch
                    )
                    let rect = CGRect(
                        x: center.x - pointDiameter / 2,
                        y: center.y - pointDiameter / 2,
                        width: pointDiameter,
                        height: pointDiameter
                    )
                    let opacity = min(
                        1,
                        density[index] * response.opacity * intensity
                    )

                    context.fill(
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
    private func modulation(row: Int, column: Int) -> Double {
        guard motion != .still else { return 1 }

        let normalizedPhase = Double(phase) * 2 * Double.pi
        switch motion {
        case .still:
            return 1
        case .orbiting:
            // One bright head with a soft trailing point moves clockwise
            // around the perimeter. The centre remains a quiet anchor.
            let dx = Double(column - 1)
            let dy = Double(row - 1)
            guard dx != 0 || dy != 0 else { return 0.36 }

            let pointAngle = atan2(dy, dx)
            let headAngle = normalizedPhase - Double.pi / 2
            let headDistance = angularDistance(pointAngle, headAngle)
            let trailDistance = angularDistance(pointAngle, headAngle - Double.pi / 4)
            let head = pow((cos(headDistance) + 1) / 2, 7)
            let trail = pow((cos(trailDistance) + 1) / 2, 7)
            return min(1, 0.08 + head * 0.92 + trail * 0.35)
        case .attention:
            // A centre-out ripple makes the waiting state feel deliberate.
            let dx = Double(column - 1)
            let dy = Double(row - 1)
            let offset = -sqrt(dx * dx + dy * dy) * 1.05
            return (sin(normalizedPhase - offset) + 1) / 2
        }
    }

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        abs(atan2(sin(first - second), cos(first - second)))
    }

    private func visualResponse(signal: Double) -> (opacity: Double, scale: CGFloat) {
        switch motion {
        case .still:
            return (1, 1)
        case .orbiting:
            // High contrast between the moving head and resting perimeter is
            // what makes rotation legible at 14pt without adding a glow.
            return (
                0.30 + signal * 0.70,
                CGFloat(0.78 + signal * 0.26)
            )
        case .attention:
            return (
                0.58 + signal * 0.42,
                CGFloat(0.84 + signal * 0.16)
            )
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
        case .idle:      return 0.52
        case .running:   return 0.96
        case .waiting:   return 1.00
        case .completed: return 0.84
        case .failed:    return 0.98
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
        case .running:   return 0.96
        case .waiting:   return 1.00
        case .completed: return 0.84
        case .failed:    return 0.98
        }
    }
}

#if PREVIEWS
#Preview("Dot matrix marks") {
    HStack(spacing: 22) {
        DotMatrixMark(color: Palette.stateIdle, size: 14, intensity: 0.52)
        DotMatrixMark(color: Palette.stateRunning, size: 14, phase: 0.2, motion: .orbiting, pattern: .orbit, intensity: 0.96)
        DotMatrixMark(color: Palette.stateWaiting, size: 14, phase: 0.6, motion: .attention, pattern: .ring)
        DotMatrixMark(color: Palette.stateCompleted, size: 14, pattern: .plus, intensity: 0.84)
        DotMatrixMark(color: Palette.stateFailed, size: 14, pattern: .cross, intensity: 0.98)
    }
    .padding(28)
    .background(Palette.notchBlack)
}
#endif
