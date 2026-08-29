import Darwin
import Dispatch
import Foundation

/// A synchronous POSIX boundary for one bounded stdin/stdout exchange.
///
/// The child receives a minimal caller-provided environment, starts in its own
/// process group, and is observed through nonblocking pipes and a monotonic
/// deadline. A response, timeout, output overflow, I/O failure, or early exit
/// always reaps the direct child and terminates every descendant in the group.
/// Callers own executable trust and protocol parsing; this type owns only the
/// process, pipe, byte, time, and cleanup boundary.
enum BoundedStdioChildProcess {
    enum Completion {
        case response(Data)
        case exitedWithoutResponse
        case timedOut
        case exceededOutputLimit
        case ioFailure
    }

    private struct SpawnedProcess {
        let pid: pid_t
        let inputDescriptor: Int32
        let outputDescriptor: Int32
    }

    static func requestResponse(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL,
        input: Data,
        outputLimit: Int,
        timeout: TimeInterval,
        terminationGrace: TimeInterval = 0.25,
        responseFromChunk: (Data) -> Data?
    ) -> Completion? {
        guard executableURL.isFileURL,
              executableURL.path.hasPrefix("/"),
              isSafeProcessString(executableURL.path, maximumBytes: 4_096),
              currentDirectoryURL.isFileURL,
              currentDirectoryURL.path.hasPrefix("/"),
              isSafeProcessString(currentDirectoryURL.path, maximumBytes: 4_096),
              isExistingDirectory(currentDirectoryURL.path),
              arguments.count <= 64,
              arguments.allSatisfy({ isSafeProcessString($0, maximumBytes: 4_096) }),
              environment.count <= 64,
              environment.allSatisfy({ key, value in
                  isSafeEnvironmentKey(key)
                      && isSafeProcessString(value, maximumBytes: 4_096)
              }),
              1...(64 * 1_024) ~= input.count,
              1...(2 * 1_024 * 1_024) ~= outputLimit,
              timeout.isFinite,
              0.05...10 ~= timeout,
              terminationGrace.isFinite,
              0.01...1 ~= terminationGrace,
              let spawned = spawn(
                  executablePath: executableURL.path,
                  arguments: arguments,
                  environment: environment,
                  currentDirectoryPath: currentDirectoryURL.path
              )
        else { return nil }

        let inputDescriptor = spawned.inputDescriptor
        let outputDescriptor = spawned.outputDescriptor
        defer {
            Darwin.close(inputDescriptor)
            Darwin.close(outputDescriptor)
        }

        guard setNonblocking(inputDescriptor),
              setNonblocking(outputDescriptor),
              suppressSigpipe(inputDescriptor)
        else {
            terminateAndReap(
                pid: spawned.pid,
                directChildExited: false,
                terminationGrace: terminationGrace
            )
            return nil
        }

        var inputOffset = 0
        var totalOutputBytes = 0
        var outputBuffer = [UInt8](repeating: 0, count: 16 * 1_024)
        defer { erase(&outputBuffer) }

        var directChildExited = false
        var ioFailed = false
        var exceededOutputLimit = false
        var response: Data?
        var status: Int32 = 0

        func writeAvailableInput() {
            while !ioFailed, inputOffset < input.count {
                let byteCount = input.withUnsafeBytes { rawBuffer -> Int in
                    guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                    return Darwin.write(
                        inputDescriptor,
                        baseAddress.advanced(by: inputOffset),
                        input.count - inputOffset
                    )
                }
                if byteCount > 0 {
                    inputOffset += byteCount
                    continue
                }
                if byteCount < 0, errno == EINTR { continue }
                if byteCount < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
                ioFailed = true
            }
        }

        func drainAvailableOutput() {
            while !ioFailed, !exceededOutputLimit, response == nil {
                let byteCount = outputBuffer.withUnsafeMutableBytes { rawBuffer in
                    Darwin.read(
                        outputDescriptor,
                        rawBuffer.baseAddress,
                        rawBuffer.count
                    )
                }
                if byteCount > 0 {
                    totalOutputBytes += byteCount
                    guard totalOutputBytes <= outputLimit else {
                        exceededOutputLimit = true
                        erasePrefix(&outputBuffer, count: byteCount)
                        return
                    }

                    var chunk = Data(outputBuffer.prefix(byteCount))
                    response = responseFromChunk(chunk)
                    chunk.resetBytes(in: chunk.indices)
                    erasePrefix(&outputBuffer, count: byteCount)
                    continue
                }
                if byteCount == 0 { return }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                ioFailed = true
            }
        }

        let timeoutNanoseconds = UInt64(timeout * 1_000_000_000)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let deadline = startedAt.addingReportingOverflow(timeoutNanoseconds)
        guard !deadline.overflow else {
            terminateAndReap(
                pid: spawned.pid,
                directChildExited: false,
                terminationGrace: terminationGrace
            )
            return nil
        }

        var timedOut = false
        while response == nil,
              !directChildExited,
              !ioFailed,
              !exceededOutputLimit {
            writeAvailableInput()
            drainAvailableOutput()
            if response != nil || ioFailed || exceededOutputLimit { break }

            let waitResult = Darwin.waitpid(spawned.pid, &status, WNOHANG)
            if waitResult == spawned.pid {
                directChildExited = true
                drainAvailableOutput()
                break
            }
            if waitResult < 0, errno != EINTR {
                ioFailed = true
                break
            }

            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadline.partialValue {
                timedOut = true
                break
            }

            let remainingMilliseconds = max(
                1,
                min(10, Int((deadline.partialValue - now) / 1_000_000))
            )
            var descriptors = [
                pollfd(
                    fd: outputDescriptor,
                    events: Int16(POLLIN | POLLHUP),
                    revents: 0
                ),
                pollfd(
                    fd: inputDescriptor,
                    events: inputOffset < input.count ? Int16(POLLOUT) : 0,
                    revents: 0
                ),
            ]
            let pollResult = Darwin.poll(
                &descriptors,
                nfds_t(descriptors.count),
                Int32(remainingMilliseconds)
            )
            if pollResult < 0, errno != EINTR {
                ioFailed = true
            }
        }

        terminateAndReap(
            pid: spawned.pid,
            directChildExited: directChildExited,
            terminationGrace: terminationGrace
        )

        if var response {
            defer { response.resetBytes(in: response.indices) }
            return .response(response)
        }
        if exceededOutputLimit { return .exceededOutputLimit }
        if timedOut { return .timedOut }
        if ioFailed { return .ioFailure }
        return .exitedWithoutResponse
    }

