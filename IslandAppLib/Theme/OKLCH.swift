import AppKit
import SwiftUI

/// A color authored as a perceptual measurement: lightness 0…1, chroma, and
/// hue in degrees. Every product color is declared this way so that palette
/// work stays arithmetic — the same hue across a ramp, contrast repaired by
/// moving `l` alone — instead of hand-picked hex values that drift.
///
/// Conversion follows Björn Ottosson's OKLab reference and clamps chroma,
/// holding lightness and hue, until the color fits sRGB.
struct OKLCH: Equatable, Sendable {
    let l: Double
    let c: Double
    let h: Double
    var alpha: Double = 1

    init(_ l: Double, _ c: Double, _ h: Double, alpha: Double = 1) {
        self.l = l
        self.c = c
        self.h = h
        self.alpha = alpha
    }

    func opacity(_ alpha: Double) -> OKLCH {
        OKLCH(l, c, h, alpha: alpha)
    }

    /// Gamma-encoded sRGB components in 0…1, chroma clamped into gamut.
    var srgb: (red: Double, green: Double, blue: Double) {
        let linear = Self.linearSRGB(l: l, chroma: Self.clampedChroma(l: l, c: c, h: h), h: h)
        return (
            Self.gammaEncode(linear.0),
            Self.gammaEncode(linear.1),
            Self.gammaEncode(linear.2)
        )
    }

    /// The 8-bit sRGB value this color renders as, for contrast math and
    /// for comparing against reviewed reference values in tests.
    var hex: UInt32 {
        let (red, green, blue) = srgb
        func byte(_ value: Double) -> UInt32 {
            UInt32(max(0, min(255, (value * 255).rounded())))
        }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    var nsColor: NSColor {
        let (red, green, blue) = srgb
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        let (red, green, blue) = srgb
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    // MARK: - Conversion

    private static func linearSRGB(l: Double, chroma: Double, h: Double) -> (Double, Double, Double) {
        let radians = h * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let lCubed = l_ * l_ * l_
        let mCubed = m_ * m_ * m_
        let sCubed = s_ * s_ * s_
        return (
            4.0767416621 * lCubed - 3.3077115913 * mCubed + 0.2309699292 * sCubed,
            -1.2684380046 * lCubed + 2.6097574011 * mCubed - 0.3413193965 * sCubed,
            -0.0041960863 * lCubed - 0.7034186147 * mCubed + 1.7076147010 * sCubed
        )
    }

    private static func isInGamut(_ linear: (Double, Double, Double)) -> Bool {
        let tolerance = 1e-6
        return [linear.0, linear.1, linear.2].allSatisfy {
            $0 >= -tolerance && $0 <= 1 + tolerance
        }
    }

    private static func clampedChroma(l: Double, c: Double, h: Double) -> Double {
        guard !isInGamut(linearSRGB(l: l, chroma: c, h: h)) else { return c }
        var low = 0.0
        var high = c
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if isInGamut(linearSRGB(l: l, chroma: middle, h: h)) {
                low = middle
            } else {
                high = middle
            }
        }
        return low
    }

    private static func gammaEncode(_ linear: Double) -> Double {
        let value = max(0, min(1, linear))
        return value <= 0.0031308
            ? 12.92 * value
            : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

/// The one neutral ramp every surface is built from, taken from the app
/// icon: the black terminal tile and the warm off-white base it sits on share
/// hue 86°. Windows read from the light end, the island from the dark end —
/// dark mode is a remap of the same steps, not a second palette.
enum Sand {
    static let hue = 86.0

    static let s0 = OKLCH(0.992, 0.0035, hue)
    static let s25 = OKLCH(0.978, 0.007, hue)
    static let s50 = OKLCH(0.963, 0.011, hue)
    static let s100 = OKLCH(0.935, 0.013, hue)
    static let s150 = OKLCH(0.905, 0.015, hue)
    static let s200 = OKLCH(0.870, 0.016, hue)
    static let s300 = OKLCH(0.790, 0.016, hue)
    static let s400 = OKLCH(0.690, 0.014, hue)
    static let s500 = OKLCH(0.600, 0.013, hue)
    static let s600 = OKLCH(0.520, 0.012, hue)
    static let s700 = OKLCH(0.450, 0.011, hue)
    static let s800 = OKLCH(0.340, 0.008, hue)
    static let s850 = OKLCH(0.280, 0.006, hue)
    static let s900 = OKLCH(0.222, 0.005, hue)
    static let s950 = OKLCH(0.180, 0.004, hue)
    static let s1000 = OKLCH(0.150, 0.003, hue)

    static let ramp: [OKLCH] = [
        s0, s25, s50, s100, s150, s200, s300, s400,
        s500, s600, s700, s800, s850, s900, s950, s1000,
    ]
}

/// State colors. Chroma encodes urgency rather than being equalized: a
/// session that needs you is the most vivid thing on screen, a failure is
/// next, a finished response is barely tinted, and running work carries no
/// hue at all — its motion is the signal. Each family shares one lightness
/// so the marks sit at the same visual weight.
enum Signal {
    // On the island (L ≈ 0.80, dark ground)
    static let attentionOnDark = OKLCH(0.80, 0.097, 72)
    static let failureOnDark = OKLCH(0.76, 0.089, 30)
    static let successOnDark = OKLCH(0.80, 0.056, 148)

    // In windows (L 0.50, light ground — every value clears 4.5:1)
    static let attentionOnLight = OKLCH(0.50, 0.066, 72)
    static let failureOnLight = OKLCH(0.50, 0.124, 30)
    static let successOnLight = OKLCH(0.50, 0.058, 148)

    /// The amber tile behind an Agent that needs action.
    static let attentionFill = OKLCH(0.80, 0.118, 72)
    /// The wash behind the one group that asks for something.
    static let attentionWash = OKLCH(0.955, 0.030, 72)
}
