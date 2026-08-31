import Darwin
import Dispatch
import Foundation
import IslandCore

// MARK: - Dev-only diagnostic commands
//
// No command is selected by default. In particular, Manus networking can be
// reached only through the explicit `manus-live-acceptance` subcommand.

private enum CLIExit {
    static let success: Int32 = 0
    static let failure: Int32 = 1
    static let manualReview: Int32 = 2
    static let usage: Int32 = 64
    static let interrupted: Int32 = 130
}

private func printUsage() {
    print("Dev Island diagnostic CLI")
    print("Usage:")
    print("  IslandCoreCLI local-hook-status")
    print("  IslandCoreCLI local-live-readiness")
    print("  IslandCoreCLI local-hermetic-listener-check")
    print("  IslandCoreCLI local-usage")
    print("  IslandCoreCLI local-hooks")
    print("  IslandCoreCLI manus-live-acceptance --journal ABSOLUTE_PATH [--timeout 60...1800]")
    print("  IslandCoreCLI manus-live-acceptance-recover --journal ABSOLUTE_PATH")
    print("")
    print("The Manus command requires an interactive TTY and never reads a key from the environment.")
}

private func runHermeticLocalListenerCheck() -> Never {
    setvbuf(stdout, nil, _IONBF, 0)
    Task {
        print("[CLI] Hermetic local listener check")
        let state = await HermeticLocalListenerReadinessHarness().run()
        print("[CLI] listener=\(state.rawValue)")
        print("[CLI] authorization=memory-only")
        print("[CLI] agent-routes=disabled")
        print("[CLI] result=\(state == .verified ? "verified" : "unavailable")")
        exit(state == .verified ? CLIExit.success : CLIExit.failure)
    }
    RunLoop.main.run()
    fatalError("RunLoop exited unexpectedly")
}

private func runLocalLiveReadiness() -> Never {
    setvbuf(stdout, nil, _IONBF, 0)
    Task {
        let snapshot = await LocalLiveReadinessProbe().snapshot()
        print("[CLI] Local live readiness")
        print("[CLI] listener=\(snapshot.listener.rawValue)")
        for agent in snapshot.agents {
            print(
                "[CLI] \(agent.source) cli=\(agent.cli.rawValue) "
                    + "hook=\(agent.hook.rawValue) activation=\(agent.activation.rawValue)"
            )
        }
        print(
            "[CLI] ready-agents=\(snapshot.readyAgentCount)/\(snapshot.agents.count) "
                + "result=\(snapshot.isReady ? "ready-for-live-acceptance" : "needs-user-action")"
        )

        if snapshot.listener != .listening {
            print("[CLI] action=open-dev-island")
        }
        for agent in snapshot.agents {
            switch agent.cli {
            case .verified:
                break
            case .reviewRequired:
                print("[CLI] action=review-\(agent.source)-version")
            case .checkFailed:
                print("[CLI] action=check-\(agent.source)-version-again")
            case .unavailable:
                print("[CLI] action=install-\(agent.source)")
            }
            switch agent.hook {
            case .connected:
                break
            case .configured where agent.source == "codex":
                print("[CLI] action=review-codex-hooks")
            case .configured:
                print("[CLI] action=confirm-\(agent.source)-activation")
            case .updateRequired:
                print("[CLI] action=update-\(agent.source)-hooks-in-settings")
            case .disconnected:
                print("[CLI] action=connect-\(agent.source)-in-settings")
            }
            if snapshot.listener == .listening, agent.isReady {
                print("[CLI] action=run-real-\(agent.source)-session")
            }
        }
        exit(snapshot.isReady ? CLIExit.success : CLIExit.manualReview)
    }
    RunLoop.main.run()
    fatalError("RunLoop exited unexpectedly")
}

private func runLocalHookStatus() -> Int32 {
    let snapshot = LocalAgentHookDiagnostics.snapshotResolvingVendorActivation()
    print("[CLI] Local Agent Hook status")
    for agent in snapshot.agents {
        print("[CLI] \(agent.source)=\(agent.state.rawValue)")
    }
    print(
        "[CLI] connected=\(snapshot.connectedCount) "
            + "configured=\(snapshot.configuredCount) "
            + "update-required=\(snapshot.updateRequiredCount) "
            + "disconnected=\(snapshot.disconnectedCount)"
    )
    return CLIExit.success
}

private func runLocalUsage() -> Int32 {
    do {
        guard let snapshot = try CodexLocalUsageReader().latestSnapshot() else {
            print("[CLI] No valid local Codex usage snapshot found")
            return CLIExit.success
        }
        print("[CLI] provider=\(snapshot.provider.rawValue) observed=\(snapshot.observedAt.ISO8601Format())")
        for window in snapshot.windows {
            let reset = window.resetsAt?.ISO8601Format() ?? "unknown"
            print("[CLI] \(window.kind.rawValue) used=\(window.usedPercent)% window=\(window.durationMinutes)m reset=\(reset)")
        }
        return CLIExit.success
    } catch {
        print("[CLI] Local usage unavailable")
        return CLIExit.failure
    }
}

