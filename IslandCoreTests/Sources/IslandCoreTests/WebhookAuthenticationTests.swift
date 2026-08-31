import Darwin
import CryptoKit
import Dispatch
import Foundation
import Security
import XCTest
@testable import IslandCore

final class WebhookAuthenticationTests: XCTestCase {
    private let externalURL = "https://example.trycloudflare.com/webhook"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRealtimeIsDisabledUntilLiveV2AcceptanceCompletes() {
        XCTAssertFalse(ManusRealtimeTrust.liveV2AcceptanceComplete)
    }

    func testMissingOrInvalidTrustAnchorCannotCreateAuthenticator() {
        XCTAssertNil(WebhookRequestAuthenticator(signaturePublicKeyPEM: ""))
        XCTAssertNil(WebhookRequestAuthenticator(signaturePublicKeyPEM: "  \n  "))
        XCTAssertNil(WebhookRequestAuthenticator(signaturePublicKeyPEM: "not-a-public-key"))
    }

    func testRSAKeyBelow2048BitsCannotCreateAuthenticator() throws {
        let weakFixture = try RSAFixture(keySizeInBits: 1_024)

        XCTAssertNil(
            WebhookRequestAuthenticator(
                signaturePublicKeyPEM: weakFixture.publicKeyPEM
            )
        )
    }

    func testMissingSignatureIsRejected() throws {
        let fixture = try RSAFixture()
        let authenticator = try XCTUnwrap(WebhookRequestAuthenticator(
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))

        XCTAssertFalse(authenticator.isAuthentic(
            body: Data("payload".utf8),
            signature: nil,
            timestamp: timestamp,
            externalURL: externalURL,
            now: now
        ))
    }

    func testInvalidBase64SignatureIsRejected() throws {
        let fixture = try RSAFixture()
        let authenticator = try XCTUnwrap(WebhookRequestAuthenticator(
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))

        XCTAssertFalse(authenticator.isAuthentic(
            body: Data("payload".utf8),
            signature: "not-base64%%%",
            timestamp: timestamp,
            externalURL: externalURL,
            now: now
        ))
    }

    func testMissingTimestampIsRejected() throws {
        let fixture = try RSAFixture()
        let authenticator = try XCTUnwrap(WebhookRequestAuthenticator(
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))
        let body = Data("payload".utf8)

        XCTAssertFalse(authenticator.isAuthentic(
            body: body,
            signature: try fixture.signature(
                for: body,
                timestamp: timestamp,
                externalURL: externalURL
            ),
            timestamp: nil,
            externalURL: externalURL,
            now: now
        ))
    }

    func testTimestampOutsideFiveMinuteWindowIsRejected() throws {
        let fixture = try RSAFixture()
        let authenticator = try XCTUnwrap(WebhookRequestAuthenticator(
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))
        let body = Data("payload".utf8)
        let staleTimestamp = String(Int(now.timeIntervalSince1970) - 301)

        XCTAssertFalse(authenticator.isAuthentic(
            body: body,
            signature: try fixture.signature(
                for: body,
                timestamp: staleTimestamp,
                externalURL: externalURL
            ),
            timestamp: staleTimestamp,
            externalURL: externalURL,
            now: now
        ))
    }

    func testValidRSASHA256SignatureIsAccepted() throws {
        let fixture = try RSAFixture()
        let authenticator = try XCTUnwrap(WebhookRequestAuthenticator(
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))
        let body = Data("verified webhook payload".utf8)

        let authentication = try XCTUnwrap(authenticator.authenticate(
            body: body,
            signature: try fixture.signature(
                for: body,
                timestamp: timestamp,
                externalURL: externalURL
            ),
            timestamp: timestamp,
            externalURL: externalURL,
            now: now
        ))
        XCTAssertEqual(authentication.signedAt, now)
        XCTAssertEqual(authentication.acceptedAt, now)
    }

