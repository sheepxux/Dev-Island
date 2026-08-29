import Foundation
@testable import IslandCore

let localHookTestAuthorization = LocalHookAuthorization(
    headerValue: "v1." + String(repeating: "a", count: 64)
)

func makeLocalHookServer(
    port: Int,
    retryPolicy: LocalHookServerRetryPolicy = .production
) -> LocalHookServer {
    LocalHookServer(
        port: port,
        retryPolicy: retryPolicy,
        authorization: localHookTestAuthorization
    )
}
