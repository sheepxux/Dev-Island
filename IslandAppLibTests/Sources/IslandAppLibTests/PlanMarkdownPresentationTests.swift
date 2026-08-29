import XCTest
@testable import IslandAppLib

final class PlanMarkdownPresentationTests: XCTestCase {
    func testParserPreservesHeadingsListsParagraphsAndCodeAsSeparateBlocks() {
        let markdown = """
        ## Release plan

        Keep **approval** visible.

        1. Run tests
        2. Verify motion
        - Save evidence

        ```swift
        priority = attention > running
        ```
        """

        XCTAssertEqual(
            PlanMarkdownPresentation.blocks(from: markdown),
            [
                .heading(level: 2, text: "Release plan"),
                .paragraph("Keep **approval** visible."),
                .orderedListItem(marker: "1.", text: "Run tests"),
                .orderedListItem(marker: "2.", text: "Verify motion"),
                .unorderedListItem("Save evidence"),
                .code("priority = attention > running"),
            ]
        )
    }

    func testWrappedParagraphLinesRemainOneReadableParagraph() {
        XCTAssertEqual(
            PlanMarkdownPresentation.blocks(from: "One wrapped\nparagraph line"),
            [.paragraph("One wrapped paragraph line")]
        )
    }

    func testUnclosedCodeFenceStillProducesABoundedCodeBlock() {
        XCTAssertEqual(
            PlanMarkdownPresentation.blocks(from: "```\nlet value = 1"),
            [.code("let value = 1")]
        )
    }

    func testRenderedDocumentPrecomputesInlineMarkdownForTheView() throws {
        let document = PlanMarkdownDocument.render(
            "## **Release**\n\nKeep *approval* visible."
        )

        XCTAssertEqual(document.blocks.count, 2)
        guard case .heading(let level, let heading) = document.blocks[0],
              case .paragraph(let paragraph) = document.blocks[1] else {
            return XCTFail("Expected one rendered heading and paragraph")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(String(heading.characters), "Release")
        XCTAssertEqual(String(paragraph.characters), "Keep approval visible.")
    }

    func testNewPlanRenderRejectsLateOlderDocument() {
        var state = PlanMarkdownRenderingOperationState()
        let firstRequest = UUID()
        let secondRequest = UUID()
        let firstOperation = UUID()
        let secondOperation = UUID()

        state.begin(requestID: firstRequest, operationID: firstOperation)
        state.begin(requestID: secondRequest, operationID: secondOperation)

        XCTAssertFalse(state.accept(
            .render("First"),
            requestID: firstRequest,
            operationID: firstOperation
        ))
        XCTAssertTrue(state.accept(
            .render("Second"),
            requestID: secondRequest,
            operationID: secondOperation
        ))
        XCTAssertEqual(state.requestID, secondRequest)
        XCTAssertFalse(state.isPreparing)
    }

    func testPlanRenderInvalidationRejectsLateDelivery() {
        var state = PlanMarkdownRenderingOperationState()
        let requestID = UUID()
        let operationID = state.begin(requestID: requestID)

        state.invalidate()

        XCTAssertFalse(state.accept(
            .render("Late"),
            requestID: requestID,
            operationID: operationID
        ))
        XCTAssertNil(state.requestID)
        XCTAssertNil(state.document)
        XCTAssertFalse(state.isPreparing)
    }

    func testRenderedDocumentRejectsAPathologicalSwiftUITree() {
        let markdown = (0...PlanMarkdownDocument.maximumRenderedBlocks)
            .map { "- Item \($0)" }
            .joined(separator: "\n")

        let document = PlanMarkdownDocument.render(markdown)

        XCTAssertFalse(document.isComplete)
        XCTAssertFalse(document.isReadyForDecision)
        XCTAssertTrue(document.blocks.isEmpty)
    }

    @MainActor
    func testPlanRenderingExecutorLeavesTheMainThread() async {
        XCTAssertTrue(Thread.isMainThread)

        let workerRanOnMainThread = await PlanMarkdownRenderingExecutor.run(
            priority: .userInitiated
        ) {
            Thread.isMainThread
        }

        XCTAssertFalse(workerRanOnMainThread)
        XCTAssertTrue(Thread.isMainThread)
    }
}
