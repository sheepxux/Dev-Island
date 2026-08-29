import Darwin
import Foundation

/// Writes the already-redacted support summary to a user-selected local file.
///
/// The exporter deliberately owns no upload or sharing behavior. It writes a
/// bounded UTF-8 document through a same-directory temporary file, applies a
/// private `0600` mode at creation time, fsyncs it, and atomically renames it
/// into place. Existing symlinks and non-regular destinations are rejected so
/// a diagnostics export can never be redirected into an unexpected target.
enum SupportDiagnosticsExporter {
    static let maximumReportBytes = 128 * 1_024

    enum ExportError: Error, Equatable, LocalizedError, Sendable {
        case invalidDestination
        case emptyReport
        case reportTooLarge
        case unavailableFolder
        case unsafeDestination
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .invalidDestination:
                return "Choose a local file destination."
            case .emptyReport:
                return "There is no diagnostic summary to save."
            case .reportTooLarge:
                return "The diagnostic summary exceeded the safe export limit."
            case .unavailableFolder:
                return "The selected folder is unavailable."
            case .unsafeDestination:
                return "Choose a regular file instead of a link or folder."
            case .writeFailed:
                return "The diagnostic file couldn’t be written safely."
            }
        }
    }

    static func suggestedFilename(
        at date: Date = .now,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Dev-Island-Diagnostics-\(formatter.string(from: date)).txt"
    }

    static func write(_ report: String, to destination: URL) throws {
        guard destination.isFileURL else {
            throw ExportError.invalidDestination
        }

        let normalizedReport = report.hasSuffix("\n") ? report : report + "\n"
        guard !normalizedReport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.emptyReport
        }
        guard let data = normalizedReport.data(using: .utf8),
              data.count <= maximumReportBytes else {
            throw ExportError.reportTooLarge
        }

        let destination = destination.standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ExportError.unavailableFolder
        }
        try validateExistingDestination(destination.path)

        let temporary = directory.appendingPathComponent(
            ".dev-island-diagnostics-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let descriptor = temporary.path.withCString { path in
            Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(S_IRUSR | S_IWUSR)
            )
        }
        guard descriptor >= 0 else { throw ExportError.writeFailed }

        var descriptorIsOpen = true
        var committed = false
        defer {
            if descriptorIsOpen {
                _ = Darwin.close(descriptor)
            }
            if !committed {
                _ = temporary.path.withCString(Darwin.unlink)
            }
        }

        do {
            try writeAll(data, to: descriptor)
            guard Darwin.fsync(descriptor) == 0 else {
                throw ExportError.writeFailed
            }
            guard Darwin.close(descriptor) == 0 else {
                throw ExportError.writeFailed
            }
            descriptorIsOpen = false

            let renameResult = temporary.path.withCString { temporaryPath in
                destination.path.withCString { destinationPath in
                    Darwin.rename(temporaryPath, destinationPath)
                }
            }
            guard renameResult == 0 else { throw ExportError.writeFailed }
            committed = true
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.writeFailed
        }
    }

    private static func validateExistingDestination(_ path: String) throws {
        var information = stat()
        let result = path.withCString { Darwin.lstat($0, &information) }
        if result == 0 {
            guard information.st_mode & S_IFMT == S_IFREG else {
                throw ExportError.unsafeDestination
            }
            return
        }
        guard errno == ENOENT else { throw ExportError.unsafeDestination }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    throw ExportError.writeFailed
                }
                guard written > 0 else { throw ExportError.writeFailed }
                offset += written
            }
        }
    }
}

enum SupportDiagnosticsExportOutcome: Equatable, Sendable {
    case saved
    case failed(SupportDiagnosticsExporter.ExportError)
}

/// Synchronous descriptor work is intentionally isolated behind this worker.
/// Product UI calls it only through `SupportDiagnosticsIOExecutor`.
enum SupportDiagnosticsExportWorker {
    static func write(
        _ report: String,
        to destination: URL
    ) -> SupportDiagnosticsExportOutcome {
        do {
            try SupportDiagnosticsExporter.write(report, to: destination)
            return .saved
        } catch let error as SupportDiagnosticsExporter.ExportError {
            return .failed(error)
        } catch {
            return .failed(.writeFailed)
        }
    }
}

/// One explicit hop from the main actor to blocking diagnostic reads/writes.
/// The operation returns only Sendable, privacy-bounded values to product UI.
enum SupportDiagnosticsIOExecutor {
    static func run<Value: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () -> Value
    ) async -> Value {
        await Task.detached(priority: priority, operation: operation).value
    }
}
