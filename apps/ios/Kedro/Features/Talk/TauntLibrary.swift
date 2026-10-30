import Foundation

/// What's happening at the table right now, for picking relevant taunts (design §8.1).
nonisolated enum TauntMoment: String, Hashable, Sendable, CaseIterable {
    /// A live knock is marked for the round being played (at the knocker, or the table).
    case liveKnock
    /// The last round's knock failed (at the knocker, or the table).
    case knockFailed
    case knockLanded
    case knockTied
    /// A red King decided the last round (at whoever held it, or the table).
    case redKing
    /// The target leads.
    case leader
    /// The target is last.
    case lastPlace
    /// The sender is behind (the target, or the leader).
    case comeback
    /// The round being played is the last planned one.
    case lastRound
}

/// One canned taunt: its copy entry (all three levels), group, and the moments it's for.
nonisolated struct CannedTaunt: Hashable, Sendable, Identifiable {
    let entry: CopyEntry
    let group: TauntGroup
    /// Empty: fits any time. Otherwise shown only while one of these is true.
    let moments: Set<TauntMoment>

    var id: String { entry.id }

    func fits(_ context: TauntContext) -> Bool {
        moments.isEmpty || !moments.isDisjoint(with: context.moments)
    }

    /// True when the taunt is about something happening right now (sorts first).
    func isTimely(in context: TauntContext) -> Bool {
        !moments.isEmpty && !moments.isDisjoint(with: context.moments)
    }
}

/// A group of taunts as the Talk sheet shows it.
nonisolated struct TauntSection: Hashable, Sendable, Identifiable {
    var group: TauntGroup
    var taunts: [CannedTaunt]
    /// Has taunts about what just happened ("KNOCKS · RIGHT NOW").
    var isTimely: Bool

    var id: TauntGroup { group }

    /// Literal label: "KNOCKS · RIGHT NOW" or "GENERAL".
    var title: String {
        isTimely ? "\(group.title) · right now" : group.title
    }
}

