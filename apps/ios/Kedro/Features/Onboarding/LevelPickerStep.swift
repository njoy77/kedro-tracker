import SwiftUI

/// "How filthy do you want it?" (design §5.1, mockup frame 2): three cards, each with its live
/// sample line (O-07…O-09, shown verbatim at every level). Unhinged is preselected for adults;
/// under 18 it's locked to Clean (O-10).
struct LevelPickerStep: View {
    @Binding var level: LanguageLevel
    var onContinue: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(app.voice.line("O-06"))
                    .kedroFont(.display)
                    .foregroundStyle(.cream)
                    .accessibilityAddTraits(.isHeader)
                Text("Every line in Kedro comes in three strengths. Change it any time in Settings.")
                    .foregroundStyle(.silver)
                    .padding(.bottom, 10)

                if prefs.isUnder18 {
                    Text(app.voice.line("O-10"))
                        .font(.callout)
                        .foregroundStyle(.cream)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.surface, in: .rect(cornerRadius: 16))
                }

                ForEach(LanguageLevel.allCases) { option in
                    LevelCard(
                        level: option,
                        isSelected: level == option,
                        isLocked: prefs.isUnder18 && option != .clean
                    ) {
                        level = option
                    }
                }

                Text("Buttons, rules and the score never change. Only the commentary does.")
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button(Literal.text("button.continue"), action: onContinue)
                .buttonStyle(.kedroPrimary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .checksAgeRange()
        .onChange(of: prefs.isUnder18, initial: true) { _, under18 in
            if under18 { level = .clean }
        }
    }
}

/// One level on the picker: name, short description, sample line, radio.
struct LevelCard: View {
    let level: LanguageLevel
    let isSelected: Bool
    var isLocked = false
    let select: () -> Void

    @Environment(AppModel.self) private var app

    private var sampleID: String {
        switch level {
        case .clean: "O-07"
        case .spicy: "O-08"
        case .unhinged: "O-09"
        }
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(level.displayName).kedroFont(.headline).foregroundStyle(.cream)
                        Text(level.shortDescription).font(.subheadline).foregroundStyle(.silver)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.kedroRed : .silverDim)
                        .accessibilityHidden(true)
                }
                // O-07…O-09 are each level's own sample, rendered verbatim (exempt from the Clean lint).
                Text(app.voice.deck[sampleID]?.clean ?? "")
                    .kedroFont(.roast)
                    .foregroundStyle(.silver)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surface, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? Color.kedroRed : .rule, lineWidth: isSelected ? 2 : 1)
            }
            .opacity(isLocked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var level = LanguageLevel.unhinged
    LevelPickerStep(level: $level) {}
        .background(.night)
        .previewEnvironment()
        .preferredColorScheme(.dark)
}
