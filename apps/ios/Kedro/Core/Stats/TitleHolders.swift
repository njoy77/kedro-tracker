import Foundation

/// Held titles need a real crowd: at least this many ranked people in your circle (design §12.7).
nonisolated enum TitleRules {
    static let minimumRankedPeople = 5
}

extension StatsSnapshot {
    /// Who holds a held title among someone's people (them included), or nil when the circle is
    /// too small or nobody qualifies. Ties go to whoever got there first.
    func holder(of title: TitleID, amongPeopleOf viewer: PlayerRef, now: Date = .now) -> PlayerRef? {
        guard let metric = title.heldMetric else { return nil }
        let year = calendar.component(.year, from: now)
        let pool = circle(of: viewer).compactMap { records[$0] }.filter { !$0.isGuest && $0.isRanked }
        guard pool.count >= TitleRules.minimumRankedPeople else { return nil }
        let candidates = pool.filter { metric.qualifies($0, year: year, calendar: calendar) }
        return candidates.min { lhs, rhs in
            let left = metric.value(lhs, year: year, calendar: calendar)
            let right = metric.value(rhs, year: year, calendar: calendar)
            if left != right { return metric.higherIsBetter ? left > right : left < right }
            let leftAt = metric.reachedAt(lhs, year: year, calendar: calendar)
            let rightAt = metric.reachedAt(rhs, year: year, calendar: calendar)
            if leftAt != rightAt { return leftAt < rightAt }
            return lhs.ref.seatID < rhs.ref.seatID
        }?.ref
    }

    /// Held titles a person holds right now, among their own people.
    func heldTitles(of ref: PlayerRef, now: Date = .now) -> [TitleID] {
        let ref = options.canonical(ref)
        return TitleID.allCases.filter { $0.isHeld && holder(of: $0, amongPeopleOf: ref, now: now) == ref }
    }

    /// Permanent titles a person has unlocked. Everyone who has played has Fresh Meat.
    func earnedTitles(of ref: PlayerRef) -> [TitleID] {
        guard let record = record(ref) else { return [.freshMeat] }
        return TitleID.allCases.filter { title in
            guard case .earned(let badge) = title.kind else { return false }
            guard let badge else { return true }
            return record.badges[badge] != nil
        }
    }

    /// Everything a person may display, in catalog order (the title picker).
    func availableTitles(of ref: PlayerRef, now: Date = .now) -> [TitleID] {
        let available = Set(earnedTitles(of: ref) + heldTitles(of: ref, now: now))
        return TitleID.allCases.filter(available.contains)
    }

    /// The best earned title (where a lost held title falls back to).
    func bestEarnedTitle(of ref: PlayerRef) -> TitleID? {
        earnedTitles(of: ref).max { $0.earnedRank < $1.earnedRank }
    }

    /// The title to show for a chosen one: a held title that was lost switches to the best earned
    /// title; nil (No title) stays nil; unknown IDs show nothing.
    func displayTitle(for ref: PlayerRef, chosen: String?, now: Date = .now) -> TitleID? {
        guard let chosen else { return nil }
        guard let title = TitleID(rawValue: chosen) else { return nil }
        if title.isHeld, !heldTitles(of: ref, now: now).contains(title) {
            return bestEarnedTitle(of: ref)
        }
        if !title.isHeld, !earnedTitles(of: ref).contains(title) { return nil }
        return title
    }

    /// Held titles someone else took off this person between two snapshots (TI-19).
    func titlesLost(by ref: PlayerRef, since earlier: StatsSnapshot, now: Date = .now) -> [(title: TitleID, takenBy: PlayerRef)] {
        let ref = options.canonical(ref)
        return TitleID.allCases.compactMap { title in
            guard title.isHeld,
                  earlier.holder(of: title, amongPeopleOf: ref, now: now) == ref,
                  let holder = holder(of: title, amongPeopleOf: ref, now: now), holder != ref
            else { return nil }
            return (title, holder)
        }
    }
}
