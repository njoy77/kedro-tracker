import SwiftUI

/// Report Your Hand (self-report games, design §7.4): a number pad, "I knocked", Send.
struct ClipReportHandSheet: View {
    @Environment(ClipModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let roundNumber: Int

    @State private var digits = ""
    @State private var isNegative = false
    @State private var knocked = false

    /// The hand typed so far, if it's a valid hand (−2…999).
    private var hand: Int? {
        guard let value = Int(digits) else { return nil }
        let signed = isNegative ? -value : value
        return Round.handRange.contains(signed) ? signed : nil
    }

    private var display: String {
        guard !digits.isEmpty else { return isNegative ? ScoreFormat.minus : "–" }
        return (isNegative ? ScoreFormat.minus : "") + digits
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(Literal.roundOf(roundNumber, model.state?.config.plannedRounds ?? roundNumber))
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .padding(.top, 24)
            Text(display)
                .kedroFont(.scoreLarge)
                .foregroundStyle(.cream)
                .contentTransition(.numericText())
                .accessibilityLabel(hand.map(ScoreFormat.spoken) ?? "No hand yet")
            Toggle(ClipCopy.iKnocked, isOn: $knocked)
                .font(.headline)
                .tint(.kedroRed)
                .padding(.horizontal, 24)
            pad
            Button(Literal.text("button.send")) {
                guard let hand else { return }
                Task {
                    await model.reportHand(hand, knocked: knocked)
                    dismiss()
                }
            }
            .buttonStyle(.kedroPrimary)
            .disabled(hand == nil || model.isWorking)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.night)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: digits)
    }

    private var pad: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        PadKey(label: key) { type(key) }
                    }
                }
            }
            GridRow {
                PadKey(label: ScoreFormat.minus, accessibility: "minus") { isNegative.toggle() }
                PadKey(label: "0") { type("0") }
                PadKey(systemImage: "delete.left", accessibility: "Delete") {
                    if digits.isEmpty { isNegative = false } else { digits.removeLast() }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func type(_ key: String) {
        guard digits.count < 3 else { return }
        digits = digits == "0" ? key : digits + key
    }
}

/// A number pad key (≥ 56 pt tall, design §14).
private struct PadKey: View {
    var label: String?
    var systemImage: String?
    var accessibility: String?
    let action: () -> Void

    init(label: String, accessibility: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.accessibility = accessibility
        self.action = action
    }

    init(systemImage: String, accessibility: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibility = accessibility
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.title2)
                } else {
                    Text(label ?? "").kedroFont(.pad)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.cream)
            .background(.surfaceRaised, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility ?? label ?? "")
    }
}

#Preview {
    ClipReportHandSheet(roundNumber: 6)
        .environment(ClipModel.preview(seated: true, throughRound: 5))
}
