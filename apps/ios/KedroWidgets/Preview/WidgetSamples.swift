import Foundation

/// The design spec's sample game (§17) as Live Activity content and widget snapshots, for
/// previews and the widget gallery placeholder. The app builds the real thing from the fold.
nonisolated enum WidgetSamples {
    static let attributes = LiveGameAttributes(
        gameID: "00000000-0000-4000-8000-000000000001",
        tableWord: "Cold Deck",
        mySeatID: "p:noah"
    )

    private static func row(
        _ id: String, _ name: String, rank: Int, ordinal: String, score: String, delta: String,
        outcome: LiveKnockOutcome? = nil, isMe: Bool = false, isLeader: Bool = false, isDealer: Bool = false,
        avatar: LiveAvatar
    ) -> LiveStandingRow {
        LiveStandingRow(
            id: id, name: name, rankLabel: "\(rank)", ordinal: ordinal, score: score, delta: delta,
            outcome: outcome, isMe: isMe, isLeader: isLeader, isDealer: isDealer, avatar: avatar
        )
    }

    /// After Round 5: Noah 26, Ana 29, Ben 44, Cleo 45, Sam 47. Noah deals Round 6.
    static let afterRound5Rows: [LiveStandingRow] = [
        row("p:noah", "Noah", rank: 1, ordinal: "1st", score: "26", delta: "\u{2212}10", outcome: .landed, isMe: true, isLeader: true, isDealer: true, avatar: .curated(id: "crow")),
        row("p:ana", "Ana", rank: 2, ordinal: "2nd", score: "29", delta: "+9", avatar: .emoji(emoji: "🦊", colorIndex: 0)),
        row("p:ben", "Ben", rank: 3, ordinal: "3rd", score: "44", delta: "+6", avatar: .curated(id: "bull")),
        row("p:cleo", "Cleo", rank: 4, ordinal: "4th", score: "45", delta: "+11", avatar: .curated(id: "joker")),
        row("g:sam", "Sam", rank: 5, ordinal: "5th", score: "47", delta: "+4", avatar: .initial(letter: "S", isGuest: true)),
    ]

    static let afterRound5 = LiveGameAttributes.ContentState(
        phase: .active,
        roundNumber: 6,
        plannedRounds: 8,
        metadataLine: "ROUND 6 OF 8 · NOAH DEALS",
        rows: afterRound5Rows,
        factLine: "Round 5. Noah knocked on 2.",
        liveKnockLine: nil,
        staleTemplate: "Last update {time} · Open Kedro to catch up",
        action: LiveActivityButton(kind: .recordRound, title: "Record Round 6"),
        updatedAt: Int(Date.now.timeIntervalSince1970)
    )

    static var liveKnock: LiveGameAttributes.ContentState {
        var state = afterRound5
        state.liveKnockLine = "Sam knocked · last turns"
        return state
    }

    /// An 8-seat table where you're 7th: ranks 1–4, ···, then you.
    static var truncated: LiveGameAttributes.ContentState {
        var state = afterRound5
        var rows = afterRound5Rows.map { row -> LiveStandingRow in
            var row = row
            row.isMe = false
            return row
        }
        rows[0].isDealer = false
        rows += [
            row("p:jo", "Jo", rank: 6, ordinal: "6th", score: "51", delta: "+12", avatar: .curated(id: "wolf")),
            row("p:max", "Max", rank: 7, ordinal: "7th", score: "58", delta: "2 + 10", outcome: .failed, isMe: true, avatar: .curated(id: "shark")),
            row("p:maya", "Maya", rank: 8, ordinal: "8th", score: "63", delta: "+15", isDealer: true, avatar: .emoji(emoji: "🐍", colorIndex: 2)),
        ]
        state.rows = rows
        state.metadataLine = "ROUND 6 OF 8 · MAYA DEALS"
        return state
    }

    static var selfReport: LiveGameAttributes.ContentState {
        var state = afterRound5
        state.action = LiveActivityButton(kind: .reportHand, title: "Report Your Hand")
        return state
    }

    static let snapshot = WidgetSnapshot(
        generatedAt: .now,
        playerName: "Noah",
        standing: StandingSnapshot(rank: 13, scopeLabel: "Global", rating: 1086, weeklyMovement: 2, gamesPlayed: 41),
        rivalry: RivalrySnapshot(
            rivalID: "p:00000000-0000-4000-8000-000000000002",
            rivalName: "Ana",
            rivalAvatar: .emoji(emoji: "🦊", colorIndex: 0),
            myAvatar: .curated(id: "crow"),
            myWins: 5,
            theirWins: 12,
            line: "Ana 12, you 5. Ana's living in your head rent-free."
        ),
        nextBadge: BadgeSnapshot(badgeID: "BG-19", name: "Three-Peat", tier: .red, progress: 1, target: 3, progressLine: "1 of 3 wins in a row")
    )

    static let newPlayer = WidgetSnapshot(
        generatedAt: .now,
        playerName: "Sam",
        standing: StandingSnapshot(rank: nil, scopeLabel: "Global", rating: nil, weeklyMovement: 0, gamesPlayed: 3),
        rivalry: nil,
        nextBadge: BadgeSnapshot(badgeID: "BG-03", name: "On the Board", tier: .silver, progress: 3, target: 10, progressLine: "3 of 10 games")
    )
}
