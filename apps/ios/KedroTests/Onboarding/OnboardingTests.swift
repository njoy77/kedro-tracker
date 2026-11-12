import Foundation
import Network
import Testing
@testable import Kedro

@MainActor
@Suite("Onboarding: permissions and copy")
struct OnboardingTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "kedro.tests.\(UUID().uuidString)") ?? .standard
    }

    // MARK: Age range

    @Test("A shared range maps to which side of 18", arguments: [
        (nil as Int?, 12 as Int?, AgeRangeOutcome.under18),
        (13, 17, .under18),
        (18, nil, .adult),
        (21, 25, .adult),
        (nil, nil, .notShared),
        (16, nil, .notShared),
    ])
    func ageRangeOutcome(lower: Int?, upper: Int?, expected: AgeRangeOutcome) {
        #expect(AgeRangeOutcome(lowerBound: lower, upperBound: upper) == expected)
    }

    @Test("Only a shared answer changes the Clean lock")
    func ageRangeApply() {
        let prefs = AppPreferences(defaults: defaults())
        AgeRangeOutcome.under18.apply(to: prefs)
        #expect(prefs.isUnder18)
        // Declining, cancelling or an unavailable capability keeps the earlier answer.
        AgeRangeOutcome.notShared.apply(to: prefs)
        AgeRangeOutcome.unavailable.apply(to: prefs)
        #expect(prefs.isUnder18)
        #expect(prefs.effectiveLanguageLevel == .clean)
        AgeRangeOutcome.adult.apply(to: prefs)
        #expect(!prefs.isUnder18)
    }

    // MARK: Local network

    @Test("New players start with nearby discovery off (no Local Network prompt before the tap)")
    func discoveryOffForNewPlayers() {
        let prefs = AppPreferences(defaults: defaults())
        #expect(!prefs.hasCompletedOnboarding)
        #expect(!prefs.nearbyDiscoveryEnabled)
    }

    @Test("Players who finished onboarding before the switch keep discovery on")
    func discoveryOnForExistingPlayers() {
        let store = defaults()
        store.set(true, forKey: AppPreferences.Key.hasCompletedOnboarding)
        let prefs = AppPreferences(defaults: store)
        #expect(prefs.nearbyDiscoveryEnabled)
    }

    @Test("Not Now sticks, even after onboarding finishes")
    func discoveryChoicePersists() {
        let store = defaults()
        let prefs = AppPreferences(defaults: store)
        prefs.nearbyDiscoveryEnabled = false
        prefs.hasCompletedOnboarding = true
        #expect(!AppPreferences(defaults: store).nearbyDiscoveryEnabled)
        prefs.nearbyDiscoveryEnabled = true
        #expect(AppPreferences(defaults: store).nearbyDiscoveryEnabled)
    }

    @Test("The probe reads a policy-denied browser as denied, and nothing else")
    func localNetworkStatus() {
        #expect(LocalNetworkAccess.status(for: .waiting(.dns(LocalNetworkAccess.policyDenied))) == .denied)
        #expect(LocalNetworkAccess.status(for: .waiting(.dns(-65537))) == nil)
        #expect(LocalNetworkAccess.status(for: .ready) == nil)
        #expect(LocalNetworkAccess.status(for: .setup) == nil)
        #expect(LocalNetworkAccess.status(for: .failed(.posix(.ECONNREFUSED))) == .unknown)
    }

    @Test("Play doesn't browse for tables until discovery is on")
    func playWaitsForDiscovery() async {
        let app = AppModel.preview(seeded: false)
        app.preferences.nearbyDiscoveryEnabled = false
        app.discovery = CountingDiscovery()
        let model = PlayModel(app: app)
        await model.followNearbyTables()
        #expect((app.discovery as? CountingDiscovery)?.browses == 0)
    }

    // MARK: Onboarding gate and copy

    @Test("Existing players aren't sent back through onboarding")
    func existingPlayersSkipOnboarding() {
        let app = AppModel.preview()
        #expect(!app.needsOnboarding(isSignedIn: true))
    }

    @Test("No user-facing copy names the game Cambio")
    func noCambio() {
        for entry in CopyDeck.standard.entries.values {
            for level in LanguageLevel.allCases {
                #expect(!entry.text(for: level).localizedCaseInsensitiveContains("cambio"), "\(entry.id) (\(level))")
            }
        }
    }

    @Test("The under-3 message is generic at every level")
    func tooFewSeatsCopy() {
        for level in LanguageLevel.allCases {
            #expect(Voice(level: level).line("E-04") == "This game needs 3. Two people is just a staring contest.")
        }
    }

    @Test("The welcome leads with competing; the math is the supporting line")
    func welcomeCopy() {
        let line = Voice(level: .clean).line("O-02")
        #expect(line.hasPrefix("Beat your friends, climb the leaderboard"))
        #expect(line.contains("Kedro does the math"))
    }
}

/// Counts browse requests; never yields.
@MainActor
private final class CountingDiscovery: TableDiscovery {
    private(set) var browses = 0

    func nearbyTables() -> AsyncStream<[NearbyTable]> {
        browses += 1
        return AsyncStream { $0.finish() }
    }

    func advertise(_ table: AdvertisedTable) async {}
    func stopAdvertising() async {}
}
