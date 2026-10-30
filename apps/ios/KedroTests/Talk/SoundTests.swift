import AVFoundation
import Foundation
import Testing
@testable import Kedro

@Suite("Sound pack: which phone plays what")
struct SoundCueTests {
    private func listener(
        _ game: TestGame, device: DeviceID? = nil, seat: Int? = nil, speaker: Bool, learners: Set<SeatID> = [], hidden: Set<UUID> = []
    ) -> SoundListener {
        SoundListener(
            device: device ?? game.deviceA,
            seat: seat.map { game.seat($0) },
            isTableSpeaker: speaker,
            learners: learners,
            deviceForOperation: Dictionary(game.operations.map { ($0.opId, $0.deviceId) }, uniquingKeysWith: { first, _ in first }),
            hiddenTaunts: hidden
        )
    }

    private func started() -> TestGame {
        var game = TestGame(players: 3)
        game.setUp()
        return game
    }

    private func moments(_ cues: [SoundCue]) -> [SoundMoment] { cues.map(\.moment) }

    @Test("The saving phone snaps the card; the table speaker plays the outcome after it")
    func roundSaved() {
        var game = started()
        let before = game.state
        game.record([2, 9, 6], knocker: 0) // landed
        let after = game.state

        let savingSpeaker = SoundCues.cues(from: before, to: after, listener: listener(game, speaker: true))
        #expect(moments(savingSpeaker) == [.roundSaved, .knockLanded])
        #expect(savingSpeaker.last?.delay == SoundCues.outcomeDelay)

        let speakerElsewhere = SoundCues.cues(from: before, to: after, listener: listener(game, device: game.deviceB, speaker: true))
        #expect(speakerElsewhere == [SoundCue(moment: .knockLanded)])

        let savingOnly = SoundCues.cues(from: before, to: after, listener: listener(game, speaker: false))
        #expect(moments(savingOnly) == [.roundSaved])

        let bystander = SoundCues.cues(from: before, to: after, listener: listener(game, device: game.deviceB, speaker: false))
        #expect(bystander.isEmpty)
    }

    @Test("Tied and failed knocks, and red Kings")
    func outcomes() {
        var game = started()
        var before = game.state
        game.record([5, 5, 9], knocker: 0) // tied
        #expect(moments(SoundCues.cues(from: before, to: game.state, listener: listener(game, device: game.deviceB, speaker: true))) == [.knockTied])

        before = game.state
        game.record([12, 3, 9], knocker: 0) // failed
        #expect(moments(SoundCues.cues(from: before, to: game.state, listener: listener(game, device: game.deviceB, speaker: true))) == [.knockFailed])

        before = game.state
        game.record([4, -1, 9], knocker: 0) // a red King decided it
        #expect(moments(SoundCues.cues(from: before, to: game.state, listener: listener(game, device: game.deviceB, speaker: true))) == [.redKing])
    }

    @Test("Never a sound for a learner's own failed knock")
    func learnerFailedKnock() {
        var game = started()
        let before = game.state
        game.record([12, 3, 9], knocker: 0)
        let cues = SoundCues.cues(
            from: before, to: game.state, listener: listener(game, device: game.deviceB, speaker: true, learners: [game.seat(0)])
        )
        #expect(cues.isEmpty)
        // Someone else being a learner doesn't silence it.
        let other = SoundCues.cues(
            from: before, to: game.state, listener: listener(game, device: game.deviceB, speaker: true, learners: [game.seat(1)])
        )
        #expect(moments(other) == [.knockFailed])
    }

    @Test("A live knock raps on the table speaker only; clearing it is silent")
    func liveKnock() {
        var game = started()
        let before = game.state
        game.add(.knockMarked(.init(roundNumber: 1, knocker: game.seat(1))))
        #expect(moments(SoundCues.cues(from: before, to: game.state, listener: listener(game, speaker: true))) == [.liveKnock])
        #expect(SoundCues.cues(from: before, to: game.state, listener: listener(game, speaker: false)).isEmpty)

        let marked = game.state
        game.add(.knockMarked(.init(roundNumber: 1, knocker: nil)))
        #expect(SoundCues.cues(from: marked, to: game.state, listener: listener(game, speaker: true)).isEmpty)
    }

