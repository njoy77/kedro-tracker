import Foundation
import Synchronization
@testable import Kedro

/// A scripted HTTP layer for `APIClient`: no network in tests. Each request is recorded and
/// answered by `respond` (status code and JSON body), or fails with `URLError` when it throws.
nonisolated final class MockHTTP: HTTPTransport, Sendable {
    struct Recorded: Sendable {
        var method: String
        var path: String
        var query: [String: String]
        var body: Data?
        var authorization: String?
    }

    private let state: Mutex<(requests: [Recorded], respond: @Sendable (Recorded) throws -> (Int, Data))>

    init(_ respond: @escaping @Sendable (Recorded) throws -> (Int, Data) = { _ in (200, Data("{}".utf8)) }) {
        state = Mutex((requests: [], respond: respond))
    }

    var requests: [Recorded] { state.withLock { $0.requests } }

    func setResponder(_ respond: @escaping @Sendable (Recorded) throws -> (Int, Data)) {
        state.withLock { $0.respond = respond }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(filePath: "/")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let recorded = Recorded(
            method: request.httpMethod ?? "GET",
            path: url.path(),
            query: Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { $1 },
            body: request.httpBody,
            authorization: request.value(forHTTPHeaderField: "Authorization")
        )
        let respond = state.withLock { state in
            state.requests.append(recorded)
            return state.respond
        }
        let (status, body) = try respond(recorded)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        return (body, response ?? URLResponse())
    }

    /// The ops of a `POST /v1/ops` body.
    static func uploadedOps(_ request: Recorded) -> [GameOperation] {
        guard let body = request.body,
              let upload = try? KedroJSON.decoder().decode(UploadBody.self, from: body) else { return [] }
        return upload.ops
    }

    private struct UploadBody: Decodable {
        var ops: [GameOperation]
    }

    static func json(_ value: some Encodable) -> Data {
        (try? KedroJSON.encoder().encode(value)) ?? Data()
    }
}

extension APIClient {
    /// A client over a mock, signed in unless `token` is nil.
    static func mock(_ http: MockHTTP, token: String? = "test-token") -> APIClient {
        APIClient(baseURL: URL(string: "https://api.kedro.test") ?? URL(filePath: "/"), http: http, accessToken: { token })
    }
}
