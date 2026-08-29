import Foundation

/// A bounded, redirect-free challenge probe for a server that must be owned
/// by this process on loopback. A conflicting local service cannot redirect
/// the challenge off-device or make the probe retain an unbounded response.
enum LoopbackHTTPReadinessProbe {
    private static let maximumExpectedBytes = 256
    private static let maximumPathBytes = 512

    static func responds(
        port: Int,
        path: String,
        expectedResponse: Data,
        timeout: TimeInterval = 0.2
    ) async -> Bool {
        guard (1...65_535).contains(port),
              timeout > 0,
              timeout <= 1,
              !expectedResponse.isEmpty,
              expectedResponse.count <= maximumExpectedBytes,
              path.hasPrefix("/"),
              path.utf8.count <= maximumPathBytes,
              path.utf8.allSatisfy({ byte in
                  byte == 0x2F
                      || byte == 0x2D
                      || byte == 0x5F
                      || (0x30...0x39).contains(byte)
                      || (0x41...0x5A).contains(byte)
                      || (0x61...0x7A).contains(byte)
              }) else { return false }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.percentEncodedPath = path
        guard let url = components.url else { return false }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(
            configuration: configuration,
            delegate: LoopbackNoRedirectDelegate.shared,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  response.url == url,
                  response.expectedContentLength == Int64(expectedResponse.count),
                  response.value(forHTTPHeaderField: "Content-Encoding") == nil else {
                return false
            }

            var iterator = bytes.makeAsyncIterator()
            for expectedByte in expectedResponse {
                guard let receivedByte = try await iterator.next(),
                      receivedByte == expectedByte else { return false }
            }
            // Content-Length is exact and redirects/content transforms are
            // disabled, so no EOF wait or unbounded accumulation is needed.
            return true
        } catch {
            return false
        }
    }
}

private final class LoopbackNoRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    static let shared = LoopbackNoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
