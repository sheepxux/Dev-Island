import AppKit
import Foundation

@MainActor
private final class ImpostorDelegate: NSObject, NSApplicationDelegate {
    private let eventLog: URL

    init(eventLog: URL) {
        self.eventLog = eventLog
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        record("did-finish-launching")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        record("did-become-active")
    }

    func applicationWillTerminate(_ notification: Notification) {
        record("will-terminate")
    }

    private func record(_ event: String) {
        guard let data = "\(event)\n".data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: eventLog) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            return
        }
    }
}

@main
private enum SingleInstanceImpostor {
    @MainActor
    static func main() {
        guard let rawLogPath = ProcessInfo.processInfo.environment[
            "DEV_ISLAND_QA_IMPOSTOR_EVENT_LOG"
        ],
        rawLogPath.hasPrefix("/"),
        !rawLogPath.contains("\0") else {
            exit(64)
        }

        let application = NSApplication.shared
        let delegate = ImpostorDelegate(
            eventLog: URL(fileURLWithPath: rawLogPath)
        )
        application.delegate = delegate
        application.run()
    }
}
