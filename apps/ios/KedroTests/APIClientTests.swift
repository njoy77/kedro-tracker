import Foundation
import Testing
@testable import Kedro

struct APIClientTests {
    @Test func decodesHealthResponse() throws {
        let json = Data(#"{"status":"ok","version":"0.1.0"}"#.utf8)
        let health = try JSONDecoder().decode(HealthResponse.self, from: json)
        #expect(health == HealthResponse(status: "ok", version: "0.1.0"))
    }
}