    func testOfficialSubjectPublicKeyInfoPEMShapeIsAccepted() throws {
        let fixture = try RSAFixture()
        let authenticator = try XCTUnwrap(WebhookRequestAuthenticator(
            signaturePublicKeyPEM: fixture.subjectPublicKeyInfoPEM
        ))
        let body = Data("official key shape".utf8)

        XCTAssertTrue(authenticator.isAuthentic(
            body: body,
            signature: try fixture.signature(
                for: body,
                timestamp: timestamp,
                externalURL: externalURL
            ),
            timestamp: timestamp,
            externalURL: externalURL,
            now: now
        ))
    }

    func testSignatureIsRejectedAfterBodyIsModified() throws {
        let fixture = try RSAFixture()
        let authenticator = try XCTUnwrap(WebhookRequestAuthenticator(
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))
        let original = Data("original payload".utf8)
        let signature = try fixture.signature(
            for: original,
            timestamp: timestamp,
            externalURL: externalURL
        )

        XCTAssertFalse(authenticator.isAuthentic(
            body: Data("modified payload".utf8),
            signature: signature,
            timestamp: timestamp,
            externalURL: externalURL,
            now: now
        ))
    }

    func testSignatureIsBoundToRegisteredExternalURL() throws {
        let fixture = try RSAFixture()
        let authenticator = try XCTUnwrap(WebhookRequestAuthenticator(
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))
        let body = Data("payload".utf8)
        let signature = try fixture.signature(
            for: body,
            timestamp: timestamp,
            externalURL: externalURL
        )

        XCTAssertFalse(authenticator.isAuthentic(
            body: body,
            signature: signature,
            timestamp: timestamp,
            externalURL: "https://attacker.example/webhook",
            now: now
        ))
    }

    func testReplayWindowRejectsDuplicateAndExtendsAuthenticatedLifetime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var window = WebhookReplayWindow(capacity: 1)

        XCTAssertEqual(
            window.register(
                eventID: "event-1",
                authentication: AuthenticatedWebhookRequest(
                    signedAt: start,
                    acceptedAt: start
                )
            ),
            .deliver
        )

        let retriedAt = start.addingTimeInterval(240)
        XCTAssertEqual(
            window.register(
                eventID: "event-1",
                authentication: AuthenticatedWebhookRequest(
                    signedAt: retriedAt,
                    acceptedAt: retriedAt
                )
            ),
            .duplicate
        )

        // The first signature has expired, but the authenticated retry can
        // still be replayed. Its newer expiry must retain the ID.
        let afterFirstExpiry = start.addingTimeInterval(301)
        XCTAssertEqual(
            window.register(
                eventID: "event-1",
                authentication: AuthenticatedWebhookRequest(
                    signedAt: retriedAt,
                    acceptedAt: afterFirstExpiry
                )
            ),
            .duplicate
        )
        XCTAssertEqual(window.expirationByEventID.count, 1)

        // Verification accepts exactly 300 seconds of clock skew, so the
        // replay ID must still occupy capacity at that exact boundary.
        let extendedExpiry = retriedAt.addingTimeInterval(300)
        XCTAssertEqual(
            window.register(
                eventID: "event-2",
                authentication: AuthenticatedWebhookRequest(
                    signedAt: extendedExpiry,
                    acceptedAt: extendedExpiry
                )
            ),
            .saturated
        )