    @Test("Taunt received: the recipient's phone, or the table speaker for the table")
    func tauntReceived() {
        var game = started()
        let before = game.state
        let id = UUID()
        game.add(.tauntSent(.init(tauntId: id, roundNumber: 1, from: game.seat(0), fromName: "P0", target: .seat(game.seat(1)), content: .canned(id: "TT-10"))))
        let after = game.state

        let recipient = listener(game, device: game.deviceB, seat: 1, speaker: false)
        #expect(moments(SoundCues.cues(from: before, to: after, listener: recipient)) == [.tauntReceived])
        let someoneElse = listener(game, device: DeviceID(), seat: 2, speaker: true)
        #expect(SoundCues.cues(from: before, to: after, listener: someoneElse).isEmpty)
        let muted = listener(game, device: game.deviceB, seat: 1, speaker: false, hidden: [id])
        #expect(SoundCues.cues(from: before, to: after, listener: muted).isEmpty)

        let beforeTable = game.state
        game.add(.tauntSent(.init(tauntId: UUID(), roundNumber: 1, from: game.seat(0), fromName: "P0", target: .table, content: .canned(id: "TT-10"))))
        let speaker = listener(game, device: game.deviceB, seat: 2, speaker: true)
        #expect(moments(SoundCues.cues(from: beforeTable, to: game.state, listener: speaker)) == [.tauntReceived])
        let sender = listener(game, device: game.deviceA, seat: 0, speaker: true)
        #expect(SoundCues.cues(from: beforeTable, to: game.state, listener: sender).isEmpty)
    }

    @Test("Game end: the neigh everywhere, then dead last on the table speaker")
    func gameEnd() {
        var game = started()
        game.record([2, 9, 20], knocker: 0)
        let before = game.state
        game.add(.gameFinished(.init(reason: .endedEarly, finalRounds: before.rounds.map(\.round))))
        let after = game.state
        #expect(after.status == .finished)

        let everyone = SoundCues.cues(from: before, to: after, listener: listener(game, device: game.deviceB, speaker: false))
        #expect(moments(everyone) == [.winner])

        let speaker = SoundCues.cues(from: before, to: after, listener: listener(game, device: game.deviceB, speaker: true))
        #expect(moments(speaker) == [.winner, .deadLast])
        #expect(speaker.last?.delay == SoundCues.afterWinner)

        // Last place for a learner stays quiet.
        let learnerLast = SoundCues.cues(
            from: before, to: after, listener: listener(game, device: game.deviceB, speaker: true, learners: [game.seat(2)])
        )
        #expect(moments(learnerLast) == [.winner])
    }

    @Test("Debut: a signed-up player's 5th game")
    func debut() {
        var state = PreviewData.sampleState(throughRound: 8, finished: true)
        #expect(SoundCues.debuts(in: state) == [PreviewData.benSeat]) // Ben, 9 games before this one
        state.seats = state.seats.map { var seat = $0; seat.gamesPlayed = 10; return seat }
        #expect(SoundCues.debuts(in: state).isEmpty)
    }

    @Test("Settings: master switch off by default, per-moment toggles")
    func settings() {
        let settings = SoundSettings(defaults: scratchDefaults())
        #expect(!settings.isEnabled)
        #expect(!settings.plays(.winner))
        settings.isEnabled = true
        #expect(settings.plays(.winner))
        settings.set(.winner, on: false)
        #expect(!settings.plays(.winner))
        #expect(settings.plays(.knockFailed))
    }

