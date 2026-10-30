import Foundation

/// Literal strings for the Table, Round sheet, History, game end and display mode that aren't in
/// `CopyDeck.standard` (buttons, labels, verdict previews, highlights). Identical in every level,
/// like the deck's §20 literals, so they render through a Clean voice.
///
/// Voice lines (roasts, banter, winner lines) never live here: they come from the copy deck by ID.
/// Report additions to foundation if they should move into the shared deck.
nonisolated enum TableText {
    static func text(_ key: String, _ args: VoiceArgs = [:]) -> String { voice.line(key, args) }

    private static let voice = Voice(level: .clean, deck: deck)

    static let deck = CopyDeck([
        // Toolbar and menus
        .literal("button.minimize", "Toolbar", "Minimize"),
        .literal("button.rules", "Toolbar", "Rules"),
        .literal("button.history", "Toolbar", "History"),
        .literal("button.more", "Toolbar", "More"),
        .literal("button.tableDisplay", "Menu", "Table Display"),
        .literal("button.exitTableDisplay", "Menu", "Exit Table Display"),
        .literal("button.handOff", "Menu", "Hand Off Scorekeeping"),
        .literal("button.tableSpeaker", "Menu", "Be the Table Speaker"),
        .literal("label.youreTableSpeaker", "Menu", "You're the Table Speaker"),
        .literal("button.changeDealer", "Menu", "Change Dealer"),
        .literal("label.handOffTitle", "Hand off", "Who keeps score?"),
        .literal("label.extendTitle", "Extend", "Add rounds"),
        .literal("button.addRound", "Extend", "Add 1 Round"),
        .literal("button.addRounds", "Extend", "Add {n} Rounds"),

        // Common buttons
        .literal("button.why", "Last-round card", "Why?"),
        .literal("button.change", "Button", "Change"),
        .literal("button.confirm", "Button", "Confirm"),
        .literal("button.cancel", "Button", "Cancel"),
        .literal("button.submit", "Button", "Submit"),
        .literal("button.close", "Button", "Close"),
        .literal("button.useThisVersion", "Button", "Use This Version"),
        .literal("button.pad", "Button", "Pad"),

        // Table
        .literal("label.whoKnocked", "Knocker row", "Who knocked?"),
        .literal("label.whosDealing", "Dealer picker", "Who's dealing?"),
        .literal("label.markedLive", "Knocker row", "marked live by {name}"),
        .literal("label.knocked", "Player row", "knocked"),
        .literal("label.keepingScoreOther", "Bottom bar caption", "{name}'s keeping score · screen stays awake"),
        .literal("label.everyoneReports", "Bottom bar caption", "Everyone reports · screen stays awake"),
        .literal("label.knockerPrefilled", "Bottom bar caption", "Knocker pre-filled: {name}"),
        .literal("label.watching", "Bottom bar caption", "Watching · seats are set after Round 1"),
        .literal("label.alreadyMarked", "Live knock", "{name} already marked {knocker}"),
        .literal("label.noRoundsYet", "Last-round card", "No rounds yet. {name} deals first."),
        .literal("label.lobbyWaiting", "Lobby", "Waiting for the deal."),
        .literal("label.revealing", "Self-report reveal", "Everyone's in."),
        .literal("label.reportStatus", "Self-report card", "Round {r} · {done} of {total} reported"),
        .literal("label.youReported", "Bottom bar", "Reported · waiting on {n}"),

        // Round sheet
        .literal("label.round", "Sheet title", "Round {r}"),
        .literal("label.verdict.landed", "Verdict preview", "{knocker} knocked on {hand} · lowest at the table · landed −10"),
        .literal("label.verdict.tied", "Verdict preview", "{knocker} knocked on {hand} · tied for lowest · tied {hand}"),
        .literal("label.verdict.failed", "Verdict preview", "{knocker} knocked on {hand} · {name} had {low} · failed {hand} + 10"),
        .literal("label.verdict.inherentBeaten", "Verdict preview", "{knocker} went out · {name} had {low} · no penalty, 0"),
        .literal("label.inherentKnock", "Round sheet toggle", "Went out (all four cards)"),
        .literal("label.inherentKnockHint", "Round sheet toggle footnote", "Inherent knock: hand 0. −10 if lowest alone, never +10."),
        .literal("label.verdict.tiedSoFar", "Verdict preview", "{knocker} knocked on {hand} · tied so far"),
        .literal("label.pickKnocker", "Round sheet", "Pick who knocked to save."),
        .literal("label.alreadySaved", "Round sheet", "Round {r} was just saved on another phone. Check the table before saving again."),
        .literal("label.redKingsOut", "Card mode", "Both red Kings are already in this round."),
        .literal("label.cardsEmpty", "Card mode", "Tap the cards in their hand."),
        .literal("label.iKnocked", "Self-report", "I knocked"),
        .literal("label.reportingFor", "Self-report", "Reporting for"),
        .literal("label.reported", "Self-report", "Reported"),
        .literal("label.valuesHidden", "Self-report", "Hands stay hidden until everyone's in."),
        .literal("label.says", "Knocker proposal", "{a} says {x} knocked"),
        .literal("label.confirmHint", "Knocker proposal", "Commits in a few seconds unless someone changes it."),

        // History
        .literal("label.scores", "History tab", "Scores"),
        .literal("label.onTheRecord", "History tab", "On the record"),
        .literal("label.feed", "History tab", "Feed"),
        .literal("label.rd", "History grid", "RD"),
        .literal("label.tot", "History grid", "TOT"),
        .literal("label.edited", "History grid", "Edited"),
        .literal("label.knockStill", "On the record", "{knocker}'s knock still {outcome}"),
        .literal("label.knockFlip", "On the record", "{knocker}'s knock: {before} → {after}"),
        .literal("label.knockFlipConfirm", "Correction", "{knocker}'s knock: {before} → {after}, {old} → {new}. Everyone sees this."),
        .literal("label.knockerChangeConfirm", "Correction", "The R{r} knocker changes from {before} to {after}. Everyone sees this."),
        .literal("label.whatChangesRound", "Correction", "{name}'s R{r}: {old} → {new}"),
        .literal("label.whatChangesTotal", "Correction", "{name}'s total: {old} → {new}"),
        .literal("label.noChange", "Correction", "Nothing changes yet."),
        .literal("label.fixRound", "Correction title", "Fix Round {r}"),

        // Abandoned
        .literal("label.abandoned", "Abandoned", "Abandoned"),
        .literal("label.abandonedNote", "Abandoned", "This game won't count for anyone."),
        .literal("label.restoreUntil", "Abandoned", "You can restore it until {time}."),

        // Game end
        .literal("label.finalStandings", "Game end", "Final standings"),
        .literal("label.highlights", "Game end", "Highlights"),
        .literal("label.ratings", "Game end", "Ratings"),
        .literal("label.badgesEarned", "Game end", "Badges earned"),
        .literal("label.highlight.bestHand", "Highlight", "Best hand: {name}, {hand} in Round {r}."),
        .literal("label.highlight.knocks", "Highlight", "Knocks: {landed} landed · {tied} tied · {failed} failed."),
        .literal("label.highlight.wentOut", "Highlight", "Went out with all four cards: {n} · {landed} at −10."),
        .literal("label.highlight.comeback", "Highlight", "Biggest comeback: {name}, {pos} after Round {r}, finished {final}."),
        .literal("label.highlight.decided", "Highlight", "Round {r} decided it: {name} took the lead for good."),
        .literal("label.ratingChange", "Game end row", "rating {delta} → {rating}"),
        .literal("label.debut", "Game end row", "On the board · debut {rating}"),
        .literal("label.guestRow", "Game end row", "guest"),
        .literal("label.endedEarly", "Game end", "Ended early after Round {r}."),
        .literal("label.sharePreview", "Share", "{word} results"),

        // Display mode
        .literal("label.holdToRecord", "Display mode", "Hold to record a round"),
        .literal("label.lastTurns", "Display mode", "{name} knocked · last turns"),
        .literal("label.ofTotal", "Display mode", "of {total}"),
        .literal("label.displayUnlocked", "Display mode", "Unlocked for 10 seconds"),

        // Attention (toasts)
        .literal("label.liveKnock", "Toast eyebrow", "LIVE KNOCK"),
        .literal("label.tauntEyebrow", "Toast eyebrow", "{from} → {to}"),
        .literal("label.tauntEyebrowCustom", "Toast eyebrow", "{from} → {to} · custom"),
        .literal("label.theTable", "Taunt target", "the table"),
        .literal("label.tauntAnnouncement", "VoiceOver", "{from} to {to}: {message}"),

        // Live knock sheet
        .literal("label.liveKnockHint", "Live knock", "Everyone gets a heads-up. It pre-fills the Round sheet."),
        .literal("button.clearKnock", "Live knock", "Clear the Knock"),

        // Menus and confirmations
        .literal("button.invite", "Menu", "Invite"),

        // Game end: claim codes for guests the host typed in (PRD §3.2, design §5.9 row 9)
        .literal("label.claimCodes", "Game end", "CLAIM CODES"),
        .literal("label.claimCodesHint", "Game end", "Guests without the app keep tonight once they sign up. Send them their code."),
        .literal("button.sendClaimCode", "Game end", "Send {name} Their Claim Code"),
        .literal("label.extendBy", "Extend", "Now playing to {total}."),
        .literal("label.handOffHint", "Hand off", "They record the rounds from their phone."),
        .literal("label.dealerHint", "Dealer picker", "The deal passes left from here. Everyone sees the change."),
        .literal("label.finishGate", "Bottom bar", "Lock in the final scores"),
        .literal("label.waitingOnFinish", "Bottom bar caption", "Last round's in · waiting on Finish Game"),
        .literal("label.syncPill", "Sync pill", "Sync status"),
        .literal("label.lobbyHint", "Lobby", "The table opens when the host taps Deal."),

        // History
        .literal("label.historyFooterLocked", "History", "Final. Locked."),
        .literal("label.conflictTitle", "History", "Round {r}, the other version"),
        .literal("label.conflictBy", "History", "Saved by {name} at {time}"),
        .literal("label.roundRow", "History list", "Round {r}"),
        .literal("label.edit", "History", "Fix"),
        .literal("label.whatChangesLine", "Correction", "{name}: R{r} {old} → {new} · total {oldTotal} → {newTotal}"),
        .literal("label.whatChangesTotalOnly", "Correction", "{name}: total {oldTotal} → {newTotal}"),
        .literal("label.cellHint", "History", "Double-tap to fix this score"),
        .literal("label.rotorRounds", "History rotor", "Rounds"),
        .literal("label.rotorEdited", "History rotor", "Edited"),
        .literal("label.rotorKnocks", "History rotor", "Knocks"),
        .literal("label.knockerCell", "History", "knocked, {outcome}"),

        // Game end
        .literal("label.knockRecordNone", "Game end row", "no knocks"),
        .literal("label.shareTitle", "Share", "{word}: {name} wins"),
        .literal("label.shareFooter", "Share", "Scored with Kedro"),
        .literal("label.runItBackTitle", "Rematch", "Run It Back"),
        .literal("label.badgeFor", "Game end", "{name} · {badge}"),
    ])
}