        let afterExtendedExpiry = extendedExpiry.addingTimeInterval(1)
        XCTAssertEqual(
            window.register(
                eventID: "event-2",
                authentication: AuthenticatedWebhookRequest(
                    signedAt: afterExtendedExpiry,
                    acceptedAt: afterExtendedExpiry
                )
            ),
            .deliver
        )
        XCTAssertEqual(window.expirationByEventID.count, 1)
    }

    func testReplayWindowFailsClosedInsteadOfEvictingLiveEventsAtCapacity() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var window = WebhookReplayWindow(capacity: 2)

        for eventID in ["event-1", "event-2"] {
            XCTAssertEqual(
                window.register(
                    eventID: eventID,
                    authentication: AuthenticatedWebhookRequest(
                        signedAt: start,
                        acceptedAt: start
                    )
                ),
                .deliver
            )
        }
        XCTAssertEqual(
            window.register(
                eventID: "event-3",
                authentication: AuthenticatedWebhookRequest(
                    signedAt: start,
                    acceptedAt: start
                )
            ),
            .saturated
        )
        XCTAssertEqual(
            window.register(
                eventID: "event-1",
                authentication: AuthenticatedWebhookRequest(
                    signedAt: start,
                    acceptedAt: start
                )
            ),
            .duplicate
        )
        XCTAssertEqual(window.expirationByEventID.count, 2)

        let afterExpiry = start.addingTimeInterval(301)
        XCTAssertEqual(
            window.register(
                eventID: "event-3",
                authentication: AuthenticatedWebhookRequest(
                    signedAt: afterExpiry,
                    acceptedAt: afterExpiry
                )
            ),
            .deliver
        )
        XCTAssertEqual(window.expirationByEventID.count, 1)
    }

    func testServerStartReturnsOnlyAfterPrivateReadinessProof() async throws {
        let fixture = try RSAFixture()
        let port = try availableLoopbackPort()
        let server = try XCTUnwrap(WebhookServer(
            port: port,
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))

        try await server.start(onEvent: { _ in })

        let readyAfterStart = await server.isReady()
        XCTAssertTrue(readyAfterStart)
        await server.stop()
        let readyAfterStop = await server.isReady()
        XCTAssertFalse(readyAfterStop)
    }

    func testServerStopJoinsServeLoopSoPortCanBeReboundImmediately() async throws {
        let fixture = try RSAFixture()
        let port = try availableLoopbackPort()
        let firstServer = try XCTUnwrap(WebhookServer(
            port: port,
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))
        let replacementServer = try XCTUnwrap(WebhookServer(
            port: port,
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))

        try await firstServer.start(onEvent: { _ in })
        await firstServer.stop()

        do {
            try await replacementServer.start(onEvent: { _ in })
            let replacementReady = await replacementServer.isReady()
            XCTAssertTrue(replacementReady)
        } catch {
            await replacementServer.stop()
            throw error
        }

        await replacementServer.stop()
    }

    func testServerStartFailsClosedWithinBoundWhenLoopbackPortIsOccupied() async throws {
        let fixture = try RSAFixture()
        let occupied = try OccupiedWebhookPort()
        defer { occupied.release() }
        let server = try XCTUnwrap(WebhookServer(
            port: occupied.port,
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))
        let startedAt = Date()

        do {
            try await server.start(onEvent: { _ in })
            XCTFail("Expected the private readiness proof to fail")
        } catch WebhookServerStartError.readinessFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
        let readyAfterFailure = await server.isReady()
        XCTAssertFalse(readyAfterFailure)
        await server.stop()
    }

    func testLiveHTTPRouteRejectsMissingInvalidAndBodyBoundAuthentication() async throws {
        let fixture = try RSAFixture()
        let port = try availableLoopbackPort()
        let server = try XCTUnwrap(WebhookServer(
            port: port,
            signaturePublicKeyPEM: fixture.publicKeyPEM
        ))
        try await server.configure(
            externalURL: externalURL,
            signaturePublicKeyPEM: fixture.publicKeyPEM
        )
        let deliveries = WebhookDeliveryRecorder()
        try await server.start { payload in
            deliveries.record(payload.eventID)
        }

        do {
            let body = webhookCreatedBody(eventID: "event_auth", taskID: "task_auth")
            let timestamp = String(Int(Date.now.timeIntervalSince1970))

            let missingAuthenticationStatus = try await sendRawWebhook(
                body,
                signature: nil,
                timestamp: nil,
                port: port
            )
            XCTAssertEqual(missingAuthenticationStatus, 401)

            let invalidSignatureStatus = try await sendRawWebhook(
                body,
                signature: "not-base64%%%",
                timestamp: timestamp,
                port: port
            )
            XCTAssertEqual(invalidSignatureStatus, 401)

            let original = webhookCreatedBody(
                eventID: "event_original",
                taskID: "task_original"
            )
            let bodyBoundSignatureStatus = try await sendRawWebhook(
                body,
                signature: try fixture.signature(
                    for: original,
                    timestamp: timestamp,
                    externalURL: externalURL
                ),
                timestamp: timestamp,
                port: port
            )
            XCTAssertEqual(bodyBoundSignatureStatus, 401)
            XCTAssertTrue(deliveries.snapshot.isEmpty)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    func testLiveHTTPRouteKeepsDuplicatesIdempotentAndFailsClosedAtCapacity() async throws {
        let fixture = try RSAFixture()
        let port = try availableLoopbackPort()
        let server = try XCTUnwrap(WebhookServer(
            port: port,
            signaturePublicKeyPEM: fixture.publicKeyPEM,
            replayCapacity: 2
        ))
        let externalURL = "https://example.trycloudflare.com/webhook"
        try await server.configure(
            externalURL: externalURL,
            signaturePublicKeyPEM: fixture.publicKeyPEM
        )
        let deliveries = WebhookDeliveryRecorder()
        try await server.start { payload in
            deliveries.record(payload.eventID)
        }

        do {
            let timestamp = String(Int(Date.now.timeIntervalSince1970))
            let event1 = webhookCreatedBody(eventID: "event_1", taskID: "task_1")
            let event2 = webhookCreatedBody(eventID: "event_2", taskID: "task_2")
            let event3 = webhookCreatedBody(eventID: "event_3", taskID: "task_3")

            let firstStatus = try await sendWebhook(
                event1,
                timestamp: timestamp,
                fixture: fixture,
                externalURL: externalURL,
                port: port
            )
            XCTAssertEqual(firstStatus, 200)
            XCTAssertEqual(deliveries.snapshot, ["event_1"])

            // A duplicate is acknowledged so Manus does not amplify retries,
            // but it must not cross the delivery boundary twice.
            let duplicateStatus = try await sendWebhook(
                event1,
                timestamp: timestamp,
                fixture: fixture,
                externalURL: externalURL,
                port: port
            )
            XCTAssertEqual(duplicateStatus, 200)
            XCTAssertEqual(deliveries.snapshot, ["event_1"])

            let secondStatus = try await sendWebhook(
                event2,
                timestamp: timestamp,
                fixture: fixture,
                externalURL: externalURL,
                port: port
            )
            XCTAssertEqual(secondStatus, 200)
            XCTAssertEqual(deliveries.snapshot, ["event_1", "event_2"])

            // Both retained IDs are still inside their authenticated window.
            // The third event fails closed at the actual HTTP route.
            let saturatedStatus = try await sendWebhook(
                event3,
                timestamp: timestamp,
                fixture: fixture,
                externalURL: externalURL,
                port: port
            )
            XCTAssertEqual(saturatedStatus, 503)
            XCTAssertEqual(deliveries.snapshot, ["event_1", "event_2"])

            // Saturation must not evict event_1. Replaying it stays an
            // idempotent 200 and still does not deliver again.
            let retainedDuplicateStatus = try await sendWebhook(
                event1,
                timestamp: timestamp,
                fixture: fixture,
                externalURL: externalURL,
                port: port
            )
            XCTAssertEqual(retainedDuplicateStatus, 200)
            XCTAssertEqual(deliveries.snapshot, ["event_1", "event_2"])
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    func testLiveHTTPReplayWindowTracksCanonicalTrustGeneration() async throws {
        let originalKey = try RSAFixture()
        let replacementKey = try RSAFixture()
        let port = try availableLoopbackPort()
        let server = try XCTUnwrap(WebhookServer(
            port: port,
            signaturePublicKeyPEM: originalKey.publicKeyPEM,
            replayCapacity: 2
        ))
        let callbackA = "https://generation-a.trycloudflare.com/webhook"
        let callbackB = "https://generation-b.trycloudflare.com/webhook"
        try await server.configure(
            externalURL: callbackA,
            signaturePublicKeyPEM: originalKey.publicKeyPEM
        )
        let deliveries = WebhookDeliveryRecorder()
        try await server.start { payload in
            deliveries.record(payload.eventID)
        }

        do {
            let timestamp = String(Int(Date.now.timeIntervalSince1970))
            let event1 = webhookCreatedBody(eventID: "generation_event_1", taskID: "generation_task_1")
            let event2 = webhookCreatedBody(eventID: "generation_event_2", taskID: "generation_task_2")
            let event3 = webhookCreatedBody(eventID: "generation_event_3", taskID: "generation_task_3")
            let event4 = webhookCreatedBody(eventID: "generation_event_4", taskID: "generation_task_4")
            let event5 = webhookCreatedBody(eventID: "generation_event_5", taskID: "generation_task_5")

            for event in [event1, event2] {
                let status = try await sendWebhook(
                    event,
                    timestamp: timestamp,
                    fixture: originalKey,
                    externalURL: callbackA,
                    port: port
                )
                XCTAssertEqual(status, 200)
            }
            XCTAssertEqual(
                deliveries.snapshot,
                ["generation_event_1", "generation_event_2"]
            )

            // PKCS#1 and SubjectPublicKeyInfo are two encodings of the same
            // RSA key. Reconfiguring the same trust tuple must not clear a live
            // replay window.
            try await server.configure(
                externalURL: callbackA,
                signaturePublicKeyPEM: originalKey.subjectPublicKeyInfoPEM
            )
            let equivalentTrustStatus = try await sendWebhook(
                event3,
                timestamp: timestamp,
                fixture: originalKey,
                externalURL: callbackA,
                port: port
            )
            XCTAssertEqual(equivalentTrustStatus, 503)

            do {
                try await server.configure(
                    externalURL: callbackA,
                    signaturePublicKeyPEM: "not-a-public-key"
                )
                XCTFail("Expected invalid trust material")
            } catch WebhookServerConfigurationError.invalidTrustMaterial {
                // Expected. The prior authenticator, URL, and replay state stay live.
            }
            do {
                try await server.configure(
                    externalURL: "http://generation-invalid.example/webhook",
                    signaturePublicKeyPEM: replacementKey.publicKeyPEM
                )
                XCTFail("Expected an invalid external URL")
            } catch WebhookServerConfigurationError.invalidExternalURL {
                // Expected. No part of the candidate tuple was committed.
            }
            let statusAfterInvalidConfiguration = try await sendWebhook(
                event3,
                timestamp: timestamp,
                fixture: originalKey,
                externalURL: callbackA,
                port: port
            )
            XCTAssertEqual(statusAfterInvalidConfiguration, 503)
            XCTAssertEqual(
                deliveries.snapshot,
                ["generation_event_1", "generation_event_2"]
            )

            // A new callback URL is a new replay generation. The same event ID
            // is delivered once for B, and B receives a fresh two-entry window.
            try await server.configure(
                externalURL: callbackB,
                signaturePublicKeyPEM: originalKey.subjectPublicKeyInfoPEM
            )
            let callbackBFirstStatus = try await sendWebhook(
                event1,
                timestamp: timestamp,
                fixture: originalKey,
                externalURL: callbackB,
                port: port
            )
            XCTAssertEqual(callbackBFirstStatus, 200)
            let callbackBSecondStatus = try await sendWebhook(
                event3,
                timestamp: timestamp,
                fixture: originalKey,
                externalURL: callbackB,
                port: port
            )
            XCTAssertEqual(callbackBSecondStatus, 200)
            let callbackBSaturatedStatus = try await sendWebhook(
                event4,
                timestamp: timestamp,
                fixture: originalKey,
                externalURL: callbackB,
                port: port
            )
            XCTAssertEqual(callbackBSaturatedStatus, 503)

            // A genuinely different RSA key also rotates the generation even
            // when the callback URL is unchanged.
            try await server.configure(
                externalURL: callbackB,
                signaturePublicKeyPEM: replacementKey.publicKeyPEM
            )
            let priorKeyStatus = try await sendWebhook(
                event4,
                timestamp: timestamp,
                fixture: originalKey,
                externalURL: callbackB,
                port: port
            )
            XCTAssertEqual(priorKeyStatus, 401)
            let replacementKeyFirstStatus = try await sendWebhook(
                event1,
                timestamp: timestamp,
                fixture: replacementKey,
                externalURL: callbackB,
                port: port
            )
            XCTAssertEqual(replacementKeyFirstStatus, 200)
            let replacementKeySecondStatus = try await sendWebhook(
                event4,
                timestamp: timestamp,
                fixture: replacementKey,
                externalURL: callbackB,
                port: port
            )
            XCTAssertEqual(replacementKeySecondStatus, 200)
            let replacementKeySaturatedStatus = try await sendWebhook(
                event5,
                timestamp: timestamp,
                fixture: replacementKey,
                externalURL: callbackB,
                port: port
            )
            XCTAssertEqual(replacementKeySaturatedStatus, 503)

            XCTAssertEqual(
                deliveries.snapshot,
                [
                    "generation_event_1",
                    "generation_event_2",
                    "generation_event_1",
                    "generation_event_3",
                    "generation_event_1",
                    "generation_event_4",
                ]
            )
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    func testLiveHTTPRequestAuthenticatedBeforeRotationCannotEnterNewTrustGeneration() async throws {
        let originalKey = try RSAFixture()
        let replacementKey = try RSAFixture()
        let interlock = WebhookAuthenticationInterlock()
        let port = try availableLoopbackPort()
        let server = try XCTUnwrap(WebhookServer(
            port: port,
            signaturePublicKeyPEM: originalKey.publicKeyPEM,
            replayCapacity: 1,
            afterAuthenticationForTesting: {
                await interlock.pause()
            }
        ))
        let callbackA = "https://interleaving-a.trycloudflare.com/webhook"
        let callbackB = "https://interleaving-b.trycloudflare.com/webhook"
        try await server.configure(
            externalURL: callbackA,
            signaturePublicKeyPEM: originalKey.publicKeyPEM
        )
        let deliveries = WebhookDeliveryRecorder()
        try await server.start { payload in
            deliveries.record(payload.eventID)
        }

        do {
            let body = webhookCreatedBody(
                eventID: "generation_interleaving_event",
                taskID: "generation_interleaving_task"
            )
            let timestamp = String(Int(Date.now.timeIntervalSince1970))
            let oldGenerationRequest = Task {
                try await sendWebhook(
                    body,
                    timestamp: timestamp,
                    fixture: originalKey,
                    externalURL: callbackA,
                    port: port
                )
            }

            guard interlock.waitUntilPaused() else {
                oldGenerationRequest.cancel()
                interlock.resume()
                _ = try? await oldGenerationRequest.value
                XCTFail("The HTTP request did not reach the post-authentication interlock")
                await server.stop()
                return
            }

            // Rotate the exact callback/key tuple while the live HTTP request
            // is suspended after successful old-generation authentication but
            // before its event ID can enter the replay window.
            try await server.configure(
                externalURL: callbackB,
                signaturePublicKeyPEM: replacementKey.publicKeyPEM
            )
            interlock.resume()

            let oldGenerationStatus = try await oldGenerationRequest.value
            XCTAssertEqual(oldGenerationStatus, 401)
            XCTAssertTrue(deliveries.snapshot.isEmpty)

            // The rejected old request must not reserve its event ID in the
            // replacement generation. The same ID, authenticated by the new
            // tuple, remains a first delivery rather than a duplicate.
            let replacementStatus = try await sendWebhook(
                body,
                timestamp: timestamp,
                fixture: replacementKey,
                externalURL: callbackB,
                port: port
            )
            XCTAssertEqual(replacementStatus, 200)
            XCTAssertEqual(deliveries.snapshot, ["generation_interleaving_event"])
        } catch {
            interlock.resume()
            await server.stop()
            throw error
        }

        await server.stop()
    }

    private func webhookCreatedBody(eventID: String, taskID: String) -> Data {
        Data(
            """
            {"event_id":"\(eventID)","event_type":"task_created","task_detail":{"task_id":"\(taskID)","task_title":"Task","task_url":"https://manus.im/app/\(taskID)"}}
            """.utf8
        )
    }

    private func sendWebhook(
        _ body: Data,
        timestamp: String,
        fixture: RSAFixture,
        externalURL: String,
        port: Int
    ) async throws -> Int {
        try await sendRawWebhook(
            body,
            signature: try fixture.signature(
                for: body,
                timestamp: timestamp,
                externalURL: externalURL
            ),
            timestamp: timestamp,
            port: port
        )
    }

    private func sendRawWebhook(
        _ body: Data,
        signature: String?,
        timestamp: String?,
        port: Int
    ) async throws -> Int {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/webhook"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let timestamp {
            request.setValue(
                timestamp,
                forHTTPHeaderField: WebhookSignature.timestampHeaderName
            )
        }
        if let signature {
            request.setValue(
                signature,
                forHTTPHeaderField: WebhookSignature.headerName
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: request)
        return try XCTUnwrap(response as? HTTPURLResponse).statusCode
    }

    private func availableLoopbackPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else { throw POSIXError(.EIO) }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private var timestamp: String {
        String(Int(now.timeIntervalSince1970))
    }
}

private final class WebhookDeliveryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var eventIDs: [String] = []

    func record(_ eventID: String) {
        lock.lock()
        eventIDs.append(eventID)
        lock.unlock()
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return eventIDs
    }
}

private final class WebhookAuthenticationInterlock: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var isReleased = false
    private var continuation: CheckedContinuation<Void, Never>?

    func pause() async {
        entered.signal()
        await withCheckedContinuation { continuation in
            lock.lock()
            if isReleased {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func waitUntilPaused() -> Bool {
        entered.wait(timeout: .now() + .seconds(2)) == .success
    }

    func resume() {
        lock.lock()
        isReleased = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

private final class OccupiedWebhookPort: @unchecked Sendable {
    private var descriptor: Int32
    let port: Int

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.EADDRINUSE)
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.EIO)
        }

        self.descriptor = descriptor
        port = Int(UInt16(bigEndian: address.sin_port))
    }

    func release() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}

private struct RSAFixture {
    let privateKey: SecKey
    let publicKeyPEM: String
    let subjectPublicKeyInfoPEM: String

    init(keySizeInBits: Int = 2_048) throws {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: keySizeInBits,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error?.takeRetainedValue() ?? NSError(
                domain: "WebhookAuthenticationTests",
                code: 1
            )
        }

        self.privateKey = privateKey
        self.publicKeyPEM = Self.pem(for: publicKeyData)
        self.subjectPublicKeyInfoPEM = Self.subjectPublicKeyInfoPEM(for: publicKeyData)
    }

    func signature(for body: Data, timestamp: String, externalURL: String) throws -> String {
        let bodyHash = SHA256.hash(data: body)
            .map { String(format: "%02x", $0) }
            .joined()
        let signedContent = Data("\(timestamp).\(externalURL).\(bodyHash)".utf8)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signedContent as CFData,
            &error
        ) as Data? else {
            throw error?.takeRetainedValue() ?? NSError(
                domain: "WebhookAuthenticationTests",
                code: 2
            )
        }
        return signature.base64EncodedString()
    }

    private static func pem(for data: Data) -> String {
        pem(label: "RSA PUBLIC KEY", data: data)
    }

    private static func subjectPublicKeyInfoPEM(for rsaPublicKey: Data) -> String {
        let algorithmIdentifier = Data([
            0x30, 0x0d,
            0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
            0x05, 0x00,
        ])
        var bitStringBody = Data([0x00])
        bitStringBody.append(rsaPublicKey)
        var bitString = Data([0x03])
        bitString.append(derLength(bitStringBody.count))
        bitString.append(bitStringBody)

        var sequenceBody = algorithmIdentifier
        sequenceBody.append(bitString)
        var sequence = Data([0x30])
        sequence.append(derLength(sequenceBody.count))
        sequence.append(sequenceBody)
        return pem(label: "PUBLIC KEY", data: sequence)
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    private static func pem(label: String, data: Data) -> String {
        let base64 = data.base64EncodedString()
        let lines = stride(from: 0, to: base64.count, by: 64).map { offset in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: min(64, base64.count - offset))
            return String(base64[start..<end])
        }
        return (["-----BEGIN \(label)-----"] + lines + [
            "-----END \(label)-----",
        ]).joined(separator: "\n")
    }
}
