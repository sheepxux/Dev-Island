import AppKit
import Foundation

private func fail(_ message: String, status: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
    exit(status)
}

private func normalizedPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
}

@main
private enum ApplicationLaunchProbe {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 || arguments.count == 4 else {
            fail("expected App path, private CFFIXED_USER_HOME, and optional impostor event log")
        }

        let appURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let privateUserRoot = URL(fileURLWithPath: arguments[2], isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard appURL.path.hasPrefix("/"),
              privateUserRoot.path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: appURL.path),
              FileManager.default.fileExists(atPath: privateUserRoot.path) else {
            fail("App and private user root must be existing absolute paths")
        }

        var environment = ["CFFIXED_USER_HOME": privateUserRoot.path]
        if arguments.count == 4 {
            let eventLog = URL(fileURLWithPath: arguments[3])
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard eventLog.path.hasPrefix("/") else {
                fail("impostor event log must be absolute")
            }
            environment["DEV_ISLAND_QA_IMPOSTOR_EVENT_LOG"] = eventLog.path
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.createsNewApplicationInstance = true
        configuration.promptsUserIfNeeded = false
        configuration.environment = environment

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        ) { application, error in
            guard error == nil,
                  let application,
                  application.processIdentifier > 0,
                  let executableURL = application.executableURL else {
                fail("LaunchServices did not return the requested QA application", status: 3)
            }
            let expectedExecutable = appURL
                .appendingPathComponent("Contents/MacOS")
                .appendingPathComponent(
                    Bundle(url: appURL)?.object(
                        forInfoDictionaryKey: "CFBundleExecutable"
                    ) as? String ?? ""
                )
            guard normalizedPath(executableURL) == normalizedPath(expectedExecutable) else {
                fail("LaunchServices substituted a different application", status: 4)
            }
            print("\(application.processIdentifier)\t\(normalizedPath(executableURL))")
            fflush(stdout)
            exit(0)
        }
        RunLoop.main.run()
    }
}
