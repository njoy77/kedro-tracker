import SwiftUI

/// A player's face (design §3.5): photo, emoji on a color, curated art, or a guest's initial in a
/// dashed ring. Optional decorations: the leader's gold K badge on the top edge, the dealer's
/// D chip, and a focus (red) or winner (gold) ring.
///
/// VoiceOver reads it as one element: "Noah, leading, dealer".
struct AvatarView: View {
    /// Sizes from the design (§3.5).
    enum Size: CGFloat, CaseIterable {
        /// Live Activity.
        case tiny = 20
        /// Compact rows, toasts, stacks.
        case compact = 32
        /// Standings.
        case standings = 44
        /// Pickers, Table card.
        case medium = 56
        /// Profile, game-end hero.
        case profile = 96
    }

    enum Ring {
        case none
        /// Selected / focused (the knocker picker, your avatar choice).
        case focus
        /// The leader in standings, the winner at game end.
        case winner
    }

    var avatar: Avatar?
    var name: String
    var isGuest = false
    var size: Size = .standings
    var isLeader = false
    var isDealer = false
    var ring: Ring = .none

    init(avatar: Avatar?, name: String, isGuest: Bool = false, size: Size = .standings, isLeader: Bool = false, isDealer: Bool = false, ring: Ring = .none) {
        self.avatar = avatar
        self.name = name
        self.isGuest = isGuest
        self.size = size
        self.isLeader = isLeader
        self.isDealer = isDealer
        self.ring = ring
    }

    /// A seated player.
    init(seat: Seat, size: Size = .standings, isLeader: Bool = false, isDealer: Bool = false, ring: Ring = .none) {
        self.init(avatar: seat.avatar, name: seat.displayName, isGuest: seat.isGuest, size: size, isLeader: isLeader, isDealer: isDealer, ring: ring)
    }

    /// A player from search, the directory, or a nearby table.
    init(player: PlayerSummary, size: Size = .standings, ring: Ring = .none) {
        self.init(avatar: player.avatar, name: player.displayName, size: size, ring: ring)
    }

    private var diameter: CGFloat { size.rawValue }
    private var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        face
            .frame(width: diameter, height: diameter)
            .overlay { ringOverlay }
            .overlay(alignment: .top) {
                if isLeader {
                    LeaderMark(size: max(12, diameter * 0.39))
                        .offset(y: -diameter * 0.22)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isDealer { dealerChip }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var face: some View {
        if isGuest && avatar == nil {
            Circle()
                .strokeBorder(.silver, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                .overlay {
                    Text(initial)
                        .font(.system(size: diameter * 0.39, weight: .semibold))
                        .foregroundStyle(.silver)
                }
        } else {
            switch avatar {
            case .photo(let url):
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialFace
                }
                .clipShape(.circle)
            case .emoji(let emoji, let colorIndex):
                Circle()
                    .fill(AvatarPalette.color(colorIndex))
                    .overlay {
                        Text(emoji).font(.system(size: diameter * 0.52))
                    }
            case .curated(let id):
                Circle()
                    .fill(CuratedTile.background)
                    .overlay { Circle().strokeBorder(CuratedTile.edge, lineWidth: 1) }
                    .overlay {
                        CuratedAvatarArt(id: id)
                            .foregroundStyle(CuratedTile.ink)
                            .frame(width: diameter * 0.64, height: diameter * 0.64)
                    }
            case nil:
                initialFace
            }
        }
    }

    private var initialFace: some View {
        Circle()
            .fill(.surfaceRaised)
            .overlay {
                Text(initial)
                    .font(.system(size: diameter * 0.39, weight: .semibold))
                    .foregroundStyle(.silver)
            }
    }

    @ViewBuilder
    private var ringOverlay: some View {
        switch ring {
        case .none:
            EmptyView()
        case .focus:
            Circle().stroke(.kedroRed, lineWidth: 2).padding(-4.5)
        case .winner:
            Circle().stroke(.gold, lineWidth: diameter >= 96 ? 3 : 2).padding(diameter >= 96 ? -6 : -4.5)
        }
    }

    private var dealerChip: some View {
        let chip = max(14, diameter * 0.41)
        return Text("D")
            .font(.system(size: chip * 0.56, weight: .bold))
            .foregroundStyle(.night)
            .frame(width: chip, height: chip)
            .background(.cream, in: .circle)
            .overlay { Circle().stroke(.night, lineWidth: 2) }
            .offset(x: chip * 0.28, y: chip * 0.17)
    }

    private var accessibilityText: String {
        var parts = [name]
        if isGuest { parts.append("guest") }
        if isLeader { parts.append("leading") }
        if isDealer { parts.append("dealer") }
        return parts.joined(separator: ", ")
    }
}

/// The leader's gold script K on the avatar's top edge (mockup frame 6).
/// TODO(design §18.1): switch to the vector small mark once it exists; a script face stands in.
struct LeaderMark: View {
    var size: CGFloat = 17

    var body: some View {
        Text("K")
            .font(.custom("SnellRoundhand-Black", fixedSize: size))
            .foregroundStyle(.gold)
            .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

#Preview("Avatars") {
    VStack(spacing: 28) {
        HStack(spacing: 20) {
            AvatarView(avatar: .curated(.crow), name: "Noah", isLeader: true, isDealer: true, ring: .winner)
            AvatarView(avatar: .emoji("🦊", colorIndex: 0), name: "Ana")
            AvatarView(avatar: .curated(.bull), name: "Ben")
            AvatarView(avatar: nil, name: "Sam", isGuest: true)
        }
        HStack(alignment: .bottom, spacing: 16) {
            ForEach(AvatarView.Size.allCases, id: \.self) { size in
                AvatarView(avatar: .curated(.horse), name: "Horse", size: size)
            }
        }
        AvatarView(avatar: .emoji("🦂", colorIndex: 1), name: "Priya", size: .medium, ring: .focus)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.night)
    .preferredColorScheme(.dark)
}