    @Test("Playing respects the settings; preview ignores them")
    func player() async {
        let recorder = RecordingSoundPlayer()
        let settings = SoundSettings(defaults: scratchDefaults())
        await recorder.play([SoundCue(moment: .roundSaved)], settings: settings)
        #expect(recorder.played.isEmpty)
        recorder.preview(.winner)
        #expect(recorder.played == [.winner])
        settings.isEnabled = true
        await recorder.play([SoundCue(moment: .knockLanded, delay: .milliseconds(20)), SoundCue(moment: .roundSaved)], settings: settings)
        #expect(recorder.played == [.winner, .roundSaved, .knockLanded])
    }
}

@Suite("Sound pack files")
struct SoundPackTests {
    @Test("Every moment has a bundled file within its length budget", arguments: SoundMoment.allCases)
    func files(moment: SoundMoment) throws {
        let player = SoundPlayer(pack: .classic, bundle: .main)
        let url = try #require(player.url(for: moment), "Missing \(SoundPack.classic.resourceName(for: moment))")
        let file = try AVAudioFile(forReading: url)
        let audio = Double(file.length) / file.processingFormat.sampleRate
        #expect(audio > 0.05)
        #expect(audio <= SoundPack.maximumDuration(for: moment) + 0.05)
    }

    @Test("Only the neigh is final; the rest are marked placeholders")
    func placeholders() {
        #expect(!SoundPack.classic.isPlaceholder(.winner))
        #expect(SoundPack.classic.isPlaceholder(.knockFailed))
    }
}

@Suite("Table speaker election")
struct TableSpeakerTests {
    @Test("Scorekeeper's phone by default, then whoever claims it")
    func election() throws {
        var operations = PreviewData.sampleOperations(throughRound: 3, finished: false)
        var state = GameState.fold(operations, gameID: PreviewData.sampleGameID)
        #expect(TableSpeaker.device(for: state) == PreviewData.noahPhone)
        #expect(TableSpeaker.isThisPhone(PreviewData.noahPhone, state: state, preference: .automatic))
        #expect(!TableSpeaker.isThisPhone(PreviewData.noahPhone, state: state, preference: .never))
        #expect(!TableSpeaker.isThisPhone(PreviewData.anaPhone, state: state, preference: .automatic))

        let last = try #require(operations.last)
        operations.append(GameOperation(
            gameId: PreviewData.sampleGameID, deviceId: PreviewData.anaPhone,
            hlc: HLC(wallMs: last.hlc.wallMs + 1_000, counter: 0, node: PreviewData.anaPhone.uuidString),
            actorPlayerId: PreviewData.ana.id, payload: .tableSpeakerClaimed(.init(deviceId: PreviewData.anaPhone))
        ))
        state = GameState.fold(operations, gameID: PreviewData.sampleGameID)
        #expect(TableSpeaker.device(for: state) == PreviewData.anaPhone)
        #expect(!TableSpeaker.isThisPhone(PreviewData.noahPhone, state: state, preference: .automatic))
    }

    @Test("A 'This Phone' phone claims once, and never takes it back from an explicit claim")
    func shouldClaim() throws {
        let state = PreviewData.sampleState(throughRound: 3)
        #expect(TableSpeaker.shouldClaim(PreviewData.anaPhone, state: state, preference: .always))
        #expect(!TableSpeaker.shouldClaim(PreviewData.anaPhone, state: state, preference: .automatic))
        #expect(!TableSpeaker.shouldClaim(PreviewData.noahPhone, state: state, preference: .always)) // already elected
        var claimed = state
        claimed.tableSpeaker = PreviewData.noahPhone
        #expect(!TableSpeaker.shouldClaim(PreviewData.anaPhone, state: claimed, preference: .always))
        let finished = PreviewData.sampleState(throughRound: 8, finished: true)
        #expect(!TableSpeaker.shouldClaim(PreviewData.anaPhone, state: finished, preference: .always))
    }
}

/// Records what would have played.
final class RecordingSoundPlayer: SoundPlaying {
    private(set) var played: [SoundMoment] = []

    func play(_ moment: SoundMoment, settings: SoundSettings) {
        guard settings.plays(moment) else { return }
        played.append(moment)
    }

    func preview(_ moment: SoundMoment) {
        played.append(moment)
    }
}
