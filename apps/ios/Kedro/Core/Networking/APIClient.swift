import Foundation

/// Thin client for the Kedro API (`apps/api`).
struct APIClient: Sendable {
    let baseURL: URL
    var session: URLSession = .shared

    func health() async throws -> HealthResponse {
        try await get("health")
    }

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        let (data, response) = try await session.data(from: baseURL.appending(path: path))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

enum APIError: Error, Equatable {
    case badStatus(Int)
}

/// Mirrors `HealthResponse` in `packages/shared`.
struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let version: String
}
