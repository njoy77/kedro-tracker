import SwiftUI

/// Kedro Wrapped for a year (design §12.9): 12 story cards in a paged `TabView`, each shareable
/// on its own as an image, Clean by default like every outbound image.
struct WrappedView: View {
    let year: Int

    @Environment(AppModel.self) private var app
    @State private var page: WrappedCard = .cover
    @State private var shareImage: Image?
    /// Outbound images are Clean unless you choose your own level.
    @State private var sharesInMyLevel = false
    #if DEBUG
    @State private var peeksEarly = false
    #endif

    private var stats: StatsModel { .shared(for: app.store) }
    private var me: PlayerRef? { app.profile?.identity }

    var body: some View {
        let snapshot = stats.snapshot
        Group {
            if let me {
                switch gate(snapshot, me: me) {
                case .available:
                    if let summary = snapshot.wrapped(for: me, year: year) {
                        stories(summary)
                    }
                case let .needsGames(played, needed):
                    ContentUnavailableView {
                        Label("Kedro Wrapped", systemImage: "sparkles")
                    } description: {
                        Text("\(app.voice.line("WR-23", ["left": needed - played])) (\(played) of \(needed))")
                    }
                case .arrives(let date):
                    ContentUnavailableView {
                        Label("Kedro Wrapped", systemImage: "sparkles")
                    } description: {
                        Text("Your \(String(year)) arrives \(date.formatted(.dateTime.month(.wide).day())).")
                    } actions: {
                        #if DEBUG
                        Button("Peek Early (Debug)") { peeksEarly = true }
                        #endif
                    }
                }
            } else {
                ContentUnavailableView("No Profile Yet", systemImage: "person.crop.circle", description: Text("Play a game to start your record."))
            }
        }
        .navigationTitle("Wrapped \(String(year))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await stats.follow(app.store, viewer: me) }
    }

    private func gate(_ snapshot: StatsSnapshot, me: PlayerRef) -> WrappedAvailability {
        let availability = snapshot.wrappedAvailability(for: me, year: year)
        #if DEBUG
        if peeksEarly, case .arrives = availability { return .available }
        #endif
        return availability
    }

    // MARK: Stories

    private func stories(_ summary: WrappedSummary) -> some View {
        let cards = WrappedCard.cards(for: summary)
        return ZStack(alignment: .top) {
            TabView(selection: $page) {
                ForEach(cards) { card in
                    WrappedCardView(card: card, summary: summary, voice: app.voice)
                        .tag(card)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(card.label)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background { WrappedBackground() }
            .ignoresSafeArea(edges: .bottom)

            StoryProgress(count: cards.count, index: cards.firstIndex(of: page) ?? 0)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) { controls(summary, cards: cards) }
        .task(id: ShareKey(page: page, inMyLevel: sharesInMyLevel)) { render(summary) }
        .preferredColorScheme(.dark)
    }

    private func controls(_ summary: WrappedSummary, cards: [WrappedCard]) -> some View {
        HStack(spacing: 10) {
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("Kedro Wrapped \(String(year)): \(page.label)", image: shareImage)
                ) {
                    Text("Share This Card")
                }
                .buttonStyle(.kedroGlassWide)
                .contextMenu {
                    Toggle("Share in My Level", isOn: $sharesInMyLevel)
                }
            }
            if let next = cards.firstIndex(of: page).flatMap({ cards.indices.contains($0 + 1) ? cards[$0 + 1] : nil }) {
                Button("Next") { withAnimation { page = next } }
                    .buttonStyle(.kedroPrimary)
                    .frame(maxWidth: 140)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// Renders the current card for sharing: Clean unless you chose your own level.
    private func render(_ summary: WrappedSummary) {
        let voice = sharesInMyLevel ? app.voice : Voice(level: .clean)
        let card = WrappedCardView(card: page, summary: summary, voice: voice)
            .frame(width: 390, height: 693)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.cgImage.map { Image(decorative: $0, scale: 3) }
    }
}

private struct ShareKey: Hashable {
    var page: WrappedCard
    var inMyLevel: Bool
}

/// The story bars along the top: filled up to the current card.
private struct StoryProgress: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { step in
                Capsule()
                    .fill(step <= index ? WrappedStyle.cream : WrappedStyle.cream.opacity(0.25))
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Card \(index + 1) of \(count)")
    }
}

#Preview {
    NavigationStack { WrappedView(year: 2026) }
        .previewEnvironment()
}