private func runLocalHooks() -> Never {
    setvbuf(stdout, nil, _IONBF, 0)
    print("[CLI] Local hooks mode")
    print("[CLI] Listening on loopback for registered local Agents")
    print("[CLI] Waiting for events (Ctrl+C to stop)")

    let connectors = Dictionary(uniqueKeysWithValues: LocalAgentRegistry.all.map {
        ($0.source, LocalAgentConnector(descriptor: $0))
    })
    let server = LocalHookServer()

    @Sendable func report(_ source: String, _ snapshot: [AgentTask]) {
        let counts = Dictionary(grouping: snapshot, by: \.status).mapValues(\.count)
        let statuses: [TaskStatus] = [.waiting, .failed, .completed, .running]
        let compact = statuses.compactMap { status -> String? in
            guard let count = counts[status], count > 0 else { return nil }
            return "\(status.rawValue)=\(count)"
        }.joined(separator: " ")
        print("[CLI] event source=\(source) sessions=\(snapshot.count) \(compact)")
    }

    Task {
        await server.start(agents: LocalAgentRegistry.all) { source, event in
            Task {
                guard let connector = connectors[source] else { return }
                let snapshot = await connector.apply(event)
                report(source, snapshot)
            }
        }
    }
    RunLoop.main.run()
    fatalError("RunLoop exited unexpectedly")
}

private struct ManusAcceptanceArguments {
    let journalPath: String
    let timeout: Duration
}

private func parseAcceptanceArguments(
    _ arguments: [String]
) -> ManusAcceptanceArguments? {
    var journalPath: String?
    var timeout: Duration = .seconds(600)
    var sawTimeout = false
    var index = 0
    while index < arguments.count {
        guard index + 1 < arguments.count else { return nil }
        let flag = arguments[index]
        let value = arguments[index + 1]
        switch flag {
        case "--journal" where journalPath == nil && !value.isEmpty:
            journalPath = value
        case "--timeout":
            guard !sawTimeout,
                  let seconds = Int(value),
                  60...1_800 ~= seconds else {
                return nil
            }
            timeout = .seconds(seconds)
            sawTimeout = true
        default:
            return nil
        }
        index += 2
    }
    guard let journalPath else { return nil }
    return ManusAcceptanceArguments(
        journalPath: journalPath,
        timeout: timeout
    )
}

private func parseRecoveryJournalPath(_ arguments: [String]) -> String? {
    guard arguments.count == 2,
          arguments[0] == "--journal",
          !arguments[1].isEmpty else {
        return nil
    }
    return arguments[1]
}

/// `readpassphrase` keeps terminal echo disabled and `RPP_REQUIRE_TTY` rejects
/// pipes, redirected stdin and non-interactive CI. The temporary C buffer is
/// explicitly cleared after validation.
private func readManusCredential() -> String? {
    var buffer = [CChar](
        repeating: 0,
        count: ManusLiveAcceptanceCredential.maximumLength + 2
    )
    defer {
        _ = buffer.withUnsafeMutableBytes { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
        }
    }

    let result = buffer.withUnsafeMutableBufferPointer { pointer in
        readpassphrase(
            "Manus API key: ",
            pointer.baseAddress,
            pointer.count,
            RPP_REQUIRE_TTY
        )
    }
    guard result != nil else { return nil }
    let candidate = String(cString: buffer)
    return ManusLiveAcceptanceCredential.validated(candidate)
}

private final class CancellationSignalBridge: @unchecked Sendable {
    private let interruptSource: DispatchSourceSignal
    private let terminateSource: DispatchSourceSignal

    init(cancel: @escaping @Sendable () -> Void) {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        interruptSource.setEventHandler(handler: cancel)
        terminateSource.setEventHandler(handler: cancel)
        interruptSource.resume()
        terminateSource.resume()
    }

    func stop() {
        interruptSource.cancel()
        terminateSource.cancel()
    }
}

