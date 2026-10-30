import OSLog
import SwiftUI

/// Send a Receipt after a finished game (design §8.5, mockup frame 13). Present as a sheet; it
/// brings its own navigation bar:
///
/// ```swift
/// .sheet(isPresented: $isSendingReceipt) { ReceiptComposer(gameID: session.gameID) }
/// ```
///
/// One receipt per rival per game, canned lines only. Two ways out: **in Kedro** (a
/// `ReceiptSent` operation plus `POST /v1/receipts` for the notification; the rival reads it in
/// their own level) and **outside Kedro** (an image through the share sheet, Clean by default).
struct ReceiptComposer: View {
    let gameID: GameID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var session: GameSession?
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    ReceiptComposerContent(session: session)
                } else if loadFailed {
                    ContentUnavailableView("Couldn't open this game", systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(.surface)
            .navigationTitle("Send a Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task(id: gameID) {
            if let live = app.liveGame, live.gameID == gameID {
                session = live
                return
            }
            do {
                let loaded = try await app.makeSession(for: gameID)
                session = loaded
                await loaded.run()
            } catch {
                loadFailed = true
            }
        }
    }
}

private struct ReceiptComposerContent: View {
    let session: GameSession

    @Environment(AppPreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var services = TalkServices.shared
    @State private var rivalID: SeatID?
    @State private var optionKey: String?
    @State private var sendsInKedro = true
    @State private var shareLevel: LanguageLevel = .clean
    @State private var shareImage: Image?
    @State private var isSending = false
    @State private var sentCount = 0
    @State private var errorText: String?

    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Receipts")

    private var state: GameState { session.state }
    private var me: Seat? { session.mySeat }
    private var myLevel: LanguageLevel { prefs.effectiveLanguageLevel }

    /// Everyone else from the game, except people you've blocked.
    private var rivals: [Seat] {
        state.seats.filter { $0.id != me?.id && !services.moderation.isBlocked($0.id) }
    }

    private var rival: Seat? {
        guard let me else { return nil }
        return rivals.first { $0.id == rivalID }
            ?? rivals.first { !Receipts.hasSent(in: state, from: me.id, to: $0.id) }
            ?? rivals.first
    }

    private var options: [ReceiptOption] {
        guard let me, let rival else { return [] }
        return Receipts.options(in: state, from: me.id, to: rival.id)
    }

    private var option: ReceiptOption? {
        options.first { $0.key == optionKey } ?? options.first
    }

    private var alreadySent: Bool {
        guard let me, let rival else { return false }
        return Receipts.hasSent(in: state, from: me.id, to: rival.id)
    }

    /// Clean, plus your own level when it's spicier ("a toggle for the sender's level").
    private var shareLevels: [LanguageLevel] {
        myLevel == .clean ? [.clean] : [.clean, myLevel]
    }

    var body: some View {
        if state.status != .finished || me == nil || rivals.isEmpty {
            ContentUnavailableView(
                "No receipts yet",
                systemImage: "lock",
                description: Text("Receipts open for the players once the game is final.")
            )
        } else if let me, let rival, let option {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    recipients(me: me, selected: rival)
                    ReceiptCard(state: state, option: option, sender: me, rival: rival, level: myLevel)
                        .frame(maxWidth: .infinity)
                    lines(selected: option)
                    delivery
                }
                .padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom) { actions(rival: rival, option: option) }
            .sensoryFeedback(.success, trigger: sentCount)
            .task(id: ShareKey(rival: rival.id, option: option.key, level: shareLevel, scale: displayScale)) {
                shareImage = ReceiptCard.image(state: state, option: option, sender: me, rival: rival, level: shareLevel, scale: displayScale)
            }
            .onChange(of: rival.id) {
                optionKey = nil
                errorText = nil
            }
        }
    }

    // MARK: To

    private func recipients(me: Seat, selected: Seat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To").kedroFont(.label).foregroundStyle(.silver).padding(.horizontal)
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(rivals) { seat in
                        recipientButton(seat, isSelected: seat.id == selected.id, sent: Receipts.hasSent(in: state, from: me.id, to: seat.id))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func recipientButton(_ seat: Seat, isSelected: Bool, sent: Bool) -> some View {
        Button {
            rivalID = seat.id
        } label: {
            VStack(spacing: 4) {
                AvatarView(seat: seat, size: .standings, ring: isSelected ? .focus : .none)
                Text(seat.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .cream : .silver)
                    .lineLimit(1)
            }
            .opacity(sent && !isSelected ? 0.5 : 1)
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sent ? "\(seat.displayName), receipt sent" : seat.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Line

    private func lines(selected: ReceiptOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line").kedroFont(.label).foregroundStyle(.silver).padding(.horizontal)
            ChipFlowLayout {
                ForEach(options) { option in
                    lineChip(option, isSelected: option.key == selected.key)
                }
            }
            .padding(.horizontal)
        }
    }

    private func lineChip(_ option: ReceiptOption, isSelected: Bool) -> some View {
        Button {
            optionKey = option.key
        } label: {
            Text(option.line(level: myLevel))
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(isSelected ? Color.white : Color.cream)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
                .background(isSelected ? Color.kedroRedDeep : Color.surfaceRaised, in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(isSelected ? Color.kedroRed : Color.rule, lineWidth: isSelected ? 1.5 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Delivery

    private var delivery: some View {
        VStack(spacing: 0) {
            if alreadySent {
                LabeledContent("Send in Kedro") {
                    Label("Sent", systemImage: "checkmark").foregroundStyle(.silver)
                }
                .padding()
            } else {
                Toggle("Send in Kedro", isOn: $sendsInKedro)
                    .tint(.kedroRed)
                    .padding()
            }
            Divider().overlay(.rule)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share outside Kedro")
                    Text("Image goes out Clean unless you change it")
                        .font(.caption)
                        .foregroundStyle(.silver)
                }
                Spacer()
                Picker("Image level", selection: $shareLevel) {
                    ForEach(shareLevels) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .tint(.silver)
                .disabled(shareLevels.count < 2)
            }
            .padding()
        }
        .foregroundStyle(.cream)
        .background(.surfaceRaised, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: Actions

    private func actions(rival: Seat, option: ReceiptOption) -> some View {
        VStack(spacing: 10) {
            if let errorText {
                Text(errorText)
                    .font(.subheadline)
                    .foregroundStyle(.cream)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if sendsInKedro && !alreadySent {
                Button {
                    Task { await send(option, to: rival) }
                } label: {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send to \(rival.displayName)")
                    }
                }
                .buttonStyle(.kedroPrimary)
                .disabled(isSending)
            }
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("Receipt from \(state.config.tableWord)", image: shareImage)
                ) {
                    Label("Share Image", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.kedroGlassWide)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.surface)
    }

    private func send(_ option: ReceiptOption, to rival: Seat) async {
        isSending = true
        defer { isSending = false }
        do {
            try await session.sendReceipt(option.key, to: rival.id)
        } catch {
            log.error("Couldn't send a receipt: \(error.localizedDescription, privacy: .public)")
            errorText = error.localizedDescription
            return
        }
        errorText = nil
        sentCount += 1
        // The operation is the record; this call is what notifies them (N-08). Guests have no
        // account to notify, and a failure here is fine: the operation still syncs.
        if let player = rival.player.playerID {
            do {
                try await services.api.sendReceipt(gameID: session.gameID, to: player, receiptKey: option.key)
            } catch {
                log.info("Receipt notification not sent: \(String(describing: error), privacy: .public)")
            }
        }
        guard let me else { return }
        if let next = rivals.first(where: { !Receipts.hasSent(in: state, from: me.id, to: $0.id) }) {
            rivalID = next.id
        } else {
            dismiss()
        }
    }
}

/// What the share image depends on.
private struct ShareKey: Hashable {
    var rival: SeatID
    var option: String
    var level: LanguageLevel
    var scale: CGFloat
}

#Preview("Finished game") {
    let app = AppModel.preview()
    Color.night
        .sheet(isPresented: .constant(true)) {
            ReceiptComposer(gameID: PreviewData.sampleGameID)
                .task {
                    _ = try? await app.store.append(PreviewData.sampleOperations(throughRound: 8, finished: true))
                }
        }
        .previewEnvironment(app)
}
