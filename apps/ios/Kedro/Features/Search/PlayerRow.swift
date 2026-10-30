import SwiftUI

/// A player in a list (Search, Played With, Search Kedro): avatar, name, @handle and a caption
/// such as "Played 3 together" or "Never played".
struct PlayerRow: View {
    let player: PlayerSummary
    var caption: String?
    var isSelected = false
    var showsSelection = false

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(player: player, size: .compact)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName).foregroundStyle(.cream)
                Text([player.handle.description, caption].compactMap(\.self).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.silver)
            }
            Spacer(minLength: 8)
            if showsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.kedroRed : .silverDim)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "Played 3 together" / "Never played".
    static func playedCaption(_ games: Int?) -> String {
        switch games ?? 0 {
        case 0: "Never played"
        case 1: "Played once together"
        case let count: "Played \(count) together"
        }
    }
}

#Preview {
    List {
        PlayerRow(player: PreviewData.ana, caption: PlayerRow.playedCaption(17))
        PlayerRow(player: PreviewData.jo, caption: PlayerRow.playedCaption(0), isSelected: true, showsSelection: true)
    }
    .previewEnvironment()
}
