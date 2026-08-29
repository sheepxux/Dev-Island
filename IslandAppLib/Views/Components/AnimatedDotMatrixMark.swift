import AppKit
import QuartzCore
import SwiftUI

/// Compositor-driven version of `DotMatrixMark` for continuously moving
/// running and waiting states.
///
/// SwiftUI's `TimelineView` is excellent for content whose layout changes on
/// every frame, but these nine points never move or resize. Core Animation can
/// therefore own only their opacity keyframes, keeping the continuous visual
/// language without invalidating the surrounding row or task list.
struct AnimatedDotMatrixMark: View {
    let color: Color
    var size: CGFloat
    var motion: DotMatrixMark.MotionStyle
    var pattern: DotMatrixMark.Pattern
    var intensity: Double = 1
    var isAnimated: Bool = true

    var body: some View {
        DotMatrixLayerRepresentable(
            configuration: .init(
                color: DotMatrixColor(color),
                size: size,
                motion: motion,
                pattern: pattern,
                intensity: intensity,
                isAnimated: isAnimated
            )
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct DotMatrixLayerRepresentable: NSViewRepresentable {
    let configuration: DotMatrixLayerView.Configuration

    func makeNSView(context: Context) -> DotMatrixLayerView {
        let view = DotMatrixLayerView()
        view.apply(configuration)
        return view
    }

    func updateNSView(_ nsView: DotMatrixLayerView, context: Context) {
        nsView.apply(configuration)
    }

    static func dismantleNSView(_ nsView: DotMatrixLayerView, coordinator: ()) {
        nsView.stopAnimations()
    }
}

struct DotMatrixColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [red, green, blue, alpha]
        ) ?? NSColor.white.cgColor
    }
}

final class DotMatrixLayerView: NSView {
    struct Configuration: Equatable {
        let color: DotMatrixColor
        let size: CGFloat
        let motion: DotMatrixMark.MotionStyle
        let pattern: DotMatrixMark.Pattern
        let intensity: Double
        let isAnimated: Bool
    }

    private static let animationKey = "dev-island.dot-matrix.opacity"
    private static let colorAnimationKey = "dev-island.dot-matrix.color"
    private static let shadowColorAnimationKey = "dev-island.dot-matrix.shadow-color"
    private let dots: [CALayer] = (0..<9).map { _ in CALayer() }
    private var configuration: Configuration?
    private var lastGeometry: GeometrySignature?

    #if DEBUG
    private(set) var geometryUpdateCount = 0
    #endif

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        dots.forEach { layer?.addSublayer($0) }
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    func apply(_ newConfiguration: Configuration) {
        guard configuration != newConfiguration else { return }
        let previous = configuration
        let presentedColors = dots.map {
            ($0.presentation() ?? $0).backgroundColor
        }
        configuration = newConfiguration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dots.forEach {
            $0.backgroundColor = newConfiguration.color.cgColor
            $0.shadowColor = newConfiguration.color.cgColor
            $0.shadowOffset = .zero
            $0.shadowOpacity = newConfiguration.pattern == .field ? 0 : 0.48
            $0.masksToBounds = false
        }
        updateGeometry()
        CATransaction.commit()

        if let previous, previous.color != newConfiguration.color {
            for (dot, presentedColor) in zip(dots, presentedColors) {
                let animation = CABasicAnimation(keyPath: "backgroundColor")
                animation.fromValue = presentedColor ?? previous.color.cgColor
                animation.toValue = newConfiguration.color.cgColor
                animation.duration = Motion.colorTransitionDuration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dot.add(animation, forKey: Self.colorAnimationKey)

                let shadowAnimation = CABasicAnimation(keyPath: "shadowColor")
                shadowAnimation.fromValue = presentedColor ?? previous.color.cgColor
                shadowAnimation.toValue = newConfiguration.color.cgColor
                shadowAnimation.duration = Motion.colorTransitionDuration
                shadowAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dot.add(shadowAnimation, forKey: Self.shadowColorAnimationKey)
            }
        }

        let animationChanged = previous?.motion != newConfiguration.motion
            || previous?.pattern != newConfiguration.pattern
            || previous?.intensity != newConfiguration.intensity
            || previous?.isAnimated != newConfiguration.isAnimated

        if previous == nil || animationChanged {
            installOpacityAnimations()
        }
    }

    func stopAnimations() {
        dots.forEach {
            $0.removeAnimation(forKey: Self.animationKey)
            $0.removeAnimation(forKey: Self.colorAnimationKey)
            $0.removeAnimation(forKey: Self.shadowColorAnimationKey)
        }
    }

    private func stopOpacityAnimations() {
        dots.forEach { $0.removeAnimation(forKey: Self.animationKey) }
    }

