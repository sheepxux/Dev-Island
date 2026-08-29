import Darwin
import Foundation
import XCTest
@testable import IslandCore

final class LocalHookServerActionTests: XCTestCase {
    func testActionRequestCannotOvertakeEarlierPassiveLifecycleHTTPEvent() async throws {
        let eventProbe = SerializedEventDeliveryProbe()
        let actionProbe = ActionProbe()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.codex],
            onActionRequest: { request in
                await actionProbe.handle(request)
            },
            onEvent: { source, event in
                await eventProbe.handle(source: source, event: event)
            }
        )

        do {
            let readyDeadline = Date().addingTimeInterval(2)
            while await server.statusSnapshot() != .listening && Date() < readyDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let listenerStatus = await server.statusSnapshot()
            XCTAssertEqual(listenerStatus, .listening)

            let passiveResponse = try curlPost(
                port: port,
                source: "codex",
                payload: codexSessionStartPayload(session: "cross-request")
            )
            XCTAssertEqual(passiveResponse, "{}")

            let eventDeadline = Date().addingTimeInterval(1)
            while !(await eventProbe.hasEnteredFirst) && Date() < eventDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            let didEnterFirst = await eventProbe.hasEnteredFirst
            XCTAssertTrue(didEnterFirst)

            let actionResponse = Task {
                try await post(port: port, session: "cross-request")
            }
            try await Task.sleep(for: .milliseconds(30))
            let actionsBeforeRelease = await actionProbe.actionCount
            XCTAssertEqual(actionsBeforeRelease, 0)

            await eventProbe.releaseFirst()
            let actionResponseBody = try await actionResponse.value
            XCTAssertEqual(
                actionResponseBody,
                CodexPermissionHook.response(for: .allow)
            )

            let deliveryDeadline = Date().addingTimeInterval(1)
            while await eventProbe.deliveredCount < 2 && Date() < deliveryDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            let delivered = await eventProbe.deliveredEvents
            XCTAssertEqual(delivered.map(\.event.sessionId), ["cross-request", "cross-request"])
            XCTAssertEqual(delivered.map(\.event.action), [
                .running,
                .waiting(
                    phase: "Needs approval",
                    message: "Approval needed: Bash"
                ),
            ])
            let maximumConcurrentDeliveries = await eventProbe.maximumConcurrentDeliveries
            XCTAssertEqual(maximumConcurrentDeliveries, 1)
            let finalActionCount = await actionProbe.actionCount
            XCTAssertEqual(finalActionCount, 1)
        } catch {
            await eventProbe.releaseFirst()
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testDeliveryQueueSerializesAndCoalescesPendingPassiveSessionState() async throws {
        let eventProbe = SerializedEventDeliveryProbe()
        let delivery = LocalHookEventDelivery(
            maximumQueuedEventsPerSource: 3,
            onEvent: { source, event in
                await eventProbe.handle(source: source, event: event)
            },
            isLive: { true }
        )

        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "first", action: .running)
        )
        let firstDeadline = Date().addingTimeInterval(1)
        while !(await eventProbe.hasEnteredFirst) && Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "second", action: .running)
        )
        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(
                sessionId: "second",
                action: .completed(phase: nil)
            )
        )
        let queuedCount = await delivery.queuedEventCount(source: "codex")
        XCTAssertEqual(queuedCount, 1)

        await eventProbe.releaseFirst()
        let deliveryDeadline = Date().addingTimeInterval(1)
        while await eventProbe.deliveredCount < 2 && Date() < deliveryDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let delivered = await eventProbe.deliveredEvents
        XCTAssertEqual(delivered.map(\.event.sessionId), ["first", "second"])
        XCTAssertEqual(delivered.map(\.event.action), [
            .running,
            .completed(phase: nil),
        ])
        let maximumConcurrentDeliveries = await eventProbe.maximumConcurrentDeliveries
        XCTAssertEqual(maximumConcurrentDeliveries, 1)
    }

    func testDeliveryQueueKeepsAgentSourcesIndependent() async throws {
        let eventProbe = SerializedEventDeliveryProbe()
        let delivery = LocalHookEventDelivery(
            maximumQueuedEventsPerSource: 2,
            onEvent: { source, event in
                await eventProbe.handle(source: source, event: event)
            },
            isLive: { true }
        )

        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "codex-held", action: .running)
        )
        let firstDeadline = Date().addingTimeInterval(1)
        while !(await eventProbe.hasEnteredFirst) && Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        await delivery.enqueuePassive(
            source: "claude-code",
            event: LocalAgentEvent(sessionId: "claude-free", action: .running)
        )

        let deliveryDeadline = Date().addingTimeInterval(1)
        while await eventProbe.deliveredCount < 2 && Date() < deliveryDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let deliveredBeforeRelease = await eventProbe.deliveredEvents
        XCTAssertEqual(deliveredBeforeRelease.map(\.source), ["codex", "claude-code"])
        let maximumConcurrentDeliveries = await eventProbe.maximumConcurrentDeliveries
        XCTAssertEqual(maximumConcurrentDeliveries, 2)
        await eventProbe.releaseFirst()
    }

    func testDeliveryQueueBoundsPassiveFloodAndPreservesActionBarrier() async throws {
        let eventProbe = SerializedEventDeliveryProbe()
        let delivery = LocalHookEventDelivery(
            maximumQueuedEventsPerSource: 2,
            onEvent: { source, event in
                await eventProbe.handle(source: source, event: event)
            },
            isLive: { true }
        )

        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "in-flight", action: .running)
        )
        let firstDeadline = Date().addingTimeInterval(1)
        while !(await eventProbe.hasEnteredFirst) && Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "evicted", action: .running)
        )
        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "retained", action: .running)
        )
        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "dropped", action: .running)
        )

        async let actionWasDelivered = delivery.deliverBeforeAction(
            source: "codex",
            event: LocalAgentEvent(
                sessionId: "action",
                action: .waiting(phase: "Needs approval", message: nil)
            )
        )
        let barrierDeadline = Date().addingTimeInterval(1)
        while await delivery.queuedActionBarrierCount(source: "codex") == 0
            && Date() < barrierDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let boundedCount = await delivery.queuedEventCount(source: "codex")
        let barrierCount = await delivery.queuedActionBarrierCount(source: "codex")
        XCTAssertEqual(boundedCount, 2)
        XCTAssertEqual(barrierCount, 1)

        await eventProbe.releaseFirst()
        let didDeliverAction = await actionWasDelivered
        XCTAssertTrue(didDeliverAction)
        let deliveryDeadline = Date().addingTimeInterval(1)
        while await eventProbe.deliveredCount < 3 && Date() < deliveryDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let delivered = await eventProbe.deliveredEvents
        XCTAssertEqual(delivered.map(\.event.sessionId), [
            "in-flight", "retained", "action",
        ])
        let maximumConcurrentDeliveries = await eventProbe.maximumConcurrentDeliveries
        XCTAssertEqual(maximumConcurrentDeliveries, 1)
    }

    func testDeliveryQueueFailsNeutralWhenCapacityContainsOnlyActions() async throws {
        let eventProbe = SerializedEventDeliveryProbe()
        let delivery = LocalHookEventDelivery(
            maximumQueuedEventsPerSource: 1,
            onEvent: { source, event in
                await eventProbe.handle(source: source, event: event)
            },
            isLive: { true }
        )

        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "in-flight", action: .running)
        )
        let firstDeadline = Date().addingTimeInterval(1)
        while !(await eventProbe.hasEnteredFirst) && Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        async let firstAction = delivery.deliverBeforeAction(
            source: "codex",
            event: LocalAgentEvent(
                sessionId: "action-one",
                action: .waiting(phase: "Needs approval", message: nil)
            )
        )
        let barrierDeadline = Date().addingTimeInterval(1)
        while await delivery.queuedActionBarrierCount(source: "codex") == 0
            && Date() < barrierDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        let secondAction = await delivery.deliverBeforeAction(
            source: "codex",
            event: LocalAgentEvent(
                sessionId: "action-two",
                action: .waiting(phase: "Needs approval", message: nil)
            )
        )
        XCTAssertFalse(secondAction)
        let boundedCount = await delivery.queuedEventCount(source: "codex")
        XCTAssertEqual(boundedCount, 1)

        await eventProbe.releaseFirst()
        let firstActionResult = await firstAction
        XCTAssertTrue(firstActionResult)
        let deliveryDeadline = Date().addingTimeInterval(1)
        while await eventProbe.deliveredCount < 2 && Date() < deliveryDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let delivered = await eventProbe.deliveredEvents
        XCTAssertEqual(delivered.map(\.event.sessionId), ["in-flight", "action-one"])
    }

    func testDeliveryQueueRejectsQueuedWorkAfterListenerEpochExpires() async throws {
        let eventProbe = SerializedEventDeliveryProbe()
        let liveness = DeliveryLivenessProbe()
        let delivery = LocalHookEventDelivery(
            maximumQueuedEventsPerSource: 2,
            onEvent: { source, event in
                await eventProbe.handle(source: source, event: event)
            },
            isLive: { await liveness.value }
        )

        await delivery.enqueuePassive(
            source: "codex",
            event: LocalAgentEvent(sessionId: "in-flight", action: .running)
        )
        let firstDeadline = Date().addingTimeInterval(1)
        while !(await eventProbe.hasEnteredFirst) && Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        async let staleAction = delivery.deliverBeforeAction(
            source: "codex",
            event: LocalAgentEvent(
                sessionId: "stale-action",
                action: .waiting(phase: "Needs approval", message: nil)
            )
        )
        let barrierDeadline = Date().addingTimeInterval(1)
        while await delivery.queuedActionBarrierCount(source: "codex") == 0
            && Date() < barrierDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        await liveness.expire()
        await eventProbe.releaseFirst()
        let staleActionResult = await staleAction
        XCTAssertFalse(staleActionResult)
        try await Task.sleep(for: .milliseconds(10))
        let delivered = await eventProbe.deliveredEvents
        XCTAssertEqual(delivered.map(\.event.sessionId), ["in-flight"])
        let remainingCount = await delivery.queuedEventCount(source: "codex")
        XCTAssertEqual(remainingCount, 0)
    }

    func testPassiveLifecycleResponseDoesNotWaitForEventPersistence() async throws {
        let descriptor = LocalAgentDescriptor(
            source: "passive-fixture",
            displayName: "Passive Fixture",
            settingsSubtitle: "Test only",
            configPath: "/tmp/dev-island-passive-fixture.json",
            hookEvents: ["SessionStart"],
            hookEntryStyle: .nested,
            appCandidates: [],
            usesTerminalFallback: false,
            capabilities: AgentCapabilities(),
            decodeEvent: { _ in
                LocalAgentEvent(
                    sessionId: "passive-session",
                    action: .running
                )
            }
        )
        let orderingGate = LocalEventOrderingGate()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [descriptor],
            onEvent: { _, _ in
                // Model a slow MainActor/SQLite delivery. The passive Hook
                // must already have received its neutral response.
                await orderingGate.hold()
            }
        )

        do {
            let readyDeadline = Date().addingTimeInterval(2)
            while await server.statusSnapshot() != .listening && Date() < readyDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let listenerStatus = await server.statusSnapshot()
            XCTAssertEqual(listenerStatus, .listening)

            let url = try XCTUnwrap(URL(
                string: "http://127.0.0.1:\(port)/hooks/\(descriptor.source)"
            ))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 0.5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(
                LocalHooksInstaller.requestHeaderValue,
                forHTTPHeaderField: LocalHooksInstaller.requestHeaderName
            )
            request.setValue(
                localHookTestAuthorization.headerValue,
                forHTTPHeaderField: LocalHookAuthorization.headerName
            )
            request.httpBody = Data("{}".utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}")

            let eventDeadline = Date().addingTimeInterval(1)
            while !(await orderingGate.hasEntered) && Date() < eventDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            let didEnterLifecycleHandler = await orderingGate.hasEntered
            XCTAssertTrue(didEnterLifecycleHandler)
            await orderingGate.release()
        } catch {
            await orderingGate.release()
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testRouteRejectsMismatchedActionIdentityBeforeCallback() async throws {
        let deliveredEvents = LocalEventProbe()
        let descriptor = LocalAgentDescriptor(
            source: "identity-fixture",
            displayName: "Identity Fixture",
            settingsSubtitle: "Test only",
            configPath: "/tmp/dev-island-identity-fixture.json",
            hookEvents: ["PermissionRequest"],
            hookEntryStyle: .nested,
            appCandidates: [],
            usesTerminalFallback: false,
            capabilities: AgentCapabilities(permissionRequests: .bidirectional),
            actionHookEvents: ["PermissionRequest"],
            decodeActionRequest: { _ in
                AgentActionRequest(
                    source: "codex",
                    sessionId: "action-session",
                    kind: .permission,
                    title: "Mismatched source",
                    message: "Must be rejected"
                )
            },
            encodeActionResponse: { _ in "unexpected" },
            decodeEvent: { _ in
                LocalAgentEvent(
                    sessionId: "event-session",
                    action: .waiting(phase: "Needs approval", message: nil)
                )
            }
        )
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [descriptor],
            onActionRequest: { _ in
                XCTFail("A mismatched descriptor action must not reach TaskStore")
                return .permission(.allow)
            },
            onEvent: { source, event in
                await deliveredEvents.record(source: source, event: event)
            }
        )

        do {
            let deadline = Date().addingTimeInterval(2)
            var response: String?
            repeat {
                do {
                    response = try curlPost(
                        port: port,
                        source: descriptor.source,
                        payload: Data("{}".utf8)
                    )
                } catch {
                    try await Task.sleep(for: .milliseconds(20))
                }
            } while response == nil && Date() < deadline
            XCTAssertEqual(response, "{}")
            try await Task.sleep(for: .milliseconds(20))
            let deliveredEventCount = await deliveredEvents.count
            XCTAssertEqual(deliveredEventCount, 0)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    @MainActor
    func testSynchronousActionCommitsWaitingEventBeforeQueueAndReturnsDecisionEndToEnd() async throws {
        let store = TaskStore.mock(tasks: [])
        let connector = LocalAgentConnector(descriptor: .codex)
        let orderingGate = LocalEventOrderingGate()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.codex],
            onActionRequest: { request in
                await store.awaitActionResponse(for: request)
            },
            onEvent: { source, event in
                // Hold the lifecycle half of this same HTTP request. The
                // actionable half must not reach TaskStore until this gate is
                // released and the Waiting snapshot has been committed.
                await orderingGate.hold()
                let snapshot = await connector.apply(event)
                await store.applyLocalSnapshot(source: source, snapshot)
            }
        )

        do {
            let readyDeadline = Date().addingTimeInterval(2)
            while await server.statusSnapshot() != .listening && Date() < readyDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let listenerStatus = await server.statusSnapshot()
            XCTAssertEqual(listenerStatus, .listening)

            let responseTask = Task {
                try await post(port: port, session: "ordered-session")
            }
            let eventDeadline = Date().addingTimeInterval(1)
            while !(await orderingGate.hasEntered) && Date() < eventDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            let didEnterLifecycleHandler = await orderingGate.hasEntered
            XCTAssertTrue(didEnterLifecycleHandler)
            XCTAssertTrue(store.pendingActionRequests.isEmpty)
            XCTAssertTrue(store.tasks.isEmpty)

            await orderingGate.release()
            let actionDeadline = Date().addingTimeInterval(1)
            while store.pendingActionRequests.isEmpty && Date() < actionDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }

            let request = try XCTUnwrap(store.pendingActionRequests.first)
            XCTAssertEqual(request.sessionId, "ordered-session")
            XCTAssertEqual(store.tasks.first?.identity, request.taskIdentity)
            XCTAssertEqual(store.tasks.first?.status, .waiting)
            XCTAssertTrue(store.respond(to: request.id, decision: .allow))

            let response = try await responseTask.value
            XCTAssertEqual(response, CodexPermissionHook.response(for: .allow))
            XCTAssertTrue(store.pendingActionRequests.isEmpty)
            XCTAssertEqual(store.tasks.first?.status, .running)
            XCTAssertNil(store.tasks.first?.waitingMessage)
        } catch {
            await orderingGate.release()
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testManagedHookCommandCarriesValidatedTerminalContextEndToEnd() async throws {
        let probe = LocalEventProbe()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.geminiCLI],
            onEvent: { source, event in
                Task { await probe.record(source: source, event: event) }
            }
        )

        do {
            let deadline = Date().addingTimeInterval(2)
            while await server.statusSnapshot() != .listening && Date() < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let listenerStatus = await server.statusSnapshot()
            XCTAssertEqual(listenerStatus, .listening)

            try runManagedHookCommand(
                LocalHooksInstaller(.geminiCLI).hookCommand(port: port),
                payload: geminiPermissionPayload(),
                environment: [
                    "__CFBundleIdentifier": "com.github.wez.wezterm",
                    "TERM_PROGRAM": "WezTerm",
                    "TMUX": "/private/tmp/tmux-501/default,77,0",
                    "TMUX_PANE": "%9",
                ]
            )

            while await probe.count == 0 && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let last = await probe.last
            let delivered = try XCTUnwrap(last)
            XCTAssertEqual(delivered.source, "gemini-cli")
            XCTAssertEqual(delivered.event.jumpContext?.terminalBundleIdentifier, "com.github.wez.wezterm")
            XCTAssertEqual(delivered.event.jumpContext?.terminalProgram, "WezTerm")
            XCTAssertEqual(delivered.event.jumpContext?.tmuxSocketPath, "/private/tmp/tmux-501/default")
            XCTAssertEqual(delivered.event.jumpContext?.tmuxPane, "%9")
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testGeminiPreviewHTTPRouteDeliversObserveOnlyWaitingEvent() async throws {
        let probe = LocalEventProbe()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.geminiCLI],
            onActionRequest: { _ in
                XCTFail("Gemini preview must never create an actionable approval request")
                return nil
            },
            onEvent: { source, event in
                Task { await probe.record(source: source, event: event) }
            }
        )

        do {
            let deadline = Date().addingTimeInterval(2)
            var response: String?
            repeat {
                do {
                    response = try curlPost(
                        port: port,
                        source: "gemini-cli",
                        payload: geminiPermissionPayload(),
                        headers: [
                            "X-Dev-Island-Terminal-Bundle": "com.mitchellh.ghostty",
                            "X-Dev-Island-Terminal-Program": "ghostty",
                            "X-Dev-Island-TTY": "ttys009",
                            "X-Dev-Island-Tmux": "/private/tmp/tmux-501/default,44,0",
                            "X-Dev-Island-Tmux-Pane": "%6",
                        ]
                    )
                } catch {
                    try await Task.sleep(for: .milliseconds(20))
                }
            } while response == nil && Date() < deadline
            XCTAssertEqual(response, "{}")

            while await probe.count == 0 && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let last = await probe.last
            let delivered = try XCTUnwrap(last)
            XCTAssertEqual(delivered.source, "gemini-cli")
            XCTAssertEqual(delivered.event.sessionId, "gemini-http")
            XCTAssertEqual(
                delivered.event.action,
                .waiting(phase: "Needs approval", message: "Approve pwd?")
            )
            XCTAssertEqual(
                delivered.event.jumpContext,
                SessionJumpContext(
                    terminalBundleIdentifier: "com.mitchellh.ghostty",
                    terminalProgram: "ghostty",
                    tty: "ttys009",
                    tmuxEnvironment: "/private/tmp/tmux-501/default,44,0",
                    tmuxPane: "%6"
                )
            )
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testCopilotPreviewManagedCommandDeliversPrivacyMinimalWaitingEvent() async throws {
        let probe = LocalEventProbe()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.copilotCLI],
            onActionRequest: { _ in
                XCTFail("Copilot Preview must not create an action without a pinned request schema")
                return nil
            },
            onEvent: { source, event in
                Task { await probe.record(source: source, event: event) }
            }
        )

        do {
            let deadline = Date().addingTimeInterval(2)
            while await server.statusSnapshot() != .listening && Date() < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let listenerStatus = await server.statusSnapshot()
            XCTAssertEqual(listenerStatus, .listening)

            try runManagedHookCommand(
                LocalHooksInstaller(.copilotCLI).hookCommand(port: port),
                payload: copilotPermissionNotificationPayload(),
                environment: [
                    "TERM_PROGRAM": "Apple_Terminal",
                    "TMUX": "/private/tmp/tmux-501/default,21,0",
                    "TMUX_PANE": "%3",
                ]
            )

            while await probe.count == 0 && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let last = await probe.last
            let delivered = try XCTUnwrap(last)
            XCTAssertEqual(delivered.source, "copilot-cli")
            XCTAssertEqual(delivered.event.sessionId, "copilot-http")
            XCTAssertEqual(
                delivered.event.action,
                .waiting(
                    phase: "Needs approval",
                    message: "Approval needed in Copilot CLI"
                )
            )
            XCTAssertEqual(delivered.event.jumpContext?.terminalProgram, "Apple_Terminal")
            XCTAssertEqual(delivered.event.jumpContext?.tmuxPane, "%3")
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testKimiCodePreviewManagedCommandDeliversObserveOnlyWaitingEvent() async throws {
        let probe = LocalEventProbe()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.kimiCode],
            onActionRequest: { _ in
                XCTFail("Kimi Code Preview permission Hooks are observe-only")
                return nil
            },
            onEvent: { source, event in
                Task { await probe.record(source: source, event: event) }
            }
        )

        do {
            let deadline = Date().addingTimeInterval(2)
            while await server.statusSnapshot() != .listening && Date() < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let listenerStatus = await server.statusSnapshot()
            XCTAssertEqual(listenerStatus, .listening)

            try runManagedHookCommand(
                LocalHooksInstaller(.kimiCode).hookCommand(port: port),
                payload: kimiPermissionRequestPayload(),
                environment: [
                    "__CFBundleIdentifier": "com.mitchellh.ghostty",
                    "TERM_PROGRAM": "ghostty",
                    "TMUX": "/private/tmp/tmux-501/default,29,0",
                    "TMUX_PANE": "%7",
                ]
            )

            while await probe.count == 0 && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let last = await probe.last
            let delivered = try XCTUnwrap(last)
            XCTAssertEqual(delivered.source, "kimi-code")
            XCTAssertEqual(delivered.event.sessionId, "kimi-http")
            XCTAssertEqual(
                delivered.event.action,
                .waiting(
                    phase: "Needs approval",
                    message: "Approval needed in Kimi Code CLI"
                )
            )
            XCTAssertEqual(delivered.event.jumpContext?.terminalProgram, "ghostty")
            XCTAssertEqual(delivered.event.jumpContext?.tmuxSocketPath, "/private/tmp/tmux-501/default")
            XCTAssertEqual(delivered.event.jumpContext?.tmuxPane, "%7")
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testOpenCodePreviewHTTPRouteDeliversPrivacyMinimalWaitingEvent() async throws {
        let probe = LocalEventProbe()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.openCode],
            onActionRequest: { _ in
                XCTFail("OpenCode Preview permission events are observe-only")
                return nil
            },
            onEvent: { source, event in
                Task { await probe.record(source: source, event: event) }
            }
        )

        do {
            let deadline = Date().addingTimeInterval(2)
            var response: String?
            repeat {
                do {
                    response = try curlPost(
                        port: port,
                        source: "opencode",
                        payload: openCodePermissionPayload()
                    )
                } catch {
                    try await Task.sleep(for: .milliseconds(20))
                }
            } while response == nil && Date() < deadline
            XCTAssertEqual(response, "{}")

            while await probe.count == 0 && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let last = await probe.last
            let delivered = try XCTUnwrap(last)
            XCTAssertEqual(delivered.source, "opencode")
            XCTAssertEqual(delivered.event.sessionId, "opencode-http")
            XCTAssertEqual(delivered.event.cwd, "/tmp/opencode-http")
            XCTAssertEqual(
                delivered.event.action,
                .waiting(
                    phase: "Needs approval",
                    message: "Approval needed in OpenCode"
                )
            )
            XCTAssertNil(delivered.event.jumpContext)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testQwenPreviewPermissionRoundTripUsesVendorDecisionShape() async throws {
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.qwenCode],
            onActionRequest: { request in
                XCTAssertEqual(request.source, "qwen-code")
                XCTAssertEqual(request.sessionId, "qwen-http")
                return .permission(.allow)
            },
            onEvent: { source, event in
                XCTAssertEqual(source, "qwen-code")
                XCTAssertEqual(event.action, .waiting(
                    phase: "Needs approval",
                    message: "Approval needed: run_shell_command"
                ))
            }
        )

        do {
            let deadline = Date().addingTimeInterval(2)
            var response: String?
            repeat {
                do {
                    response = try curlPost(
                        port: port,
                        source: "qwen-code",
                        payload: qwenPermissionPayload()
                    )
                } catch {
                    try await Task.sleep(for: .milliseconds(20))
                }
            } while response == nil && Date() < deadline

            XCTAssertEqual(response, QwenPermissionHook.response(for: .allow))
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testAskUserQuestionHTTPRoundTripReturnsUpdatedInput() async throws {
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.claudeCode],
            onActionRequest: { request in
                guard request.kind == .question else { return nil }
                return .question(AgentQuestionSubmission(
                    questions: request.questions,
                    answers: request.questions.map { question in
                        AgentQuestionAnswer(
                            question: question.question,
                            selectedLabels: [question.options[0].label]
                        )
                    }
                ))
            },
            onEvent: { _, _ in }
        )

        do {
            let response = try await postQuestionUntilServerIsReady(port: port)
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(
                with: Data(response.utf8)
            ) as? [String: Any])
            let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
            XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
            XCTAssertEqual(output["permissionDecision"] as? String, "allow")
            let input = try XCTUnwrap(output["updatedInput"] as? [String: Any])
            let answers = try XCTUnwrap(input["answers"] as? [String: String])
            XCTAssertEqual(answers["Choose a mode"], "Safe")
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testExitPlanModeHTTPRoundTripPreservesInjectedInput() async throws {
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)
        await server.start(
            agents: [.claudeCode],
            onActionRequest: { request in
                guard request.kind == .planReview,
                      let review = request.planReview else { return nil }
                return .planReview(.allow, review)
            },
            onEvent: { _, _ in }
        )

        do {
            let deadline = Date().addingTimeInterval(2)
            var response: String?
            repeat {
                do {
                    response = try curlPost(
                        port: port,
                        source: "claude-code",
                        payload: planPayload()
                    )
                } catch {
                    try await Task.sleep(for: .milliseconds(20))
                }
            } while response == nil && Date() < deadline

            let body = try XCTUnwrap(response)
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(
                with: Data(body.utf8)
            ) as? [String: Any])
            let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
            XCTAssertEqual(output["permissionDecision"] as? String, "allow")
            let input = try XCTUnwrap(output["updatedInput"] as? [String: Any])
            XCTAssertEqual(input["plan"] as? String, "# Plan\n\n- Update the island")
            XCTAssertEqual(input["planFilePath"] as? String, "/tmp/plan.md")
            XCTAssertEqual(input["futureField"] as? Int, 7)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testListenerRestartRotatesCredentialAndRejectsThePriorEpoch() async throws {
        let authorizationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-hook-rotation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: authorizationRoot) }
        try FileManager.default.createDirectory(
            at: authorizationRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let authorizationFile = authorizationRoot
            .appendingPathComponent("private", isDirectory: true)
            .appendingPathComponent("authorization.header")
        let probe = ActionProbe()
        let port = try availableLoopbackPort()
        let server = LocalHookServer(
            port: port,
            retryPolicy: .production,
            authorizationProvider: {
                try LocalHookAuthorizationStore.rotate(at: authorizationFile)
            }
        )
        await server.start(
            agents: [.codex],
            onActionRequest: { request in await probe.handle(request) },
            onEvent: { _, _ in }
        )

        do {
            let firstReadyDeadline = Date().addingTimeInterval(2)
            while await server.statusSnapshot() != .listening && Date() < firstReadyDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let firstStatus = await server.statusSnapshot()
            XCTAssertEqual(firstStatus, .listening)
            let firstCredential = try authorizationValue(in: authorizationFile)
            let firstBody = try await post(
                port: port,
                session: "first-epoch",
                authorizationHeader: firstCredential
            )
            XCTAssertEqual(firstBody, CodexPermissionHook.response(for: .allow))
            let firstActionCount = await probe.actionCount
            XCTAssertEqual(firstActionCount, 1)

            await server.restart()
            let secondReadyDeadline = Date().addingTimeInterval(2)
            while await server.statusSnapshot() != .listening && Date() < secondReadyDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let secondStatus = await server.statusSnapshot()
            XCTAssertEqual(secondStatus, .listening)
            let secondCredential = try authorizationValue(in: authorizationFile)
            XCTAssertNotEqual(secondCredential, firstCredential)

            let staleBody = try await post(
                port: port,
                session: "stale-epoch",
                authorizationHeader: firstCredential
            )
            XCTAssertEqual(staleBody, "{}")
            let staleActionCount = await probe.actionCount
            XCTAssertEqual(staleActionCount, 1)

            let currentBody = try await post(
                port: port,
                session: "second-epoch",
                authorizationHeader: secondCredential
            )
            XCTAssertEqual(currentBody, CodexPermissionHook.response(for: .allow))
            let secondActionCount = await probe.actionCount
            XCTAssertEqual(secondActionCount, 2)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    func testPermissionHTTPRoundTripAndBrowserRequestBoundary() async throws {
        let probe = ActionProbe()
        let port = try availableLoopbackPort()
        let server = makeLocalHookServer(port: port)

        await server.start(
            agents: [.codex, .claudeCode],
            onActionRequest: { request in
                await probe.handle(request)
            },
            onEvent: { _, _ in
                Task { await probe.recordEvent() }
            }
        )

        do {
            let allowBody = try await postUntilServerIsReady(port: port)
            XCTAssertEqual(
                allowBody,
                CodexPermissionHook.response(for: .allow)
            )
            let allowActionCount = await probe.actionCount
            XCTAssertEqual(allowActionCount, 1)

            let claudeBody = try curlPost(
                port: port,
                source: "claude-code",
                session: "claude-allow"
            )
            XCTAssertEqual(claudeBody, ClaudePermissionHook.response(for: .allow))
            let crossVendorActionCount = await probe.actionCount
            XCTAssertEqual(crossVendorActionCount, 2)

            await probe.setDecision(nil)
            let neutralBody = try await post(port: port, session: "session-neutral")
            XCTAssertEqual(neutralBody, "{}")
            let neutralActionCount = await probe.actionCount
            XCTAssertEqual(neutralActionCount, 3)

            await probe.setDecision(.allow)
            let actionsBeforeOrigin = await probe.actionCount
            let eventsBeforeOrigin = await probe.eventCount
            let rejectedBody = try await post(
                port: port,
                session: "session-browser",
                origin: "https://malicious.example"
            )
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(rejectedBody, "{}")
            let actionsAfterOrigin = await probe.actionCount
            let eventsAfterOrigin = await probe.eventCount
            XCTAssertEqual(actionsAfterOrigin, actionsBeforeOrigin)
            XCTAssertEqual(eventsAfterOrigin, eventsBeforeOrigin)

            let preflightURL = try XCTUnwrap(
                URL(string: "http://127.0.0.1:\(port)/hooks/codex")
            )
            var preflight = URLRequest(url: preflightURL)
            preflight.httpMethod = "OPTIONS"
            preflight.setValue(
                "https://malicious.example",
                forHTTPHeaderField: "Origin"
            )
            preflight.setValue(
                "POST",
                forHTTPHeaderField: "Access-Control-Request-Method"
            )
            preflight.setValue(
                "\(LocalHooksInstaller.requestHeaderName), \(LocalHookAuthorization.headerName)",
                forHTTPHeaderField: "Access-Control-Request-Headers"
            )
            let (_, rawPreflightResponse) = try await URLSession.shared.data(for: preflight)
            let preflightResponse = try XCTUnwrap(rawPreflightResponse as? HTTPURLResponse)
            XCTAssertNil(preflightResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin"))
            XCTAssertNil(preflightResponse.value(forHTTPHeaderField: "Access-Control-Allow-Headers"))

            let missingHeaderBody = try await post(
                port: port,
                session: "session-missing-hook-header",
                hookHeader: nil
            )
            let wrongHeaderBody = try await post(
                port: port,
                session: "session-wrong-hook-header",
                hookHeader: "wrong"
            )
            let missingAuthorizationBody = try await post(
                port: port,
                session: "session-missing-authorization",
                authorizationHeader: nil
            )
            let wrongAuthorizationBody = try await post(
                port: port,
                session: "session-wrong-authorization",
                authorizationHeader: "v1." + String(repeating: "b", count: 64)
            )
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(missingHeaderBody, "{}")
            XCTAssertEqual(wrongHeaderBody, "{}")
            XCTAssertEqual(missingAuthorizationBody, "{}")
            XCTAssertEqual(wrongAuthorizationBody, "{}")
            let actionsAfterInvalidHeaders = await probe.actionCount
            let eventsAfterInvalidHeaders = await probe.eventCount
            XCTAssertEqual(actionsAfterInvalidHeaders, actionsBeforeOrigin)
            XCTAssertEqual(eventsAfterInvalidHeaders, eventsBeforeOrigin)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    private func postUntilServerIsReady(port: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(2)
        var lastError: Error?
        repeat {
            do {
                return try curlPost(port: port, session: "session-allow")
            } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(20))
            }
        } while Date() < deadline
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func authorizationValue(in file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        let line = try XCTUnwrap(String(data: data, encoding: .utf8))
        let prefix = "\(LocalHookAuthorization.headerName): "
        guard line.hasPrefix(prefix), line.hasSuffix("\n"),
              !line.dropLast().contains("\n"),
              !line.contains("\r") else {
            throw URLError(.cannotParseResponse)
        }
        return String(line.dropFirst(prefix.count).dropLast())
    }

    private func postQuestionUntilServerIsReady(port: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(2)
        var lastError: Error?
        repeat {
            do {
                return try curlPost(
                    port: port,
                    source: "claude-code",
                    payload: questionPayload()
                )
            } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(20))
            }
        } while Date() < deadline
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    /// Exercise the same stdin → curl → stdout shape installed in Codex'
    /// hooks.json rather than relying only on URLSession test traffic.
    private func curlPost(
        port: Int,
        source: String = "codex",
        session: String
    ) throws -> String {
        try curlPost(port: port, source: source, payload: payload(session: session))
    }

    private func curlPost(
        port: Int,
        source: String,
        payload: Data,
        headers: [String: String] = [:]
    ) throws -> String {
        let authorizationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-hook-curl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: authorizationDirectory) }
        try FileManager.default.createDirectory(
            at: authorizationDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let authorizationFile = authorizationDirectory
            .appendingPathComponent("authorization.header")
        try localHookTestAuthorization.headerFileData.write(
            to: authorizationFile,
            options: .withoutOverwriting
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: authorizationFile.path
        )

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var arguments = [
            "--noproxy", "127.0.0.1",
            "-sf", "-m", "1",
            "-X", "POST",
            "http://127.0.0.1:\(port)/hooks/\(source)",
            "-H", "Content-Type: application/json",
            "-H", "\(LocalHooksInstaller.requestHeaderName): \(LocalHooksInstaller.requestHeaderValue)",
            "-H", "@\(authorizationFile.path)",
        ]
        for key in headers.keys.sorted() {
            arguments += ["-H", "\(key): \(headers[key]!)"]
        }
        arguments += ["--data-binary", "@-"]
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(payload)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw URLError(.cannotConnectToHost)
        }
        return String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    }

    private func post(
        port: Int,
        session: String,
        origin: String? = nil,
        hookHeader: String? = LocalHooksInstaller.requestHeaderValue,
        authorizationHeader: String? = localHookTestAuthorization.headerValue
    ) async throws -> String {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/hooks/codex"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 0.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let hookHeader {
            request.setValue(
                hookHeader,
                forHTTPHeaderField: LocalHooksInstaller.requestHeaderName
            )
        }
        if let authorizationHeader {
            request.setValue(
                authorizationHeader,
                forHTTPHeaderField: LocalHookAuthorization.headerName
            )
        }
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        request.httpBody = payload(session: session)

        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return String(decoding: data, as: UTF8.self)
    }

    private func runManagedHookCommand(
        _ command: String,
        payload: Data,
        environment: [String: String]
    ) throws {
        let isolatedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-hook-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: isolatedHome) }
        let authorizationFile = isolatedHome
            .appendingPathComponent(LocalHookAuthorizationStore.relativeHeaderFilePath)
        try FileManager.default.createDirectory(
            at: authorizationFile.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try localHookTestAuthorization.headerFileData.write(
            to: authorizationFile,
            options: .withoutOverwriting
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: authorizationFile.path
        )

        let process = Process()
        let input = Pipe()
        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment.merge(environment) { _, new in new }
        mergedEnvironment["HOME"] = isolatedHome.path
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = mergedEnvironment
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(payload)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func payload(session: String) -> Data {
        Data(#"""
        {
          "hook_event_name": "PermissionRequest",
          "session_id": "\#(session)",
          "tool_name": "Bash",
          "tool_input": {"command": "pwd", "description": "Inspect cwd"}
        }
        """#.utf8)
    }

    private func codexSessionStartPayload(session: String) -> Data {
        Data(#"""
        {
          "hook_event_name": "SessionStart",
          "session_id": "\#(session)",
          "cwd": "/tmp/cross-request"
        }
        """#.utf8)
    }

    private func questionPayload() -> Data {
        Data(#"""
        {
          "hook_event_name": "PreToolUse",
          "session_id": "question-http",
          "tool_name": "AskUserQuestion",
          "tool_input": {
            "questions": [{
              "question": "Choose a mode",
              "header": "Mode",
              "options": [
                {"label": "Safe", "description": "Review each change"},
                {"label": "Fast", "description": "Prefer speed"}
              ],
              "multiSelect": false
            }]
          }
        }
        """#.utf8)
    }

    private func planPayload() -> Data {
        Data(#"""
        {
          "hook_event_name": "PreToolUse",
          "session_id": "plan-http",
          "tool_name": "ExitPlanMode",
          "tool_input": {
            "plan": "# Plan\n\n- Update the island",
            "planFilePath": "/tmp/plan.md",
            "futureField": 7
          }
        }
        """#.utf8)
    }

    private func geminiPermissionPayload() -> Data {
        Data(#"""
        {
          "session_id": "gemini-http",
          "cwd": "/tmp/gemini-http",
          "hook_event_name": "Notification",
          "notification_type": "ToolPermission",
          "message": "Approve pwd?",
          "prompt": "sensitive field must not be retained",
          "details": {"tool_name": "run_shell_command"}
        }
        """#.utf8)
    }

    private func qwenPermissionPayload() -> Data {
        Data(#"""
        {
          "session_id": "qwen-http",
          "transcript_path": "/tmp/qwen.jsonl",
          "cwd": "/tmp/qwen-http",
          "hook_event_name": "PermissionRequest",
          "timestamp": "2026-08-26T05:00:00.000Z",
          "permission_mode": "default",
          "tool_name": "run_shell_command",
          "tool_input": {"command": "pwd", "description": "Inspect cwd"},
          "permission_suggestions": []
        }
        """#.utf8)
    }

    private func copilotPermissionNotificationPayload() -> Data {
        Data(#"""
        {
          "hook_event_name": "Notification",
          "session_id": "copilot-http",
          "timestamp": "2026-08-26T06:00:00.000Z",
          "cwd": "/tmp/copilot-http",
          "title": "Permission needed",
          "message": "Sensitive vendor text must not enter task state",
          "notification_type": "permission_prompt"
        }
        """#.utf8)
    }

    private func kimiPermissionRequestPayload() -> Data {
        Data(#"""
        {
          "hook_event_name": "PermissionRequest",
          "session_id": "kimi-http",
          "cwd": "/tmp/kimi-http",
          "tool_name": "Shell",
          "tool_input": {"command": "echo sensitive-value"},
          "display": "Private approval copy must not enter task state",
          "future": {"prompt": "private prompt"}
        }
        """#.utf8)
    }

    private func openCodePermissionPayload() -> Data {
        Data(#"""
        {
          "schema_version": 1,
          "event": "permission.updated",
          "session_id": "opencode-http",
          "cwd": "/tmp/opencode-http",
          "title": "Private project title must be ignored",
          "prompt": "Sensitive prompt must be ignored",
          "tool": {"args": {"token": "secret-must-not-enter-state"}},
          "permission": {"metadata": {"command": "private-command"}},
          "future": {"assistant_output": "private-output"}
        }
        """#.utf8)
    }

    /// Reserve an ephemeral loopback port long enough to discover its number.
    /// The socket is closed before Hummingbird binds it; the race window is
    /// tiny and avoids hard-coding a port that may be in use on a developer Mac.
    private func availableLoopbackPort() throws -> Int {
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(fileDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fileDescriptor, $0, &length)
            }
        }
        guard nameResult == 0 else { throw POSIXError(.EIO) }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

private actor LocalEventOrderingGate {
    private(set) var hasEntered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func hold() async {
        hasEntered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SerializedEventDeliveryProbe {
    private(set) var deliveredEvents: [
        (source: String, event: LocalAgentEvent)
    ] = []
    private(set) var maximumConcurrentDeliveries = 0
    private var activeDeliveries = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?

    var hasEnteredFirst: Bool { !deliveredEvents.isEmpty }
    var deliveredCount: Int { deliveredEvents.count }

    func handle(source: String, event: LocalAgentEvent) async {
        activeDeliveries += 1
        maximumConcurrentDeliveries = max(
            maximumConcurrentDeliveries,
            activeDeliveries
        )
        deliveredEvents.append((source: source, event: event))
        if deliveredEvents.count == 1 {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        activeDeliveries -= 1
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

private actor DeliveryLivenessProbe {
    private(set) var value = true

    func expire() {
        value = false
    }
}

private actor ActionProbe {
    private(set) var actionCount = 0
    private(set) var eventCount = 0
    private var decision: AgentActionDecision? = .allow

    func handle(_ request: AgentActionRequest) -> AgentActionResponse? {
        actionCount += 1
        return decision.map(AgentActionResponse.permission)
    }

    func recordEvent() {
        eventCount += 1
    }

    func setDecision(_ decision: AgentActionDecision?) {
        self.decision = decision
    }
}

private actor LocalEventProbe {
    private(set) var last: (source: String, event: LocalAgentEvent)?

    var count: Int { last == nil ? 0 : 1 }

    func record(source: String, event: LocalAgentEvent) {
        last = (source, event)
    }
}
