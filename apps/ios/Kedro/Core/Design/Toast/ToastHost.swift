import SwiftUI

extension View {
    /// Shows the app's toasts over this view, under the top safe area. Apply at the root and on
    /// every `fullScreenCover` root (the Table, display mode), because a cover hides the root's.
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHostModifier(center: center))
    }
}

private struct ToastHostModifier: ViewModifier {
    let center: ToastCenter
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            VStack(spacing: 8) {
                ForEach(center.visible) { toast in
                    ToastView(toast: toast, center: center)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if center.overflowCount > 0 {
                    Text("+\(center.overflowCount) more in the feed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.silver)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.surfaceRaised, in: .capsule)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: center.visible.map(\.id))
        }
        .onChange(of: center.visible.last?.id) { _, newID in
            guard voiceOverEnabled, let toast = center.visible.first(where: { $0.id == newID }) else { return }
            AccessibilityNotification.Announcement(toast.spokenText).post()
        }
    }
}

/// One toast card (mockup frame 9).
struct ToastView: View {
    let toast: Toast
    let center: ToastCenter

    var body: some View {
        HStack(spacing: 10) {
            if let name = toast.avatarName {
                AvatarView(avatar: toast.avatar, name: name, isGuest: toast.avatarIsGuest, size: .compact)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow = toast.eyebrow {
                    if toast.kind == .liveKnock {
                        Text(eyebrow).kedroFont(.label).foregroundStyle(.kedroRed)
                    } else {
                        Text(eyebrow).font(.caption).foregroundStyle(.silver)
                    }
                }
                Text(toast.message)
                    .font(toast.kind == .liveKnock ? .body.weight(.semibold) : .body)
                    .foregroundStyle(.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = toast.action {
                Button(action.title) { center.performAction(of: toast.id) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.kedroRed)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.surfaceRaised, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(toast.kind == .liveKnock ? Color.kedroRed.opacity(0.5) : Color.cream.opacity(0.1))
        }
        .shadow(color: .black.opacity(0.45), radius: 15, y: 12)
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture { center.tap(toast.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Dismiss") { center.dismiss(toast.id) }
    }
}

#Preview("Toasts") {
    @Previewable @State var center: ToastCenter = {
        let center = ToastCenter()
        center.show(Toast(kind: .liveKnock, avatarName: "Sam", avatarIsGuest: true, eyebrow: "LIVE KNOCK",
                          message: "Sam knocked. Last turns. Pray, you animals.",
                          action: .init(title: "Undo") {}, duration: .seconds(600)))
        center.show(Toast(kind: .taunt, avatar: .emoji("🦊", colorIndex: 0), avatarName: "Ana", eyebrow: "Ana → Sam",
                          message: "Knocking on that? Brave as shit.", duration: .seconds(600)))
        center.show(Toast(message: "Round 6 saved.", action: .init(title: "Undo") {}, duration: .seconds(600)))
        return center
    }()
    Color.night
        .ignoresSafeArea()
        .toastHost(center)
        .preferredColorScheme(.dark)
}