private func runManusLiveAcceptance(
    timeout: Duration,
    journalPath: String
) -> Never {
    setvbuf(stdout, nil, _IONBF, 0)
    print("[CLI] Manus v2 live acceptance")
    print("[CLI] This creates a temporary public tunnel and webhook, then removes both.")
    print("[CLI] During the run, create one task that finishes and one task that pauses for input.")
    print("[CLI] Provider identifiers, callback addresses, payload text and raw errors are never printed.")

    guard let journal = try? ManusLiveAcceptanceRecoveryJournal(
        path: journalPath
    ) else {
        print("[CLI] result=journal_rejected")
        exit(CLIExit.usage)
    }

    guard let apiKey = readManusCredential() else {
        print("[CLI] credential_rejected")
        exit(CLIExit.usage)
    }

    let runner = ManusLiveAcceptanceRunner(
        client: ManusAPIClient(apiKey: apiKey),
        journal: journal,
        checkpointHandler: { checkpoint in
            print("[CLI] checkpoint=\(checkpoint.rawValue)")
        }
    )
    let runTask = Task {
        await runner.run(timeout: timeout)
    }
    let signals = CancellationSignalBridge {
        runTask.cancel()
    }

    Task {
        let report = await runTask.value
        signals.stop()

        let exitCode: Int32
        if report.manualWebhookReviewRequired {
            print("[CLI] result=manual_webhook_review_required")
            exitCode = CLIExit.manualReview
        } else {
            switch report.termination {
            case .accepted where report.accepted:
                print("[CLI] result=accepted")
                exitCode = CLIExit.success
            case .accepted:
                print("[CLI] result=incomplete_cleanup")
                exitCode = CLIExit.failure
            case .timedOut:
                print("[CLI] result=timed_out")
                exitCode = CLIExit.failure
            case .cancelled:
                print("[CLI] result=cancelled")
                exitCode = CLIExit.interrupted
            case .failed(let stage):
                print("[CLI] result=failed stage=\(stage.rawValue)")
                exitCode = CLIExit.failure
            }
        }
        exit(exitCode)
    }

    RunLoop.main.run()
    fatalError("RunLoop exited unexpectedly")
}

private func runManusLiveAcceptanceRecovery(journalPath: String) -> Never {
    setvbuf(stdout, nil, _IONBF, 0)
    print("[CLI] Manus v2 live acceptance recovery")
    print("[CLI] This removes only a webhook proven by one explicit private journal.")
    print("[CLI] Provider identifiers, callback addresses and raw errors are never printed.")

    guard let journal = try? ManusLiveAcceptanceRecoveryJournal(
        path: journalPath
    ) else {
        print("[CLI] result=journal_rejected")
        exit(CLIExit.usage)
    }
    guard let apiKey = readManusCredential() else {
        print("[CLI] credential_rejected")
        exit(CLIExit.usage)
    }

    let runner = ManusLiveAcceptanceRecoveryRunner(
        client: ManusAPIClient(apiKey: apiKey),
        journal: journal,
        checkpointHandler: { checkpoint in
            print("[CLI] checkpoint=\(checkpoint.rawValue)")
        }
    )
    let recoveryTask = Task {
        await runner.recover()
    }
    let signals = CancellationSignalBridge {
        recoveryTask.cancel()
    }

    Task {
        let result = await recoveryTask.value
        signals.stop()
        switch result {
        case .recovered:
            print("[CLI] result=recovered")
            exit(CLIExit.success)
        case .noJournal:
            print("[CLI] result=no_recovery_journal")
            exit(CLIExit.failure)
        case .manualReviewRequired:
            print("[CLI] result=manual_webhook_review_required")
            exit(CLIExit.manualReview)
        }
    }

    RunLoop.main.run()
    fatalError("RunLoop exited unexpectedly")
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    printUsage()
    exit(CLIExit.usage)
}

switch command {
case "help", "--help", "-h":
    printUsage()
    exit(CLIExit.success)

case "local-hook-status" where arguments.count == 1:
    exit(runLocalHookStatus())

case "local-live-readiness" where arguments.count == 1:
    runLocalLiveReadiness()

case "local-hermetic-listener-check" where arguments.count == 1:
    runHermeticLocalListenerCheck()

case "local-usage" where arguments.count == 1:
    exit(runLocalUsage())

case "local-hooks" where arguments.count == 1,
     "claude-hooks" where arguments.count == 1:
    runLocalHooks()

case "manus-live-acceptance":
    guard let parsed = parseAcceptanceArguments(
        Array(arguments.dropFirst())
    ) else {
        print("[CLI] invalid_acceptance_arguments")
        printUsage()
        exit(CLIExit.usage)
    }
    runManusLiveAcceptance(
        timeout: parsed.timeout,
        journalPath: parsed.journalPath
    )

case "manus-live-acceptance-recover":
    guard let journalPath = parseRecoveryJournalPath(
        Array(arguments.dropFirst())
    ) else {
        print("[CLI] invalid_recovery_arguments")
        printUsage()
        exit(CLIExit.usage)
    }
    runManusLiveAcceptanceRecovery(journalPath: journalPath)

default:
    print("[CLI] unknown_command")
    printUsage()
    exit(CLIExit.usage)
}
