import Darwin
import Dispatch
import Foundation

/// A synchronous POSIX child-process boundary for small local helper commands.
///
/// It drains stdout while the child runs, owns `waitpid`, uses a monotonic
/// deadline, and terminates the entire child process group. Callers still own
/// executable trust and output parsing; this type owns only bounded process,
/// pipe, and cleanup semantics.
enum BoundedChildProcess {
    struct Result {
        var output: Data
        let exitCode: Int32?
        let timedOut: Bool
        let exceededOutputLimit: Bool
    }

    private struct SpawnedProcess {
        let pid: pid_t
        let outputDescriptor: Int32
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        outputLimit: Int,
        timeout: TimeInterval,
        terminationGrace: TimeInterval = 0.25
    ) -> Result? {
        guard executableURL.isFileURL,
              executableURL.path.hasPrefix("/"),
              isSafeProcessString(executableURL.path, maximumBytes: 4_096),
              arguments.count <= 64,
              arguments.allSatisfy({ isSafeProcessString($0, maximumBytes: 4_096) }),
              environment.count <= 64,
              environment.allSatisfy({ key, value in
                  isSafeEnvironmentKey(key)
                      && isSafeProcessString(value, maximumBytes: 4_096)
              }),
              1...(2 * 1_024 * 1_024) ~= outputLimit,
              timeout.isFinite,
              0.05...10 ~= timeout,
              terminationGrace.isFinite,
              0.01...1 ~= terminationGrace,
              let spawned = spawn(
                  executablePath: executableURL.path,
                  arguments: arguments,
                  environment: environment
              )
        else { return nil }

        let descriptor = spawned.outputDescriptor
        defer { Darwin.close(descriptor) }
        let existingFlags = Darwin.fcntl(descriptor, F_GETFL)
        guard existingFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, existingFlags | O_NONBLOCK) == 0
        else {
            signalProcessGroup(spawned.pid, signal: SIGKILL)
            reap(spawned.pid)
            return nil
        }

        var output = Data()
        var exceededOutputLimit = false
        var readFailed = false
        var buffer = [UInt8](repeating: 0, count: 4 * 1_024)
        defer {
            erase(&buffer)
            if readFailed {
                erase(&output)
            }
        }

        func drainAvailableOutput() {
            while !readFailed, !exceededOutputLimit {
                let byteCount = buffer.withUnsafeMutableBytes { rawBuffer in
                    Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
                }
                if byteCount > 0 {
                    if output.count + byteCount <= outputLimit {
                        output.append(contentsOf: buffer.prefix(byteCount))
                    } else {
                        exceededOutputLimit = true
                        erase(&output)
                    }
                    buffer.withUnsafeMutableBytes { rawBuffer in
                        if let address = rawBuffer.baseAddress {
                            Darwin.memset(address, 0, byteCount)
                        }
                    }
                    continue
                }
                if byteCount == 0 { return }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                readFailed = true
            }
        }

        let timeoutNanoseconds = UInt64(timeout * 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var status: Int32 = 0
        var didExit = false
        var timedOut = false

        while !didExit, !readFailed, !exceededOutputLimit {
            drainAvailableOutput()
            if readFailed || exceededOutputLimit { break }

            let waitResult = Darwin.waitpid(spawned.pid, &status, WNOHANG)
            if waitResult == spawned.pid {
                didExit = true
                break
            }
            if waitResult < 0, errno != EINTR {
                readFailed = true
                break
            }

            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadline {
                timedOut = true
                break
            }
            let remainingMilliseconds = max(
                1,
                min(10, Int((deadline - now) / 1_000_000))
            )
            var pollDescriptor = pollfd(
                fd: descriptor,
                events: Int16(POLLIN | POLLHUP),
                revents: 0
            )
            let pollResult = Darwin.poll(
                &pollDescriptor,
                1,
                Int32(remainingMilliseconds)
            )
            if pollResult < 0, errno != EINTR {
                readFailed = true
            }
        }

        if timedOut || exceededOutputLimit || readFailed {
            signalProcessGroup(spawned.pid, signal: SIGTERM)
            let graceNanoseconds = UInt64(terminationGrace * 1_000_000_000)
            let graceDeadline = DispatchTime.now().uptimeNanoseconds + graceNanoseconds
            while !didExit, DispatchTime.now().uptimeNanoseconds < graceDeadline {
                drainAvailableOutput()
                let waitResult = Darwin.waitpid(spawned.pid, &status, WNOHANG)
                if waitResult == spawned.pid {
                    didExit = true
                    break
                }
                if waitResult < 0, errno != EINTR { break }
                Darwin.usleep(5_000)
            }
            if !didExit {
                signalProcessGroup(spawned.pid, signal: SIGKILL)
                reap(spawned.pid, status: &status)
                didExit = true
            }
        }

        drainAvailableOutput()
        guard didExit, !readFailed else { return nil }
        // A helper is not allowed to daemonize work behind Dev Island. The
        // process-group ID cannot disappear while a descendant still belongs
        // to it, so this is a no-op for an ordinary completed command and
        // closes any background child that inherited the pipe.
        signalProcessGroup(spawned.pid, signal: SIGKILL)
        let exitedNormally = (status & 0x7F) == 0
        let exitCode = exitedNormally ? (status >> 8) & 0xFF : nil
        return Result(
            output: output,
            exitCode: exitCode,
            timedOut: timedOut,
            exceededOutputLimit: exceededOutputLimit
        )
    }

    private static func spawn(
        executablePath: String,
        arguments: [String],
        environment: [String: String]
    ) -> SpawnedProcess? {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&descriptors) == 0 else { return nil }
        var readDescriptor = descriptors[0]
        var writeDescriptor = descriptors[1]
        var nullDescriptor = Darwin.open("/dev/null", O_RDWR | O_CLOEXEC)
        defer {
            if readDescriptor >= 0 { Darwin.close(readDescriptor) }
            if writeDescriptor >= 0 { Darwin.close(writeDescriptor) }
            if nullDescriptor >= 0 { Darwin.close(nullDescriptor) }
        }
        guard nullDescriptor >= 0 else { return nil }

        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        guard posix_spawn_file_actions_adddup2(
            &fileActions,
            nullDescriptor,
            STDIN_FILENO
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            writeDescriptor,
            STDOUT_FILENO
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            nullDescriptor,
            STDERR_FILENO
        ) == 0,
        posix_spawn_file_actions_addclose(&fileActions, readDescriptor) == 0,
        posix_spawn_file_actions_addclose(&fileActions, writeDescriptor) == 0,
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

        Darwin.close(writeDescriptor)
        writeDescriptor = -1
        Darwin.close(nullDescriptor)
        nullDescriptor = -1
        let result = SpawnedProcess(
            pid: pid,
            outputDescriptor: readDescriptor
        )
        readDescriptor = -1
        return result
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

    private static func signalProcessGroup(_ pid: pid_t, signal: Int32) {
        if Darwin.kill(-pid, signal) != 0 {
            _ = Darwin.kill(pid, signal)
        }
    }

    private static func reap(_ pid: pid_t) {
        var status: Int32 = 0
        reap(pid, status: &status)
    }

    private static func reap(_ pid: pid_t, status: inout Int32) {
        while Darwin.waitpid(pid, &status, 0) < 0, errno == EINTR {}
    }

    private static func erase(_ data: inout Data) {
        data.resetBytes(in: data.indices)
        data.removeAll(keepingCapacity: false)
    }

    private static func erase(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { rawBuffer in
            if let address = rawBuffer.baseAddress {
                Darwin.memset(address, 0, rawBuffer.count)
            }
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
}
