import AppKit
import Foundation

private func normalizedPath(_ url: URL?) -> String? {
    url?.standardizedFileURL.resolvingSymlinksInPath().path
}

private func fail(_ message: String, status: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
    exit(status)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("expected list or terminate command")
}

switch arguments[1] {
case "list":
    guard arguments.count == 3 else {
        fail("list requires one Bundle ID")
    }
    let bundleIdentifier = arguments[2]
    guard !bundleIdentifier.isEmpty else {
        fail("Bundle ID must not be empty")
    }

    let applications = NSWorkspace.shared.runningApplications
        .filter { $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated }
        .sorted { $0.processIdentifier < $1.processIdentifier }
    for application in applications {
        guard let path = normalizedPath(application.executableURL),
              !path.contains("\t"),
              !path.contains("\n") else {
            fail("running application has no safe executable path", status: 3)
        }
        print("\(application.processIdentifier)\t\(path)")
    }

case "terminate":
    guard arguments.count == 4,
          let rawPID = Int32(arguments[2]),
          rawPID > 0 else {
        fail("terminate requires a positive PID and expected executable path")
    }
    let expectedPath = URL(fileURLWithPath: arguments[3])
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .path
    guard let application = NSRunningApplication(processIdentifier: rawPID),
          !application.isTerminated,
          normalizedPath(application.executableURL) == expectedPath else {
        fail("PID is no longer the expected QA application", status: 4)
    }
    guard application.terminate() else {
        fail("AppKit refused the QA application termination request", status: 5)
    }

default:
    fail("unsupported command")
}
