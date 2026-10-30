import SwiftUI

/// The Table's bottom bar (design §6.1 item 6, mockup frame 6): Knock and Talk flank Record Round
/// (Report Your Hand in self-report mode), with a caption underneath. Nothing ever covers it.
struct TableBottomBar: View {
    struct Primary {
        var title: String
        /// kedroRed (the scorekeeper, or anyone with a hand to report) or glass.
        var isProminent: Bool
        var action: () -> Void
    }

    var primary: Primary?
    var caption: String
    /// A live knock is marked for the round being played: the Knock button gets a red ring.
    var isKnockMarked = false
    var canKnock = true
    var canTalk = true
    var onKnock: () -> Void
    var onTalk: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if canKnock {
                    Button(action: onKnock) {
                        Image(systemName: isKnockMarked ? "hand.raised.fill" : "hand.raised")
                            .font(.title3)
                            .frame(width: 28)
                    }
                    .buttonStyle(.kedroGlass)
                    .overlay {
                        if isKnockMarked {
                            Capsule().strokeBorder(.kedroRed, lineWidth: 1.5).allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(Literal.text("button.knock"))
                    .accessibilityValue(isKnockMarked ? "Marked" : "")
                }
                if let primary {
                    if primary.isProminent {
                        Button(primary.title, action: primary.action)
                            .buttonStyle(.kedroPrimary)
                    } else {
                        Button(primary.title, action: primary.action)
                            .buttonStyle(.kedroGlassWide)
                    }
                } else {
                    Spacer(minLength: 0)
                }
                if canTalk {
                    Button(action: onTalk) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.title3)
                            .frame(width: 28)
                    }
                    .buttonStyle(.kedroGlass)
                    .accessibilityLabel(Literal.text("button.talk"))
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.silver)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            LinearGradient(colors: [Color.night.opacity(0), Color.night], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

/// The sync pill: only when something's unusual (design §6.1 item 1, F-01–F-03). A word, never a
/// color.
struct SyncPill: View {
    let syncState: SyncState
    let voice: Voice

    var body: some View {
        if syncState.isUnusual, let id = syncState.copyID {
            Label {
                Text(voice.line(id, ["n": syncState.phoneCount ?? 1]))
            } icon: {
                Image(systemName: syncState == .syncing ? "arrow.triangle.2.circlepath" : "wifi.slash")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.silver)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.surfaceRaised, in: .capsule)
            .overlay { Capsule().strokeBorder(.rule) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(TableText.text("label.syncPill"))
            .accessibilityValue(voice.line(id, ["n": syncState.phoneCount ?? 1]))
        }
    }
}

#Preview("Bottom bar") {
    VStack {
        Spacer()
        SyncPill(syncState: .offlinePeers(4), voice: Voice(level: .clean))
        SyncPill(syncState: .syncing, voice: Voice(level: .clean))
        Spacer()
        TableBottomBar(
            primary: .init(title: Literal.recordRound(6), isProminent: true) {},
            caption: Literal.text("label.keepingScore"),
            onKnock: {},
            onTalk: {}
        )
        TableBottomBar(
            primary: .init(title: Literal.recordRound(6), isProminent: false) {},
            caption: TableText.text("label.knockerPrefilled", ["name": "Sam"]),
            isKnockMarked: true,
            onKnock: {},
            onTalk: {}
        )
    }
    .background(.night)
    .previewEnvironment()
}
