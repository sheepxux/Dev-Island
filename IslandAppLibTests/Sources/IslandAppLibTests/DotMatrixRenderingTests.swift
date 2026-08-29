import AppKit
import SwiftUI
import XCTest
@testable import IslandAppLib

final class DotMatrixRenderingTests: XCTestCase {
    func testKeyframesAreSharedPerSignatureAndCacheRemainsBounded() {
        let cache = DotMatrixKeyframeCache.shared
        cache.resetForTesting()

        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            _ = cache.keyframes(
                pattern: .orbit,
                motion: .orbiting,
                intensity: 0.97
            )
        }

        let firstSnapshot = cache.snapshot()
        XCTAssertEqual(firstSnapshot.entryCount, 1)
        XCTAssertEqual(firstSnapshot.generationCount, 1)

        let first = cache.keyframes(
            pattern: .orbit,
            motion: .orbiting,
            intensity: 0.97
        )
        let second = cache.keyframes(
            pattern: .orbit,
            motion: .orbiting,
            intensity: 0.97
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.values.count, 9)
        XCTAssertTrue(
            first.values.allSatisfy {
                $0.count == DotMatrixKeyframeCache.sampleCount + 1
            }
        )
        XCTAssertEqual(
            first.keyTimes.count,
            DotMatrixKeyframeCache.sampleCount + 1
        )
        XCTAssertEqual(cache.snapshot(), firstSnapshot)

        for index in 0..<(DotMatrixKeyframeCache.maximumEntryCount + 4) {
            _ = cache.keyframes(
                pattern: .ring,
                motion: .attention,
                intensity: 0.50 + Double(index) / 100
            )
            XCTAssertLessThanOrEqual(
                cache.snapshot().entryCount,
                DotMatrixKeyframeCache.maximumEntryCount
            )
        }
    }

    @MainActor
    func testRepeatedLayoutReusesDotGeometryUntilSizeActuallyChanges() {
        let view = DotMatrixLayerView(
            frame: NSRect(x: 0, y: 0, width: 14, height: 14)
        )
        let base = DotMatrixLayerView.Configuration(
            color: DotMatrixColor(.green),
            size: 14,
            motion: .orbiting,
            pattern: .orbit,
            intensity: 0.97,
            isAnimated: false
        )

        view.apply(base)
        let initialUpdates = view.geometryUpdateCount
        XCTAssertEqual(initialUpdates, 1)

        view.layout()
        view.layout()
        XCTAssertEqual(view.geometryUpdateCount, initialUpdates)

        view.apply(
            .init(
                color: DotMatrixColor(.orange),
                size: 14,
                motion: .attention,
                pattern: .ring,
                intensity: 1,
                isAnimated: false
            )
        )
        XCTAssertEqual(
            view.geometryUpdateCount,
            initialUpdates,
            "Color, state, and motion changes must not rebuild identical paths"
        )

        view.frame = NSRect(x: 0, y: 0, width: 18, height: 18)
        view.layout()
        let resizedUpdates = view.geometryUpdateCount
        XCTAssertGreaterThan(resizedUpdates, initialUpdates)

        view.layout()
        XCTAssertEqual(view.geometryUpdateCount, resizedUpdates)
    }
}
