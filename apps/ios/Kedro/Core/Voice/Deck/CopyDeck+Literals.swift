// Literal strings from docs/kedro-ios-copy.md §20: identical in every language level, enforced by
// the catalog parity test. Use the typed helpers in `Literal` rather than these keys directly.

nonisolated extension CopyDeck {
    static let literals: [CopyEntry] = [
        // Buttons (verbs, never jokes)
        .literal("button.sitDown", "Button", "Sit Down"),
        .literal("button.askToSit", "Button", "Ask to Sit"),
        .literal("button.letIn", "Button", "Let {name} In"),
        .literal("button.remove", "Button", "Remove"),
        .literal("button.newTable", "Button", "New Table"),
        .literal("button.deal", "Button", "Deal"),
        .literal("button.recordRound", "Button", "Record Round {r}"),
        .literal("button.reportHand", "Button", "Report Your Hand"),
        .literal("button.knock", "Button", "Knock"),
        .literal("button.talk", "Button", "Talk"),
        .literal("button.send", "Button", "Send"),
        .literal("button.next", "Button", "Next: {name} ›"),
        .literal("button.saveRound", "Button", "Save Round {r}"),
        .literal("button.saveChange", "Button", "Save Change"),
        .literal("button.undo", "Button", "Undo"),
        .literal("button.cards", "Button", "Cards"),
        .literal("button.keepHand", "Button", "Keep {hand}"),
        .literal("button.fix", "Button", "Fix {name}"),
        .literal("button.finishGame", "Button", "Finish Game"),
        .literal("button.fixRoundFirst", "Button", "Fix a Round First"),
        .literal("button.playAnotherRound", "Button", "Play Another Round"),
        .literal("button.extend", "Button", "Extend"),
        .literal("button.endEarly", "Button", "End Early"),
        .literal("button.abandon", "Button", "Abandon"),
        .literal("button.endGame", "Button", "End Game"),
        .literal("button.addPlayer", "Button", "Add Player"),
        .literal("button.restoreGame", "Button", "Restore Game"),
        .literal("button.runItBack", "Button", "Run It Back"),
        .literal("button.sendReceipt", "Button", "Send a Receipt"),
        .literal("button.shareResults", "Button", "Share Results"),
        .literal("button.playAgainWith", "Button", "Play Again with {name}"),
        .literal("button.inviteWithQR", "Button", "Invite with QR"),
        .literal("button.thatsMe", "Button", "Yes, that's me"),
        .literal("button.muteTaunts", "Button", "Mute Their Taunts"),
        .literal("button.block", "Button", "Block"),
        .literal("button.report", "Button", "Report"),
        .literal("button.done", "Button", "Done"),
        .literal("button.playAsGuest", "Button", "Play as a Guest"),
        .literal("button.joinWithCode", "Button", "Join with Code"),
        .literal("button.watch", "Button", "Watch"),
        .literal("button.continue", "Button", "Continue"),

        // Fact and verdict lines
        .literal("fact.round", "Fact line", "Round {r}. {knocker} knocked on {hand}."),
        .literal("verdict.landed", "Verdict", "Landed: −10."),
        .literal("verdict.tied", "Verdict", "Tied: {hand}."),
        .literal("verdict.failed", "Verdict", "Failed: {hand} + 10 = {score}."),

        // Delta captions (the knocker's math, never a bare +12)
        .literal("delta.landed", "Delta caption", "landed · −10"),
        .literal("delta.tied", "Delta caption", "tied · {hand}"),
        .literal("delta.failed", "Delta caption", "failed · {hand} + 10"),

        // Labels
        .literal("label.roundOf", "Metadata line", "ROUND {r} OF {total}"),
        .literal("label.deals", "Metadata line", "{word} · {name} DEALS"),
        .literal("label.leading", "Standings tag", "LEADING"),
        .literal("label.guest", "Guest caption", "guest"),
        .literal("label.keepingScore", "Bottom bar caption", "You're keeping score · screen stays awake"),
        .literal("label.miniBar", "Mini bar", "{word} · R{r}/{total} · You {rank} · {score}"),
        .literal("label.meter", "Progress meter", "{n} of 5"),

        // Audit log
        .literal("audit.handChanged", "Audit", "{name} changed {player}'s R{r} hand {old} → {new} at {time}"),
    ]
}
