import Foundation
import XCTest
@testable import IslandAppLib

final class ProjectBranchReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectBranchReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeRepository(named name: String, head: String) throws -> URL {
        let project = root.appendingPathComponent(name, isDirectory: true)
        let git = project.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try Data(head.utf8).write(to: git.appendingPathComponent("HEAD"))
        return project
    }

    func testReadsCheckedOutBranchFromRepositoryRoot() throws {
        let project = try makeRepository(named: "island", head: "ref: refs/heads/feat/vibe\n")
        XCTAssertEqual(ProjectBranchReader.branch(forProjectPath: project.path), "feat/vibe")
        XCTAssertEqual(
            ProjectBranchReader.branch(forTaskURL: project.absoluteString),
            "feat/vibe"
        )
    }

    func testWalksUpFromANestedWorkingDirectory() throws {
        let project = try makeRepository(named: "nested", head: "ref: refs/heads/main\n")
        let deep = project.appendingPathComponent("Sources/App/Views", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        XCTAssertEqual(ProjectBranchReader.branch(forProjectPath: deep.path), "main")
    }

    func testDetachedHeadShowsShortObjectID() throws {
        let sha = String(repeating: "ab", count: 20)
        let project = try makeRepository(named: "detached", head: sha + "\n")
        XCTAssertEqual(ProjectBranchReader.branch(forProjectPath: project.path), "abababa")
    }

    func testWorktreeGitFileIsFollowedToItsGitDirectory() throws {
        let gitDirectory = root.appendingPathComponent("common/.git/worktrees/wt", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try Data("ref: refs/heads/worktree-branch\n".utf8)
            .write(to: gitDirectory.appendingPathComponent("HEAD"))

        let worktree = root.appendingPathComponent("wt", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("gitdir: \(gitDirectory.path)\n".utf8)
            .write(to: worktree.appendingPathComponent(".git"))

        XCTAssertEqual(ProjectBranchReader.branch(forProjectPath: worktree.path), "worktree-branch")
    }

    func testNonRepositoryAndRemoteTasksHaveNoBranch() throws {
        let plain = root.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        XCTAssertNil(ProjectBranchReader.branch(forProjectPath: plain.path))
        XCTAssertNil(ProjectBranchReader.branch(forTaskURL: "https://manus.im/app/abc"))
        XCTAssertNil(ProjectBranchReader.branch(forTaskURL: ""))
    }

    func testSymlinkedHeadAndOversizedHeadAreRejected() throws {
        let project = try makeRepository(named: "linked", head: "ref: refs/heads/real\n")
        let git = project.appendingPathComponent(".git", isDirectory: true)
        let real = git.appendingPathComponent("HEAD")
        let elsewhere = root.appendingPathComponent("elsewhere-HEAD")
        try Data("ref: refs/heads/elsewhere\n".utf8).write(to: elsewhere)
        try FileManager.default.removeItem(at: real)
        try FileManager.default.createSymbolicLink(at: real, withDestinationURL: elsewhere)
        XCTAssertNil(ProjectBranchReader.branch(forProjectPath: project.path))

        try FileManager.default.removeItem(at: real)
        let oversized = "ref: refs/heads/" + String(repeating: "x", count: ProjectBranchReader.maximumBytes)
        try Data(oversized.utf8).write(to: real)
        XCTAssertNil(ProjectBranchReader.branch(forProjectPath: project.path))
    }

    func testBranchNamesAreBoundedAndControlFree() {
        XCTAssertNil(ProjectBranchReader.parseHead("ref: refs/heads/bad\u{07}name"))
        XCTAssertNil(ProjectBranchReader.parseHead("ref: refs/heads/"))
        XCTAssertNil(ProjectBranchReader.parseHead("garbage"))
        let long = String(repeating: "b", count: 100)
        let parsed = ProjectBranchReader.parseHead("ref: refs/heads/\(long)")
        XCTAssertEqual(parsed?.count, ProjectBranchReader.maximumBranchCharacters)
        XCTAssertTrue(parsed?.hasSuffix("…") == true)
    }

    @MainActor
    func testCacheResolvesOffMainAndRefreshesAfterInterval() async {
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let resolutions = ResolutionCounter()
        let cache = ProjectBranchCache(
            resolver: { url in
                resolutions.increment()
                return url.hasSuffix("/a/") ? "main" : nil
            },
            now: { clock }
        )

        XCTAssertNil(cache.branch(forTaskURL: "file:///tmp/a/"))
        await waitUntil { resolutions.count == 1 }
        XCTAssertEqual(cache.branch(forTaskURL: "file:///tmp/a/"), "main")
        XCTAssertEqual(resolutions.count, 1, "fresh entries are served from memory")

        clock = clock.addingTimeInterval(ProjectBranchCache.refreshInterval + 1)
        XCTAssertEqual(cache.branch(forTaskURL: "file:///tmp/a/"), "main", "stale value stays visible")
        await waitUntil { resolutions.count == 2 }

        XCTAssertNil(cache.branch(forTaskURL: "https://manus.im/app/x"))
        XCTAssertEqual(resolutions.count, 2, "remote tasks never touch the resolver")
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }
}

private final class ResolutionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
