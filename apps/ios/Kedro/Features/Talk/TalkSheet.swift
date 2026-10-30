import SwiftUI

/// The Talk sheet: canned and custom taunts (design §8.1, mockup frame 10). Present at .medium;
/// it brings its own navigation bar and detents.
///
/// ```swift
/// .sheet(isPresented: $isTalking) {
///     TalkSheet(session: session, target: .suggested(for: session.state, me: session.mySeatID))
/// }
/// ```
struct TalkSheet: View {
    let session: GameSession
    let target: TauntTarget

    var body: some View {
        TalkSheetContent(composer: TalkComposer(session: session, target: target))
    }
}

private struct TalkSheetContent: View {
    @State var composer: TalkComposer

    @Environment(AppPreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var services = TalkServices.shared
    @State private var sentCount = 0
    @FocusState private var isWriting: Bool

    private var voice: Voice { Voice(level: prefs.effectiveLanguageLevel) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    targetPicker
                    if composer.canWriteCustom(preferences: prefs) {
                        Picker("Kind", selection: $composer.mode) {
                            ForEach(TalkComposer.Mode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }
                    switch composer.mode {
                    case .canned: cannedList
                    case .custom: customField
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.surface)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(voice.line("T-01"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: sentCount)
        .onChange(of: composer.mode) { _, mode in isWriting = mode == .custom }
        .onAppear {
            if !composer.canWriteCustom(preferences: prefs) { composer.mode = .canned }
        }
    }

    // MARK: At

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("At").kedroFont(.label).foregroundStyle(.silver).padding(.horizontal)
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    targetButton(.table, name: "Table") {
                        Circle()
                            .fill(.surfaceRaised)
                            .frame(width: AvatarView.Size.compact.rawValue + 12, height: AvatarView.Size.compact.rawValue + 12)
                            .overlay { Image(systemName: "suit.spade.fill").foregroundStyle(.cream) }
                    }
                    ForEach(composer.targetSeats) { seat in
                        targetButton(.seat(seat.id), name: seat.displayName) {
                            AvatarView(seat: seat, size: .standings)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func targetButton(_ target: TauntTarget, name: String, @ViewBuilder face: () -> some View) -> some View {
        let isSelected = composer.target == target
        return Button {
            composer.target = target
        } label: {
            VStack(spacing: 4) {
                face()
                    .overlay {
                        if isSelected {
                            Circle().strokeBorder(.kedroRed, lineWidth: 2.5).padding(-4)
                        }
                    }
                Text(name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .cream : .silver)
                    .lineLimit(1)
            }
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target == .table ? "The table" : name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Canned

    private var cannedList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(composer.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .kedroFont(.label)
                        .foregroundStyle(section.isTimely ? .kedroRed : .silver)
                        .padding(.horizontal)
                    ChipFlowLayout {
                        ForEach(section.taunts) { taunt in
                            chip(for: taunt)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func chip(for taunt: CannedTaunt) -> some View {
        let isSelected = composer.selectedTauntID == taunt.id
        return Button {
            composer.selectedTauntID = isSelected ? nil : taunt.id
        } label: {
            Text(voice.line(taunt.entry))
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

    // MARK: Custom

    private var customField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(voice.line("T-02"), text: $composer.customText, axis: .vertical)
                .lineLimit(2...4)
                .focused($isWriting)
                .submitLabel(.send)
                .padding(12)
                .background(.surfaceRaised, in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.rule) }
            HStack {
                Text("Only this table sees it. Anyone can report it.")
                Spacer()
                Text("\(composer.customText.count)/\(TauntContent.customMaxLength)")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.silver)
        }
        .padding(.horizontal)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = noticeText {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(.cream)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            HStack(spacing: 12) {
                Text(composer.allowance.canSend ? composer.allowanceText : voice.line("T-10"))
                    .font(.caption)
                    .foregroundStyle(.silver)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task {
                        if await composer.send(services: services, preferences: prefs) {
                            sentCount += 1
                            dismiss()
                        }
                    }
                } label: {
                    if composer.isSending {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(.kedroPrimary)
                .frame(width: 120)
                .disabled(!composer.canSend(preferences: prefs))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.surface)
        .animation(.default, value: composer.notice)
    }

    private var noticeText: String? {
        switch composer.notice {
        case .blocked: voice.line("T-12")
        case .rateLimited: voice.line("T-10")
        case .failed(let message): message
        case nil: nil
        }
    }
}

#Preview("After a live knock") {
    let app = AppModel.preview(liveGame: true)
    Color.night
        .sheet(isPresented: .constant(true)) {
            TalkSheet(session: PreviewData.sampleSession(liveKnock: true), target: .seat(PreviewData.samSeat))
        }
        .previewEnvironment(app)
}

#Preview("At the table") {
    TalkSheet(session: PreviewData.sampleSession(), target: .table).previewEnvironment()
}
