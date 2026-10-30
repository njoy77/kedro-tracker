import Foundation

/// Where a self-reported round stands (design §7.4), evaluated from the fold's `SelfReportRound`
/// and the clock. Pure: every phone evaluates the same operations to the same answer.
///
/// Knocker resolution: exactly one "I knocked" settles it. Nobody or several: every phone asks
/// "Who knocked?" (K-15/K-16). The first tap is a proposal shown everywhere with a 5-second ring;
/// it commits unless someone proposes a different knocker inside that window, which is a contest
/// (K-17, "Sort it out"). A fresh proposal after the window starts a clean ring.
nonisolated enum KnockerResolution: Hashable, Sendable {
    /// Hands still coming in.
    case collecting(waitingOn: [SeatID])
    /// Everyone reported and nobody (empty) or several claimed the knock; no live proposal.
    case undecided(claims: [SeatID])
    /// A proposal's ring is running.
    case proposed(KnockerProposal, deadline: Date)
    /// Two proposals disagree inside one ring.
    case contested(earlier: KnockerProposal, later: KnockerProposal)
    /// The ring ran out uncontested: commit this knocker (`KnockerResolved`).
    case ready(SeatID)
    /// Settled (one claim, or resolved); the fold saves the round.
    case settled(SeatID)

    /// How long a proposal waits for disagreement (design §7.4).
    static let ringDuration: TimeInterval = 5
    /// Phones other than the proposer's commit this much later, as a back-stop if the
    /// proposer's phone went quiet. Duplicate `KnockerResolved`s are harmless.
    static let backstopDelay: TimeInterval = 2

    static func evaluate(_ report: SelfReportRound?, seats: [SeatID], now: Date) -> KnockerResolution {
        guard let report else { return .collecting(waitingOn: seats) }
        guard report.waitingOn.isEmpty else { return .collecting(waitingOn: report.waitingOn) }
        if let knocker = report.knocker { return .settled(knocker) }
        let proposals = report.proposals.sorted { ($0.at, $0.opId.uuidString) < ($1.at, $1.opId.uuidString) }
        guard let latest = proposals.last else { return .undecided(claims: report.claimedKnockers) }
        let rival = proposals.dropLast().last { other in
            other.knocker != latest.knocker && latest.at.timeIntervalSince(other.at) < ringDuration
        }
        if let rival { return .contested(earlier: rival, later: latest) }
        let deadline = latest.at.addingTimeInterval(ringDuration)
        return now >= deadline ? .ready(latest.knocker) : .proposed(latest, deadline: deadline)
    }

    /// When this phone should send `KnockerResolved` for a running proposal, or nil if it
    /// shouldn't (the ring is untimed on a phone using VoiceOver or Switch Control: those people
    /// tap Confirm instead, and the other phones back-stop).
    static func commitTime(for proposal: KnockerProposal, mySeat: SeatID?, isUntimed: Bool) -> Date? {
        let deadline = proposal.at.addingTimeInterval(ringDuration)
        if proposal.proposer != nil, proposal.proposer == mySeat {
            return isUntimed ? nil : deadline
        }
        return deadline.addingTimeInterval(backstopDelay)
    }

    /// The prompt above "Who knocked?": K-15 (several claimed) or K-16 (nobody did).
    var promptID: String? {
        switch self {
        case .undecided(let claims): claims.count > 1 ? "K-15" : "K-16"
        case .contested: "K-17"
        default: nil
        }
    }

    var needsDecision: Bool {
        switch self {
        case .undecided, .proposed, .contested, .ready: true
        case .collecting, .settled: false
        }
    }
}

/// Who reports a guest's hand in self-report mode (design §7.4): the seat's assigned reporter,
/// else the nearest player to their left (the next seat clockwise) who isn't a guest.
nonisolated enum GuestReporters {
    static func reporter(for guest: Seat, in seats: [Seat]) -> SeatID? {
        guard guest.isGuest else { return guest.id }
        if let assigned = guest.reporter, seats.contains(where: { $0.id == assigned && !$0.isGuest }) {
            return assigned
        }
        guard let index = seats.firstIndex(where: { $0.id == guest.id }) else { return nil }
        for offset in 1..<max(seats.count, 1) {
            let seat = seats[(index + offset) % seats.count]
            if !seat.isGuest { return seat.id }
        }
        return nil
    }

    /// The seats a phone reports for: its own, then each guest it's the reporter for, in seat order.
    static func seats(reportedBy me: SeatID, in seats: [Seat]) -> [SeatID] {
        let guests = seats.filter { $0.id != me && $0.isGuest && reporter(for: $0, in: seats) == me }.map(\.id)
        return seats.contains { $0.id == me } ? [me] + guests : guests
    }
}

/// The shared reveal (design §7.4): self-reported values stay hidden until everyone has reported,
/// then flip together. The round is saved by the operation that completed it, so every phone
/// reveals at that operation's time plus a short beat, whenever it received it.
nonisolated enum SelfReportReveal {
    static let delay: TimeInterval = 1.5

    static func revealTime(for record: RoundRecord) -> Date {
        record.recordedAt.addingTimeInterval(delay)
    }

    static func isHidden(_ record: RoundRecord, mode: ScoringMode, now: Date) -> Bool {
        mode == .selfReport && now < revealTime(for: record)
    }
}