    private static func spawn(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectoryPath: String
    ) -> SpawnedProcess? {
        var inputDescriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&inputDescriptors) == 0 else { return nil }
        var childInputDescriptor = inputDescriptors[0]
        var parentInputDescriptor = inputDescriptors[1]

        var outputDescriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&outputDescriptors) == 0 else {
            Darwin.close(childInputDescriptor)
            Darwin.close(parentInputDescriptor)
            return nil
        }
        var parentOutputDescriptor = outputDescriptors[0]
        var childOutputDescriptor = outputDescriptors[1]
        var nullDescriptor = Darwin.open("/dev/null", O_RDWR | O_CLOEXEC)
        defer {
            if childInputDescriptor >= 0 { Darwin.close(childInputDescriptor) }
            if parentInputDescriptor >= 0 { Darwin.close(parentInputDescriptor) }
            if parentOutputDescriptor >= 0 { Darwin.close(parentOutputDescriptor) }
            if childOutputDescriptor >= 0 { Darwin.close(childOutputDescriptor) }
            if nullDescriptor >= 0 { Darwin.close(nullDescriptor) }
        }
        guard nullDescriptor >= 0,
              normalizePipeDescriptor(&childInputDescriptor),
              normalizePipeDescriptor(&parentInputDescriptor),
              normalizePipeDescriptor(&parentOutputDescriptor),
              normalizePipeDescriptor(&childOutputDescriptor),
              normalizePipeDescriptor(&nullDescriptor)
        else { return nil }

        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        guard posix_spawn_file_actions_addchdir_np(
            &fileActions,
            currentDirectoryPath
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            childInputDescriptor,
            STDIN_FILENO
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            childOutputDescriptor,
            STDOUT_FILENO
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            nullDescriptor,
            STDERR_FILENO
        ) == 0,
        posix_spawn_file_actions_addclose(&fileActions, childInputDescriptor) == 0,
        posix_spawn_file_actions_addclose(&fileActions, parentInputDescriptor) == 0,
        posix_spawn_file_actions_addclose(&fileActions, parentOutputDescriptor) == 0,
        posix_spawn_file_actions_addclose(&fileActions, childOutputDescriptor) == 0,
        posix_spawn_file_actions_addclose(&fileActions, nullDescriptor) == 0
        else { return nil }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP)
        ) == 0,
        posix_spawnattr_setpgroup(&attributes, 0) == 0
        else { return nil }

        let argumentStrings = [executablePath] + arguments
        let environmentStrings = environment.keys.sorted().map { key in
            "\(key)=\(environment[key] ?? "")"
        }
        guard var argumentPointers = duplicatedCStringArray(argumentStrings),
              var environmentPointers = duplicatedCStringArray(environmentStrings)
        else { return nil }
        defer {
            freeCStringArray(argumentPointers)
            freeCStringArray(environmentPointers)
        }

        var pid: pid_t = 0
        let spawnResult = executablePath.withCString { executable in
            argumentPointers.withUnsafeMutableBufferPointer { argumentsBuffer in
                environmentPointers.withUnsafeMutableBufferPointer { environmentBuffer in
                    posix_spawn(
                        &pid,
                        executable,
                        &fileActions,
                        &attributes,
                        argumentsBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }
        guard spawnResult == 0, pid > 0 else { return nil }

        Darwin.close(childInputDescriptor)
        childInputDescriptor = -1
        Darwin.close(childOutputDescriptor)
        childOutputDescriptor = -1
        Darwin.close(nullDescriptor)
        nullDescriptor = -1

        let result = SpawnedProcess(
            pid: pid,
            inputDescriptor: parentInputDescriptor,
            outputDescriptor: parentOutputDescriptor
        )
        parentInputDescriptor = -1
        parentOutputDescriptor = -1
        return result
    }

    private static func terminateAndReap(
        pid: pid_t,
        directChildExited: Bool,
        terminationGrace: TimeInterval
    ) {
        var didExit = directChildExited
        var status: Int32 = 0

        if !didExit {
            signalProcessGroup(pid, signal: SIGTERM)
            let graceNanoseconds = UInt64(terminationGrace * 1_000_000_000)
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let deadline = startedAt.addingReportingOverflow(graceNanoseconds)

            if !deadline.overflow {
                while DispatchTime.now().uptimeNanoseconds < deadline.partialValue {
                    let waitResult = Darwin.waitpid(pid, &status, WNOHANG)
                    if waitResult == pid {
                        didExit = true
                        break
                    }
                    if waitResult < 0, errno != EINTR { break }
                    Darwin.usleep(5_000)
                }
            }
        }

        if !didExit {
            signalProcessGroup(pid, signal: SIGKILL)
            while Darwin.waitpid(pid, &status, 0) < 0, errno == EINTR {}
        }

        // A direct child may exit while a background helper remains in the
        // inherited process group. Kill the group once more immediately after
        // reaping so an ordinary early exit cannot daemonize work behind the
        // readiness probe.
        signalProcessGroup(pid, signal: SIGKILL)
    }

    private static func setNonblocking(_ descriptor: Int32) -> Bool {
        let flags = Darwin.fcntl(descriptor, F_GETFL)
        return flags >= 0
            && Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
    }

    /// A child can close stdin between `posix_spawn` returning and the next
    /// parent write. On Darwin, an ordinary pipe write would then terminate
    /// the complete App with SIGPIPE before it could observe EPIPE. Keep the
    /// failure local to this request/response boundary.
    private static func suppressSigpipe(_ descriptor: Int32) -> Bool {
        Darwin.fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0
    }

    /// GUI processes normally inherit stdin/stdout/stderr, but the process
    /// boundary must remain correct if one of those descriptors was closed by
    /// a launcher. Keep every pipe endpoint above the standard range before
    /// composing dup/close file actions, and prevent unrelated concurrent
    /// child launches from inheriting a parent endpoint.
    private static func normalizePipeDescriptor(_ descriptor: inout Int32) -> Bool {
        guard descriptor >= 0 else { return false }
        if descriptor <= STDERR_FILENO {
            let duplicate = Darwin.fcntl(
                descriptor,
                F_DUPFD_CLOEXEC,
                STDERR_FILENO + 1
            )
            guard duplicate >= 0 else { return false }
            Darwin.close(descriptor)
            descriptor = duplicate
            return true
        }

        let flags = Darwin.fcntl(descriptor, F_GETFD)
        return flags >= 0
            && Darwin.fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) == 0
    }

    private static func signalProcessGroup(_ pid: pid_t, signal: Int32) {
        if Darwin.kill(-pid, signal) != 0 {
            _ = Darwin.kill(pid, signal)
        }
    }

    private static func isExistingDirectory(_ path: String) -> Bool {
        var metadata = stat()
        return Darwin.lstat(path, &metadata) == 0
            && (metadata.st_mode & S_IFMT) == S_IFDIR
    }

    private static func duplicatedCStringArray(
        _ strings: [String]
    ) -> [UnsafeMutablePointer<CChar>?]? {
        var result: [UnsafeMutablePointer<CChar>?] = []
        result.reserveCapacity(strings.count + 1)
        for string in strings {
            guard let pointer = Darwin.strdup(string) else {
                freeCStringArray(result)
                return nil
            }
            result.append(pointer)
        }
        result.append(nil)
        return result
    }

    private static func freeCStringArray(
        _ pointers: [UnsafeMutablePointer<CChar>?]
    ) {
        for pointer in pointers {
            if let pointer { Darwin.free(pointer) }
        }
    }

    private static func isSafeProcessString(
        _ value: String,
        maximumBytes: Int
    ) -> Bool {
        !value.contains("\0") && value.utf8.count <= maximumBytes
    }

    private static func isSafeEnvironmentKey(_ key: String) -> Bool {
        guard !key.isEmpty,
              key.utf8.count <= 128,
              !key.contains("="),
              key.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII
                      && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
              })
        else { return false }
        return true
    }

    private static func erase(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { rawBuffer in
            if let address = rawBuffer.baseAddress {
                Darwin.memset(address, 0, rawBuffer.count)
            }
        }
    }

    private static func erasePrefix(_ bytes: inout [UInt8], count: Int) {
        guard count > 0 else { return }
        bytes.withUnsafeMutableBytes { rawBuffer in
            if let address = rawBuffer.baseAddress {
                Darwin.memset(address, 0, min(count, rawBuffer.count))
            }
        }
    }
}
