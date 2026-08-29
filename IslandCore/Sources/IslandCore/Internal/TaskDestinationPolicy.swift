import Foundation

/// Converts an untrusted task destination into the only URL Dev Island is
/// willing to hand to Launch Services.
///
/// Manus owns one reviewed HTTPS route. Local CLI connectors own only an
/// existing Finder directory. Everything else (custom schemes, remote file
/// URLs, regular files, app bundles and stale paths) fails closed.
enum TaskDestinationPolicy {
    private static let maximumURLBytes = 2_048
    private static let blockedDirectoryExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "xpc",
    ]

    static func destination(
        for task: AgentTask,
        fileManager: FileManager = .default
    ) -> URL? {
        if task.source == "manus" {
            return manusDestination(rawValue: task.taskURL, taskID: task.id)
        }
        return localDirectoryDestination(rawValue: task.taskURL, fileManager: fileManager)
    }

    static func manusDestination(rawValue: String, taskID: String) -> URL? {
        guard isBoundedPrintableASCII(rawValue),
              ManusRemoteContentPolicy.isValidOpaqueIdentifier(taskID),
              let components = URLComponents(string: rawValue),
              components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.host == "manus.im",
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath == "/app/\(taskID)",
              components.url?.absoluteString == rawValue else {
            return nil
        }
        return components.url
    }

    private static func localDirectoryDestination(
        rawValue: String,
        fileManager: FileManager
    ) -> URL? {
        guard isBoundedPrintableASCII(rawValue),
              let parsed = URL(string: rawValue),
              parsed.isFileURL,
              parsed.host == nil,
              parsed.query == nil,
              parsed.fragment == nil,
              parsed.absoluteString == rawValue else {
            return nil
        }

        let resolved = parsed.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathExtension.lowercased().isEmpty ||
                !blockedDirectoryExtensions.contains(resolved.pathExtension.lowercased()) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let values = try? resolved.resourceValues(forKeys: [
                  .isApplicationKey,
                  .isPackageKey,
                  .isDirectoryKey,
              ]),
              values.isDirectory == true,
              values.isApplication != true,
              values.isPackage != true else {
            return nil
        }
        return resolved
    }

    private static func isBoundedPrintableASCII(_ value: String) -> Bool {
        let bytes = value.utf8
        return !bytes.isEmpty &&
            bytes.count <= maximumURLBytes &&
            bytes.allSatisfy { 0x21...0x7e ~= $0 }
    }

}
