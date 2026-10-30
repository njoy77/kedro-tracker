import Foundation

/// The HTTP layer under `APIClient`, so tests can swap in a mock (no network in tests).
nonisolated protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// `URLSession` as an `HTTPTransport`.
nonisolated struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Client for the Kedro API (`apps/api`, Hono). JSON both ways with `KedroJSON` coders and a
/// Supabase JWT bearer token on every authenticated call.
///
/// Endpoints live in `APIClient+Endpoints.swift`; request and response shapes in `APIModels.swift`.
/// Both must match the API contract exactly.
nonisolated struct APIClient: Sendable {
    let baseURL: URL
    var http: any HTTPTransport
    /// The signed-in user's access token, or nil when signed out (guest phones, the DEBUG test user).
    /// Defaults to `SupabaseAccessToken.current` (the AuthStore's client once registered).
    var accessToken: @Sendable () async -> String?

    init(
        baseURL: URL,
        http: any HTTPTransport = URLSessionTransport(),
        accessToken: @escaping @Sendable () async -> String? = SupabaseAccessToken.current
    ) {
        self.baseURL = baseURL
        self.http = http
        self.accessToken = accessToken
    }

    func health() async throws -> HealthResponse {
        try await send("GET", "health", authenticated: false)
    }

    /// Whether calls that need an account can be made right now.
    func hasAccount() async -> Bool {
        await accessToken() != nil
    }

    // MARK: Requests

    /// Sends a request without a body.
    func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> Response {
        try await perform(makeRequest(method, path, query: query, body: nil, authenticated: authenticated))
    }

    /// Sends a request with a JSON body.
    func send<Body: Encodable, Response: Decodable>(
        _ method: String,
        _ path: String,
        body: Body,
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> Response {
        let data: Data
        do {
            data = try KedroJSON.encoder().encode(body)
        } catch {
            throw APIError.encoding(String(describing: error))
        }
        return try await perform(makeRequest(method, path, query: query, body: data, authenticated: authenticated))
    }

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, authenticated: Bool) async throws -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let token = await accessToken() else { throw APIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw APIError.unauthorized(http.statusCode)
        default: throw APIError.badStatus(http.statusCode)
        }
        do {
            return try KedroJSON.decoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

nonisolated enum APIError: Error, Equatable, Sendable {
    /// A non-2xx status other than 401/403.
    case badStatus(Int)
    /// 401 or 403: the token was rejected or the caller isn't allowed.
    case unauthorized(Int)
    /// The call needs an account and this phone isn't signed in.
    case notSignedIn
    /// The request never got a response (offline, timeout, TLS).
    case transport(String)
    case encoding(String)
    case decoding(String)

    /// Worth retrying later (the server or the network may come back).
    var isRetryable: Bool {
        switch self {
        case .transport: true
        case .badStatus(let code): code == 408 || code == 429 || code >= 500
        case .unauthorized, .notSignedIn, .encoding, .decoding: false
        }
    }
}

/// Mirrors `HealthResponse` in `packages/shared`.
nonisolated struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let version: String
}
