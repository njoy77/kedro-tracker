// Transcribed from docs/kedro-ios-copy.md §11 (N, F, E, T), §12 (TT), §13 (RC) and §19 (SN).
// Keep in sync with the deck.

nonisolated extension CopyDeck {
    static let system: [CopyEntry] = [
        CopyEntry("N-01", "Saved you a seat",
                  clean: "{host} saved you a seat at {word}."),
        CopyEntry("N-02", "Made the leaderboard",
                  clean: "You're on the board. {rating}. No more hiding."),
        CopyEntry("N-03", "Badge earned away",
                  clean: "You earned {badge}. Go look."),
        CopyEntry("N-04", "Guest claimed",
                  clean: "{name} claimed their games. You did this."),
        CopyEntry("N-05", "Self-report nudge (Live Activity)",
                  clean: "Round {r}: your hand. The table's waiting.",
                  spicy: "Round {r}: your hand. The table's waiting a fucking while."),
        CopyEntry("N-06", "Live Activity stale",
                  clean: "Last update {time} · Open Kedro to catch up"),
        CopyEntry("N-07", "Nearby alert",
                  clean: "{name} started a table nearby."),
        CopyEntry("N-08", "Receipt received",
                  clean: "{name} sent you a receipt from {word}."),
        CopyEntry("N-09", "Wrapped is ready",
                  clean: "Your {year} in Kedro is ready. Brace yourself.",
                  unhinged: "Your {year} in Kedro is ready. It's a lot."),
        CopyEntry("F-01", "Offline, peers in sync",
                  clean: "Offline · {n} phones in sync"),
        CopyEntry("F-02", "Offline, solo",
                  clean: "Offline · saved on this phone"),
        CopyEntry("F-03", "Syncing",
                  clean: "Syncing…"),
        CopyEntry("F-04", "App Clip offline",
                  clean: "This needs internet. Ask {host} to report your hand for now."),
        CopyEntry("F-05", "Offline explainer",
                  clean: "No internet? No problem. Phones at a table talk to each other directly.",
                  spicy: "No internet? Who gives a shit. Phones at a table talk to each other directly."),
        CopyEntry("E-01", "Server error",
                  clean: "Our servers fell over. Your game's safe on this phone.",
                  spicy: "Our servers shat the bed. Your game's safe on this phone."),
        CopyEntry("E-02", "Nearby permission denied",
                  clean: "Kedro can't see the table without Local Network. Turn it on in Settings, or use the QR code."),
        CopyEntry("E-03", "Couldn't join",
                  clean: "Couldn't reach {host}'s phone. Move closer or scan their QR code."),
        CopyEntry("E-04", "Under 3 seats",
                  clean: "Cambio needs 3. Two people is just a staring contest."),
        CopyEntry("T-01", "Talk sheet title",
                  clean: "Talk your trash",
                  spicy: "Talk your shit"),
        CopyEntry("T-02", "Custom field placeholder",
                  clean: "Say it. 80 characters.",
                  unhinged: "Say it. 80 characters. Make them count."),
        CopyEntry("T-10", "Rate limit",
                  clean: "Save some for the next round.",
                  unhinged: "Save some for the next round, motormouth."),
        // T-11 (muted) has no string: the sender is never told.
        CopyEntry("T-12", "Blocked by filter",
                  clean: "That one's not going out. Kedro doesn't do slurs."),
        CopyEntry("T-13", "Reported (to reporter)",
                  clean: "Reported. You won't see it again."),
    ]

    /// Canned taunt library (the deck's launch sample). Groups: `TauntGroup`.
    static let taunts: [CopyEntry] = [
        CopyEntry("TT-01", "Knocks (at a knocker)",
                  clean: "Knocking on that? Brave.",
                  unhinged: "Knocking on that? Brave as shit."),
        CopyEntry("TT-02", "Knocks",
                  clean: "Knock now. I dare you.",
                  unhinged: "Knock now. I fucking dare you."),
        CopyEntry("TT-03", "Knocks (after a fail)",
                  clean: "+10. Worth it?",
                  unhinged: "+10. Worth it, dumbass?"),
        CopyEntry("TT-04", "Red Kings",
                  clean: "Enjoy that red King. It's the last nice thing you'll get."),
        CopyEntry("TT-05", "Leader",
                  clean: "Comfortable up there?",
                  unhinged: "Comfortable up there, you smug bastard?"),
        CopyEntry("TT-06", "Leader",
                  clean: "It's a long game.",
                  unhinged: "It's a long game, asshole."),
        CopyEntry("TT-07", "Last place",
                  clean: "Have you tried being lower?",
                  unhinged: "Have you tried being lower, genius?"),
        CopyEntry("TT-08", "Last place",
                  clean: "Thoughts and prayers."),
        CopyEntry("TT-09", "Comebacks",
                  clean: "I'm coming for you.",
                  unhinged: "I'm coming for your ass."),
        CopyEntry("TT-10", "General",
                  clean: "Scoreboard."),
        CopyEntry("TT-11", "General",
                  clean: "Talk is cheap. Your hand isn't."),
        CopyEntry("TT-12", "General",
                  clean: "No notes.",
                  unhinged: "No notes. Just disgust."),
        CopyEntry("TT-13", "General",
                  clean: "Somebody's sweating.",
                  unhinged: "Somebody's sweating fucking bullets."),
        CopyEntry("TT-14", "General",
                  clean: "Deal faster.",
                  unhinged: "Deal faster, I'm aging over here."),
    ]

    static let receipts: [CopyEntry] = [
        CopyEntry("RC-01", "You won",
                  clean: "Scoreboard.",
                  unhinged: "Scoreboard, dickhead."),
        CopyEntry("RC-02", "They failed a knock",
                  clean: "Knocking on {hand} is a choice. A bad choice.",
                  spicy: "Knocking on {hand} is a choice. A shit choice."),
        CopyEntry("RC-03", "Rematch",
                  clean: "Run it back. I'll go easy. (I won't.)",
                  spicy: "Run it back. I'll go easy. (I fucking won't.)"),
        CopyEntry("RC-04", "Chasing them",
                  clean: "Gap's {gap}. Sleep with one eye open.",
                  unhinged: "Gap's {gap}. Sleep with one eye open, asshole."),
        CopyEntry("RC-05", "They finished last",
                  clean: "Last place looked good on you.",
                  unhinged: "Last place looked fucking great on you."),
        CopyEntry("RC-06", "You beat their knock",
                  clean: "Your knock. My {low}. Remember that."),
    ]

    static let sounds: [CopyEntry] = [
        CopyEntry("SN-01", "Sounds footer",
                  clean: "Off by default. Respects your Silent switch. Only the table speaker plays the big moments."),
        CopyEntry("SN-02", "Table speaker explainer",
                  clean: "One phone plays the shared sounds so eight phones don't neigh at once.",
                  unhinged: "One phone plays the shared sounds so eight phones don't neigh at once like a goddamn stable."),
        CopyEntry("SN-03", "Turning sounds on",
                  clean: "Sounds on. The neigh is earned, not given."),
    ]
}

/// Canned taunt groups (design §8.1), in display order.
nonisolated enum TauntGroup: String, Sendable, CaseIterable, Identifiable {
    case knocks, redKings, leader, lastPlace, comebacks, general

    var id: String { rawValue }

    /// Literal group title.
    var title: String {
        switch self {
        case .knocks: "Knocks"
        case .redKings: "Red Kings"
        case .leader: "Leader"
        case .lastPlace: "Last place"
        case .comebacks: "Comebacks"
        case .general: "General"
        }
    }

    /// The canned taunts in this group (copy IDs).
    var tauntIDs: [String] {
        switch self {
        case .knocks: ["TT-01", "TT-02", "TT-03"]
        case .redKings: ["TT-04"]
        case .leader: ["TT-05", "TT-06"]
        case .lastPlace: ["TT-07", "TT-08"]
        case .comebacks: ["TT-09"]
        case .general: ["TT-10", "TT-11", "TT-12", "TT-13", "TT-14"]
        }
    }
}
