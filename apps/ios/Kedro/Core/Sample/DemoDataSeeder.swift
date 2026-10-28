#if DEBUG
import Foundation

/// DEBUG only: fills a store with the sample history and the finished sample game, so stats
/// screens have something to show. Surfaced as "Load Demo Data" in debug builds (Settings and
/// the Play stub). The DEBUG test user signs in as Noah, so "You" is Noah in the demo.
enum DemoDataSeeder {
    /// Appends the demo games (idempotent: re-seeding adds nothing).
    /// - Returns: the number of new operations stored.
    @discardableResult
    static func seed(into store: any GameStore, includeSampleGame: Bool = true) async throws -> Int {
        var operations = PreviewData.historyOperations
        if includeSampleGame {
            operations += PreviewData.sampleOperations(throughRound: 8, finished: true)
        }
        return try await store.append(operations).count
    }
}
#endif
