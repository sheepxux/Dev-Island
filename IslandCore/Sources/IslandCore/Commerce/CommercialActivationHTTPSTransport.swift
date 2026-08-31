import Foundation

/// Fail-closed errors from the provider-neutral HTTPS activation transport.
///
/// No case carries an endpoint, response body, activation code, URLSession
/// error, certificate detail, or provider message. The activation service
/// further collapses every thrown value to `transportUnavailable`.
public enum CommercialActivationHTTPSTransportError: Error, Equatable, Sendable {
    case invalidEndpoint
    case unavailable
    case invalidResponse
    case responseTooLarge
}

/// A disabled-by-default production transport foundation for a future
/// provider-owned activation endpoint.
///
/// Constructing this value does not enable commercial mode: the shipping App
/// still instantiates neither this transport, a trust anchor, nor an activation
/// service. A future provider integration must hard-code its reviewed endpoint
/// and inject a configured verifier/store deliberately.
///
/// The transport accepts only a public DNS HTTPS origin on the fixed
/// `/v1/activate` path, uses platform TLS/hostname validation, refuses
/// redirects, cookies, caches and ambient URL credentials, sends the bounded
/// code only in an octet-stream POST body, and bounds license bytes while they
/// are read rather than after an untrusted response has already been buffered.
public struct CommercialActivationHTTPSTransport:
    CommercialActivationTransport,
    @unchecked Sendable
{
    public static let activationPath = "/v1/activate"
    public static let licenseContentType = "application/vnd.devisland.license"
    public static let requestTimeout: TimeInterval = 10

    private let endpoint: URL
    private let session: URLSession

    /// Module-internal until a provider and its exact endpoint are approved.
    /// A future shipping integration must add a source-reviewed, no-argument
    /// provider factory instead of accepting a URL from UI, preferences,
    /// environment, remote configuration, or another runtime input.
    init(endpoint: URL) throws {
        try Self.validate(endpoint: endpoint)
        self.endpoint = endpoint
        session = Self.makeSession()
    }

    /// Internal network injection is available only to the IslandCore test
    /// target. Public callers cannot weaken endpoint validation or replace the
    /// hardened URLSession configuration.
    init(endpoint: URL, session: URLSession) throws {
        try Self.validate(endpoint: endpoint)
        self.endpoint = endpoint
        self.session = session
    }

    public func exchange(
        activationCode: CommercialActivationCode
    ) async throws -> CommercialActivationTransportResponse {
        do {
            try Task.checkCancellation()

            var request = URLRequest(
                url: endpoint,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: Self.requestTimeout
            )
            request.httpMethod = "POST"
            request.setValue(
                "application/octet-stream",
                forHTTPHeaderField: "Content-Type"
            )
            request.setValue(
                Self.licenseContentType,
                forHTTPHeaderField: "Accept"
            )
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

            var requestBody = activationCode.withUnsafeUTF8Bytes { Data($0) }
            request.httpBody = requestBody
            defer {
                request.httpBody = nil
                requestBody.resetBytes(
                    in: requestBody.startIndex..<requestBody.endIndex
                )
            }

            let (bytes, rawResponse) = try await session.bytes(for: request)
            try Task.checkCancellation()

            guard let response = rawResponse as? HTTPURLResponse,
                  response.url == endpoint else {
                throw CommercialActivationHTTPSTransportError.invalidResponse
            }

            switch response.statusCode {
            case 200:
                return .licenseDocument(
                    try await readLicenseDocument(
                        from: bytes,
                        response: response
                    )
                )
            case 400, 401, 404:
                return .rejected(.codeRejected)
            case 429:
                return .rejected(.rateLimited)
            case 500...599:
                return .rejected(.serviceUnavailable)
            default:
                throw CommercialActivationHTTPSTransportError.invalidResponse
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError
            where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch let error as CommercialActivationHTTPSTransportError {
            throw error
        } catch {
            throw CommercialActivationHTTPSTransportError.unavailable
        }
    }

    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 1
        return configuration
    }

    static func makeSession() -> URLSession {
        URLSession(
            configuration: makeSessionConfiguration(),
            delegate: CommercialActivationHTTPSNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    private func readLicenseDocument(
        from bytes: URLSession.AsyncBytes,
        response: HTTPURLResponse
    ) async throws -> Data {
        guard response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == Self.licenseContentType else {
            throw CommercialActivationHTTPSTransportError.invalidResponse
        }

        let maximumBytes = CommercialLicenseDocumentStore.maximumDocumentBytes
        let declaredLength = response.expectedContentLength
        guard declaredLength <= Int64(maximumBytes) else {
            throw CommercialActivationHTTPSTransportError.responseTooLarge
        }

        var document = Data()
        if declaredLength > 0 {
            document.reserveCapacity(Int(declaredLength))
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            guard document.count < maximumBytes else {
                throw CommercialActivationHTTPSTransportError.responseTooLarge
            }
            document.append(byte)
        }

        guard !document.isEmpty else {
            throw CommercialActivationHTTPSTransportError.invalidResponse
        }
        return document
    }

    private static func validate(endpoint: URL) throws {
        guard endpoint.baseURL == nil,
              let components = URLComponents(
                url: endpoint,
                resolvingAgainstBaseURL: false
              ),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              isPublicDNSName(host),
              components.port == nil || components.port == 443,
              components.user == nil,
              components.password == nil,
              components.percentEncodedPath == activationPath,
              components.percentEncodedQuery == nil,
              components.fragment == nil else {
            throw CommercialActivationHTTPSTransportError.invalidEndpoint
        }
    }

    private static func isPublicDNSName(_ host: String) -> Bool {
        guard host.utf8.count <= 253,
              host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains(":"),
              host.unicodeScalars.allSatisfy(\.isASCII) else {
            return false
        }

        let disallowedSuffixes = [
            ".internal", ".invalid", ".local", ".localhost", ".test",
        ]
        guard host != "localhost",
              !disallowedSuffixes.contains(where: host.hasSuffix),
              !host.allSatisfy({ $0.isNumber || $0 == "." }) else {
            return false
        }

        return host.split(separator: ".", omittingEmptySubsequences: false)
            .allSatisfy { label in
                guard (1...63).contains(label.utf8.count),
                      label.first?.isLetter == true || label.first?.isNumber == true,
                      label.last?.isLetter == true || label.last?.isNumber == true else {
                    return false
                }
                return label.allSatisfy {
                    $0.isLetter || $0.isNumber || $0 == "-"
                }
            }
    }
}

final class CommercialActivationHTTPSNoRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
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
