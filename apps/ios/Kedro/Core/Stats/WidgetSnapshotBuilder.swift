import Foundation

// Builds the home and Lock Screen widgets' snapshot (design §13.3) from stats. Widgets never
// compute stats themselves; the app publishes this through `WidgetSnapshotPublisher` when a game
// finishes and after a claim.

extension StatsSnapshot {
    /// The widget snapshot for a player, with every line rendered in `voice`.
    func widgetSnapshot(for me: PlayerRef, name: String, avatar: Avatar?, voice: Voice, now: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            playerName: name,
            standing: standingSnapshot(for: me, now: now),
            rivalry: rivalrySnapshot(for: me, myName: name, myAvatar: avatar, voice: voice),
            nextBadge: progress(for: me).nextBadge.map(Self.badgeSnapshot)
        )
    }

    /// Rank on the Played With board by rating, plus places gained since a week ago.
    func standingSnapshot(for me: PlayerRef, now: Date) -> StandingSnapshot {
        let progress = progress(for: me)
        let rank = progress.isRanked ? ratingRank(of: me, scope: .playedWith, viewer: me) : nil
        var movement = 0
        if let rank {
            let weekAgo = now.addingTimeInterval(-7 * 24 * 3_600)
            let earlier = StatsSnapshot(games: games.filter { $0.finishedAt < weekAgo }, options: options, calendar: calendar)
            if let before = earlier.ratingRank(of: me, scope: .playedWith, viewer: me) {
                movement = before.position - rank.position
            }
        }
        return StandingSnapshot(
            rank: rank?.position,
            scopeLabel: "Played With",
            rating: progress.isRanked ? progress.rating : nil,
            weeklyMovement: movement,
            gamesPlayed: progress.gamesPlayed
        )
    }

    /// The most-played rival and how the head-to-head stands (R-06 when they lead, R-03 when
    /// you do, R-04 when it's even).
    func rivalrySnapshot(for me: PlayerRef, myName: String, myAvatar: Avatar?, voice: Voice) -> RivalrySnapshot? {
        guard let rival = rivals(of: me, limit: 1).first else { return nil }
        let h2h = headToHead(me, rival)
        let mine = h2h.a == options.canonical(me) ? h2h.aAhead : h2h.bAhead
        let theirs = h2h.a == options.canonical(me) ? h2h.bAhead : h2h.aAhead
        let rivalName = name(of: rival)
        let line: String = if theirs > mine {
            voice.line("R-06", ["name": rivalName, "a": theirs, "b": mine])
        } else if mine > theirs {
            voice.line("R-03", ["name": rivalName, "a": mine, "b": theirs])
        } else {
            voice.line("R-04", ["a": mine])
        }
        return RivalrySnapshot(
            rivalID: rival.seatID.rawValue,
            rivalName: rivalName,
            rivalAvatar: Self.liveAvatar(identity(of: rival)?.avatar, name: rivalName, isGuest: rival.isGuest),
            myAvatar: Self.liveAvatar(myAvatar, name: myName, isGuest: me.isGuest),
            myWins: mine,
            theirWins: theirs,
            line: line
        )
    }

    private static func badgeSnapshot(_ progress: BadgeProgress) -> BadgeSnapshot {
        let definition = progress.badge.definition
        let tier: BadgeTierSnapshot = switch definition.tier {
        case .gold: .gold
        case .red: .red
        case .silver, .none: .silver
        }
        return BadgeSnapshot(
            badgeID: progress.badge.rawValue,
            name: definition.name,
            tier: tier,
            progress: min(progress.value, progress.target),
            target: progress.target,
            progressLine: definition.rule.isEmpty ? progress.label : "\(progress.label) · \(definition.rule)"
        )
    }

    private static func liveAvatar(_ avatar: Avatar?, name: String, isGuest: Bool) -> LiveAvatar {
        switch avatar {
        case .emoji(let emoji, let colorIndex): .emoji(emoji: emoji, colorIndex: colorIndex)
        case .curated(let id): .curated(id: id.rawValue)
        case .photo, nil: .initial(letter: name.first.map { String($0).uppercased() } ?? "?", isGuest: isGuest)
        }
    }
}