/// The canned taunt library (design §8.1, copy deck §12): the deck's 14 samples (`TT-01…TT-14`,
/// resolved from `CopyDeck.standard`) plus the launch library kept here (`TT-15…`). Every taunt
/// renders in the viewer's level; Clean never swears, Spicy swears about a third of the time
/// (one per line), Unhinged at least half (enforced by `TauntLibraryTests`).
///
/// TODO(copy): the copy deck targets ~150 taunts at launch; this is 92. Report new lines to
/// foundation so the deck stays the source of truth.
nonisolated enum TauntLibrary {
    /// Every canned taunt, in library order.
    static let all: [CannedTaunt] = deckTaunts + launchTaunts

    private static let byID: [String: CannedTaunt] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func taunt(_ id: String) -> CannedTaunt? { byID[id] }

    /// The copy entry for a canned taunt ID (deck or library). Unknown IDs (a newer phone's
    /// library) return nil; callers show nothing rather than an ID.
    static func entry(_ id: String) -> CopyEntry? { byID[id]?.entry ?? CopyDeck.standard[id] }

    /// The sections for a moment: taunts that fit, timely groups first (in display order), and
    /// within a group timely taunts first.
    static func sections(for context: TauntContext) -> [TauntSection] {
        let sections = TauntGroup.allCases.compactMap { group -> TauntSection? in
            let fitting = all.filter { $0.group == group && $0.fits(context) }
            guard !fitting.isEmpty else { return nil }
            let timely = fitting.filter { $0.isTimely(in: context) }
            let rest = fitting.filter { !$0.isTimely(in: context) }
            return TauntSection(group: group, taunts: timely + rest, isTimely: !timely.isEmpty)
        }
        return sections.filter(\.isTimely) + sections.filter { !$0.isTimely }
    }

    // MARK: Library

    /// The deck's samples with their groups and moments.
    private static let deckTaunts: [CannedTaunt] = [
        deck("TT-01", .knocks, [.liveKnock]),
        deck("TT-02", .knocks),
        deck("TT-03", .knocks, [.knockFailed]),
        deck("TT-04", .redKings, [.redKing]),
        deck("TT-05", .leader, [.leader]),
        deck("TT-06", .leader, [.leader]),
        deck("TT-07", .lastPlace, [.lastPlace]),
        deck("TT-08", .lastPlace, [.lastPlace]),
        deck("TT-09", .comebacks, [.comeback]),
        deck("TT-10", .general),
        deck("TT-11", .general),
        deck("TT-12", .general),
        deck("TT-13", .general),
        deck("TT-14", .general),
    ]

    private static func deck(_ id: String, _ group: TauntGroup, _ moments: Set<TauntMoment> = []) -> CannedTaunt {
        let entry = CopyDeck.standard[id] ?? CopyEntry(id, group.title, clean: "")
        return CannedTaunt(entry: entry, group: group, moments: moments)
    }

    private static func line(
        _ id: String, _ group: TauntGroup, _ moments: Set<TauntMoment> = [],
        clean: String, spicy: String? = nil, unhinged: String? = nil
    ) -> CannedTaunt {
        CannedTaunt(entry: CopyEntry(id, group.title, clean: clean, spicy: spicy, unhinged: unhinged), group: group, moments: moments)
    }

    /// The launch library. In each line, a nil level is "=" in the deck (same as the level to
    /// its left).
    private static let launchTaunts: [CannedTaunt] = [
        // Knocks
        line("TT-15", .knocks, [.liveKnock], clean: "Last turns. Make them count.", unhinged: "Last turns. Make them fucking count."),
        line("TT-16", .knocks, [.liveKnock], clean: "Bold knock. Let's see the cards.", spicy: "Bold knock. Let's see the damn cards.", unhinged: "Bold fucking knock. Cards up."),
        line("TT-17", .knocks, [.liveKnock], clean: "That knock smells like a bluff.", spicy: "That knock smells like bullshit."),
        line("TT-18", .knocks, [.knockFailed], clean: "Knocked into a wall.", spicy: "Knocked straight into a damn wall.", unhinged: "Knocked face-first into a wall, dumbass."),
        line("TT-19", .knocks, [.knockFailed], clean: "Ten points for confidence.", unhinged: "Ten points for confidence. Zero for brains."),
        line("TT-20", .knocks, [.knockFailed], clean: "That knock aged badly.", spicy: "That knock aged like shit."),
        line("TT-21", .knocks, [.knockFailed], clean: "Plus ten. Wear it.", unhinged: "Plus ten. Wear it, you menace."),
        line("TT-22", .knocks, [.knockLanded], clean: "Fine. That one was clean.", spicy: "Fine. That one was clean as hell."),
        line("TT-23", .knocks, [.knockLanded], clean: "Minus ten. Don't get used to it.", unhinged: "Minus ten. Don't get fucking used to it."),
        line("TT-24", .knocks, [.knockLanded], clean: "Lucky knock. Say it with me: lucky.", unhinged: "Lucky fucking knock. Say it."),
        line("TT-25", .knocks, [.knockTied], clean: "Tied. All that drama for nothing.", spicy: "Tied. All that drama for shit."),
        line("TT-26", .knocks, [.knockTied], clean: "A tie. The most boring outcome.", spicy: "A tie. Boring as shit."),
        line("TT-27", .knocks, clean: "Knock already. We're waiting.", unhinged: "Knock already. We're fucking waiting."),
        line("TT-28", .knocks, clean: "Scared to knock? Understandable.", unhinged: "Scared to knock? Understandable, coward."),
        line("TT-29", .knocks, clean: "You're not knocking on that. Right?", unhinged: "You're not knocking on that. Right, genius?"),
        line("TT-30", .knocks, [.liveKnock], clean: "Somebody knocked. Everybody panic.", spicy: "Somebody knocked. Shit's getting real."),

        // Red Kings
        line("TT-31", .redKings, [.redKing], clean: "Red King bailout. Must be nice.", unhinged: "Red King bailout. Must be fucking nice."),
        line("TT-32", .redKings, [.redKing], clean: "Saved by royalty. Embarrassing.", unhinged: "Saved by royalty, you lucky bastard."),
        line("TT-33", .redKings, [.redKing], clean: "That red King did all the work.", spicy: "That red King did all the damn work."),
        line("TT-34", .redKings, [.redKing], clean: "Below zero. Show-off.", unhinged: "Below zero, you show-off bastard."),
        line("TT-35", .redKings, clean: "Who's hiding the red King?", spicy: "Who's hiding the damn red King?", unhinged: "Who the fuck has the red King?"),
        line("TT-36", .redKings, clean: "I can smell a red King from here."),
        line("TT-37", .redKings, clean: "Red King or not, you're in trouble.", spicy: "Red King or not, you're in deep shit."),
        line("TT-38", .redKings, [.redKing], clean: "One card carried that whole round.", unhinged: "One card carried your sorry ass."),
        line("TT-39", .redKings, clean: "Peek at your cards. Go on. Peek.", unhinged: "Peek at your cards. Go on. I'll wait, asshole."),

        // Leader
        line("TT-40", .leader, [.leader], clean: "Enjoy the view. It won't last.", unhinged: "Enjoy the view. It won't fucking last."),
        line("TT-41", .leader, [.leader], clean: "First place looks nervous.", spicy: "First place looks nervous as hell."),
        line("TT-42", .leader, [.leader], clean: "The crown's on loan.", unhinged: "The crown's on loan, dickhead."),
        line("TT-43", .leader, [.leader], clean: "Leading means nothing until it's final.", spicy: "Leading means shit until it's final."),
        line("TT-44", .leader, [.leader], clean: "Big lead. Bigger target.", spicy: "Big lead. Bigger target on your ass."),
        line("TT-45", .leader, [.leader], clean: "Every leader blows it eventually.", unhinged: "Every leader bottles it eventually. Your turn."),
        line("TT-46", .leader, [.leader], clean: "Somebody knock that one down a peg.", spicy: "Somebody knock that smug ass down a peg."),
        line("TT-47", .leader, [.leader], clean: "You peaked. Respectfully.", unhinged: "You peaked. Respectfully, fuck you."),
        line("TT-48", .leader, [.leader], clean: "Nice lead. Shame about the rest of the game.", unhinged: "Nice lead. Shame about the rest of the damn game."),
        line("TT-49", .leader, [.leader], clean: "Wire to wire? Not on my watch.", unhinged: "Wire to wire? Not on my fucking watch."),
        line("TT-50", .leader, [.leader], clean: "Don't get comfortable.", spicy: "Don't get comfortable, smartass."),

        // Last place
        line("TT-51", .lastPlace, [.lastPlace], clean: "The bottom has a great view of everyone."),
        line("TT-52", .lastPlace, [.lastPlace], clean: "Last place is a choice. Bold one.", spicy: "Last place is a choice. A shit one."),
        line("TT-53", .lastPlace, [.lastPlace], clean: "Someone has to be last. Thanks for volunteering.", unhinged: "Someone has to be last. Thanks for volunteering, genius."),
        line("TT-54", .lastPlace, [.lastPlace], clean: "Rock bottom called. It wants its seat back."),
        line("TT-55", .lastPlace, [.lastPlace], clean: "Cooked. Fully cooked.", spicy: "Cooked. Fully fucking cooked."),
        line("TT-56", .lastPlace, [.lastPlace], clean: "Still time. Not much, but some.", unhinged: "Still time. Not a lot, but some, dumbass."),
        line("TT-57", .lastPlace, [.lastPlace], clean: "Is the plan to lose on purpose?", unhinged: "Is the plan to lose on purpose, or what the hell?"),
        line("TT-58", .lastPlace, [.lastPlace], clean: "Last place. Say something.", unhinged: "Last place. Say something, loser."),
        line("TT-59", .lastPlace, [.lastPlace], clean: "Thoughts, prayers and a calculator."),
        line("TT-60", .lastPlace, [.lastPlace], clean: "That score's a cry for help.", spicy: "That score's a damn cry for help.", unhinged: "That score's a fucking cry for help."),

        // Comebacks
        line("TT-61", .comebacks, [.comeback], clean: "Check your mirrors.", spicy: "Check your damn mirrors.", unhinged: "Check your mirrors, asshole."),
        line("TT-62", .comebacks, [.comeback], clean: "Gap's closing. Feel it?", unhinged: "Gap's closing. Feel it, you bastard?"),
        line("TT-63", .comebacks, [.comeback], clean: "Remember this round. I will.", unhinged: "Remember this round. I fucking will."),
        line("TT-64", .comebacks, [.comeback], clean: "Comeback loading.", unhinged: "Comeback loading. Brace your ass."),
        line("TT-65", .comebacks, [.comeback], clean: "Down isn't out.", spicy: "Down isn't out. Not by a damn mile."),
        line("TT-66", .comebacks, [.comeback], clean: "I've been worse. Then I won.", spicy: "I've been in worse shit. Then I won."),
        line("TT-67", .comebacks, [.comeback], clean: "Watch me climb.", unhinged: "Watch me climb, assholes."),
        line("TT-68", .comebacks, [.comeback], clean: "Two rounds. That's all I need.", unhinged: "Two rounds. That's all I fucking need."),
        line("TT-69", .comebacks, [.comeback], clean: "Nobody's safe. Least of all you.", unhinged: "Nobody's safe. Least of all your smug ass."),
        line("TT-70", .comebacks, [.comeback], clean: "Hope you saved some luck.", spicy: "Hope you saved some luck. You'll damn well need it.", unhinged: "Hope you saved some luck. You'll fucking need it."),

        // General
        line("TT-71", .general, clean: "Your game face needs work.", unhinged: "Your game face needs fucking work."),
        line("TT-72", .general, clean: "I saw that look.", unhinged: "I saw that look. You're fucked."),
        line("TT-73", .general, clean: "Count your cards. Then count again."),
        line("TT-74", .general, clean: "Big talk for someone with that hand.", spicy: "Big talk for someone with that shit hand."),
        line("TT-75", .general, clean: "Interesting strategy. Wrong, but interesting.", unhinged: "Interesting strategy. Wrong as hell, but interesting."),
        line("TT-76", .general, clean: "Somebody's bluffing.", unhinged: "Somebody's bluffing their ass off."),
        line("TT-77", .general, clean: "Quiet over there. Suspicious.", spicy: "Quiet over there. Suspicious as hell.", unhinged: "Quiet over there. Suspicious as fuck."),
        line("TT-78", .general, clean: "That swap was a mistake.", spicy: "That swap was a damn mistake.", unhinged: "That swap was a fucking mistake."),
        line("TT-79", .general, clean: "Stop memorizing. It's not helping.", unhinged: "Stop memorizing. It's not helping, genius."),
        line("TT-80", .general, clean: "Whatever you're planning, no.", spicy: "Whatever the hell you're planning, no."),
        line("TT-81", .general, clean: "Shuffle like you mean it.", unhinged: "Shuffle like you fucking mean it."),
        line("TT-82", .general, clean: "Play faster. The table has plans.", unhinged: "Play faster, for fuck's sake."),
        line("TT-83", .general, clean: "This is my table now.", spicy: "This is my damn table now.", unhinged: "This is my fucking table now."),
        line("TT-84", .general, clean: "Menace behavior. Respect."),
        line("TT-85", .general, clean: "Act natural. You're failing.", unhinged: "Act natural. You're failing, dumbass."),
        line("TT-86", .general, clean: "Every card you touch turns to garbage.", spicy: "Every card you touch turns to shit."),
        line("TT-87", .general, clean: "Somebody's about to get humbled.", spicy: "Somebody's about to get humbled as hell.", unhinged: "Somebody's about to get fucking humbled."),
        line("TT-88", .general, clean: "I've seen better hands on a clock."),
        line("TT-89", .general, [.lastRound], clean: "Last round. No pressure.", unhinged: "Last round. No pressure, asshole."),
        line("TT-90", .general, [.lastRound], clean: "One round left. Finish strong. Or don't.", unhinged: "One round left. Don't fuck it up."),
        line("TT-91", .general, clean: "Receipts are coming.", unhinged: "Receipts are fucking coming."),
        line("TT-92", .general, clean: "Say less. Play more.", unhinged: "Say less. Play more, motormouth."),
    ]
}
