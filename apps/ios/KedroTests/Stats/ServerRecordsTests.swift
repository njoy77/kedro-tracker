import Foundation
import Testing
@testable import Kedro

/// The Board's records from the server (`GET /v1/records`), mapped onto the same rows the
/// records grid and record boards render for this phone's own history.
@Suite("Server records")
struct ServerRecordsTests {
    @Test("Server records map onto record rows, with the game a best game was set in")
    func mapping() throws {
        let ana = PreviewData.ana
        let ben = PreviewData.ben
        let game = GameID()
        func player(_ summary: PlayerSummary) -> String {
            #"{"id":"\#(summary.id.uuidString.lowercased())","displayName":"\#(summary.displayName)","handle":"\#(summary.handle.rawValue)","avatar":{"kind":"curated","id":"spade"}}"#
        }
        let json = """
        {"scope":"playedWith","records":[
          {"kind":"bestGame","rows":[
            {"rank":1,"player":\(player(ana)),"value":-30,"isMe":false,"game":{"gameId":"\(game.uuidString.lowercased())","tableWord":"Cold Deck","finishedAt":"2026-10-24T21:33:19Z"}},
            {"rank":2,"player":\(player(ben)),"value":-10,"isMe":true}
          ]},
          {"kind":"mostGames","rows":[
            {"rank":1,"player":\(player(ana)),"value":22,"isMe":false},
            {"rank":1,"player":\(player(ben)),"value":22,"isMe":true}
          ]},
          {"kind":"someFutureRecord","rows":[]}
        ]}
        """
        let response = try KedroJSON.decoder().decode(RecordsResponse.self, from: Data(json.utf8))
        let records = ServerStats.records(from: response)

        #expect(Set(records.keys) == [.bestGame, .mostGames], "unknown kinds are skipped")
        let best = try #require(records[.bestGame])
        #expect(best.map(\.identity.name) == ["Ana", "Ben"])
        #expect(best.map(\.value) == [-30, -10])
        #expect(best.first?.ref == ana.ref)
        #expect(best.first?.gameID == game)
        #expect(best.first?.tableWord == "Cold Deck")
        #expect(best.first?.date != nil)
        #expect(best.last?.tableWord == nil)
        #expect(records[.mostGames]?.map(\.rank) == [1, 1], "ties share a rank")
    }
}