    private func updateGeometry() {
        guard let configuration else { return }
        guard bounds.width > 0, bounds.height > 0, configuration.size > 0 else {
            return
        }

        let geometry = GeometrySignature(
            width: bounds.width,
            height: bounds.height,
            requestedSize: configuration.size
        )
        guard geometry != lastGeometry else { return }
        lastGeometry = geometry

        #if DEBUG
        geometryUpdateCount += 1
        #endif

        let footprint = min(bounds.width, bounds.height, configuration.size)
        let diameter = max(0.9, min(2.6, footprint * 0.20))
        let pitch = (footprint - diameter) / 2
        let originX = (bounds.width - footprint) / 2
        let originY = (bounds.height - footprint) / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for row in 0..<3 {
            for column in 0..<3 {
                let dot = dots[row * 3 + column]
                dot.frame = CGRect(
                    x: originX + CGFloat(column) * pitch,
                    y: originY + CGFloat(row) * pitch,
                    width: diameter,
                    height: diameter
                )
                dot.cornerRadius = diameter / 2
                dot.shadowRadius = max(0.65, diameter * 0.52)
                dot.shadowPath = CGPath(
                    ellipseIn: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)),
                    transform: nil
                )
            }
        }
        CATransaction.commit()
    }

    private func installOpacityAnimations() {
        guard let configuration else { return }
        stopOpacityAnimations()

        let duration: TimeInterval
        switch configuration.motion {
        case .orbiting: duration = Motion.runningOrbitPeriod
        case .attention: duration = Motion.waitingBreathPeriod
        case .still: duration = 0
        }

        let shouldAnimate = configuration.isAnimated
            && configuration.motion != .still
            && duration > 0

        let keyframes = shouldAnimate
            ? DotMatrixKeyframeCache.shared.keyframes(
                pattern: configuration.pattern,
                motion: configuration.motion,
                intensity: configuration.intensity
            )
            : nil
        let synchronizedPhase = shouldAnimate
            ? Double(
                StatusPhase.cyclePhase(
                    Date.timeIntervalSinceReferenceDate,
                    period: duration
                )
            )
            : 0
        let mediaTime = shouldAnimate ? CACurrentMediaTime() : 0

        for row in 0..<3 {
            for column in 0..<3 {
                let dot = dots[row * 3 + column]
                let restingOpacity = DotMatrixMark.opacity(
                    pattern: configuration.pattern,
                    motion: configuration.motion,
                    intensity: configuration.intensity,
                    row: row,
                    column: column,
                    phase: 0.5
                )
                dot.opacity = Float(restingOpacity)

                guard shouldAnimate, let keyframes else { continue }

                let animation = CAKeyframeAnimation(keyPath: "opacity")
                let index = row * 3 + column
                animation.values = keyframes.values[index]
                animation.keyTimes = keyframes.keyTimes
                animation.duration = duration
                animation.repeatCount = .infinity
                animation.calculationMode = .linear
                animation.isRemovedOnCompletion = false

                // Match the previous wall-clock-derived phase so status
                // changes and newly visible rows join the same loop instead
                // of all visibly restarting from frame zero.
                let localNow = dot.convertTime(mediaTime, from: nil)
                animation.beginTime = localNow - synchronizedPhase * duration
                dot.add(animation, forKey: Self.animationKey)
            }
        }
    }

    private struct GeometrySignature: Equatable {
        let width: CGFloat
        let height: CGFloat
        let requestedSize: CGFloat
    }
}

/// Reuses the expensive trigonometric opacity samples across identical marks.
/// A twenty-session panel normally has many copies of the same Running or
/// Waiting signature; generating those 441 samples once keeps the reveal path
/// light while Core Animation still owns an independent phase-aligned loop for
/// every visible mark.
final class DotMatrixKeyframeCache: @unchecked Sendable {
    static let shared = DotMatrixKeyframeCache()
    static let sampleCount = 48
    static let maximumEntryCount = 16

    struct Keyframes: Equatable {
        let values: [[NSNumber]]
        let keyTimes: [NSNumber]
    }

    struct Snapshot: Equatable {
        let entryCount: Int
        let generationCount: Int
    }

    private struct Signature: Hashable {
        let pattern: DotMatrixMark.Pattern
        let motion: DotMatrixMark.MotionStyle
        let intensityBits: UInt64
    }

    private let lock = NSLock()
    private var storage: [Signature: Keyframes] = [:]
    private var generationCount = 0

    private init() {}

    func keyframes(
        pattern: DotMatrixMark.Pattern,
        motion: DotMatrixMark.MotionStyle,
        intensity: Double
    ) -> Keyframes {
        let signature = Signature(
            pattern: pattern,
            motion: motion,
            intensityBits: intensity.bitPattern
        )

        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[signature] {
            return cached
        }
        if storage.count >= Self.maximumEntryCount {
            // Animated signatures are a tiny semantic set. The hard cap keeps
            // a future preview/debug caller with arbitrary intensities from
            // turning this optimization into process-lifetime growth.
            storage.removeAll(keepingCapacity: true)
        }
        // Generate the small semantic cache miss while still owning the lock.
        // This makes a concurrent first reveal calculate the 441 samples once,
        // rather than allowing a thundering herd to compute identical values
        // before only one result wins insertion.
        let generated = Self.generate(
            pattern: pattern,
            motion: motion,
            intensity: intensity
        )
        storage[signature] = generated
        generationCount += 1
        return generated
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            entryCount: storage.count,
            generationCount: generationCount
        )
    }

    #if DEBUG
    func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll(keepingCapacity: true)
        generationCount = 0
    }
    #endif

    private static func generate(
        pattern: DotMatrixMark.Pattern,
        motion: DotMatrixMark.MotionStyle,
        intensity: Double
    ) -> Keyframes {
        let keyTimes = (0...sampleCount).map { sample in
            NSNumber(value: Double(sample) / Double(sampleCount))
        }
        let values = (0..<9).map { index in
            let row = index / 3
            let column = index % 3
            return (0...sampleCount).map { sample in
                NSNumber(
                    value: Float(
                        DotMatrixMark.opacity(
                            pattern: pattern,
                            motion: motion,
                            intensity: intensity,
                            row: row,
                            column: column,
                            phase: CGFloat(sample) / CGFloat(sampleCount)
                        )
                    )
                )
            }
        }
        return Keyframes(values: values, keyTimes: keyTimes)
    }
}
